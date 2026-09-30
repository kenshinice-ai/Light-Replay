import Foundation
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
