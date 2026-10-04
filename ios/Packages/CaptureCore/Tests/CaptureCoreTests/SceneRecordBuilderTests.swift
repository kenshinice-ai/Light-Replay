import Foundation
import NorthResolver
import SceneRecord
import XCTest
@testable import CaptureCore

final class SceneRecordBuilderTests: XCTestCase {
    private let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    private let intrinsics: [Double] = [1400, 0, 0, 0, 1400, 0, 960, 720, 1]
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func frame(_ i: Int, offset: Double?, state: String = "normal", x: Double = 0) -> FrameSample {
        var transform = identity
        transform[12] = x
        return FrameSample(frameID: String(format: "f%05d", i), t: Double(i) * 0.1, cameraTransform: transform, intrinsics: intrinsics,
                           trackingState: state, lensOffsetM: offset, hasSceneDepth: i > 0, exposureOffset: 0)
    }

    private func sampleLog(frames: [FrameSample]? = nil, anchor: SIMD3<Double>? = SIMD3(0, 0, 0), anchorFrameID: String? = "f00000",
                           headings: [HeadingSample]? = nil) -> CaptureLog {
        let defaultFrames = (0..<3).map { frame($0, offset: Double($0) * 0.05, x: Double($0) * 0.05) }
        return CaptureLog(
            sessionID: "S-TEST", startedAt: start, endedAt: start.addingTimeInterval(20), firstFrameAt: start.addingTimeInterval(0.5),
            timezone: TimeZone(identifier: "Australia/Melbourne")!,
            device: DeviceInfo(model: "iPhone99,9", os: "iOS 27.0", lidar: true, sceneDepth: true, geoTracking: "unavailable"),
            appVersion: "0.1.0", appBuild: "1", targetLabel: "Synthetic test target, not a real property", targetHeightM: nil,
            frames: frames ?? defaultFrames, anchor: anchor, anchorFrameID: anchorFrameID,
            maxDriftM: (frames ?? defaultFrames).compactMap(\.lensOffsetM).max(),
            headings: headings ?? [HeadingSample(trueHeading: 8.2, magneticHeading: 19.9, headingAccuracy: 12, sampledAt: start.addingTimeInterval(0.6))],
            location: LocationSample(latitude: -37.8136, longitude: 144.9631, altitudeM: 31, horizontalAccuracyM: 8, verticalAccuracyM: 5, capturedAt: start)
        )
    }

    private func object(_ value: JSONValue?) -> [String: JSONValue] {
        if case .object(let o) = value ?? .null { return o }
        return [:]
    }

    func testCaptureOnlyRecordPassesValidator() throws {
        let document = try SceneRecordBuilder.build(sampleLog(), sceneID: "PR-20260930-01")
        let reparsed = try SceneRecordDocument(data: try document.encoded())
        XCTAssertEqual(reparsed.fields["scene_id"], .string("PR-20260930-01"))
        let quality = object(reparsed.fields["quality"])
        XCTAssertEqual(quality["level"], .string("R0"))
        XCTAssertEqual(quality["false_valid_guard"], .string("blocked"))
        XCTAssertEqual(object(quality["gates"])["lens"], .string("blocked"))
        XCTAssertEqual(reparsed.fields["analysis"], .array([]))
    }

    /// What Save writes is schema 0.2.0 at revision 0 (ADR-0022): nothing analysed, every check still to run, and
    /// the lights exactly the ones the evaluator gives for that — which, with the horizon unchecked, blocks `level`.
    func testTheSavedRecordIsSchema2AtRevisionZero() throws {
        let document = try SceneRecordBuilder.build(sampleLog(), sceneID: "PR-20261004-01")
        let fields = try SceneRecordDocument(data: try document.encoded()).fields
        XCTAssertEqual(fields["schema_version"], .string("0.2.0"))
        let result = object(fields["result"])
        XCTAssertEqual(result["revision"], .number(0))
        XCTAssertEqual(result["inputs_hash"], .null)
        XCTAssertEqual(result["capture_digest"], .string("no-frames-kept"))
        let gates = object(object(fields["quality"])["gates"]).mapValues { $0 == .string("blocked") }
        XCTAssertEqual(gates, ["coverage": true, "north": true, "segmentation": true, "level": true, "lens": true])
        XCTAssertEqual(object(object(object(fields["quality"])["evidence"])["lens"])["status"], .string("not_run"))
        let session = object(fields["capture_session"])
        XCTAssertEqual(session["keyframes"], .array([]))
        if case .array(let frames)? = session["frames"] {
            XCTAssertTrue(frames.allSatisfy { object($0)["role"] == .string("visibility") })
        } else { XCTFail("no frames") }
        XCTAssertEqual(object(session["hero_frame"])["image"], .null, "no hero was taken in this log")
        // The same candidates give the same north digest; the time the record was built does not enter it.
        let later = try SceneRecordBuilder.build(sampleLog(), sceneID: "PR-20261004-01", createdAt: Date().addingTimeInterval(500))
        XCTAssertEqual(object(later.fields["result"])["north_digest"], result["north_digest"])
    }

