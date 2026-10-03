import Foundation
import NorthResolver

/// What the evidence in a record gives for the lights that can be worked out again from it.
public struct QualityEvaluation: Sendable, Equatable {
    /// The lights schema 0.1.0 carries evidence for. `level` (tracking) and `lens` are decided by on-device detectors
    /// whose evidence the schema does not carry, so they stay as recorded.
    public enum Light: String, CaseIterable, Sendable {
        case coverage, north, segmentation
    }

    public let gates: [Light: QualityGate]
    public let reasons: [Light: String]
    /// The direction the candidates give, and the light it earns.
    public let north: NorthResolution
    /// Physical contradictions that forbid anything beyond R0 whatever the lights say.
    public let problems: [String]
}

/// The five lights are claims; this works three of them out again from the record's own evidence and refuses a record
/// whose claims differ (docs/04 §6, ADR-0009, reviews F05 and R08). Mirrors `engine/lightreplay/quality.py`; the two
/// are held together by `engine/tests/fixtures/quality-cases.json`. Every limit is a candidate until the spike.
public enum QualityEvaluator {
    public static let version = "quality-0.1"
    /// Share of the sun corridor seen: at least this passes, at least `coverageWarnPct` warns (docs/04 §6).
    public static let coveragePassPct = 90.0
    public static let coverageWarnPct = 70.0
    /// Share of the corridor that is glass-uncertain: below warn passes, up to block warns (docs/04 §6).
    public static let glassWarnPct = 10.0
    public static let glassBlockPct = 25.0
    /// A frame further than this from the anchor is not merged into the visibility grid (docs/04 §4).
    public static let driftLimitM = 0.40
    /// Numerical slack for "the same point" and for one-decimal rounding of a stored resolution. Not product limits.
    static let anchorMatchM = 1e-6
    static let resolvedMatchDeg = 0.1

    /// Recomputes the evaluable lights of a shape-valid record.
    public static func evaluate(_ fields: [String: JSONValue]) -> QualityEvaluation {
        var gates: [QualityEvaluation.Light: QualityGate] = [:]
        var reasons: [QualityEvaluation.Light: String] = [:]
        let visibility = fields["visibility"]?.object
        let coverage = visibility?["coverage"]?.object
        let corridor = coverage?["corridor_cells"]?.number ?? 0
        // Cell counts are integers, so the limits are compared without division: 63 of 90 is exactly 70%.
        if corridor <= 0 {
            (gates[.coverage], reasons[.coverage]) = (.blocked, "no sun corridor evidence")
        } else {
            let covered = coverage?["covered_cells"]?.number ?? 0
            gates[.coverage] = covered * 100 >= coveragePassPct * corridor ? .pass
                : covered * 100 >= coverageWarnPct * corridor ? .warn : .blocked
            reasons[.coverage] = "\(Int(covered)) of \(Int(corridor)) corridor cells seen"
        }

        let segmentation = visibility?["segmentation"]?.object
        if corridor <= 0 || segmentation == nil || segmentation?["model"]?.string == nil {
            (gates[.segmentation], reasons[.segmentation]) = (.blocked, "no segmentation evidence")
        } else {
            let glass = coverage?["glass_cells"]?.number ?? 0
            gates[.segmentation] = glass * 100 < glassWarnPct * corridor ? .pass
                : glass * 100 <= glassBlockPct * corridor ? .warn : .blocked
            reasons[.segmentation] = "\(Int(glass)) of \(Int(corridor)) corridor cells are glass-uncertain"
        }

        let north = NorthResolver.resolve(readings(fields))
        (gates[.north], reasons[.north]) = (north.gate, north.reason)

        var problems: [String] = []
        let session = fields["capture_session"]?.object
        if let target = fields["target"]?.object?["anchor_world"]?.vector,
           let lock = session?["viewpoint_lock"]?.object?["anchor_world"]?.vector, target.count == 3, lock.count == 3 {
            let gap = zip(target, lock).reduce(0) { $0 + pow($1.0 - $1.1, 2) }.squareRoot()
            if gap > anchorMatchM {
                problems.append("target anchor and viewpoint lock anchor are \(String(format: "%.3f", gap)) m apart: not one viewpoint")
            }
        }
        for frame in session?["frames"]?.array?.compactMap(\.object) ?? [] where frame["used_for_visibility"] == .bool(true) {
            let id = frame["frame_id"]?.string ?? "?"
            if frame["tracking_state"] != .string("normal") {
                problems.append("frame \(id) is used for visibility without normal tracking")
            } else if (frame["lens_offset_m"]?.number).map({ $0 > driftLimitM + 1e-9 }) ?? true {
                problems.append("frame \(id) is used for visibility beyond the \(driftLimitM) m drift limit")
            }
        }
        return QualityEvaluation(gates: gates, reasons: reasons, north: north, problems: problems)
    }

    /// Throws unless the record's stated quality follows from its evidence. For every record: the three evaluable
    /// lights are stated as the evidence gives them, and a stored north resolution is the one its candidates produce.
    /// For a record that claims more than R0: no physical contradiction either. Unknown stays unknown: missing
    /// evidence is `blocked`, never assumed.
    @discardableResult
    static func check(_ fields: [String: JSONValue]) throws -> QualityEvaluation {
        let result = evaluate(fields)
        let quality = fields["quality"]?.object
        let stated = quality?["gates"]?.object
        for light in QualityEvaluation.Light.allCases {
            let claim = stated?[light.rawValue]?.string ?? "nothing"
            let given = result.gates[light] ?? .blocked
            if claim != given.rawValue {
                throw SceneRecordValidationError("$.quality.gates.\(light.rawValue)",
                    "stated \(claim), but the evidence gives \(given.rawValue) (\(result.reasons[light] ?? ""))")
            }
        }
        if let resolved = fields["north"]?.object?["resolved"]?.object {
            let north = result.north
            let same = north.yawDeg.map { yaw in
                Set(resolved["groups_used"]?.strings ?? []) == Set(north.groupsUsed.map(\.rawValue))
                    && Set(resolved["groups_rejected"]?.strings ?? []) == Set(north.groupsRejected.map(\.rawValue))
                    && resolved["conflict"] == .bool(north.conflict)
                    && (resolved["yaw_deg"]?.number).map { NorthResolver.circularDifference($0, yaw) <= resolvedMatchDeg } == true
                    && (resolved["sigma_deg"]?.number).map { abs($0 - (north.sigmaDeg ?? .infinity)) <= resolvedMatchDeg } == true
            } ?? false
            if !same { throw SceneRecordValidationError("$.north.resolved", "does not follow from the candidates") }
        }
        if quality?["level"] != .string("R0"), let problem = result.problems.first {
            throw SceneRecordValidationError("$.quality.level", problem)
        }
        return result
    }

    /// The record's valid candidates as readings. A candidate that is not valid, or carries no azimuth or σ, is left out.
    private static func readings(_ fields: [String: JSONValue]) -> [NorthReading] {
        (fields["north"]?.object?["candidates"]?.array ?? []).compactMap { item in
            guard let candidate = item.object, candidate["valid"] == .bool(true),
                  let group = candidate["group"]?.string.flatMap(NorthGroup.init(rawValue:)),
                  let yaw = candidate["yaw_deg"]?.number, let sigma = candidate["sigma_deg"]?.number else { return nil }
            return NorthReading(group: group, yawDeg: yaw, sigmaDeg: sigma)
        }
    }
}

extension JSONValue {
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var strings: [String]? { array?.compactMap(\.string) }
    var vector: [Double]? { array?.compactMap(\.number) }
}
