import Foundation
import XCTest
@testable import GuideCore

/// Runs the checker over the generated fixture sets in `Tests/Fixtures/`:
/// `guide-regression.json` (the set the checker was tuned on) and `guide-regression-holdout.json`
/// (generated after tuning, with another seed, to measure the checker blind).
///
/// - Every compliant text must produce zero violations.
/// - Every violating text must be caught by the rule family its label maps to.
/// - Candidates a human reviewed and judged mislabelled by the generator are listed in
///   `guide-regression-review.json` with a reason, and are left out of both counts.
final class GuideRegressionFixtureTests: XCTestCase {
    struct Fixture: Decodable {
        struct Case: Decodable {
            var id: String
            var tags: [String]
            var locale: String
            var toolResult: GuideToolResult
            var candidates: [Candidate]
        }
        struct Candidate: Decodable {
            var text: String
            var compliant: Bool
            var violation: String?
            var whatChanged: String?
        }
        var cases: [Case]
    }
    struct Review: Decodable {
        /// "generator_error": the label is wrong (a "compliant" text breaks a rule, or a "violating" text does not).
        var verdict: String
        var note: String
    }

    private var fixturesURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent(); url.deleteLastPathComponent()
        return url.appendingPathComponent("Fixtures")
    }

    /// Label → the violation kinds that count as catching it.
    static let accepted: [String: Set<Violation.Kind>] = [
        "rewrite_number": [.missingNumber, .unexpectedNumber, .misattributedNumber, .unhedgedUpperBound],
        "round_number": [.missingNumber, .unexpectedNumber, .misattributedNumber, .unhedgedUpperBound],
        "invented_bearing": [.unexpectedNumber, .unexpectedBearing],
        "unknown_as_certain": [.certaintyOnUncertain, .uncertaintyNotMentioned, .unexpectedNumber, .unhedgedUpperBound],
        "glass_as_certain": [.certaintyOnUncertain, .uncertaintyNotMentioned],
    ]

    func testTuningSet() throws { try run("guide-regression", minimumCases: 250) }
    func testHoldoutSet() throws { try run("guide-regression-holdout", minimumCases: 80) }

    private func run(_ name: String, minimumCases: Int) throws {
        let fixture = try GuideToolResult.decoder.decode(Fixture.self, from: Data(contentsOf: fixturesURL.appendingPathComponent(name + ".json")))
        let allReviews = try JSONDecoder().decode([String: Review].self, from: Data(contentsOf: fixturesURL.appendingPathComponent("guide-regression-review.json")))
        let ids = Set(fixture.cases.map(\.id))
        let reviews = allReviews.filter { ids.contains(String($0.key.split(separator: "#")[0])) }
        XCTAssertGreaterThanOrEqual(fixture.cases.count, minimumCases, "\(name) shrank")

        var compliant = 0, falsePositives: [String] = [], violating = 0, misses: [String] = [], excluded = 0
        var byLabel: [String: (total: Int, caught: Int)] = [:], kindsHit: [Violation.Kind: Int] = [:]
        for c in fixture.cases {
            let expectation = GuideExpectation(c.toolResult)
            for (i, cand) in c.candidates.enumerated() {
                let key = "\(c.id)#\(i)"
                if reviews[key] != nil { excluded += 1; continue }
                let found = GuideRegressionCheck.check(text: cand.text, against: expectation)
                if cand.compliant {
                    compliant += 1
                    if !found.isEmpty { falsePositives.append("\(key) \(found) :: \(cand.text)") }
                } else {
                    violating += 1
                    let label = cand.violation ?? "?"
                    let hit = found.contains { Self.accepted[label, default: []].contains($0.kind) }
                    byLabel[label, default: (0, 0)].total += 1
                    if hit { byLabel[label]!.caught += 1 } else { misses.append("\(key) [\(label)] \(found) :: \(cand.text) // \(cand.whatChanged ?? "")") }
                    for v in found { kindsHit[v.kind, default: 0] += 1 }
                }
            }
        }

        var report = ["cases=\(fixture.cases.count) compliant=\(compliant) violating=\(violating) excluded=\(excluded)",
                      "falsePositives=\(falsePositives.count) misses=\(misses.count)"]
        report += byLabel.sorted { $0.key < $1.key }.map { "label \($0.key): caught \($0.value.caught)/\($0.value.total)" }
        report += kindsHit.sorted { $0.key.rawValue < $1.key.rawValue }.map { "kind \($0.key.rawValue): \($0.value)" }
        report += falsePositives.map { "FP " + $0 } + misses.map { "MISS " + $0 }
        // Full listing goes to a file: test logs truncate long lines.
        let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent(name + "-report.txt")
        try report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print("Guide regression \(name): \(report[0]); \(report[1]); full report \(reportURL.path)")
        XCTAssertEqual(falsePositives.count, 0, "compliant texts flagged")
        XCTAssertEqual(misses.count, 0, "violating texts not caught")
    }
}
