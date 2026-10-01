import Foundation

/// The independent groups a direction reading can belong to (docs/05 §2). Readings inside one group share a sensor
/// or a method, so they count once. Declared most trusted first (docs/05 §3 step 4).
public enum NorthGroup: String, CaseIterable, Sendable, Codable {
    case solar, vps, map, magnetic
}

/// One source's reading of Δ, the true azimuth of the AR world's −Z axis, with its 1σ.
public struct NorthReading: Sendable, Equatable {
    public let group: NorthGroup
    public let yawDeg: Double
    public let sigmaDeg: Double

    public init(group: NorthGroup, yawDeg: Double, sigmaDeg: Double) {
        self.group = group
        self.yawDeg = yawDeg
        self.sigmaDeg = sigmaDeg
    }

    /// A reading that states no uncertainty cannot be weighed.
    var isUsable: Bool { yawDeg.isFinite && sigmaDeg.isFinite && sigmaDeg > 0 }
}

/// The lights of docs/04 §6.
public enum QualityGate: String, Sendable, Codable {
    case pass, warn, blocked
}

public struct NorthResolution: Sendable, Equatable {
    public struct Group: Sendable, Equatable {
        public let yawDeg: Double
        public let sigmaDeg: Double
        /// RMS of the readings about their median.
        public let spreadDeg: Double
        public let readings: Int
    }

    public struct Disagreement: Sendable, Equatable {
        public let a: NorthGroup
        public let b: NorthGroup
        public let differenceDeg: Double
        public let limitDeg: Double
    }

    /// Fused Δ and its 1σ; nil when no group is usable.
    public let yawDeg: Double?
    public let sigmaDeg: Double?
    public let groups: [NorthGroup: Group]
    /// Most trusted first.
    public let groupsUsed: [NorthGroup]
    public let groupsRejected: [NorthGroup]
    /// A group other than `magnetic` was rejected (ADR-0009 rule 4).
    public let conflict: Bool
    /// Every pair that disagrees, including a compass that was simply outvoted.
    public let disagreements: [Disagreement]
    public let gate: QualityGate
    /// One minimal confirmation is required before anything beyond R0.
    public let needsConfirmation: Bool
    public let reason: String
}

/// Direction fusion (docs/05 §3, ADR-0009). Mirrors `engine/lightreplay/north.py`; the two are held together by
/// `engine/tests/fixtures/north-cases.json`. The σ model and every limit are candidates until the sundial spike.
public enum NorthResolver {
    public static let version = "northresolver-0.1"
    public static let method = "robust_circular_v0"
    /// Two groups conflict when their circular difference exceeds K · sqrt(σ_i² + σ_j²) (docs/05 §3 step 3).
    public static let conflictK = 3.0
    /// A single group above this σ needs one confirmation before anything beyond R0 (docs/05 §3 step 5, candidate).
    public static let singleGroupSigmaLimitDeg = 6.0

    /// `angle` folded into [0, 360).
    public static func mod360(_ angle: Double) -> Double {
        let folded = angle - 360 * (angle / 360).rounded(.down)
        return folded >= 360 ? folded - 360 : folded   // −1e-17 folds to 360.0 in floating point
    }

    /// Unsigned difference between two azimuths, 0…180.
    public static func circularDifference(_ a: Double, _ b: Double) -> Double {
        let d = mod360(a - b)
        return min(d, 360 - d)
    }

    /// `angle − reference` folded into [−180, 180).
    public static func signedOffset(_ angle: Double, from reference: Double) -> Double {
        mod360(angle - reference + 180) - 180
    }

