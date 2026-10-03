#if DEBUG
import CaptureCore
import CoreLocation
import Foundation
import SunEngine
import simd

/// Simulator stand-in for the camera (DEBUG only, never on a device): a scripted sweep over the northern sky so the
/// sun-path overlay, coverage, guidance and save path can be seen and UI-tested without ARKit. Δ is exactly 0.
struct SyntheticSweep {
    /// Pretend phone held upright: the view's vertical field of view, like a wide camera in portrait.
    static let verticalFOVDeg = 74.0
    /// Turning speed along the path, well under `ScanCoach.fastTurnDegPerSec`. UI tests can set it with the launch
    /// argument `-syntheticSweepSpeed <deg/s>` (0 keeps the pretend camera still).
    static var speedDegPerSec: Double {
        // Launch arguments arrive as strings; `double(forKey:)` converts them.
        UserDefaults.standard.object(forKey: "syntheticSweepSpeed") == nil ? 32 : UserDefaults.standard.double(forKey: "syntheticSweepSpeed")
    }
    /// Low across the winter path, high across summer noon, low again across summer mornings and evenings.
    /// Azimuths are unwrapped (−125 is 235°) so the path never jumps. `-syntheticSweepPasses 1` stops after the
    /// first pass: the winter path is covered, the all-year path is not.
    static var waypoints: [(az: Double, alt: Double)] {
        let all: [(az: Double, alt: Double)] = [(-85, 14), (85, 14), (125, 48), (-125, 48), (-125, 22), (125, 22)]
        return UserDefaults.standard.integer(forKey: "syntheticSweepPasses") == 1 ? Array(all.prefix(2)) : all
    }

    private(set) var recordingStart: TimeInterval?
    private var frames: [FrameSample] = []
    private var headings: [HeadingSample] = []
    private var startedAt = Date()

    mutating func beginRecording(at t: TimeInterval) {
        recordingStart = t
        frames = []
        headings = []
        startedAt = Date()
    }

    mutating func reset() {
        recordingStart = nil
        frames = []
        headings = []
    }

    /// True once the scripted path has been walked to its end (or it never moves).
    func isFinished(at t: TimeInterval) -> Bool {
        guard let start = recordingStart else { return true }
        let speed = Self.speedDegPerSec
        guard speed > 0 else { return true }
        let total = zip(Self.waypoints, Self.waypoints.dropFirst()).reduce(0.0) { sum, pair in
            sum + ((pair.1.az - pair.0.az) * (pair.1.az - pair.0.az) + (pair.1.alt - pair.0.alt) * (pair.1.alt - pair.0.alt)).squareRoot()
        }
        return (t - start) * speed >= total
    }

    func pose(at t: TimeInterval) -> (az: Double, alt: Double) {
        guard let start = recordingStart else { return (0, 14) }
        var remaining = (t - start) * Self.speedDegPerSec
        for (a, b) in zip(Self.waypoints, Self.waypoints.dropFirst()) {
            let length = ((b.az - a.az) * (b.az - a.az) + (b.alt - a.alt) * (b.alt - a.alt)).squareRoot()
            if remaining <= length {
                let f = remaining / length
                return (Self.wrap(a.az + (b.az - a.az) * f), a.alt + (b.alt - a.alt) * f)
            }
            remaining -= length
        }
        let last = Self.waypoints[Self.waypoints.count - 1]
        return (Self.wrap(last.az), last.alt)
    }

    /// A camera whose image is the view itself, so pixels are view points.
    static func camera(azimuthDeg: Double, altitudeDeg: Double, viewSize: CGSize) -> PinholeCamera {
        let aspect = viewSize.width / max(1, viewSize.height)
        let horizontal = 2 * atan(tan(verticalFOVDeg * .pi / 360) * aspect) * 180 / .pi
        return .looking(azimuthDeg: azimuthDeg, altitudeDeg: altitudeDeg, horizontalFOVDeg: horizontal,
                        imageWidth: viewSize.width, imageHeight: viewSize.height)
    }

    /// Samples the pose like CaptureRecorder does: transform, intrinsics, one compass reading per frame.
    mutating func record(_ camera: PinholeCamera, at t: TimeInterval) {
        guard let start = recordingStart else { return }
        let r = camera.rotation
        let transform = [r.columns.0.x, r.columns.0.y, r.columns.0.z, 0,
                         r.columns.1.x, r.columns.1.y, r.columns.1.z, 0,
                         r.columns.2.x, r.columns.2.y, r.columns.2.z, 0,
                         0, 0, 0, 1]
        let intrinsics = [camera.fx, 0, 0, 0, camera.fy, 0, camera.cx, camera.cy, 1]
        frames.append(FrameSample(frameID: String(format: "f%05d", frames.count), t: t - start, cameraTransform: transform,
                                  intrinsics: intrinsics, trackingState: "normal", lensOffsetM: 0, hasSceneDepth: false,
                                  exposureOffset: 0))
        let heading = SkyDirection.angles(of: camera.forward).azimuthDeg   // Δ = 0: AR azimuth is true azimuth
        headings.append(HeadingSample(trueHeading: heading, magneticHeading: heading, headingAccuracy: 5,
                                      sampledAt: startedAt.addingTimeInterval(t - start)))
    }

    func makeLog(label: String, coordinate: CLLocationCoordinate2D, targetHeightM: Double?) -> CaptureLog? {
        guard let last = frames.last else { return nil }
        let ended = startedAt.addingTimeInterval(last.t + 0.05)
        return CaptureLog(sessionID: UUID().uuidString, startedAt: startedAt, endedAt: ended, firstFrameAt: startedAt,
                          timezone: .current,
                          device: DeviceInfo(model: "simulator", os: "iOS simulator", lidar: false, sceneDepth: false, geoTracking: "unavailable"),
                          appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                          appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
                          targetLabel: label, targetHeightM: targetHeightM, frames: frames, anchor: .zero,
                          anchorFrameID: frames.first?.frameID, maxDriftM: 0, headings: headings,
                          location: LocationSample(latitude: coordinate.latitude, longitude: coordinate.longitude, altitudeM: nil,
                                                   horizontalAccuracyM: 5, verticalAccuracyM: nil, capturedAt: startedAt))
    }

    private static func wrap(_ az: Double) -> Double {
        let r = az.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
#endif
