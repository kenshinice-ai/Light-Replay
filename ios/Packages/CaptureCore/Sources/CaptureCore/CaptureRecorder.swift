import ARKit
import CoreLocation
import Foundation
import simd
import UIKit

/// The OneTake recorder (docs/04, docs/07 W1): runs an ARKit world-tracking session, samples every frame's pose
/// and intrinsics as plain values, records heading readings and a location fix, and hands back a `CaptureLog`.
/// It never keeps ARFrames and never computes anything about the sun.
///
/// Two stages: `startPreview()` runs the session so a camera view can show it and the compass can settle;
/// `start()` begins the record (and the preview if needed), and the viewpoint anchor locks on the next normal frame.
@MainActor
public final class CaptureRecorder: NSObject, ObservableObject {
    public enum Availability: Sendable, Equatable {
        case supported
        case unsupported(String)
    }

    /// True while a record is being taken.
    @Published public private(set) var isRunning = false
    /// True while the ARSession runs, recording or not.
    @Published public private(set) var isPreviewing = false
    @Published public private(set) var frameCount = 0
    @Published public private(set) var trackingState = "not_available"
    @Published public private(set) var anchorLocked = false
    @Published public private(set) var currentDriftM: Double?
    /// Lens position minus the anchor, AR world metres. Nil before the anchor locks.
    @Published public private(set) var currentOffset: SIMD3<Double>?
    @Published public private(set) var maxDriftM: Double?
    @Published public private(set) var latestHeading: HeadingSample?
    @Published public private(set) var location: LocationSample?
    @Published public private(set) var failureReason: String?
    /// Frames kept for analysis so far in this record.
    @Published public private(set) var spooledFrames = 0

    public let availability: Availability
    /// Whether a record keeps frames for analysis (docs/04 §12). The capture validator turns it off.
    public var keepsSpool = true
    public var viewpointToleranceM = 0.15
    /// The orientation the interface is showing. CLHeading is measured from the top edge of the device, so the
    /// location manager has to be told which edge is up, or every landscape reading is 90° off.
    public var interfaceOrientation: UIInterfaceOrientation = .portrait {
        didSet { locationManager.headingOrientation = Self.headingOrientation(for: interfaceOrientation) }
    }
    /// Called on the main queue with every frame while the session runs. It must not keep the frame.
    public var frameObserver: (@MainActor (ARFrame) -> Void)?
    /// The session a camera view (RealityKit `ARView`) displays. The recorder stays its delegate.
    public var arSession: ARSession { session }

    private let session = ARSession()
    private let locationManager = CLLocationManager()
    private var startedAt: Date?
    private var firstFrameAt: Date?
    private var firstFrameTimestamp: TimeInterval?
    private var anchor: SIMD3<Double>?
    private var anchorFrameID: String?
    private var frames: [FrameSample] = []
    private var lastKeptTimestamp: TimeInterval?
    private var headings: [HeadingSample] = []
    /// Surfaces of the running session, by anchor. The session's, not the recording's: one found during the preview
    /// is in the same world frame and still there when the recording ends.
    private var planes: [UUID: SpoolPlane] = [:]
    /// "2 wall, 1 window", for the scan screen's diagnostics and the device probe.
    public var planeSummary: String {
        let counts = Dictionary(grouping: planes.values, by: \.classification).mapValues(\.count)
        return counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }
    private var lastHeadingKeptAt: Date?
    private var sessionID = UUID().uuidString
    private var spool: FrameSpoolWriter?
    private var lastPose: (timestamp: TimeInterval, forward: SIMD3<Double>)?
    private var lastSpooled: (timestamp: TimeInterval, forward: SIMD3<Double>)?
    private var turnRateDegPerSec = 0.0

