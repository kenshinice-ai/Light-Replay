import Foundation
import simd

/// Plain, Sendable values sampled from an ARKit session. No ARFrame is retained (docs/04 §3, docs/02 §5).
public struct FrameSample: Sendable, Equatable {
    public var frameID: String
    /// Seconds since the session started.
    public var t: Double
    /// Column-major 4x4 camera-to-world transform (ARKit world, gravity aligned).
    public var cameraTransform: [Double]
    /// Column-major 3x3 intrinsics of the captured image.
    public var intrinsics: [Double]
    /// "normal", "limited:<reason>" or "not_available" (docs/03 §3).
    public var trackingState: String
    /// Distance between the lens centre and the viewpoint anchor, metres.
    public var lensOffsetM: Double
    public var hasSceneDepth: Bool
    public var exposureOffset: Double?

    public init(frameID: String, t: Double, cameraTransform: [Double], intrinsics: [Double],
                trackingState: String, lensOffsetM: Double, hasSceneDepth: Bool, exposureOffset: Double?) {
        self.frameID = frameID
        self.t = t
        self.cameraTransform = cameraTransform
        self.intrinsics = intrinsics
        self.trackingState = trackingState
        self.lensOffsetM = lensOffsetM
        self.hasSceneDepth = hasSceneDepth
        self.exposureOffset = exposureOffset
    }

    /// Camera position in AR world coordinates (translation column of the transform).
    public var position: SIMD3<Double> {
        SIMD3(cameraTransform[12], cameraTransform[13], cameraTransform[14])
    }
}

/// One magnetometer reading (NorthResolver candidate in the `magnetic` group, docs/05 §2).
public struct HeadingSample: Sendable, Equatable {
    public var trueHeading: Double
    public var magneticHeading: Double
    /// CLHeading.headingAccuracy: negative means invalid.
    public var headingAccuracy: Double
    public var sampledAt: Date

    public init(trueHeading: Double, magneticHeading: Double, headingAccuracy: Double, sampledAt: Date) {
        self.trueHeading = trueHeading
        self.magneticHeading = magneticHeading
        self.headingAccuracy = headingAccuracy
        self.sampledAt = sampledAt
    }
}

public struct LocationSample: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var altitudeM: Double?
    public var horizontalAccuracyM: Double?
    public var verticalAccuracyM: Double?
    public var capturedAt: Date

    public init(latitude: Double, longitude: Double, altitudeM: Double?, horizontalAccuracyM: Double?,
                verticalAccuracyM: Double?, capturedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeM = altitudeM
        self.horizontalAccuracyM = horizontalAccuracyM
        self.verticalAccuracyM = verticalAccuracyM
        self.capturedAt = capturedAt
    }
}

public struct DeviceInfo: Sendable, Equatable {
    public var model: String
    public var os: String
    public var lidar: Bool
    public var sceneDepth: Bool
    public var geoTracking: String

    public init(model: String, os: String, lidar: Bool, sceneDepth: Bool, geoTracking: String) {
        self.model = model
        self.os = os
        self.lidar = lidar
        self.sceneDepth = sceneDepth
        self.geoTracking = geoTracking
    }
}

/// Everything one OneTake session produced, before any analysis. Feeds `SceneRecordBuilder`.
public struct CaptureLog: Sendable, Equatable {
    public var sessionID: String
    public var startedAt: Date
    public var endedAt: Date
    public var timezone: TimeZone
    public var device: DeviceInfo
    public var appVersion: String
    public var appBuild: String
    public var targetLabel: String
    public var targetHeightM: Double?
    public var frames: [FrameSample]
    public var heading: HeadingSample?
    public var location: LocationSample?
    public var viewpointToleranceM: Double

    public init(sessionID: String, startedAt: Date, endedAt: Date, timezone: TimeZone, device: DeviceInfo,
                appVersion: String, appBuild: String, targetLabel: String, targetHeightM: Double?,
                frames: [FrameSample], heading: HeadingSample?, location: LocationSample?,
                viewpointToleranceM: Double = 0.15) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezone = timezone
        self.device = device
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.targetLabel = targetLabel
        self.targetHeightM = targetHeightM
        self.frames = frames
        self.heading = heading
        self.location = location
        self.viewpointToleranceM = viewpointToleranceM
    }

    public var heroFrame: FrameSample? { frames.first }

    /// Largest lens offset seen during the scan (docs/04 §4). Nil when nothing was recorded.
    public var maxDriftM: Double? { frames.map(\.lensOffsetM).max() }
}
