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

    public let availability: Availability
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
    private var sessionID = UUID().uuidString

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
        startedAt = Date()
        isRunning = true
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

    /// Stops the session and returns the log. Returns nil if nothing was recorded.
    public func stop(targetLabel: String = "Capture validator target", targetHeightM: Double? = nil) -> CaptureLog? {
        guard isRunning, let startedAt else { return nil }
        endPreview()
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
            failureReason: failureReason
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
        MainActor.assumeIsolated {
            self.record(transform: transform, intrinsics: intrinsics, state: state,
                        hasDepth: hasDepth, exposure: exposure, timestamp: timestamp)
        }
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

    private func record(transform: [Double], intrinsics: [Double], state: String,
                        hasDepth: Bool, exposure: Double, timestamp: TimeInterval) {
        if trackingState != state { trackingState = state }   // published: only on change, not 60 times a second
        guard isRunning else { return }
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
        guard Self.keepsFrame(at: timestamp, lastKept: lastKeptTimestamp, stateChanged: frames.last.map { $0.trackingState != state } ?? true,
                              locksAnchor: locksAnchor) else { return }
        lastKeptTimestamp = timestamp
        frames.append(FrameSample(
            frameID: frameID,
            t: timestamp - (firstFrameTimestamp ?? timestamp),
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

extension CaptureRecorder: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading, magneticHeading = newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy, sampledAt = newHeading.timestamp
        MainActor.assumeIsolated {
            let sample = HeadingSample(trueHeading: trueHeading, magneticHeading: magneticHeading, headingAccuracy: accuracy,
                                       sampledAt: sampledAt, deviceOrientation: Self.name(self.locationManager.headingOrientation))
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
