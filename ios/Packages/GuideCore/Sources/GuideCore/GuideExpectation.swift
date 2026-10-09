/// What a Guide text must and must not contain, derived from one `GuideToolResult`.
///
/// Derived by code, never written by a model: the expectation is only as trustworthy as the tool result.
public struct GuideExpectation: Equatable, Sendable {
    /// A number with its unit class, e.g. `3.5` hours or `359.9` degrees.
    public struct Quantity: Hashable, Sendable, CustomStringConvertible {
        public enum Unit: String, Sendable { case hours, degrees, percent, minutes, none }
        public var value: String
        public var unit: Unit
        public init(_ value: String, _ unit: Unit) { self.value = value; self.unit = unit }
        public var description: String {
            switch unit {
            case .hours: "\(value) h"
            case .degrees: "\(value)°"
            case .percent: "\(value)%"
            case .minutes: "\(value) min"
            case .none: value
            }
        }
    }

    /// A required number and the period it belongs to (nil when it belongs to the whole result).
    public struct Required: Hashable, Sendable {
        public enum Token: Hashable, Sendable { case quantity(Quantity), time(String) }
        public var token: Token
        public var period: String?
    }

    /// Something the text must flag as uncertain.
    public struct Subject: Hashable, Sendable {
        public enum Kind: String, Sendable { case unknownPeriod, glass, allUnknown }
        public var kind: Kind
        /// Display name used in violations.
        public var name: String
        /// Words that refer to it in text (lowercased). Empty for `allUnknown`: it covers the whole text.
        public var aliases: [String]
    }

    /// Stable direct hours of every known period, and the times of its direct and sensitive segments.
    public var required: [Required]
    /// Every other number the tool gave: may be quoted, need not be.
    public var permittedQuantities: Set<Quantity>
    public var permittedTimes: Set<String>
    /// `yyyy-MM-dd` and `MM-dd` forms of every period date.
    public var permittedDates: Set<String>
    /// Upper bounds may be quoted only next to an upper-bound marker.
    public var upperBounds: Set<Quantity>
    public var subjects: [Subject]
    /// Period labels (lowercased) → period key. Used to attribute clauses to periods.
    public var periodAliases: [(key: String, aliases: [String])]
    /// Compass words the tool used in its own labels; any other compass word is invented.
    public var permittedCompass: Set<String>
    /// Each inner list is a set of alternatives; the text must contain one of them.
    public var requiredPhrases: [[String]]
    /// Time ranges the tool gave: every segment and every attribution span.
    public var permittedRanges: Set<[String]>
    /// Runs of back-to-back segments in one period ("11:15–12:40" for 11:15–12:15 direct +
    /// 12:15–12:40 sensitive). Allowed only beside an inclusion word ("其中", "of which"); otherwise
    /// the span relabels the sensitive part as direct.
    public var mergedRanges: Set<[String]>
    /// The tool's own cause labels (lowercased), e.g. "西侧建筑". Their compass words are the tool's, not Guide's.
    public var causeLabels: [String]

    public static func == (a: GuideExpectation, b: GuideExpectation) -> Bool {
        a.required == b.required && a.permittedQuantities == b.permittedQuantities && a.permittedTimes == b.permittedTimes
            && a.permittedDates == b.permittedDates && a.upperBounds == b.upperBounds && a.subjects == b.subjects
            && a.periodAliases.map(\.key) == b.periodAliases.map(\.key) && a.permittedCompass == b.permittedCompass
            && a.requiredPhrases == b.requiredPhrases && a.permittedRanges == b.permittedRanges && a.mergedRanges == b.mergedRanges && a.causeLabels == b.causeLabels
    }

    public init(_ r: GuideToolResult) {
        var required: [Required] = []
        var quantities = Set<Quantity>(), times = Set<String>(), dates = Set<String>(), bounds = Set<Quantity>()
        var subjects: [Subject] = [], aliases: [(String, [String])] = []

        for p in r.periods {
            let key = p.labelEn.lowercased()
            aliases.append((key, [p.labelZh.lowercased(), p.labelEn.lowercased()]))
            dates.insert(p.date)
            if p.date.count == 10 { dates.insert(String(p.date.suffix(5))) }
            if let h = p.directHours, !r.isAllUnknown {
                required.append(Required(token: .quantity(Quantity(h, .hours)), period: key))
            }
            if let u = p.upperBoundHours { bounds.insert(Quantity(u, .hours)) }
            for s in p.segments {
                if !r.isAllUnknown, p.state != .unknown, s.state == .direct || s.state == .sensitive {
                    for t in [s.from, s.to] { required.append(Required(token: .time(t), period: key)) }
                } else {
                    times.formUnion([s.from, s.to])
                }
            }
            if p.state == .unknown, !r.isAllUnknown {
                subjects.append(Subject(kind: .unknownPeriod, name: p.labelEn, aliases: [p.labelZh.lowercased(), p.labelEn.lowercased()]))
            }
        }
        for a in r.attribution {
            times.formUnion([a.from, a.to])
            quantities.formUnion(a.azRangeDeg.map { Quantity($0, .degrees) })
        }
        if let f = r.facing { quantities.insert(Quantity(f.deg, .degrees)) }
        if let s = r.north.sigmaDeg { quantities.insert(Quantity(s, .degrees)) }
        if let c = r.coveragePct { quantities.insert(Quantity(c, .percent)) }
        quantities.formUnion(bounds)
        if r.isAllUnknown { subjects.insert(Subject(kind: .allUnknown, name: "all", aliases: []), at: 0) }
        if r.glassUncertain { subjects.append(Subject(kind: .glass, name: "glass", aliases: GuideLexicon.glass)) }

        var compassSources = r.attribution.flatMap { [$0.causeZh, $0.causeEn] }
        if let f = r.facing { compassSources += [f.labelZh, f.labelEn] }
        var phrases: [[String]] = []
        if r.degraded.contains("seg_assets_missing") { phrases.append(GuideLexicon.manualSegmentation) }
        if r.north.status == .conflict { phrases.append(GuideLexicon.needsReview) }

        self.required = required
        self.permittedQuantities = quantities
        self.permittedTimes = times.subtracting(required.compactMap { if case .time(let t) = $0.token { t } else { nil } })
        self.permittedDates = dates
        self.upperBounds = bounds
        self.subjects = subjects
        self.periodAliases = aliases.map { (key: $0.0, aliases: $0.1) }
        self.permittedCompass = Set(compassSources.flatMap { GuideText.compassWords(in: $0.lowercased(), loose: true) })
        self.requiredPhrases = phrases
        var merged = Set<[String]>()
        for p in r.periods {
            for i in p.segments.indices {
                var j = i
                while j + 1 < p.segments.count, p.segments[j + 1].from == p.segments[j].to {
                    j += 1; merged.insert([p.segments[i].from, p.segments[j].to])
                }
            }
        }
        self.permittedRanges = Set(r.periods.flatMap { $0.segments.map { [$0.from, $0.to] } } + r.attribution.map { [$0.from, $0.to] })
        self.mergedRanges = merged.subtracting(permittedRanges)
        self.causeLabels = r.attribution.flatMap { [$0.causeZh.lowercased(), $0.causeEn.lowercased()] }
    }
}
