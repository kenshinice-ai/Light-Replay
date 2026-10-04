import Foundation
import simd

/// Plain, Sendable values sampled from an ARKit session. No ARFrame is retained (docs/04 §3, docs/02 §5).
public struct FrameSample: Sendable, Equatable {
    public var frameID: String
    /// Seconds since the first frame of the session, from ARFrame timestamps (monotonic).
    public var t: Double
    /// Column-major 4x4 camera-to-world transform (ARKit world, gravity aligned).
    public var cameraTransform: [Double]
    /// Column-major 3x3 intrinsics of the captured image.
    public var intrinsics: [Double]
    /// "normal", "limited:<reason>" or "not_available" (docs/03 §3).
    public var trackingState: String
    /// Distance between the lens centre and the viewpoint anchor, metres. Nil before the anchor is locked (docs/03 §1: unknown is null).
    public var lensOffsetM: Double?
    public var hasSceneDepth: Bool
    public var exposureOffset: Double?

    public init(frameID: String, t: Double, cameraTransform: [Double], intrinsics: [Double],
                trackingState: String, lensOffsetM: Double?, hasSceneDepth: Bool, exposureOffset: Double?) {
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

    /// Azimuth of the camera's forward axis in the AR world frame (docs/02 §3): forward = R·(0,0,−1),
    /// `az_ar = atan2(d_x, −d_z)`, clockwise from the session's −Z axis.
    public var cameraAzimuthAR: Double {
        let m = cameraTransform
        let forward = SIMD3(-m[8], -m[9], -m[10])
        let degrees = atan2(forward.x, -forward.z) * 180 / .pi
        return (degrees < 0 ? degrees + 360 : degrees).truncatingRemainder(dividingBy: 360)
    }

    /// Elevation of the camera's forward axis above the horizontal, degrees: `asin(d_y)` (docs/02 §3).
    public var cameraPitchDeg: Double {
        asin(max(-1, min(1, -cameraTransform[9]))) * 180 / .pi
    }
}

/// One magnetometer reading (NorthResolver candidate in the `magnetic` group, docs/05 §2).
public struct HeadingSample: Sendable, Equatable {
    public var trueHeading: Double
    public var magneticHeading: Double
    /// CLHeading.headingAccuracy: negative means invalid.
    public var headingAccuracy: Double
    public var sampledAt: Date
    /// The device orientation the reading was referenced to (`CLLocationManager.headingOrientation`), in
    /// CLDeviceOrientation names: "portrait", "landscapeLeft", "landscapeRight", ... The compass measures from the
    /// top edge of the device, so this is part of the reading, not a display detail.
    public var deviceOrientation: String

    public init(trueHeading: Double, magneticHeading: Double, headingAccuracy: Double, sampledAt: Date,
                deviceOrientation: String = "portrait") {
        self.trueHeading = trueHeading
        self.magneticHeading = magneticHeading
        self.headingAccuracy = headingAccuracy
        self.sampledAt = sampledAt
        self.deviceOrientation = deviceOrientation
    }

    /// CLHeading reports "unavailable" as a negative value on either field.
    public var isValid: Bool { headingAccuracy >= 0 && trueHeading >= 0 }
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
    /// Wall-clock time of the first frame; frame `t` values are offsets from it.
    public var firstFrameAt: Date?
    public var timezone: TimeZone
    public var device: DeviceInfo
    public var appVersion: String
    public var appBuild: String
    public var targetLabel: String
    public var targetHeightM: Double?
    public var frames: [FrameSample]
    /// The lens position the scan is referenced to: the first frame with normal tracking. Nil if tracking never settled.
    public var anchor: SIMD3<Double>?
    public var anchorFrameID: String?
    /// Largest lens offset observed after the anchor locked (docs/04 §4). Nil when never locked.
    public var maxDriftM: Double?
    /// Every heading reading during the session, valid or not.
    public var headings: [HeadingSample]
    public var location: LocationSample?
    public var viewpointToleranceM: Double
    /// ARSession failure or interruption, verbatim, when one happened.
    public var failureReason: String?
    /// The picture the scan is remembered by: the frame that locked the viewpoint, upright. Nil when none was taken.
    public var hero: HeroImage?
    /// The frames kept on this device for analysis (docs/04 §12). Nil when none were kept.
    public var spool: SpoolManifest?

    public init(sessionID: String, startedAt: Date, endedAt: Date, firstFrameAt: Date?, timezone: TimeZone, device: DeviceInfo,
                appVersion: String, appBuild: String, targetLabel: String, targetHeightM: Double?,
                frames: [FrameSample], anchor: SIMD3<Double>?, anchorFrameID: String?, maxDriftM: Double?,
                headings: [HeadingSample], location: LocationSample?, viewpointToleranceM: Double = 0.15,
                failureReason: String? = nil, hero: HeroImage? = nil, spool: SpoolManifest? = nil) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.firstFrameAt = firstFrameAt
        self.timezone = timezone
        self.device = device
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.targetLabel = targetLabel
        self.targetHeightM = targetHeightM
        self.frames = frames
        self.anchor = anchor
        self.anchorFrameID = anchorFrameID
        self.maxDriftM = maxDriftM
        self.headings = headings
        self.location = location
        self.viewpointToleranceM = viewpointToleranceM
        self.failureReason = failureReason
        self.hero = hero
        self.spool = spool
    }

    /// The anchor frame if there is one, else the first frame: never a frame the scan is not referenced to.
    public var heroFrame: FrameSample? {
        if let anchorFrameID, let anchored = frames.first(where: { $0.frameID == anchorFrameID }) { return anchored }
        return frames.first
    }

    /// First valid heading reading of the session (session-start heading, docs/05 §4).
    public var firstValidHeading: HeadingSample? { headings.first(where: \.isValid) }


    public func frameDate(_ frame: FrameSample) -> Date? { firstFrameAt?.addingTimeInterval(frame.t) }
}