    public override init() {
        if ARWorldTrackingConfiguration.isSupported {
            availability = .supported
        } else {
            availability = .unsupported("ARKit world tracking is not supported here (simulator or unsupported device).")
        }
        super.init()
        session.delegate = self
        session.delegateQueue = .main
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.headingOrientation = .portrait
        // Every reading, not only those a degree away from the last one (the default filter): a phone held level and
        // still — what "finding north" asks for — otherwise sends none. PR-20261009-01 and -03 waited 10 s for one.
        locationManager.headingFilter = kCLHeadingFilterNone
    }

    /// UIInterfaceOrientation and CLDeviceOrientation name landscape from opposite sides: an interface shown in
    /// `.landscapeLeft` means the device was turned to `.landscapeRight`.
    public static func headingOrientation(for orientation: UIInterfaceOrientation) -> CLDeviceOrientation {
        switch orientation {
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }

    static func name(_ orientation: CLDeviceOrientation) -> String {
        switch orientation {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        case .faceUp: "faceUp"
        case .faceDown: "faceDown"
        default: "unknown"
        }
    }

    /// Runs the session without recording: camera view, tracking, compass and location warm up.
    public func startPreview() {
        guard availability == .supported, !isPreviewing else { return }
        latestHeading = nil
        location = nil
        failureReason = nil
        trackingState = "not_available"
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity   // az_ar is measured from the session's -Z axis (docs/02 §3)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        // Walls, windows and doors: the spool keeps them so the analysis can tell a pane from a wall (docs/04 §12).
        configuration.planeDetection = [.vertical]
        planes.removeAll()
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isPreviewing = true
    }

    /// Begins a record in the running session (starting it if needed). The anchor locks on the next normal frame.
    public func start() {
        guard availability == .supported, !isRunning else { return }
        startPreview()
        // Fresh record, fresh evidence: nothing from a previous scan may leak into this one.
        frames.removeAll()
        lastKeptTimestamp = nil
        headings.removeAll()
        anchor = nil
        anchorFrameID = nil
        anchorLocked = false
        frameCount = 0
        maxDriftM = nil
        currentDriftM = nil
        currentOffset = nil
        failureReason = nil
        firstFrameAt = nil
        firstFrameTimestamp = nil
        sessionID = UUID().uuidString
        spool?.discard()
        spool = keepsSpool ? try? FrameSpoolWriter(sessionID: sessionID) : nil
        spooledFrames = 0
        lastPose = nil
        lastSpooled = nil
        turnRateDegPerSec = 0
        startedAt = Date()
        isRunning = true
    }

    /// The clockwise turn that shows the sensor image the way the screen showed it. The sensor image is upright when
    /// the interface is landscape with the home side on the right.
    nonisolated public static func heroRotationDeg(for orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeRight: 0
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }

    /// Stops the session without keeping anything. Safe when nothing runs.
    public func endPreview() {
        guard isPreviewing else { return }
        session.pause()
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
        isPreviewing = false
        isRunning = false
    }

    /// Stops the session and returns the log, without the frames kept for analysis: they are dropped. For a scan
    /// that is being thrown away, and for the capture validator. Returns nil if nothing was recorded.
    public func stop(targetLabel: String = "Capture validator target", targetHeightM: Double? = nil) -> CaptureLog? {
        guard isRunning, let startedAt else { return nil }
        endPreview()
        spool?.discard()
        spool = nil
        return makeLog(startedAt: startedAt, targetLabel: targetLabel, targetHeightM: targetHeightM, hero: nil, manifest: nil)
    }

    /// Stops the session, waits for the frames to be written, and returns the log with the hero and the spool's
    /// manifest. Only after this has returned are the frames safely on disk.
    public func finish(targetLabel: String, targetHeightM: Double? = nil) async -> CaptureLog? {
        guard isRunning, let startedAt else { return nil }
        endPreview()
        let writer = spool
        spool = nil
        let kept = await writer?.finish(planes: Array(planes.values), planeClassification: ARPlaneAnchor.isClassificationSupported)
        if kept?.manifest == nil { writer?.discard() }   // nothing usable: do not leave an empty folder behind
        return makeLog(startedAt: startedAt, targetLabel: targetLabel, targetHeightM: targetHeightM, hero: kept?.hero, manifest: kept?.manifest)
    }

    private func makeLog(startedAt: Date, targetLabel: String, targetHeightM: Double?, hero: HeroImage?, manifest: SpoolManifest?) -> CaptureLog {
        let device = DeviceInfo(
            model: Self.modelIdentifier,
            os: "iOS \(UIDevice.current.systemVersion)",
            lidar: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            sceneDepth: frames.contains { $0.hasSceneDepth },
            geoTracking: ARGeoTrackingConfiguration.isSupported ? "supported_device" : "unavailable"
        )
        let info = Bundle.main.infoDictionary
        return CaptureLog(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: Date(),
            firstFrameAt: firstFrameAt,
            timezone: .current,
            device: device,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "0",
            appBuild: info?["CFBundleVersion"] as? String ?? "0",
            targetLabel: targetLabel,
            targetHeightM: targetHeightM,
            frames: frames,
            anchor: anchor,
            anchorFrameID: anchorFrameID,
            maxDriftM: maxDriftM,
            headings: headings,
            location: location,
            viewpointToleranceM: viewpointToleranceM,
            failureReason: failureReason,
            hero: hero,
            spool: manifest
        )
    }

    private static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    // Column-major flattening; simd subscripts are [column][row] (docs/03 §3).
    nonisolated static func flatten(_ m: simd_float4x4) -> [Double] {
        (0..<4).flatMap { c in (0..<4).map { r in Double(m[c][r]) } }
    }

    nonisolated static func flatten(_ m: simd_float3x3) -> [Double] {
        (0..<3).flatMap { c in (0..<3).map { r in Double(m[c][r]) } }
    }

    nonisolated static func describe(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "normal"
        case .notAvailable: return "not_available"
        case .limited(let reason):
            switch reason {
            case .initializing: return "limited:initializing"
            case .excessiveMotion: return "limited:excessive_motion"
            case .insufficientFeatures: return "limited:insufficient_features"
            case .relocalizing: return "limited:relocalizing"
            @unknown default: return "limited:unknown"
            }
        }
    }
}