    private static func median(_ sorted: [Double]) -> Double {
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Readings of one independent group as one value (docs/05 §3 step 1): the circular median, with σ the larger
    /// of the readings' median σ and their RMS spread about that median. Readings of one sensor are not independent
    /// evidence, so more of them never shrinks σ. `readings` must not be empty.
    public static func merge(_ readings: [(yawDeg: Double, sigmaDeg: Double)]) -> NorthResolution.Group {
        if readings.count == 1 {   // one reading is its own median, exactly: no trigonometry in between
            return .init(yawDeg: mod360(readings[0].yawDeg), sigmaDeg: readings[0].sigmaDeg, spreadDeg: 0, readings: 1)
        }
        let radians = Double.pi / 180
        let s = readings.reduce(0) { $0 + sin($1.yawDeg * radians) }
        let c = readings.reduce(0) { $0 + cos($1.yawDeg * radians) }
        // Offsets are taken about the mean direction so the median is not split by the 0°/360° seam. Readings that
        // cancel out have no mean direction; the first one is the reference then, and the spread says the rest.
        let reference = hypot(s, c) > 1e-9 ? atan2(s, c) / radians : readings[0].yawDeg
        let yaw = mod360(reference + median(readings.map { signedOffset($0.yawDeg, from: reference) }.sorted()))
        let spread = (readings.reduce(0) { $0 + pow(signedOffset($1.yawDeg, from: yaw), 2) } / Double(readings.count)).squareRoot()
        return .init(yawDeg: yaw, sigmaDeg: max(median(readings.map(\.sigmaDeg).sorted()), spread), spreadDeg: spread,
                     readings: readings.count)
    }

    public static func resolve(_ readings: [NorthReading]) -> NorthResolution {
        var byGroup: [NorthGroup: [(yawDeg: Double, sigmaDeg: Double)]] = [:]
        for reading in readings where reading.isUsable {
            byGroup[reading.group, default: []].append((reading.yawDeg, reading.sigmaDeg))
        }
        let order = NorthGroup.allCases.filter { byGroup[$0] != nil }
        let groups = Dictionary(uniqueKeysWithValues: order.map { ($0, merge(byGroup[$0]!)) })
        guard !order.isEmpty else {
            return .init(yawDeg: nil, sigmaDeg: nil, groups: [:], groupsUsed: [], groupsRejected: [], conflict: false,
                         disagreements: [], gate: .blocked, needsConfirmation: false, reason: "no valid direction source")
        }
        func limit(_ a: NorthGroup, _ b: NorthGroup) -> Double { conflictK * hypot(groups[a]!.sigmaDeg, groups[b]!.sigmaDeg) }
        func difference(_ a: NorthGroup, _ b: NorthGroup) -> Double { circularDifference(groups[a]!.yawDeg, groups[b]!.yawDeg) }
        func agree(_ a: NorthGroup, _ b: NorthGroup) -> Bool { difference(a, b) <= limit(a, b) }
        func pairs(_ set: [NorthGroup]) -> [(NorthGroup, NorthGroup)] {
            set.indices.flatMap { i in set.indices.filter { $0 > i }.map { (set[i], set[$0]) } }
        }
        let disagreements = pairs(order).filter { !agree($0.0, $0.1) }.map {
            NorthResolution.Disagreement(a: $0.0, b: $0.1, differenceDeg: difference($0.0, $0.1), limitDeg: limit($0.0, $0.1))
        }
        // The largest set whose members all agree with each other. Subsets are tried largest first and, within one
        // size, in trust order, so the first that holds together has the most trusted members (step 4).
        let used = subsets(of: order).first { set in pairs(set).allSatisfy { agree($0.0, $0.1) } }!
        let weights = used.map { 1 / pow(groups[$0]!.sigmaDeg, 2) }
        let radians = Double.pi / 180
        let s = zip(weights, used).reduce(0) { $0 + $1.0 * sin(groups[$1.1]!.yawDeg * radians) }
        let c = zip(weights, used).reduce(0) { $0 + $1.0 * cos(groups[$1.1]!.yawDeg * radians) }
        let sigma = (1 / weights.reduce(0, +)).squareRoot()
        let rejected = order.filter { !used.contains($0) }
        let conflict = rejected.contains { $0 != .magnetic }
        let gate: QualityGate, needsConfirmation: Bool, reason: String
        if conflict {
            (gate, needsConfirmation) = (.blocked, true)
            reason = "sources disagree: " + rejected.filter { $0 != .magnetic }.map(\.rawValue).joined(separator: ", ") + " rejected"
        } else if used.count >= 2 {
            (gate, needsConfirmation, reason) = (.pass, false, "\(used.count) independent groups agree")
        } else if sigma <= singleGroupSigmaLimitDeg {
            (gate, needsConfirmation, reason) = (.warn, false, "one group only")
        } else {
            (gate, needsConfirmation) = (.blocked, true)
            reason = "one group only, and its sigma is above \(formatted(singleGroupSigmaLimitDeg)) degrees"
        }
        return .init(yawDeg: mod360(atan2(s, c) / radians), sigmaDeg: sigma, groups: groups, groupsUsed: used,
                     groupsRejected: rejected, conflict: conflict, disagreements: disagreements, gate: gate,
                     needsConfirmation: needsConfirmation, reason: reason)
    }

    /// Non-empty subsets, largest first; within one size in the order Python's `itertools.combinations` gives.
    private static func subsets(of order: [NorthGroup]) -> [[NorthGroup]] {
        func combinations(_ items: ArraySlice<NorthGroup>, _ count: Int) -> [[NorthGroup]] {
            guard count > 0 else { return [[]] }
            guard let first = items.first, items.count >= count else { return [] }
            return combinations(items.dropFirst(), count - 1).map { [first] + $0 } + combinations(items.dropFirst(), count)
        }
        return (1...order.count).reversed().flatMap { combinations(order[...], $0) }
    }

    /// 6.0 as "6", 6.5 as "6.5": the same text Python's `:g` gives, so reasons match across the two implementations.
    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
