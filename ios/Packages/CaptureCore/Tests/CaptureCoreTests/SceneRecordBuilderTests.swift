import Foundation
import SceneRecord
import XCTest
@testable import CaptureCore

final class SceneRecordBuilderTests: XCTestCase {
    private func sampleLog(frames: Int = 3) -> CaptureLog {
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let intrinsics: [Double] = [1400, 0, 0, 0, 1400, 0, 960, 720, 1]
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return CaptureLog(
            sessionID: "S-TEST",
            startedAt: start,
            endedAt: start.addingTimeInterval(20),
            timezone: TimeZone(identifier: "Australia/Melbourne")!,
            device: DeviceInfo(model: "iPhone99,9", os: "iOS 27.0", lidar: true, sceneDepth: true, geoTracking: "unavailable"),
            appVersion: "0.1.0", appBuild: "1",
            targetLabel: "Synthetic test target, not a real property",
            targetHeightM: nil,
            frames: (0..<frames).map { i in
                var transform = identity
                transform[12] = Double(i) * 0.05   // drift 0, 5 cm, 10 cm …
                return FrameSample(frameID: "f\(i)", t: Double(i) * 0.1, cameraTransform: transform, intrinsics: intrinsics,
                                   trackingState: "normal", lensOffsetM: Double(i) * 0.05, hasSceneDepth: i > 0, exposureOffset: 0)
            },
            heading: HeadingSample(trueHeading: 8.2, magneticHeading: 19.9, headingAccuracy: 12, sampledAt: start),
            location: LocationSample(latitude: -37.8136, longitude: 144.9631, altitudeM: 31, horizontalAccuracyM: 8, verticalAccuracyM: 5, capturedAt: start)
        )
    }

    func testCaptureOnlyRecordPassesValidator() throws {
        let document = try SceneRecordBuilder.build(sampleLog(), sceneID: "PR-20260930-01")
        let data = try document.encoded()
        // Round trip through the strict decoder: duplicate keys, nesting and schema are all re-checked.
        let reparsed = try SceneRecordDocument(data: data)
        XCTAssertEqual(reparsed.fields["scene_id"], .string("PR-20260930-01"))
        guard case .object(let quality) = reparsed.fields["quality"] ?? .null else { return XCTFail("quality missing") }
        XCTAssertEqual(quality["level"], .string("R0"))
        XCTAssertEqual(quality["false_valid_guard"], .string("blocked"))
        XCTAssertEqual(reparsed.fields["analysis"], .array([]))
    }

    func testViewpointLockCountsFramesAgainstTolerance() throws {
        var log = sampleLog(frames: 5)   // offsets 0, .05, .10, .15, .20
        log.viewpointToleranceM = 0.15
        let document = try SceneRecordBuilder.build(log, sceneID: "PR-20260930-02")
        guard case .object(let session) = document.fields["capture_session"] ?? .null,
              case .object(let lock) = session["viewpoint_lock"] ?? .null else { return XCTFail("viewpoint_lock missing") }
        XCTAssertEqual(lock["frames_within"], .number(4))
        XCTAssertEqual(lock["frames_beyond"], .number(1))
        XCTAssertEqual(lock["max_drift_m"], .number(0.2))
    }

    func testInvalidHeadingBecomesInvalidCandidate() throws {
        var log = sampleLog()
        log.heading = HeadingSample(trueHeading: 0, magneticHeading: 0, headingAccuracy: -1, sampledAt: log.startedAt)
        let document = try SceneRecordBuilder.build(log, sceneID: "PR-20260930-03")
        guard case .object(let north) = document.fields["north"] ?? .null,
              case .array(let candidates) = north["candidates"] ?? .null,
              case .object(let magnetic) = candidates.first ?? .null else { return XCTFail("candidate missing") }
        XCTAssertEqual(magnetic["valid"], .bool(false))
        XCTAssertEqual(magnetic["yaw_deg"], .null)
    }

    func testNoFramesStillValidates() throws {
        var log = sampleLog(frames: 0)
        log.location = nil
        log.heading = nil
        XCTAssertNoThrow(try SceneRecordBuilder.build(log, sceneID: "PR-20260930-04"))
    }

    func testSceneIDFormat() {
        let tz = TimeZone(identifier: "Australia/Melbourne")!
        let date = ISO8601DateFormatter().date(from: "2026-09-30T23:30:00+10:00")!
        XCTAssertEqual(SceneRecordBuilder.sceneID(date: date, sequence: 7, timezone: tz), "PR-20260930-07")
    }
}