extension CaptureRecorder: ARSessionDelegate {
    nonisolated public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // The delegate queue is main (init), so the frame is handed to the observer synchronously; it must not
        // outlive this callback.
        MainActor.assumeIsolated { self.frameObserver?(frame) }
        // Extract plain values now; the ARFrame must not outlive this callback.
        let transform = Self.flatten(frame.camera.transform)
        let intrinsics = Self.flatten(frame.camera.intrinsics)
        let state = Self.describe(frame.camera.trackingState)
        let hasDepth = frame.sceneDepth != nil
        let exposure = Double(frame.camera.exposureOffset)
        let timestamp = frame.timestamp
        // The pixel buffers are handed on only for the few frames the spool keeps; the ARFrame itself never is.
        let buffers = FrameBuffers(image: frame.capturedImage, depth: frame.sceneDepth?.depthMap, confidence: frame.sceneDepth?.confidenceMap)
        MainActor.assumeIsolated {
            self.record(transform: transform, intrinsics: intrinsics, state: state,
                        hasDepth: hasDepth, exposure: exposure, timestamp: timestamp, buffers: buffers)
        }
    }

    nonisolated public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { keep(anchors) }
    nonisolated public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { keep(anchors) }

    nonisolated public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let gone = anchors.map(\.identifier)
        MainActor.assumeIsolated { for id in gone { self.planes[id] = nil } }
    }

    nonisolated private func keep(_ anchors: [ARAnchor]) {
        let found = anchors.compactMap { $0 as? ARPlaneAnchor }.map { ($0.identifier, Self.plane($0)) }
        guard !found.isEmpty else { return }
        MainActor.assumeIsolated { for (id, plane) in found { self.planes[id] = plane } }
    }

    /// The plain values of a plane anchor: the anchor itself must not outlive the callback.
    nonisolated static func plane(_ anchor: ARPlaneAnchor) -> SpoolPlane {
        let label: String, status: String
        switch anchor.classification {
        case .wall: (label, status) = ("wall", "known")
        case .floor: (label, status) = ("floor", "known")
        case .ceiling: (label, status) = ("ceiling", "known")
        case .table: (label, status) = ("table", "known")
        case .seat: (label, status) = ("seat", "known")
        case .window: (label, status) = ("window", "known")
        case .door: (label, status) = ("door", "known")
        case .none(.notAvailable): (label, status) = ("none", "not_available")
        case .none(.undetermined): (label, status) = ("none", "undetermined")
        case .none(.unknown): (label, status) = ("none", "unknown")
        @unknown default: (label, status) = ("none", "unknown")
        }
        let extent = anchor.planeExtent
        return SpoolPlane(id: anchor.identifier.uuidString, alignment: anchor.alignment == .vertical ? "vertical" : "horizontal",
                          classification: label, classificationStatus: status, transform: flatten(anchor.transform),
                          center: [Double(anchor.center.x), Double(anchor.center.y), Double(anchor.center.z)],
                          widthM: Double(extent.width), heightM: Double(extent.height), rotationOnYAxis: Double(extent.rotationOnYAxis),
                          boundary: anchor.geometry.boundaryVertices.map { [Double($0.x), Double($0.y), Double($0.z)] })
    }

    nonisolated public func session(_ session: ARSession, didFailWithError error: any Error) {
        let text = error.localizedDescription
        MainActor.assumeIsolated {
            self.failureReason = "failed: \(text)"
            self.trackingState = "not_available"
        }
    }

    nonisolated public func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated { self.failureReason = "interrupted" }
    }

    nonisolated public func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { self.failureReason = (self.failureReason ?? "interrupted") + "; interruption ended" }
    }

    private struct FrameBuffers: @unchecked Sendable {
        let image: CVPixelBuffer
        let depth: CVPixelBuffer?
        let confidence: CVPixelBuffer?
    }

    private func record(transform: [Double], intrinsics: [Double], state: String,
                        hasDepth: Bool, exposure: Double, timestamp: TimeInterval, buffers: FrameBuffers? = nil) {
        if trackingState != state { trackingState = state }   // published: only on change, not 60 times a second
        guard isRunning else { return }
        let forward = SIMD3(-transform[8], -transform[9], -transform[10])
        if let last = lastPose, timestamp > last.timestamp {
            let angle = acos(max(-1, min(1, simd_dot(last.forward, forward)))) * 180 / .pi
            turnRateDegPerSec = 0.8 * turnRateDegPerSec + 0.2 * angle / (timestamp - last.timestamp)
        }
        lastPose = (timestamp, forward)
        if firstFrameTimestamp == nil {
            firstFrameTimestamp = timestamp
            firstFrameAt = Date()
        }
        let position = SIMD3(transform[12], transform[13], transform[14])
        let frameID = String(format: "f%05d", frames.count)
        let locksAnchor = anchor == nil && state == "normal"
        if locksAnchor {
            anchor = position
            anchorFrameID = frameID
            anchorLocked = true
        }
        // Drift is followed on every frame; the record keeps a thinned trail (ADR-0020).
        let drift = anchor.map { simd_distance($0, position) }
        currentDriftM = drift
        currentOffset = anchor.map { position - $0 }
        if let drift { maxDriftM = max(maxDriftM ?? 0, drift) }
        // A frame kept for analysis is always in the pose log too, so its pose is its own and not a neighbour's.
        let forSpool = spool != nil && buffers != nil && SpoolAdmission.admits(
            trackingNormal: state == "normal", lensOffsetM: drift, turnRateDegPerSec: turnRateDegPerSec,
            sinceLast: lastSpooled.map { timestamp - $0.timestamp },
            angleFromLastDeg: lastSpooled.map { acos(max(-1, min(1, simd_dot($0.forward, forward)))) * 180 / .pi })
        guard forSpool || Self.keepsFrame(at: timestamp, lastKept: lastKeptTimestamp, stateChanged: frames.last.map { $0.trackingState != state } ?? true,
                                          locksAnchor: locksAnchor) else { return }
        lastKeptTimestamp = timestamp
        let t = timestamp - (firstFrameTimestamp ?? timestamp)
        if let buffers, let spool {
            if locksAnchor {
                spool.setHero(image: buffers.image, rotationDeg: Self.heroRotationDeg(for: interfaceOrientation), frameID: frameID)
            }
            if forSpool, spool.offer(image: buffers.image, depth: buffers.depth, confidence: buffers.confidence,
                                     meta: .init(frameID: frameID, timestamp: timestamp, t: t, cameraTransform: transform, intrinsics: intrinsics,
                                                 exposureOffset: exposure, lensOffsetM: drift, turnRateDegPerSec: turnRateDegPerSec)) {
                lastSpooled = (timestamp, forward)
                spooledFrames += 1
            }
        }
        frames.append(FrameSample(
            frameID: frameID,
            t: t,
            cameraTransform: transform,
            intrinsics: intrinsics,
            trackingState: state,
            lensOffsetM: drift,
            hasSceneDepth: hasDepth,
            exposureOffset: exposure
        ))
        frameCount = frames.count
    }
}

