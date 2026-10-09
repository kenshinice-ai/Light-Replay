import Foundation

/// A rule the Guide text broke. Every violation blocks the text (ADR-0010 "回归": 命中即阻断).
public struct Violation: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, CaseIterable, Sendable {
        /// A number the tool gave is not in the text, character for character, with its unit.
        case missingNumber
        /// A number the tool did not give: rewritten, rounded, converted, spelled out, or invented.
        case unexpectedNumber
        /// A tool number placed under a different period than the one it belongs to.
        case misattributedNumber
        /// A compass word the tool did not use.
        case unexpectedBearing
        /// Unknown or glass-uncertain stated as known.
        case certaintyOnUncertain
        /// An Unknown period, an all-Unknown result, or glass uncertainty that the text never flags.
        case uncertaintyNotMentioned
        /// An upper bound quoted without an upper-bound word, so it reads as the answer.
        case unhedgedUpperBound
        /// Wording `11` §2 bans outright.
        case forbiddenWording
        /// A label a degraded path requires ("手工分割", "待复核").
        case missingPhrase
    }

    /// Rule families. A fixture's labelled violation type must be caught by its family.
    public enum Family: String, Sendable { case numbers, uncertainty, wording }

    public var kind: Kind
    public var detail: String

    public var family: Family {
        switch kind {
        case .missingNumber, .unexpectedNumber, .misattributedNumber, .unexpectedBearing, .unhedgedUpperBound: .numbers
        case .certaintyOnUncertain, .uncertaintyNotMentioned: .uncertainty
        case .forbiddenWording, .missingPhrase: .wording
        }
    }

    public init(_ kind: Kind, _ detail: String) { self.kind = kind; self.detail = detail }
    public var description: String { "\(kind.rawValue): \(detail)" }
}

/// The Guide regression check (ADR-0010 "回归"; `docs/02-architecture.md` §6).
///
/// Rules:
/// 1. Every required tool number appears verbatim with its unit, under its own period.
/// 2. No number appears that the tool did not give. Numbers in words count as numbers.
/// 3. Unknown periods, all-Unknown results and glass uncertainty are named as uncertain,
///    and no clause about them states a sun state as known.
/// 4. When anything is uncertain, absolute certainty words appear only negated.
/// 5. No compass word the tool did not use; no `11` §2 wording; degraded labels present.
///
/// The check is lexical. It cannot judge meaning, so a clean result is necessary, not sufficient.
public enum GuideRegressionCheck {
    public static func check(text: String, against toolResult: GuideToolResult) -> [Violation] {
        check(text: text, against: GuideExpectation(toolResult))
    }

