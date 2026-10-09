import Foundation
import SwiftData

/// The few facts about a light scan that a row or a Compare cell needs (ADR-0022, review V2-04). It is derived from
/// the SceneRecord and the scan, written by the app, and shown as a sentence in whatever language the reader uses.
/// The sentence used to be written into `text`, the buyer's own column; an analysis arriving late could then have
/// overwritten what the buyer wrote.
public struct LightDigest: Codable, Sendable, Equatable {
    /// "R0", "R1"… as the record states and the validator accepted.
    public var level: String
    /// The five lights, by name, as the record states them. Empty for rows written before digests existed.
    public var gates: [String: String]
    /// `LightQuestion` raw value: "winter" or "allYear".
    public var question: String?
    /// Share of the question's sun path the camera pointed at during the scan. Not a measure of sky or sunlight.
    public var sweptCoveragePct: Int?
    /// `result.revision` of the record: 0 until an analysis has been committed.
    public var revision: Int
    /// Frames kept on this device for analysis; nil when none were kept.
    public var spoolFrames: Int?

    public init(level: String = "R0", gates: [String: String] = [:], question: String? = nil, sweptCoveragePct: Int? = nil,
                revision: Int = 0, spoolFrames: Int? = nil) {
        self.level = level
        self.gates = gates
        self.question = question
        self.sweptCoveragePct = sweptCoveragePct
        self.revision = revision
        self.spoolFrames = spoolFrames
    }

    public var encoded: Data? { try? JSONEncoder().encode(self) }

    /// The question in the middle of a sentence: "winter sun", "all-year sun".
    public var questionName: String? {
        switch question {
        case "winter": String(localized: "winter sun", bundle: .module)
        case "allYear": String(localized: "all-year sun", bundle: .module)
        default: nil
        }
    }

    /// What the row says about itself. No hours: an R0 scan has none (ADR-0013).
    public var statusLine: String {
        if let pct = sweptCoveragePct, let name = questionName {
            return String(localized: "Light scan · camera covered \(pct)% of the \(name) path · sunlight not calculated", bundle: .module)
        }
        return String(localized: "Light scan · sunlight not calculated", bundle: .module)
    }
}

extension InspectionObservation {
    public var lightDigest: LightDigest? {
        get { lightDigestData.flatMap { try? JSONDecoder().decode(LightDigest.self, from: $0) } }
        set { lightDigestData = newValue?.encoded }
    }
}

/// Light rows written before the digest existed carry a generated sentence in `text`. This gives each a digest and
/// takes the sentence out of the buyer's column — only when the text is exactly a sentence the app generated and the
/// buyer never edited it. Anything else stays where it is: likeness is not proof that the app wrote it.
public enum LightStatusMigration {
    private static let generated: [(pattern: String, coverage: Int?, question: Int?)] = [
        (#"^Light scan · camera covered (\d+)% of the (winter sun|all-year sun) path · sunlight not calculated$"#, 1, 2),
        // The Chinese sentence as it was stored until 2026-10-04, arguments in the English order.
        (#"^光线扫描 · 镜头覆盖了(\d+)路径的 (冬季阳光|全年阳光)% · 日照未计算$"#, 1, 2),
        (#"^Light scan · (winter sun|all-year sun) path (\d+)% seen · analysis pending$"#, 2, 1),
        (#"^Light measurement recorded \(analysis pending\)$"#, nil, nil),
        (#"^已记录光线测量（等待分析）$"#, nil, nil)
    ]

    /// The digest a generated sentence stands for, or nil when the text is not one the app generated.
    static func digest(fromGenerated text: String) -> LightDigest? {
        for entry in generated {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            func group(_ index: Int?) -> String? {
                guard let index, let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
            let question: String? = switch group(entry.question) {
            case "winter sun", "冬季阳光": "winter"
            case "all-year sun", "全年阳光": "allYear"
            default: nil
            }
            return LightDigest(question: question, sweptCoveragePct: group(entry.coverage).flatMap(Int.init))
        }
        return nil
    }

    /// Returns how many rows were given a digest. Saves once; a failure leaves every row as it was.
    @MainActor @discardableResult
    public static func migrate(in context: ModelContext) throws -> Int {
        let light = ObservationKind.light.rawValue
        let rows = try context.fetch(FetchDescriptor<InspectionObservation>(predicate: #Predicate { $0.kindRaw == light && $0.lightDigestData == nil }))
            .filter { !$0.isDeleted }
        guard !rows.isEmpty else { return 0 }
        for row in rows {
            if let text = row.text, row.originalText == nil, let digest = digest(fromGenerated: text) {
                row.lightDigest = digest
                row.text = nil
            } else {
                row.lightDigest = LightDigest()   // the buyer's words, or words the app cannot vouch for, stay in `text`
            }
        }
        try PropertyStore.commit(context)
        return rows.count
    }
}