extension CaptureRecorder {
    /// Poses go into the record at most this often (ADR-0020): 60 fps wrote 25 MB for one six-minute scan on
    /// 2026-10-03, and nothing that reads the poses — heading pairing, the viewpoint lock, keyframe masks — needs more.
    nonisolated public static let poseLogHz: Double = 10

    /// Whether a frame joins the record: the first, the one that locks the anchor, any change of tracking state, and
    /// otherwise one per 1/`poseLogHz` seconds. Pure, so it is tested without an ARSession.
    nonisolated public static func keepsFrame(at timestamp: TimeInterval, lastKept: TimeInterval?, stateChanged: Bool, locksAnchor: Bool) -> Bool {
        guard let lastKept else { return true }
        if locksAnchor || stateChanged { return true }
        return timestamp - lastKept >= 1 / poseLogHz - 1e-6
    }
}

extension CaptureRecorder {
    /// Compass readings are thinned like poses (ADR-0020): one per 1/`poseLogHz` seconds, for the screen and the record
    /// alike, so both merge the same readings. Unfiltered they arrive faster than they carry anything new.
    nonisolated public static func keepsHeading(at sampledAt: Date, lastKept: Date?) -> Bool {
        guard let lastKept else { return true }
        let gap = sampledAt.timeIntervalSince(lastKept)
        return gap >= 1 / poseLogHz - 1e-6 || gap < 0   // a clock that stepped back must not silence the compass
    }
}

extension CaptureRecorder: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading, magneticHeading = newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy, sampledAt = newHeading.timestamp
        MainActor.assumeIsolated {
            let sample = HeadingSample(trueHeading: trueHeading, magneticHeading: magneticHeading, headingAccuracy: accuracy,
                                       sampledAt: sampledAt, deviceOrientation: Self.name(self.locationManager.headingOrientation))
            guard Self.keepsHeading(at: sampledAt, lastKept: self.lastHeadingKeptAt) else { return }
            self.lastHeadingKeptAt = sampledAt
            self.latestHeading = sample
            if self.isRunning { self.headings.append(sample) }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let sample = LocationSample(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude,
                                    altitudeM: last.verticalAccuracy >= 0 ? last.altitude : nil,
                                    horizontalAccuracyM: last.horizontalAccuracy >= 0 ? last.horizontalAccuracy : nil,
                                    verticalAccuracyM: last.verticalAccuracy >= 0 ? last.verticalAccuracy : nil,
                                    capturedAt: last.timestamp)
        MainActor.assumeIsolated { if self.isPreviewing { self.location = sample } }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
