import XCTest
@testable import GuideCore

// Hand-written cases for each rule. Synthetic inputs only; none come from a field record.
final class GuideRegressionCheckTests: XCTestCase {
    private func result(periods: [GuideToolResult.Period], glass: Bool = false, level: GuideToolResult.Level = .r1,
                        guardState: GuideToolResult.FalseValidGuard = .passed, degraded: [String] = [],
                        north: GuideToolResult.North = .init(status: .agreed, sigmaDeg: "1.8")) -> GuideToolResult {
        GuideToolResult(hemisphere: .south, level: level, falseValidGuard: guardState,
                        facing: .init(deg: "315", labelZh: "西北", labelEn: "northwest"), north: north, coveragePct: "92",
                        glassUncertain: glass, degraded: degraded, periods: periods,
                        attribution: [.init(from: "14:10", to: "sunset", causeZh: "西侧建筑", causeEn: "building to the west", azRangeDeg: ["250", "290"])])
    }
    private let winter = GuideToolResult.Period(labelZh: "冬至", labelEn: "winter solstice", date: "2026-06-21", state: .direct,
                                                directHours: "3.5", segments: [.init(from: "10:40", to: "14:10", state: .direct)])
    private let summerUnknown = GuideToolResult.Period(labelZh: "夏至", labelEn: "summer solstice", date: "2026-12-21", state: .unknown,
                                                       directHours: nil, upperBoundHours: "6", segments: [.init(from: "09:00", to: "16:00", state: .unknown)])

    private func kinds(_ text: String, _ r: GuideToolResult) -> Set<Violation.Kind> {
        Set(GuideRegressionCheck.check(text: text, against: r).map(\.kind))
    }

    func testCompliantChineseAndEnglishPass() {
        let r = result(periods: [winter, summerUnknown])
        XCTAssertEqual(GuideRegressionCheck.check(text: "冬至约 10:40–14:10 稳定直射，共 3.5 小时；14:10 后西侧建筑遮挡。夏至资料不足，无法判断是否有直射。", against: r), [])
        XCTAssertEqual(GuideRegressionCheck.check(text: "On the winter solstice, direct sun from 10:40 to 14:10, 3.5 hours in total. The summer solstice is unknown: not enough sky was scanned.", against: r), [])
    }

    func testRoundedAndRewrittenNumbers() {
        let r = result(periods: [winter])
        XCTAssertEqual(kinds("冬至约 10:40–14:10 直射，共 4 小时。", r), [.missingNumber, .unexpectedNumber])
        XCTAssertEqual(kinds("冬至约 10:40–14:10 直射，共三个半小时。", r), [.missingNumber, .unexpectedNumber])
        XCTAssertEqual(kinds("冬至约 10:40–14:10 直射，共 3.5 小时，窗朝 315° 偏 2°。", r), [.unexpectedNumber])
        XCTAssertEqual(kinds("冬至约 10:30–14:10 直射，共 3.5 小时。", r), [.missingNumber, .unexpectedNumber])
    }

    func testInventedBearing() {
        let r = result(periods: [winter])
        XCTAssertEqual(kinds("冬至 10:40–14:10 直射 3.5 小时，阳光从东北方向进来。", r), [.unexpectedBearing])
        XCTAssertEqual(kinds("Winter solstice: 3.5 h of direct sun, 10:40 to 14:10, through the northwest window.", r), [])
        XCTAssertEqual(kinds("Winter solstice: 3.5 h of direct sun, 10:40 to 14:10, from the north-east.", r), [.unexpectedBearing])
    }

    func testUnknownStatedAsCertain() {
        let r = result(periods: [winter, summerUnknown])
        let base = "冬至 10:40–14:10 直射，共 3.5 小时。"
        XCTAssertEqual(kinds(base + "夏至阳光充足。", r), [.certaintyOnUncertain, .uncertaintyNotMentioned])
        XCTAssertEqual(kinds(base + "夏至资料不足，但肯定会有直射。", r), [.certaintyOnUncertain])
        XCTAssertEqual(kinds(base, r), [.uncertaintyNotMentioned])
        XCTAssertEqual(kinds(base + "夏至资料不足，直射至多 6 小时。", r), [])
        XCTAssertEqual(kinds(base + "夏至资料不足，预计直射 6 小时。", r), [.unhedgedUpperBound, .certaintyOnUncertain])
    }

    func testGlassUncertainty() {
        let r = result(periods: [winter], glass: true)
        let base = "冬至 10:40–14:10 直射，共 3.5 小时。"
        XCTAssertEqual(kinds(base + "窗外玻璃反射的区域不确定，结果可能偏乐观。", r), [])
        XCTAssertEqual(kinds(base + "玻璃反射不影响结果。", r), [.certaintyOnUncertain, .uncertaintyNotMentioned])
        XCTAssertEqual(kinds(base, r), [.uncertaintyNotMentioned])
    }

    func testAllUnknownAndDegraded() {
        let blocked = GuideToolResult.Period(labelZh: "冬至", labelEn: "winter solstice", date: "2026-06-21", state: .unknown, directHours: nil, segments: [])
        let r = result(periods: [blocked], level: .r0, guardState: .blocked, degraded: ["seg_assets_missing"],
                       north: .init(status: .conflict, sigmaDeg: nil))
        XCTAssertEqual(kinds("方向来源有分歧，待复核；本次为手工分割，覆盖率 92%，资料不足，暂不给出直射时段。", r), [])
        XCTAssertEqual(kinds("冬至大约有 2 小时直射。", r), [.unexpectedNumber, .certaintyOnUncertain, .uncertaintyNotMentioned, .missingPhrase])
    }

    func testForbiddenWordingAndMisattribution() {
        let summer = GuideToolResult.Period(labelZh: "夏至", labelEn: "summer solstice", date: "2026-12-21", state: .direct,
                                            directHours: "0", segments: [])
        let r = result(periods: [winter, summer])
        XCTAssertEqual(kinds("冬至 10:40–14:10 直射，共 3.5 小时；夏至 0 小时。", r), [])
        XCTAssertEqual(kinds("冬至 10:40–14:10 直射，共 0 小时；夏至 3.5 小时。", r), [.misattributedNumber])
        XCTAssertEqual(kinds("精确测得冬至 10:40–14:10 直射，共 3.5 小时；夏至 0 小时。", r), [.forbiddenWording])
    }

    func testTokenizerKeepsDecimalsTimesAndIdentifiers() {
        let t = GuideText.tokens(in: "r1 结果：23.9 小时，359.9°，0°，6 月 21 日，09:00–10:30，41%")
        XCTAssertEqual(t.count, 7)
        XCTAssertEqual(t.first, .quantity(.init("23.9", .hours), raw: "23.9 小时"))
    }
}
