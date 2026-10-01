import Foundation
import XCTest
@testable import NorthResolver

// Synthetic candidates only. Nothing here is field-validated; the sundial spike (docs/07) calibrates the σ model.
final class NorthResolverTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Candidate: Decodable {
            let group: String
            let yaw_deg: Double?
            let sigma_deg: Double?
            let valid: Bool
        }
        struct Group: Decodable {
            let yaw_deg: Double
            let sigma_deg: Double
            let spread_deg: Double
            let readings: Int
        }
        struct Disagreement: Decodable {
            let a: String
            let b: String
            let difference_deg: Double
            let limit_deg: Double
        }
        struct Expected: Decodable {
            let yaw_deg: Double?
            let sigma_deg: Double?
            let groups: [String: Group]
            let groups_used: [String]
            let groups_rejected: [String]
            let conflict: Bool
            let disagreements: [Disagreement]
            let gate: String
            let needs_confirmation: Bool
            let reason: String
        }
        struct Case: Decodable {
            let name: String
            let candidates: [Candidate]
            let expected: Expected
        }
        let version: String
        let cases: [Case]
    }

    /// engine/tests/fixtures/north-cases.json, written by the Python reference (engine/scripts/make_north_fixture.py).
    private func fixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "engine/tests/fixtures/north-cases.json")))
    }

    private func readings(_ candidates: [Fixture.Candidate]) -> [NorthReading] {
        candidates.compactMap { candidate in
            guard candidate.valid, let yaw = candidate.yaw_deg, let sigma = candidate.sigma_deg,
                  let group = NorthGroup(rawValue: candidate.group) else { return nil }
            return NorthReading(group: group, yawDeg: yaw, sigmaDeg: sigma)
        }
    }

    private func reading(_ group: NorthGroup, _ yaw: Double, _ sigma: Double) -> NorthReading {
        NorthReading(group: group, yawDeg: yaw, sigmaDeg: sigma)
    }

    func testMatchesThePythonReferenceOnEveryCase() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.version, NorthResolver.version)
        XCTAssertGreaterThan(fixture.cases.count, 200)
        for item in fixture.cases {
            let result = NorthResolver.resolve(readings(item.candidates)), expected = item.expected
            XCTAssertEqual(result.gate.rawValue, expected.gate, item.name)
            XCTAssertEqual(result.groupsUsed.map(\.rawValue), expected.groups_used, item.name)
            XCTAssertEqual(result.groupsRejected.map(\.rawValue), expected.groups_rejected, item.name)
            XCTAssertEqual(result.conflict, expected.conflict, item.name)
            XCTAssertEqual(result.needsConfirmation, expected.needs_confirmation, item.name)
            XCTAssertEqual(result.reason, expected.reason, item.name)
            XCTAssertEqual(result.yawDeg == nil, expected.yaw_deg == nil, item.name)
            if let yaw = result.yawDeg, let sigma = result.sigmaDeg, let wantYaw = expected.yaw_deg, let wantSigma = expected.sigma_deg {
                XCTAssertLessThan(NorthResolver.circularDifference(yaw, wantYaw), 1e-9, item.name)
                XCTAssertEqual(sigma, wantSigma, accuracy: 1e-9, item.name)
            }
            XCTAssertEqual(Set(result.groups.keys.map(\.rawValue)), Set(expected.groups.keys), item.name)
            for (group, merged) in result.groups {
                let want = expected.groups[group.rawValue]!
                XCTAssertLessThan(NorthResolver.circularDifference(merged.yawDeg, want.yaw_deg), 1e-9, item.name)
                XCTAssertEqual(merged.sigmaDeg, want.sigma_deg, accuracy: 1e-9, item.name)
                XCTAssertEqual(merged.spreadDeg, want.spread_deg, accuracy: 1e-9, item.name)
                XCTAssertEqual(merged.readings, want.readings, item.name)
            }
            XCTAssertEqual(result.disagreements.count, expected.disagreements.count, item.name)
            for (got, want) in zip(result.disagreements, expected.disagreements) {
                XCTAssertEqual([got.a.rawValue, got.b.rawValue], [want.a, want.b], item.name)
                XCTAssertEqual(got.differenceDeg, want.difference_deg, accuracy: 1e-9, item.name)
                XCTAssertEqual(got.limitDeg, want.limit_deg, accuracy: 1e-9, item.name)
            }
        }
    }

    // The rest are written from the documents, not from the fixture.

    func testWorkedExampleOfDocs03() {
        // docs/03 §4: magnetic 8±12, map 2±4, solar 359±2 → 359.78 / 1.77, all three used.
        let r = NorthResolver.resolve([reading(.magnetic, 8, 12), reading(.map, 2, 4), reading(.solar, 359, 2)])
        XCTAssertEqual(r.yawDeg!, 359.78, accuracy: 0.005)
        XCTAssertEqual(r.sigmaDeg!, 1.77, accuracy: 0.005)
        XCTAssertEqual(r.groupsUsed, [.solar, .map, .magnetic])
        XCTAssertEqual(r.gate, .pass)
        XCTAssertFalse(r.conflict)
    }

    func testDifferencesCrossTheSeam() {
        XCTAssertEqual(NorthResolver.circularDifference(359, 2), 3, accuracy: 1e-12)   // blueprint review #4: not 357
        XCTAssertEqual(NorthResolver.signedOffset(359, from: 1), -2, accuracy: 1e-12)
        XCTAssertEqual(NorthResolver.signedOffset(1, from: 359), 2, accuracy: 1e-12)
        for angle in [-1e-17, 360.0, 720.0, -360.0, 359.99999999999994] {
            XCTAssertTrue((0..<360).contains(NorthResolver.mod360(angle)), "\(angle)")
        }
    }

    func testCompassAloneOffIsNotAConflict() {
        // ADR-0009 background 1.
        let r = NorthResolver.resolve([reading(.solar, 1, 2), reading(.map, 3, 4), reading(.magnetic, 40, 8)])
        XCTAssertEqual(r.groupsUsed, [.solar, .map])
        XCTAssertEqual(r.groupsRejected, [.magnetic])
        XCTAssertEqual(r.gate, .pass)
        XCTAssertFalse(r.conflict)
        XCTAssertEqual(r.disagreements.count, 2, "the rejected reading's disagreements are still recorded")
    }

    func testConfidentWrongReadingDoesNotWin() {
        // ADR-0009 background 2.
        let r = NorthResolver.resolve([reading(.solar, 20, 2), reading(.vps, 3, 3), reading(.map, 2, 4)])
        XCTAssertEqual(r.groupsUsed, [.vps, .map])
        XCTAssertEqual(r.groupsRejected, [.solar])
        XCTAssertEqual(r.gate, .blocked)
        XCTAssertTrue(r.conflict)
        XCTAssertTrue(r.needsConfirmation)
    }

    func testSingleGroupLights() {
        XCTAssertEqual(NorthResolver.resolve([reading(.map, 123, 4)]).gate, .warn)
        XCTAssertEqual(NorthResolver.resolve([reading(.map, 123, 6)]).gate, .warn)
        let wide = NorthResolver.resolve([reading(.magnetic, 77, 12)])   // review R08 probe
        XCTAssertEqual(wide.gate, .blocked)
        XCTAssertTrue(wide.needsConfirmation)
    }

    func testNothingUsableIsBlockedAndUnresolved() {
        for readings in [[], [reading(.map, 5, 0)], [reading(.map, .nan, 4)]] {
            let r = NorthResolver.resolve(readings)
            XCTAssertEqual(r.gate, .blocked)
            XCTAssertNil(r.yawDeg)
            XCTAssertNil(r.sigmaDeg)
            XCTAssertTrue(r.groupsUsed.isEmpty)
        }
    }

    func testReadingsOfOneSensorCountOnce() {
        let one = NorthResolver.resolve([reading(.magnetic, 100, 8)])
        let many = NorthResolver.resolve(Array(repeating: reading(.magnetic, 100, 8), count: 50))
        XCTAssertEqual(one.sigmaDeg, 8)
        XCTAssertEqual(many.sigmaDeg, 8, "fifty readings of one compass are not fifty pieces of evidence")
        XCTAssertEqual(many.gate, .blocked)
        let seam = NorthResolver.merge([(359, 8), (1, 8), (3, 8)])
        XCTAssertEqual(seam.yawDeg, 1, accuracy: 1e-9)
        XCTAssertEqual(seam.spreadDeg, (8.0 / 3).squareRoot(), accuracy: 1e-9)
    }

    func testTurningEveryReadingTurnsTheAnswer() {
        let base = [reading(.solar, 350, 2), reading(.map, 355, 4), reading(.magnetic, 20, 9), reading(.magnetic, 12, 8)]
        let reference = NorthResolver.resolve(base)
        for turn in stride(from: 7.0, to: 360, by: 23.5) {
            let turned = NorthResolver.resolve(base.map { reading($0.group, ($0.yawDeg + turn).truncatingRemainder(dividingBy: 360), $0.sigmaDeg) })
            XCTAssertEqual(turned.gate, reference.gate)
            XCTAssertEqual(turned.groupsUsed, reference.groupsUsed)
            XCTAssertLessThan(NorthResolver.circularDifference(turned.yawDeg!, reference.yawDeg! + turn), 1e-9)
            XCTAssertEqual(turned.sigmaDeg!, reference.sigmaDeg!, accuracy: 1e-9)
        }
    }
}