    func testAHeroAndASpoolAreDescribedAndTheRecordStillValidates() throws {
        var log = sampleLog()
        let stored = StoredImage(file: nil, nativeWidth: 1920, nativeHeight: 1440, encodedWidth: 1440, encodedHeight: 1920, scale: 1, rotationDeg: 90,
                                 byteCount: 900_000, sha256: String(repeating: "a", count: 64))
        log.hero = HeroImage(data: Data(count: 4), image: stored, frameID: "f00000")
        let picture = StoredImage(file: "f00001.jpg", nativeWidth: 1920, nativeHeight: 1440, encodedWidth: 960, encodedHeight: 720, scale: 0.5,
                                  rotationDeg: 0, byteCount: 120_000, sha256: String(repeating: "b", count: 64))
        log.spool = SpoolManifest(sessionID: log.sessionID, createdAt: start, truncated: false,
                                  frames: [SpoolFrame(frameID: "f00001", timestamp: 10.1, t: 0.1, cameraTransform: identity, intrinsics: intrinsics, image: picture,
                                                      depth: nil, exposureOffset: 0, lensOffsetM: 0.05, turnRateDegPerSec: 5, role: "visibility")],
                                  hero: stored, heroFrameID: "f00000", expiresAt: start.addingTimeInterval(FrameSpool.retention))
        let fields = try SceneRecordDocument(data: try SceneRecordBuilder.build(log, sceneID: "PR-20261004-02").encoded()).fields
        let image = object(object(object(fields["capture_session"])["hero_frame"])["image"])
        XCTAssertEqual(image["storage"], .string("row.photo"))
        XCTAssertEqual(image["rotation_deg"], .number(90))
        XCTAssertEqual(image["encoded_size"], .array([.number(1440), .number(1920)]))
        XCTAssertEqual(object(fields["result"])["capture_digest"], .string(log.spool!.digest))
        // A hero whose stated scale does not give its stated size is refused by the validator, not written.
        log.hero?.image.scale = 0.5
        XCTAssertThrowsError(try SceneRecordBuilder.build(log, sceneID: "PR-20261004-03"))
    }

    func testViewpointLockCountsOnlyFramesWithAnOffset() throws {
        // f0 has no offset (pre-lock), then 0.05 … 0.20
        var frames = [frame(0, offset: nil, state: "limited:initializing")]
        frames += (1...5).map { frame($0, offset: Double($0 - 1) * 0.05, x: Double($0 - 1) * 0.05) }
        let log = sampleLog(frames: frames, anchor: SIMD3(0, 0, 0), anchorFrameID: "f00001")
        let document = try SceneRecordBuilder.build(log, sceneID: "PR-20260930-02")
        let lock = object(object(document.fields["capture_session"])["viewpoint_lock"])
        XCTAssertEqual(lock["frames_within"], .number(4))   // 0, .05, .10, .15
        XCTAssertEqual(lock["frames_beyond"], .number(1))   // .20
        XCTAssertEqual(lock["max_drift_m"], .number(0.2))
        XCTAssertEqual(lock["handling"], .string("tolerated"))
        let hero = object(object(document.fields["capture_session"])["hero_frame"])
        XCTAssertEqual(hero["frame_id"], .string("f00001"), "hero is the anchor frame, not the pre-lock frame")
    }

    func testNeverLockedIsRejectedAndNullOffsets() throws {
        let frames = (0..<3).map { frame($0, offset: nil, state: "limited:initializing") }
        let log = sampleLog(frames: frames, anchor: nil, anchorFrameID: nil)
        let document = try SceneRecordBuilder.build(log, sceneID: "PR-20260930-03")
        let session = object(document.fields["capture_session"])
        XCTAssertEqual(object(session["viewpoint_lock"])["handling"], .string("rejected"))
        XCTAssertEqual(object(session["viewpoint_lock"])["max_drift_m"], .null)
        if case .array(let frameValues) = session["frames"] ?? .null {
            XCTAssertEqual(object(frameValues.first)["lens_offset_m"], .null)
        } else { XCTFail("frames missing") }
        if case .array(let flags) = object(document.fields["quality"])["flags"] ?? .null {
            XCTAssertTrue(flags.contains(.string("anchor_never_locked")))
        }
    }