    public static func check(text raw: String, against e: GuideExpectation) -> [Violation] {
        let text = raw.lowercased()
        var out: [Violation] = []
        func add(_ k: Violation.Kind, _ d: String) {
            let v = Violation(k, d); if !out.contains(v) { out.append(v) }
        }

        // Clause attribution: a clause belongs to the periods it names, or else to the last ones named before it.
        let sentences = GuideText.clauses(in: text)
        var clauses: [(text: String, periods: Set<String>, subjects: Set<String>, sentence: Int, names: Bool)] = []
        var currentPeriods = Set<String>(), currentSubjects = Set<String>()
        for (index, sentence) in sentences.enumerated() {
            for clause in sentence {
                let periods = Set(e.periodAliases.filter { GuideText.contains(clause, anyOf: $0.aliases) }.map(\.key))
                let subjects = Set(e.subjects.filter { !$0.aliases.isEmpty && GuideText.contains(clause, anyOf: $0.aliases) }.map(\.name))
                let names = !periods.isEmpty || !subjects.isEmpty
                if names { currentPeriods = periods; currentSubjects = subjects }
                clauses.append((clause, currentPeriods, currentSubjects, index, names))
            }
        }

        // 1–2. Numbers.
        let requiredKeys = Set(e.required.map(\.token))
        var seen: [(GuideExpectation.Required.Token, Set<String>)] = []
        for (clause, periods, _, _, _) in clauses {
            for token in GuideText.tokens(in: clause) {
                switch token {
                case .quantity(let q, let raw):
                    if requiredKeys.contains(.quantity(q)) { seen.append((.quantity(q), periods)) }
                    else if e.upperBounds.contains(q) {
                        if !GuideText.contains(clause, anyOf: GuideLexicon.upperBoundMarkers) { add(.unhedgedUpperBound, raw) }
                    } else if !e.permittedQuantities.contains(q) { add(.unexpectedNumber, raw) }
                case .time(let t):
                    if requiredKeys.contains(.time(t)) { seen.append((.time(t), periods)) }
                    else if !e.permittedTimes.contains(t) { add(.unexpectedNumber, t) }
                case .date(let d, let raw):
                    if !e.permittedDates.contains(d) { add(.unexpectedNumber, raw) }
                case .spelled(let s):
                    add(.unexpectedNumber, s)
                }
            }
        }
        // A time range must be one the tool gave; mixing one segment's start with another's end rewrites both.
        for sentence in sentences {
            let joined = sentence.joined(separator: " ")
            let inclusive = GuideText.contains(joined, anyOf: GuideLexicon.inclusion)
            for (a, b) in GuideText.timeRanges(in: joined) where !e.permittedRanges.contains([a, b]) {
                if inclusive, e.mergedRanges.contains([a, b]) { continue }
                add(.unexpectedNumber, "\(a)–\(b)")
            }
        }
        for req in e.required where !seen.contains(where: { $0.0 == req.token }) {
            add(.missingNumber, describe(req.token))
        }
        // Binding: only for numbers that belong to exactly one period, and only when the text names periods at all.
        let owners = Dictionary(grouping: e.required, by: \.token).mapValues { Set($0.compactMap(\.period)) }
        for req in e.required {
            guard let p = req.period, owners[req.token] == [p], e.periodAliases.count > 1 else { continue }
            let places = seen.filter { $0.0 == req.token }.map(\.1)
            if !places.isEmpty, !places.contains(where: { $0.contains(p) || $0.isEmpty }) {
                add(.misattributedNumber, "\(describe(req.token)) belongs to \(p)")
            }
        }

        // 3–4. Uncertainty.
        let markers = GuideLexicon.uncertaintyMarkers
        for s in e.subjects {
            let about = s.kind == .allUnknown ? clauses : clauses.filter { $0.subjects.contains(s.name) || $0.periods.contains(s.name.lowercased()) }
            // The flag must sit in the sentence that names the subject, in a clause about it.
            // A marker carried over from another sentence ("Direction uncertainty is 2.2°") does not count.
            let namingSentences = Set(about.filter { c in c.names && GuideText.contains(c.text, anyOf: s.aliases) }.map(\.sentence))
            let flagged = s.kind == .allUnknown ? clauses : about.filter { namingSentences.contains($0.sentence) }
            if !flagged.contains(where: { GuideText.contains($0.text, anyOf: markers) }) {
                add(.uncertaintyNotMentioned, s.name)
            }
            for c in about where !GuideText.contains(c.text, anyOf: markers + GuideLexicon.upperBoundMarkers) {
                // For glass, the clause must name glass itself; a clause carried over from glass talk to a known period is not about glass.
                if s.kind == .glass, !GuideText.contains(c.text, anyOf: s.aliases) { continue }
                if let hit = firstStateClaim(in: c.text) { add(.certaintyOnUncertain, "\(s.name): \(hit)") }
            }
        }
        if !e.subjects.isEmpty {
            for hit in GuideText.unnegated(GuideLexicon.absoluteCertainty, in: text) { add(.certaintyOnUncertain, "any: \(hit)") }
        }

        // 5. Bearings, wording, required labels.
        for w in GuideText.compassWords(in: text, loose: false) where !e.permittedCompass.contains(w) {
            add(.unexpectedBearing, w)
        }
        for w in GuideText.sunBearings(in: text, masking: e.causeLabels) { add(.unexpectedBearing, "sun \(w)") }
        for w in GuideLexicon.forbidden where !GuideText.occurrences(of: w, in: text).isEmpty { add(.forbiddenWording, w) }
        for group in e.requiredPhrases where !GuideText.contains(text, anyOf: group) { add(.missingPhrase, group[0]) }
        return out
    }

    private static func firstStateClaim(in clause: String) -> String? {
        GuideLexicon.stateClaims.sorted { $0.count > $1.count }.first { !GuideText.occurrences(of: $0, in: clause).isEmpty }
    }

    private static func describe(_ t: GuideExpectation.Required.Token) -> String {
        switch t { case .quantity(let q): q.description; case .time(let s): s }
    }
}
