#if DEBUG
import CaptureCore
import CoreLocation
import Foundation
import SunEngine
import UIKit
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

    /// The pretend world, for the frames the pretend camera keeps: sky above a flat horizon, and one block of flats
    /// to the north-east that stands 25° high. Whether a direction is sky is therefore known exactly, which is what
    /// lets the analysis be tested end to end in the simulator.
    static func isSky(azimuthDeg: Double, altitudeDeg: Double) -> Bool {
        altitudeDeg > ((20...50).contains(azimuthDeg) ? 25 : 0)
    }

    /// The pretend world as the camera of `frame` sees it, drawn at `scale` of the frame's own size.
    static func picture(of frame: FrameSample, scale: Double) -> (jpeg: Data, width: Int, height: Int, nativeWidth: Int, nativeHeight: Int)? {
        let m = frame.cameraTransform, k = frame.intrinsics
        let nativeWidth = Int((k[6] * 2).rounded()), nativeHeight = Int((k[7] * 2).rounded())
        let width = max(1, Int(Double(nativeWidth) * scale)), height = max(1, Int(Double(nativeHeight) * scale))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for v in 0..<height {
            for u in 0..<width {
                // docs/02 §3: the ray of a pixel of the sensor image, in the camera's axes (x right, y up, looking along −z).
                let x = ((Double(u) + 0.5) / scale - k[6]) / k[0], y = -((Double(v) + 0.5) / scale - k[7]) / k[4]
                let world = SIMD3(m[0] * x + m[4] * y - m[8], m[1] * x + m[5] * y - m[9], m[2] * x + m[6] * y - m[10])
                let angles = SkyDirection.angles(of: simd_normalize(world))
                let at = (v * width + u) * 4
                if isSky(azimuthDeg: angles.azimuthDeg, altitudeDeg: angles.altitudeDeg) {
                    let fade = UInt8(min(90, max(0, 90 - angles.altitudeDeg)))   // paler towards the horizon
                    (pixels[at], pixels[at + 1], pixels[at + 2]) = (70 + fade, 130 + fade, 235)
                } else if angles.altitudeDeg > 0 {
                    (pixels[at], pixels[at + 1], pixels[at + 2]) = (96, 92, 86)      // the block of flats
                } else {
                    (pixels[at], pixels[at + 1], pixels[at + 2]) = (62, 70, 52)      // ground
                }
            }
        }
        let image: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        guard let image, let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { return nil }
        return (jpeg, width, height, nativeWidth, nativeHeight)
    }

    /// The log, with a hero and a spool drawn from the pretend world: about three frames a second, as on a device.
    func makeLog(label: String, coordinate: CLLocationCoordinate2D, targetHeightM: Double?) async -> CaptureLog? {
        guard let last = frames.last, let first = frames.first else { return nil }
        let ended = startedAt.addingTimeInterval(last.t + 0.05)
        let session = UUID().uuidString
        var kept: (manifest: SpoolManifest?, hero: HeroImage?)?
        if let writer = try? FrameSpoolWriter(sessionID: session) {
            if let hero = Self.picture(of: first, scale: 1) {
                writer.setHero(jpeg: hero.jpeg, width: hero.width, height: hero.height, frameID: first.frameID)
            }
            var lastT = -1.0
            for frame in frames where frame.t - lastT >= SpoolAdmission.intervalS {
                guard let drawn = Self.picture(of: frame, scale: 0.5) else { continue }
                let meta = FrameSpoolWriter.Meta(frameID: frame.frameID, timestamp: frame.t, t: frame.t, cameraTransform: frame.cameraTransform,
                                                 intrinsics: frame.intrinsics, exposureOffset: 0, lensOffsetM: 0, turnRateDegPerSec: Self.speedDegPerSec)
                while !writer.offer(jpeg: drawn.jpeg, width: drawn.width, height: drawn.height, native: (drawn.nativeWidth, drawn.nativeHeight), meta: meta) {
                    try? await Task.sleep(for: .milliseconds(5))   // the writer refuses when busy; nothing here is in a hurry
                    if Task.isCancelled { break }
                }
                lastT = frame.t
            }
            kept = await writer.finish()
            if kept?.manifest == nil { writer.discard() }
        }
        return CaptureLog(sessionID: session, startedAt: startedAt, endedAt: ended, firstFrameAt: startedAt,
                          timezone: .current,
                          device: DeviceInfo(model: "simulator", os: "iOS simulator", lidar: false, sceneDepth: false, geoTracking: "unavailable"),
                          appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                          appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
                          targetLabel: label, targetHeightM: targetHeightM, frames: frames, anchor: .zero,
                          anchorFrameID: frames.first?.frameID, maxDriftM: 0, headings: headings,
                          location: LocationSample(latitude: coordinate.latitude, longitude: coordinate.longitude, altitudeM: nil,
                                                   horizontalAccuracyM: 5, verticalAccuracyM: nil, capturedAt: startedAt),
                          hero: kept?.hero, spool: kept?.manifest)
    }

    private static func wrap(_ az: Double) -> Double {
        let r = az.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
#endif
