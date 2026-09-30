import ARKit
import CoreLocation
import Foundation
import simd
import UIKit

/// Week-1 capture validator (docs/07 W1): runs an ARKit world-tracking session, samples every frame's pose
/// and intrinsics as plain values, records one magnetometer reading and one location fix, and hands back a
/// `CaptureLog`. It never keeps ARFrames and never computes anything about the sun.
@MainActor
public final class CaptureRecorder: NSObject, ObservableObject {
    public enum Availability: Sendable, Equatable {
        case supported
        case unsupported(String)
    }

    @Published public private(set) var isRunning = false
    @Published public private(set) var frameCount = 0
    @Published public private(set) var trackingState = "not_available"
    @Published public private(set) var currentDriftM = 0.0
    @Published public private(set) var maxDriftM = 0.0
    @Published public private(set) var heading: HeadingSample?
    @Published public private(set) var location: LocationSample?

    public let availability: Availability
    public var viewpointToleranceM = 0.15

    private let session = ARSession()
    private let locationManager = CLLocationManager()
    private var startedAt: Date?
    private var anchor: SIMD3<Double>?
    private var frames: [FrameSample] = []
    private var sessionID = UUID().uuidString
    private var lastSampleTime: TimeInterval = -1

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
    }

    public func start() {
        guard availability == .supported, !isRunning else { return }
        frames.removeAll()
        anchor = nil
        frameCount = 0
        maxDriftM = 0
        currentDriftM = 0
        sessionID = UUID().uuidString
        startedAt = Date()
        lastSampleTime = -1
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity   // az_ar is measured from the session's -Z axis (docs/02 §3)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    /// Stops the session and returns the log. Returns nil if nothing was started.
    public func stop() -> CaptureLog? {
        guard isRunning, let startedAt else { return nil }
        session.pause()
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
        isRunning = false
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
            timezone: .current,
            device: device,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "0",
            appBuild: info?["CFBundleVersion"] as? String ?? "0",
            targetLabel: "Capture validator target",
            targetHeightM: nil,
            frames: frames,
            heading: heading,
            location: location,
            viewpointToleranceM: viewpointToleranceM
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

    private func record(transform: [Double], intrinsics: [Double], state: String,
                        hasDepth: Bool, exposure: Double, timestamp: TimeInterval) {
        guard isRunning, let startedAt else { return }
        if lastSampleTime < 0 { lastSampleTime = timestamp }
        let position = SIMD3(transform[12], transform[13], transform[14])
        if anchor == nil, state == "normal" { anchor = position }
        let drift = anchor.map { simd_distance($0, position) } ?? 0
        currentDriftM = drift
        maxDriftM = max(maxDriftM, drift)
        trackingState = state
        // Poses every frame would be ~60 Hz; 10 Hz is plenty for W1 drift statistics (docs/02 §7).
        guard timestamp - lastSampleTime >= 0.1 || frames.isEmpty else { return }
        lastSampleTime = timestamp
        frames.append(FrameSample(
            frameID: String(format: "f%05d", frames.count),
            t: max(0, Date().timeIntervalSince(startedAt)),
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

extension CaptureRecorder: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let sample = HeadingSample(trueHeading: newHeading.trueHeading, magneticHeading: newHeading.magneticHeading,
                                   headingAccuracy: newHeading.headingAccuracy, sampledAt: newHeading.timestamp)
        MainActor.assumeIsolated { if self.heading == nil { self.heading = sample } }   // first reading = session start heading
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let sample = LocationSample(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude,
                                    altitudeM: last.verticalAccuracy >= 0 ? last.altitude : nil,
                                    horizontalAccuracyM: last.horizontalAccuracy >= 0 ? last.horizontalAccuracy : nil,
                                    verticalAccuracyM: last.verticalAccuracy >= 0 ? last.verticalAccuracy : nil,
                                    capturedAt: last.timestamp)
        MainActor.assumeIsolated { self.location = sample }
    }
}