    func testNegativeTrueHeadingIsInvalidCandidate() throws {
        let log = sampleLog(headings: [HeadingSample(trueHeading: -1, magneticHeading: 20, headingAccuracy: 5, sampledAt: start)])
        let document = try SceneRecordBuilder.build(log, sceneID: "PR-20260930-04")
        let candidates = object(document.fields["north"])["candidates"]
        guard case .array(let list) = candidates ?? .null, let first = list.first else { return XCTFail("candidate missing") }
        XCTAssertEqual(object(first)["valid"], .bool(false))
        XCTAssertEqual(object(first)["yaw_deg"], .null)
    }

    func testYawIsHeadingMinusCameraAzimuth() throws {
        // Camera rotated +90° about +Y: R = [[0,0,1],[0,1,0],[-1,0,0]] (row-major), so forward (0,0,-1) → (-1,0,0)
        // and az_ar = atan2(-1, 0) = 270°. Column-major storage: column 0 = (0,0,-1), column 2 = (1,0,0).
        var transform = identity
        transform[0] = 0; transform[2] = -1; transform[8] = 1; transform[10] = 0
        let f = FrameSample(frameID: "f00000", t: 0, cameraTransform: transform, intrinsics: intrinsics, trackingState: "normal",
                            lensOffsetM: 0, hasSceneDepth: false, exposureOffset: 0)
        XCTAssertEqual(f.cameraAzimuthAR, 270, accuracy: 1e-9)
        let heading = HeadingSample(trueHeading: 300, magneticHeading: 288, headingAccuracy: 10, sampledAt: start.addingTimeInterval(0.5))
        let log = sampleLog(frames: [f], headings: [heading])
        let document = try SceneRecordBuilder.build(log, sceneID: "PR-20260930-05")
        guard case .array(let list) = object(document.fields["north"])["candidates"] ?? .null, let first = list.first else { return XCTFail() }
        XCTAssertEqual(object(first)["yaw_deg"], .number(30))   // (300 − 270) mod 360
        XCTAssertEqual(object(object(first)["raw"])["camera_az_ar_deg"], .number(270))
    }

    func testHeadingWithoutSynchronisedPoseIsInvalid() throws {
        let heading = HeadingSample(trueHeading: 10, magneticHeading: 0, headingAccuracy: 5, sampledAt: start.addingTimeInterval(30))
        let document = try SceneRecordBuilder.build(sampleLog(headings: [heading]), sceneID: "PR-20260930-06")
        guard case .array(let list) = object(document.fields["north"])["candidates"] ?? .null, let first = list.first else { return XCTFail() }
        XCTAssertEqual(object(first)["valid"], .bool(false))
    }

    // MARK: Compass samples (review R08)

    /// A frame looking along AR azimuth `azimuth`, tilted `pitch` degrees above the horizontal, `t` seconds in.
    private func pose(_ i: Int, t: Double, azimuth: Double, pitch: Double = 0, state: String = "normal") -> FrameSample {
        var transform = identity
        let a = azimuth * .pi / 180, p = pitch * .pi / 180
        // forward = (sin a cos p, sin p, −cos a cos p) and the transform's third column is −forward.
        transform[8] = -sin(a) * cos(p); transform[9] = -sin(p); transform[10] = cos(a) * cos(p)
        return FrameSample(frameID: String(format: "f%05d", i), t: t, cameraTransform: transform, intrinsics: intrinsics,
                           trackingState: state, lensOffsetM: 0, hasSceneDepth: false, exposureOffset: 0)
    }

    private func heading(_ value: Double, accuracy: Double = 5, at seconds: Double) -> HeadingSample {
        HeadingSample(trueHeading: value, magneticHeading: value, headingAccuracy: accuracy, sampledAt: start.addingTimeInterval(0.5 + seconds))
    }

    private func magnetic(_ document: SceneRecordDocument) -> [String: JSONValue] {
        guard case .array(let list) = object(document.fields["north"])["candidates"] ?? .null else { return [:] }
        return object(list.first)
    }

    private func number(_ value: JSONValue?) -> Double {
        if case .number(let n) = value ?? .null { return n }
        return .nan
    }

