import Foundation
import XCTest
@testable import SceneRecord

// Synthetic software checks only. None of these inputs or assets are field-validated.
final class SceneRecordTests: XCTestCase {
    private var fixtureURL: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("engine/tests/fixtures/scene-r0.json")
    }

    private func fixture() throws -> [String: JSONValue] {
        try SceneRecordDocument(data: Data(contentsOf: fixtureURL)).fields
    }

    private func json(_ value: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))
    }

    private func replacing(_ value: JSONValue, _ parts: ArraySlice<String>, _ replacement: JSONValue) -> JSONValue {
        guard let key = parts.first else { return replacement }
        switch value {
        case .object(var fields):
            fields[key] = replacing(fields[key] ?? .null, parts.dropFirst(), replacement)
            return .object(fields)
        case .array(var items):
            let index = Int(key)!
            items[index] = replacing(items[index], parts.dropFirst(), replacement)
            return .array(items)
        default: preconditionFailure("Invalid test mutation path")
        }
    }

    private func changed(_ fields: [String: JSONValue], _ path: String, _ value: JSONValue) -> [String: JSONValue] {
        guard case .object(let result) = replacing(.object(fields), path.components(separatedBy: ".")[...], value) else { preconditionFailure() }
        return result
    }

    private func ready() throws -> [String: JSONValue] {
        var r = try fixture()
        r = changed(r, "target.height_m", .number(1.15))
        r = changed(r, "target.confirmed_by", .string("user"))
        r = changed(r, "app.algorithms", try json("""
        {"sun":"synthetic-test-only","north":"synthetic-test-only","segmentation":"synthetic-test-only","visibility":"synthetic-test-only"}
        """))
        r = changed(r, "capture_session.frames.0.mask_ref", .string("masks/synthetic-frame-001.png"))
        r = changed(r, "capture_session.frames.0.used_for_visibility", .bool(true))
        r = changed(r, "north.candidates.0.yaw_deg", .number(0))
        r = changed(r, "north.candidates.0.sigma_deg", .number(2))
        r = changed(r, "north.candidates.0.valid", .bool(true))
        r = changed(r, "north.candidates.0.raw.true_heading", .number(0))
        r = changed(r, "north.candidates.0.raw.magnetic_heading", .number(0))
        r = changed(r, "north.candidates.0.raw.heading_accuracy", .number(2))
        r = changed(r, "north.resolved", try json("""
        {"yaw_deg":0,"sigma_deg":2,"method":"synthetic-input-not-a-resolver","groups_used":["magnetic"],"groups_rejected":[],"conflict":false,"conflict_detail":null,"resolved_at":"2026-09-21T10:42:12+10:00"}
        """))
        r["visibility"] = try json("""
        {"grid":{"az_step_deg":1,"alt_step_deg":1,"az_frame":"ar_world","alt_range":[-10,90]},
         "states_ref":"visibility/states.png","confidence_ref":"visibility/confidence.png","votes":{"sky":10},
         "coverage":{"corridor_cells":10,"unknown_cells":1,"glass_cells":0,"covered_cells":9,"coverage_pct":0.9},
         "segmentation":{"model":"synthetic-test-only","glass_detected":false,"reflection_flags":[],"manual_edits":[]},"near_field":null}
        """ )
        r["quality"] = try json("""
        {"level":"R1","gates":{"level":"pass","coverage":"pass","north":"warn","segmentation":"pass","lens":"pass"},"flags":["synthetic_fixture"],"false_valid_guard":"passed","blocked_reason":null}
        """ )
        r["analysis"] = try json("""
        [{"query":{"date_from":"2026-06-21","date_to":"2026-06-21","time_window":["10:00","12:00"],"scenario":"current"},
          "bands":[{"date":"2026-06-21","segments":[{"from":"10:00","to":"11:00","state":"sensitive"}]}],
          "heatmap_ref":null,"attribution":[],"uncertainty":{"yaw_sigma_deg":2,"samples":1,"boundary_jitter_deg":0},
          "versions":{"inputs_hash":"synthetic-placeholder-not-a-real-hash","sun":"synthetic-test-only"},"computed_at":"2026-09-21T10:42:13+10:00"}]
        """ )
        return r
    }

    func testSharedSyntheticFixture() throws {
        let r = try fixture()
        XCTAssertEqual(r["scene_id"], .string("SYNTHETIC-R0-001"))
        XCTAssertEqual(r["analysis"], .array([]))
        XCTAssertEqual(r["geometry"], .null)
    }

    func testFixedPublicAPIAndAllJSONValueCases() throws {
        let value: JSONValue = .object(["array": .array([.string("fictional"), .number(1.5), .bool(false), .null])])
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
        let document = try SceneRecordDocument(fields: fixture())
        XCTAssertEqual(try SceneRecordDocument(data: document.encoded()).fields, document.fields)
    }

    func testNullAndUnknownSourceRoundtrip() throws {
        var r = try fixture()
        r = changed(r, "north.candidates.0.raw.future_source", try json("""
        {"missing":null,"samples":[null,0,false,"fictional"]}
        """))
        r["unknown_root"] = .array([.null, .object(["custom": .string("retained")])])
        for pretty in [true, false] {
            let data = try SceneRecordDocument(fields: r).encoded(prettyPrinted: pretty)
            XCTAssertEqual(try SceneRecordDocument(data: data).fields, r)
        }
    }

    func testPartialR0NullRoots() throws {
        var r = try fixture()
        for key in ["geometry", "location", "target", "capture_session", "visibility"] { r[key] = .null }
        XCTAssertEqual(try SceneRecordDocument(data: SceneRecordDocument(fields: r).encoded()).fields, r)
    }

    func testNullAlgorithmVersionsAndFrameRefs() throws {
        var r = try fixture()
        r = changed(r, "capture_session.hero_frame.image_ref", .null)
        r = changed(r, "capture_session.frames.0.image_ref", .null)
        XCTAssertEqual(try SceneRecordDocument(data: SceneRecordDocument(fields: r).encoded()).fields, r)
    }

    func testAllRequiredRootKeys() throws {
        let r = try fixture()
        for key in r.keys {
            var missing = r
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try SceneRecordDocument(fields: missing), key)
        }
    }

    func testMissingExplicitSensorNullIsNotDefaulted() throws {
        let r = try fixture()
        guard case .object(let capture) = r["capture_session"], case .array(let frames) = capture["frames"], case .object(let frame) = frames[0] else { return XCTFail() }
        for key in ["mask_ref", "depth_ref", "depth_confidence_ref"] {
            var missing = frame
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, "capture_session.frames.0", .object(missing))), key)
        }
    }

    func testMalformedShapesAndVocabulary() throws {
        let r = try fixture()
        let cases: [(String, JSONValue)] = [
            ("schema_version", .string("0.2.0")), ("scene_id", .string("")), ("analysis", .object([:])),
            ("north", .null), ("app.algorithms", .array([])), ("device.lidar", .number(1)),
            ("location.lat", .number(90.1)), ("location.lon", .number(-180.1)),
            ("location.h_acc_m", .number(-1)), ("location.v_acc_m", .bool(true)), ("location.alt_m", .string("unknown")),
            ("target.height_m", .number(-1)), ("target.anchor_world", .array([.number(0), .number(1)])),
            ("capture_session.hero_frame.camera_transform", .array(Array(repeating: .number(1), count: 15))),
            ("capture_session.frames.0.camera_transform", .array(Array(repeating: .array(Array(repeating: .number(1), count: 4)), count: 4))),
            ("capture_session.frames.0.intrinsics", .array(Array(repeating: .number(1), count: 8))),
            ("capture_session.frames.0.intrinsics", .array(Array(repeating: .bool(true), count: 9))),
            ("capture_session.frames.0.used_for_visibility", .number(1)),
            ("capture_session.frames.0.tracking_state", .string("limited:")),
            ("capture_session.frames.0.t", .number(-1)), ("capture_session.frames.0.lens_offset_m", .number(-1)),
            ("capture_session.world_alignment", .string("north")),
            ("capture_session.guidance.question", .string("made-up")),
            ("capture_session.viewpoint_lock.frames_within", .number(0.5)),
            ("north.candidates.0.valid", .bool(true)), ("north.candidates.0.group", .string("imaginary")),
            ("north.candidates.0.raw.heading_accuracy", .number(-1)),
            ("quality.gates.coverage", .string("green")), ("quality.false_valid_guard", .string("pass")),
            ("quality.level", .string("R4")), ("quality.flags", .string("ok")),
            ("sharing.revoked", .bool(true)), ("context", .null)
        ]
        for (path, value) in cases { XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, path, value)), path) }
    }

    func testMaliciousR0AnalysisMustBeEntirelyEmpty() throws {
        let r = try fixture()
        for data in ["[{\"hours\":8}]", "[{\"nested\":{\"duration_seconds\":900}}]", "[{\"bands\":[]}]", "[null]"] {
            XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, "analysis", json(data))), data)
        }
    }

    func testSyntheticR1WithCompleteInputEvidence() throws {
        let r = try ready()
        XCTAssertEqual(try SceneRecordDocument(data: SceneRecordDocument(fields: r).encoded()).fields, r)
    }

    func testMaliciousR1MissingEvidenceOrBlockedGates() throws {
        let r = try ready()
        let cases: [(String, JSONValue)] = [
            ("quality.false_valid_guard", .string("blocked")), ("quality.level", .string("R0")),
            ("quality.gates.north", .string("blocked")), ("quality.gates.extra", .string("blocked")),
            ("quality.blocked_reason", .string("unresolved")), ("location", .null), ("location.lat", .null),
            ("target", .null), ("target.height_m", .null), ("target.confirmed_by", .string("algorithm")),
            ("capture_session", .null), ("capture_session.frames", .array([])),
            ("capture_session.frames.0.mask_ref", .null), ("capture_session.frames.0.used_for_visibility", .bool(false)),
            ("capture_session.frames.0.tracking_state", .string("limited:synthetic")),
            ("capture_session.viewpoint_lock.handling", .string("rejected")),
            ("north.resolved", .null), ("north.resolved.conflict", .bool(true)),
            ("north.resolved.groups_used", .array([])), ("north.resolved.groups_used", .array([.string("solar")])),
            ("north.resolved.groups_rejected", .array([.string("magnetic")])),
            ("north.candidates", .array([])), ("north.candidates.0.valid", .bool(false)),
            ("visibility", .null), ("visibility.states_ref", .null), ("visibility.confidence_ref", .null),
            ("visibility.segmentation", .null), ("visibility.coverage.covered_cells", .number(10)),
            ("visibility.coverage.coverage_pct", .number(90)), ("visibility.coverage.glass_cells", .number(10)),
            ("visibility.grid.alt_range", .array([.number(90), .number(-10)])), ("visibility.grid.az_step_deg", .number(0)),
            ("analysis.0.bands.0.date", .string("2026-02-30")),
            ("analysis.0.bands.0.segments.0.state", .string("certain")),
            ("analysis.0.bands.0.segments.0.to", .string("09:00")), ("analysis.0.versions.inputs_hash", .null)
        ]
        for (path, value) in cases { XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, path, value)), path) }
    }

    func testR1EmptyAnalysisStillRequiresEvidence() throws {
        var r = try fixture()
        r["quality"] = try ready()["quality"]
        XCTAssertThrowsError(try SceneRecordDocument(fields: r))
    }

    func testR0PassedGuardIsInconsistent() throws {
        XCTAssertThrowsError(try SceneRecordDocument(fields: changed(fixture(), "quality.false_valid_guard", .string("passed"))))
    }

    func testUnsafeAssetPaths() throws {
        let r = try fixture()
        for path in ["/tmp/hero.heic", "../hero.heic", "masks/../../x", "./x", "a/./x", "a//b", "a/", "", "https://example.invalid/x", "file:hero.heic", "C:\\x", "a\\b", "%2e%2e/x", "a%2fb", "hero.heic?q=x", "hero.heic#x", "a\0b", "a\nb"] {
            XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, "capture_session.hero_frame.image_ref", .string(path))), path)
        }
    }

    func testValidRelativePathsAndNullRefs() throws {
        let r = try fixture()
        for path: JSONValue in [.null, .string("hero.heic"), .string("masks/frame-001.png"), .string("depth/frame-001.bin.conf"), .string("fictional assets/hero.heic")] {
            XCTAssertNoThrow(try SceneRecordDocument(fields: changed(r, "capture_session.hero_frame.image_ref", path)))
        }
    }

    func testKnownAndFutureAssetRefsAreChecked() throws {
        let r = try fixture()
        for path in ["capture_session.guidance.corridor_ref", "capture_session.frames.0.depth_ref", "capture_session.frames.0.mask_ref", "context.future_ref"] {
            XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, path, .string("../unsafe"))), path)
        }
    }

    func testValidTimestampsOffsetsAndLeapDates() throws {
        let r = try fixture()
        for value in ["2024-02-29T12:30:00Z", "2000-02-29T00:00:00+00:00", "2026-01-01T00:00:00+05:45", "2026-01-01T00:00:00-03:30", "2026-01-01T00:00:00.123456789+14:00"] {
            XCTAssertNoThrow(try SceneRecordDocument(fields: changed(r, "created_at", .string(value))), value)
        }
    }

    func testInvalidCalendarTimestampsAndOffsets() throws {
        let r = try fixture()
        for value in ["2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-01-01T00:00:00", "2026-01-01", "2026-01-01T24:00:00Z", "2026-01-01T00:00:60Z", "2026-01-01T00:00:00+24:00", "2026-01-01T00:00:00+10:60", "0000-01-01T00:00:00Z", "2026-01-01T00:00:00Z\n", "2026-01-01T00:00:00.1234567890Z"] {
            XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, "created_at", .string(value))), value)
        }
    }

    func testIANATimezonesNotFixedOffsets() throws {
        let r = try fixture()
        for value in ["UTC", "Etc/UTC", "Australia/Melbourne", "Asia/Kolkata", "America/St_Johns"] {
            XCTAssertNoThrow(try SceneRecordDocument(fields: changed(r, "timezone", .string(value))), value)
        }
        for value in ["UTC+10", "+10:00", "Mars/Olympus", "../Australia/Melbourne", "", "PST"] {
            XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, "timezone", .string(value))), value)
        }
    }

    func testSessionOrderUsesUTCOffsets() throws {
        var r = try fixture()
        r = changed(r, "capture_session.started_at", .string("2026-01-01T11:00:00+02:00"))
        r = changed(r, "capture_session.ended_at", .string("2026-01-01T10:01:00+01:00"))
        XCTAssertNoThrow(try SceneRecordDocument(fields: r))
        r = changed(r, "capture_session.ended_at", .string("2026-01-01T10:59:59+02:00"))
        XCTAssertThrowsError(try SceneRecordDocument(fields: r))
    }

    func testDirectNonfiniteJSONValuesIncludingUnknownFields() throws {
        let r = try fixture()
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            for path in ["location.lat", "capture_session.frames.0.intrinsics.0", "context.future_numeric"] {
                XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, path, .number(value))), path)
            }
            XCTAssertThrowsError(try JSONEncoder().encode(JSONValue.number(value)))
        }
    }

    func testNonJSONNumberTokensAndOverflow() throws {
        let source = try String(contentsOf: fixtureURL, encoding: .utf8)
        for token in ["NaN", "Infinity", "-Infinity", "1e400"] {
            let data = source.replacingOccurrences(of: "\"alt_m\": null", with: "\"alt_m\": " + token)
            XCTAssertThrowsError(try SceneRecordDocument(data: Data(data.utf8)), token)
        }
    }

    func testLatitudeLongitudeBoundariesAndNullableAccuracy() throws {
        var r = try fixture()
        for (lat, lon): (JSONValue, JSONValue) in [(.number(-90), .number(-180)), (.number(90), .number(180)), (.null, .null)] {
            r = changed(r, "location.lat", lat)
            r = changed(r, "location.lon", lon)
            r = changed(r, "location.h_acc_m", .number(0))
            XCTAssertNoThrow(try SceneRecordDocument(fields: r))
        }
    }

    func testColumnMajorMatrixOrderIsPreserved() throws {
        let values = JSONValue.array((0..<16).map { .number(Double($0)) })
        let r = try changed(fixture(), "capture_session.frames.0.camera_transform", values)
        XCTAssertEqual(try SceneRecordDocument(data: SceneRecordDocument(fields: r).encoded()).fields, r)
    }

    func testDuplicateFrameIDs() throws {
        let r = try fixture()
        guard case .object(let capture) = r["capture_session"], case .array(let frames) = capture["frames"] else { return XCTFail() }
        XCTAssertThrowsError(try SceneRecordDocument(fields: changed(r, "capture_session.frames", .array(frames + frames))))
    }

    func testDuplicateJSONKeysIncludingEscapedAliases() {
        for data in ["{\"quality\":{},\"quality\":{}}", "{\"x\":1,\"\\u0078\":2}", "{\"nested\":{\"x\":1,\"x\":2}}"] {
            XCTAssertThrowsError(try SceneRecordDocument(data: Data(data.utf8)), data)
        }
    }

    func testMalformedJSONAndNonObjectRoots() {
        for data in ["[]", "null", "true", "1", "{", "{\"x\":1,}", "{} {}", "{\"x\":\"\\ud800\"}"] {
            XCTAssertThrowsError(try SceneRecordDocument(data: Data(data.utf8)), data)
        }
    }

    func testDeepNestingRejected() throws {
        var r = try fixture()
        var nested = JSONValue.null
        for _ in 0..<130 { nested = .array([nested]) }
        r["deep"] = nested
        XCTAssertThrowsError(try SceneRecordDocument(fields: r))
        let source = String(repeating: "[", count: 130) + "null" + String(repeating: "]", count: 130)
        XCTAssertThrowsError(try SceneRecordDocument(data: Data(source.utf8)))
    }
}
