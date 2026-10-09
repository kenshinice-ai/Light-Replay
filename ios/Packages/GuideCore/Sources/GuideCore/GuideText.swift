import Foundation

/// Tokenising helpers for the regression check. All functions take lowercased text.
enum GuideText {
    enum Token: Equatable {
        case quantity(GuideExpectation.Quantity, raw: String)
        case time(String)
        case date(String, raw: String)
        /// A number written in words ("三个半小时", "an hour"). The tool never writes numbers this way.
        case spelled(String)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august",
                                 "september", "october", "november", "december"]
    private static let monthAlt = months.joined(separator: "|")

    // Order matters: each pass masks what it matched so later passes cannot re-read it.
    private static let isoDate = regex(#"(?<![\d.])(\d{4})-(\d{2})-(\d{2})(?!\d)"#)
    private static let zhDate = regex(#"(?<![\d.])(\d{1,2})\s*月\s*(\d{1,2})\s*日"#)
    private static let enDateMonthFirst = regex(#"\b(\#(monthAlt))\s+(\d{1,2})(?:st|nd|rd|th)?\b"#)
    private static let enDateDayFirst = regex(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(\#(monthAlt))\b"#)
    // A colon before the time is fine ("6小时:07:20"); a digit or a second colon after it is not.
    private static let time = regex(#"(?<![\d.])(\d{1,2}):([0-5]\d)(?![\d]|:\d)"#)
    private static let range = regex(#"(?<![\d.])(\d{1,2}:[0-5]\d)\s*(?:–|—|-|~|～|至|到|to|until|till|and)\s*(\d{1,2}:[0-5]\d)(?!\d)"#)
    private static let number = regex(
        #"(?<![\d.a-z_])(\d+(?:\.\d+)?)(?:\s?(?:个\s?)?(小时|钟头|hours|hour|hrs|hr|h(?![a-z])|°|度|%|％|分钟|minutes|minute|mins|min(?![a-z])))?"#)
    private static let spelledZh = regex(#"[零〇一二两三四五六七八九十百]+\s?个?半?\s?(?:小时|钟头|度|分钟)|半\s?个?\s?(?:小时|钟头)"#)
    private static let spelledEn = regex(
        #"\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|twenty|thirty|forty|forty-five|fifty|sixty|ninety|half|an|a|a few|a couple of|several|many)(?:\s+and\s+a\s+half)?[\s-]+(?:hours?|degrees?|minutes?)\b|\bhalf(?:\s+an|-)\s*hour\b|\bhalf\s+a\s+day\b"#)

    static func tokens(in text: String) -> [Token] {
        let ns = NSMutableString(string: text)
        var found: [(Int, Token)] = []

        func pass(_ re: NSRegularExpression, _ make: (NSTextCheckingResult, NSString) -> Token?) {
            let snapshot = ns.copy() as! NSString
            for m in re.matches(in: snapshot as String, range: NSRange(location: 0, length: snapshot.length)) {
                guard let token = make(m, snapshot) else { continue }
                found.append((m.range.location, token))
                ns.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
        }
        func group(_ m: NSTextCheckingResult, _ s: NSString, _ i: Int) -> String? {
            let r = m.range(at: i); return r.location == NSNotFound ? nil : s.substring(with: r)
        }
        func pad(_ v: String) -> String { v.count == 1 ? "0" + v : v }
        func monthNumber(_ name: String) -> String { pad(String((months.firstIndex(of: name.lowercased()) ?? 0) + 1)) }

        pass(isoDate) { m, s in .date(s.substring(with: m.range), raw: s.substring(with: m.range)) }
        pass(zhDate) { m, s in .date(pad(group(m, s, 1)!) + "-" + pad(group(m, s, 2)!), raw: s.substring(with: m.range)) }
        pass(enDateMonthFirst) { m, s in .date(monthNumber(group(m, s, 1)!) + "-" + pad(group(m, s, 2)!), raw: s.substring(with: m.range)) }
        pass(enDateDayFirst) { m, s in .date(monthNumber(group(m, s, 2)!) + "-" + pad(group(m, s, 1)!), raw: s.substring(with: m.range)) }
        pass(time) { m, s in .time(s.substring(with: m.range)) }
        pass(spelledZh) { m, s in .spelled(s.substring(with: m.range)) }
        pass(spelledEn) { m, s in .spelled(s.substring(with: m.range)) }
        pass(number) { m, s in
            let unit: GuideExpectation.Quantity.Unit
            switch group(m, s, 2)?.lowercased() {
            case "小时", "钟头", "hours", "hour", "hrs", "hr", "h": unit = .hours
            case "°", "度": unit = .degrees
            case "%", "％": unit = .percent
            case "分钟", "minutes", "minute", "mins", "min": unit = .minutes
            default: unit = .none
            }
            return .quantity(.init(group(m, s, 1)!, unit), raw: s.substring(with: m.range))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Time ranges written as "10:40–14:10", "10:40 至 14:10", "from 10:40 to 14:10".
    static func timeRanges(in text: String) -> [(String, String)] {
        let ns = text as NSString
        return range.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2)))
        }
    }

    // MARK: Sentences and clauses

    /// Splits into sentences, then clauses. A decimal point or a time colon never splits.
    static func clauses(in text: String) -> [[String]] {
        let sentenceBreak = regex(#"[。！？!?；;\n]+|\.(?=\s|$)"#)
        // "、" is left out: it lists items ("秋分、夏至资料不足") and must not split them.
        let clauseBreak = regex(#"[，,：]|——|\bbut\b|\bhowever\b|但是?|不过|然而|可是"#)
        return split(text, by: sentenceBreak).map { split($0, by: clauseBreak) }.filter { !$0.isEmpty }
    }

    private static func split(_ text: String, by re: NSRegularExpression) -> [String] {
        let ns = text as NSString
        var parts: [String] = [], start = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: start))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: Phrase search

    private static func isASCIIWord(_ s: String) -> Bool { s.unicodeScalars.allSatisfy { $0.isASCII } }

    /// Ranges where `phrase` occurs. English phrases need word boundaries; Chinese ones do not.
    static func occurrences(of phrase: String, in text: String) -> [NSRange] {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = isASCIIWord(phrase) ? #"(?<![a-z0-9'])"# + escaped + #"(?![a-z0-9])"# : escaped
        let ns = text as NSString
        return regex(pattern).matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }

    static func contains(_ text: String, anyOf phrases: [String]) -> Bool {
        phrases.contains { !occurrences(of: $0, in: text).isEmpty }
    }

    /// True when a negation sits right before `range` (three characters in Chinese, three words in English).
    static func isNegated(_ range: NSRange, in text: String) -> Bool {
        let ns = text as NSString
        let before = ns.substring(to: range.location)
        let zhWindow = String(before.suffix(3))
        if GuideLexicon.negationsZh.contains(where: zhWindow.contains) { return true }
        let words = before.split(whereSeparator: { !$0.isLetter && $0 != "'" }).suffix(3).map { $0.lowercased() }
        return words.contains { w in GuideLexicon.negationsEn.contains(w) || w.hasSuffix("n't") }
    }

    /// Phrases from `list` found in `text` that are not negated, longest match first so
    /// "稳定直射" is reported once, not also as "直射".
    static func unnegated(_ list: [String], in text: String) -> [String] {
        var taken: [NSRange] = [], hits: [String] = []
        for phrase in list.sorted(by: { $0.count > $1.count }) {
            for r in occurrences(of: phrase, in: text) where !taken.contains(where: { NSIntersectionRange($0, r).length > 0 }) {
                taken.append(r)
                if !isNegated(r, in: text) { hits.append(phrase) }
            }
        }
        return hits
    }

    // MARK: Compass words

    private static let compassZhCore = "东北|东南|西北|西南|东|南|西|北"
    // "北向", "真北", "指北", "磁北" name the north reference, not a bearing.
    private static let compassZhStrict = regex(#"(?<![真磁指])((?:正|偏)?(?:\#(compassZhCore))(?:偏[东南西北])?)(?=[向侧面窗方边部])|[朝向往]\s?((?:正)?(?:\#(compassZhCore))(?:偏[东南西北])?)"#)
    private static let northReference = regex(#"(?<![朝正])北向"#)
    private static let compassZhLoose = regex(#"((?:\#(compassZhCore))(?:偏[东南西北])?)"#)
    private static let compassEn = regex(#"(?<!true |magnetic )\b(?:(north|south)[\s-]?(east|west)|(north|south|east|west))\b(?![\s-]+(?:direction|source|reference|reading|readings|alignment|estimate|heading)\b)"#)

    /// Compass words in `text`. `loose` reads tool labels ("西北"); strict reads prose and needs a
    /// direction suffix in Chinese, so "南半球" and "真北" are not read as bearings.
    static func compassWords(in raw: String, loose: Bool) -> [String] {
        let text = loose ? raw : northReference.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "  ")
        let ns = text as NSString, all = NSRange(location: 0, length: ns.length)
        var out: [String] = []
        for m in (loose ? compassZhLoose : compassZhStrict).matches(in: text, range: all) {
            for i in 1..<m.numberOfRanges where m.range(at: i).location != NSNotFound {
                var word = ns.substring(with: m.range(at: i))
                if word.hasPrefix("偏") { word.removeFirst() }  // "偏南" says the same bearing word as "南"
                out.append(word)
            }
        }
        for m in compassEn.matches(in: text, range: all) {
            if m.range(at: 1).location != NSNotFound {
                out.append(ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)))
            } else {
                out.append(ns.substring(with: m.range(at: 3)))
            }
        }
        return out.map { $0.lowercased() }
    }

    // The tool never gives the sun's own direction, so any sun bearing is invented,
    // even when it reuses the window's compass word ("窗朝南，正午太阳偏南").
    private static let sunBearingZh = regex(#"(?:太阳|阳光|日光|日照)[^，。；,;！？\n]{0,6}?((?:正|偏)?(?:\#(compassZhCore))(?:偏[东南西北])?)(?![窗墙侧面边])"#)
    private static let sunBearingEn = regex(#"\bsun(?:light|shine)?\b[^.,;:!?]{0,40}?\b(?:from|in|towards?|to|across|over|at|into|through)\s+the\s+(?:low\s+|high\s+)?((?:north|south)[\s-]?(?:east|west)|north|south|east|west)(?:ern)?\b(?![\s-]*(?:facing|window|side|wall)\b)|\b((?:north|south)[\s-]?(?:east|west)|north|south|east|west)(?:ern|erly)\s+(?:sky|sun|light)\b"#)

    /// Sun bearings in `text`, after the tool's own cause labels are blanked out.
    static func sunBearings(in text: String, masking labels: [String]) -> [String] {
        var masked = text
        for label in labels where !label.isEmpty { masked = masked.replacingOccurrences(of: label, with: String(repeating: " ", count: label.count)) }
        let ns = masked as NSString, all = NSRange(location: 0, length: ns.length)
        return (sunBearingZh.matches(in: masked, range: all) + sunBearingEn.matches(in: masked, range: all)).map { m in
            (1..<m.numberOfRanges).compactMap { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }.joined()
        }
    }
}