    func testEveryCompassReadingIsKeptAndTheCandidateIsTheirMedian() throws {
        // The phone turns through five azimuths; the true azimuth of −Z is 30 throughout, read as 28, 29, 30, 31, 47.
        let azimuths: [Double] = [0, 40, 80, 320, 280], deltas: [Double] = [28, 29, 30, 31, 47]
        let frames = azimuths.enumerated().map { pose($0.offset, t: Double($0.offset), azimuth: $0.element) }
        let headings = zip(azimuths, deltas).enumerated().map { heading(($0.element.0 + $0.element.1).truncatingRemainder(dividingBy: 360), at: Double($0.offset)) }
        let document = try SceneRecordBuilder.build(sampleLog(frames: frames, headings: headings), sceneID: "PR-20261001-01")
        let candidate = magnetic(document), raw = object(candidate["raw"])
        XCTAssertEqual(candidate["valid"], .bool(true))
        XCTAssertEqual(number(candidate["yaw_deg"]), 30, accuracy: 1e-9, "the median, not the first reading and not pulled by the outlier")
        guard case .array(let samples) = raw["samples"] ?? .null else { return XCTFail("samples missing") }
        XCTAssertEqual(samples.count, 5, "every reading is kept")
        XCTAssertEqual(samples.map { number(object($0)["yaw_deg"]).rounded() }, deltas)
        XCTAssertEqual(object(raw["merged"])["samples_used"], .number(5))
        let spread = ((4 + 1 + 0 + 1 + 289) / 5.0).squareRoot()   // offsets −2, −1, 0, 1, 17 about the median
        XCTAssertEqual(number(object(raw["merged"])["spread_deg"]), spread, accuracy: 1e-9)
        XCTAssertEqual(number(candidate["sigma_deg"]), 8, accuracy: 1e-9, "the 8 degree prior is larger than this spread")
        XCTAssertEqual(number(raw["true_heading"]), 28, accuracy: 1e-9, "the session-start reading stays where readers expect it")
    }

    func testAWanderingCompassSaysSoInItsSigma() throws {
        // Reported accuracy 5, but the readings disagree by tens of degrees as the phone turns.
        let azimuths: [Double] = [0, 60, 120, 180, 240], deltas: [Double] = [10, 35, 60, 85, 110]
        let frames = azimuths.enumerated().map { pose($0.offset, t: Double($0.offset), azimuth: $0.element) }
        let headings = zip(azimuths, deltas).enumerated().map { heading(($0.element.0 + $0.element.1).truncatingRemainder(dividingBy: 360), at: Double($0.offset)) }
        let candidate = magnetic(try SceneRecordBuilder.build(sampleLog(frames: frames, headings: headings), sceneID: "PR-20261001-02"))
        XCTAssertEqual(number(candidate["yaw_deg"]), 60, accuracy: 1e-9)
        XCTAssertEqual(number(candidate["sigma_deg"]), (2500.0 / 2).squareRoot(), accuracy: 1e-9)   // RMS of −50, −25, 0, 25, 50
    }

    func testReadingsTakenLookingSteeplyUpAreKeptButNotMerged() throws {
        let frames = [pose(0, t: 0, azimuth: 10), pose(1, t: 1, azimuth: 10, pitch: 70), pose(2, t: 2, azimuth: 10)]
        let headings = [heading(40, at: 0), heading(200, at: 1), heading(42, at: 2)]
        let candidate = magnetic(try SceneRecordBuilder.build(sampleLog(frames: frames, headings: headings), sceneID: "PR-20261001-03"))
        XCTAssertEqual(number(candidate["yaw_deg"]), 31, accuracy: 1e-9, "median of 30 and 32; the reading at 70 degrees of pitch is left out")
        let raw = object(candidate["raw"])
        guard case .array(let samples) = raw["samples"] ?? .null else { return XCTFail("samples missing") }
        XCTAssertEqual(samples.map { object($0)["used"] }, [.bool(true), .bool(false), .bool(true)])
        XCTAssertEqual(number(object(samples[1])["camera_pitch_deg"]), 70, accuracy: 1e-9)
        XCTAssertEqual(object(raw["merged"])["samples_used"], .number(2))
        XCTAssertEqual(object(raw["merged"])["samples_total"], .number(3))
        XCTAssertEqual(object(raw["merged"])["readings_seen"], .number(3))

        let steep = [pose(0, t: 0, azimuth: 10, pitch: 65)]
        let none = magnetic(try SceneRecordBuilder.build(sampleLog(frames: steep, headings: [heading(40, at: 0)]), sceneID: "PR-20261001-04"))
        XCTAssertEqual(none["valid"], .bool(false))
        XCTAssertEqual(none["yaw_deg"], .null)
        guard case .array(let kept) = object(none["raw"])["samples"] ?? .null else { return XCTFail("samples missing") }
        XCTAssertEqual(kept.count, 1, "the reading is still on record")
    }

    func testReadingsAreTiedToTrackedPosesOnly() throws {
        // The pose nearest the second reading has limited tracking; the next tracked pose is over a second away.
        let frames = [pose(0, t: 0, azimuth: 0), pose(1, t: 3, azimuth: 90, state: "limited:excessive_motion"), pose(2, t: 6, azimuth: 180)]
        let headings = [heading(20, at: 0.2), heading(110, at: 3), heading(200, at: 5.6)]
        let raw = object(magnetic(try SceneRecordBuilder.build(sampleLog(frames: frames, headings: headings), sceneID: "PR-20261001-05"))["raw"])
        guard case .array(let samples) = raw["samples"] ?? .null else { return XCTFail("samples missing") }
        XCTAssertEqual(samples.map { object($0)["frame_id"] }, [.string("f00000"), .string("f00002")])
        XCTAssertEqual(number(object(samples[1])["pose_gap_s"]), 0.4, accuracy: 1e-6)   // wall-clock dates carry about 1e-7 s
        XCTAssertEqual(object(raw["merged"])["readings_seen"], .number(3), "the reading with no tracked pose is counted, not hidden")
        XCTAssertEqual(object(raw["merged"])["samples_total"], .number(2))
    }

    func testALongSweepIsMergedQuickly() throws {
        // 60 s at 60 frames a second with a heading every 30 ms: the size of a slow real scan.
        let frames = (0..<3600).map { pose($0, t: Double($0) / 60, azimuth: Double($0) * 0.1) }
        let headings = (0..<2000).map { i -> HeadingSample in
            let t = Double(i) * 0.03
            return heading((t * 6 + 45).truncatingRemainder(dividingBy: 360), at: t)   // azimuth is 6 degrees a second
        }
        var log = sampleLog(frames: frames, headings: headings)
        log.endedAt = start.addingTimeInterval(61)
        let started = Date()
        let candidate = magnetic(try SceneRecordBuilder.build(log, sceneID: "PR-20261001-07"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "building a record must not make saving feel stuck")
        XCTAssertEqual(number(candidate["yaw_deg"]), 45, accuracy: 0.11, "each heading meets the frame within 1/120 s of it")
        XCTAssertEqual(object(object(candidate["raw"])["merged"])["samples_total"], .number(2000))
    }

    func testTheNorthLightIsStatedAsTheEvidenceGivesIt() throws {
        let document = try SceneRecordBuilder.build(sampleLog(), sceneID: "PR-20261001-06")
        let reparsed = try SceneRecordDocument(data: try document.encoded())   // the validator recomputes the light
        XCTAssertEqual(object(object(reparsed.fields["quality"])["gates"])["north"], .string("blocked"), "one compass group, sigma 12")
        XCTAssertEqual(object(reparsed.fields["north"])["resolved"], .null, "a direction that needs confirming is not written as resolved")
        XCTAssertEqual(object(object(reparsed.fields["app"])["algorithms"])["north"], .string(NorthResolver.version))
        XCTAssertEqual(QualityEvaluator.evaluate(reparsed.fields).north.needsConfirmation, true)
    }

    func testNoFramesStillValidates() throws {
        var log = sampleLog(frames: [], anchor: nil, anchorFrameID: nil, headings: [])
        log.location = nil
        XCTAssertNoThrow(try SceneRecordBuilder.build(log, sceneID: "PR-20260930-07"))
    }

    func testSceneIDsComeFromDisk() throws {
        let tz = TimeZone(identifier: "Australia/Melbourne")!
        let date = ISO8601DateFormatter().date(from: "2026-09-30T23:30:00+10:00")!
        XCTAssertEqual(SceneRecordBuilder.sceneID(date: date, sequence: 7, timezone: tz), "PR-20260930-07")
        let root = FileManager.default.temporaryDirectory.appending(path: "scenes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(try SceneRecordBuilder.nextSceneID(in: root, date: date, timezone: tz), "PR-20260930-01")
        try FileManager.default.createDirectory(at: root.appending(path: "PR-20260930-01"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "PR-20260930-03"), withIntermediateDirectories: true)
        XCTAssertEqual(try SceneRecordBuilder.nextSceneID(in: root, date: date, timezone: tz), "PR-20260930-04")
    }
}
