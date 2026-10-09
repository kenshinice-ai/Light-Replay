import Foundation
import NorthResolver

/// What the evidence in a record gives for the lights that can be worked out again from it.
public struct QualityEvaluation: Sendable, Equatable {
    /// The five lights. A 0.1.0 record carries evidence for the first three only; `level` (tracking) and `lens` stay
    /// as recorded there. A 0.2.0 record carries evidence for all five (ADR-0022).
    public enum Light: String, CaseIterable, Sendable {
        case coverage, north, segmentation, level, lens

        /// The lights that can be worked out again from a record of this schema version.
        public static func evaluated(v2: Bool) -> [Light] { v2 ? allCases : [.coverage, .north, .segmentation] }
    }

    public let gates: [Light: QualityGate]
    public let reasons: [Light: String]
    /// The direction the candidates give, and the light it earns.
    public let north: NorthResolution
    /// Physical contradictions that forbid anything beyond R0 whatever the lights say.
    public let problems: [String]
}

/// The five lights are claims; this works them out again from the record's own evidence and refuses a record whose
/// claims differ (docs/04 §6, ADR-0009, ADR-0022, reviews F05 and R08). quality-0.1 recomputes three lights of a
/// 0.1.0 record; quality-0.2 recomputes all five of a 0.2.0 record: tracking from the frames themselves, the horizon,
/// lens and reflection checks from `quality.evidence`. A check that did not run is missing evidence, and missing
/// evidence blocks; a check that ran and found nothing is not proof of absence. Mirrors `engine/lightreplay/quality.py`;
/// the two are held together by `quality-cases.json` and `scene-v2-cases.json`. Every limit is a candidate until the spike.
public enum QualityEvaluator {
    public static let version = "quality-0.1"
    public static let version2 = "quality-0.2"
    /// Tracking (quality-0.2): the longest stretch without normal tracking after it first became normal.
    public static let limitedWarnS = 0.5
    public static let limitedBlockS = 2.0
    /// Horizon against gravity, both as angles in the image (quality-0.2).
    public static let horizonPassDeg = 2.0
    public static let horizonWarnDeg = 5.0
    /// Lens smudge confidence from the detector, 0…1 (quality-0.2). Candidates until calibrated on the device.
    public static let smudgeWarn = 0.3
    public static let smudgeBlock = 0.6
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

        if fields["schema_version"] == .string("0.2.0") {
            let evidence = fields["quality"]?.object?["evidence"]?.object
            if corridor > 0, segmentation?["model"]?.string != nil {
                // "Reflections not identified" blocks (docs/04 §6). Looking and finding nothing lets the glass share
                // stand; it does not say there is no glass.
                switch evidence?["reflection"]?.object?["status"]?.string {
                case "none_found": break
                case "undetermined":
                    gates[.segmentation] = worst(gates[.segmentation] ?? .blocked, .warn)
                    reasons[.segmentation, default: ""] += "; reflections could not be ruled out"
                case "suspected":
                    gates[.segmentation] = worst(gates[.segmentation] ?? .blocked, .warn)
                    reasons[.segmentation, default: ""] += "; reflections suspected"
                default: (gates[.segmentation], reasons[.segmentation]) = (.blocked, "reflections were not checked")
                }
            }
            var (level, why) = tracking(fields["capture_session"]?.object?["frames"]?.array?.compactMap(\.object) ?? [])
            let horizon = evidence?["horizon"]?.object
            switch horizon?["status"]?.string {
            case "measured":
                let residual = horizon?["residual_deg"]?.number ?? .infinity
                level = worst(level, residual <= horizonPassDeg ? .pass : residual <= horizonWarnDeg ? .warn : .blocked)
                why += "; horizon \(residual) degrees off gravity"
            case "not_found": why += "; no horizon in view"   // most indoor frames have none: nothing held against the scan
            default:
                level = .blocked
                why += "; horizon not checked"
            }
            (gates[.level], reasons[.level]) = (level, why)
            let lens = evidence?["lens"]?.object
            if lens?["status"]?.string == "measured", let smudge = lens?["smudge_confidence"]?.number {
                gates[.lens] = smudge < smudgeWarn ? .pass : smudge < smudgeBlock ? .warn : .blocked
                reasons[.lens] = "lens smudge confidence \(smudge)"
            } else {
                gates[.lens] = .blocked
                reasons[.lens] = lens?["status"]?.string == "unusable_input" ? "no frame steady enough to check the lens" : "lens not checked"
            }
        }

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

    private static func worst(_ a: QualityGate, _ b: QualityGate) -> QualityGate {
        let order: [QualityGate] = [.pass, .warn, .blocked]
        return order.firstIndex(of: a)! >= order.firstIndex(of: b)! ? a : b
    }

    /// The tracking light from the frames of the scan itself. Frames taken while confirming the direction
    /// (`role: calibration`) are not part of the scan; what happens before tracking first becomes normal is start-up.
    /// The recorder keeps every change of tracking state (ADR-0020), so a stretch runs from its first frame to the
    /// next normal one.
    static func tracking(_ frames: [[String: JSONValue]]) -> (gate: QualityGate, reason: String) {
        let scan = frames.filter { ($0["role"]?.string ?? "visibility") == "visibility" }
        guard let first = scan.firstIndex(where: { $0["tracking_state"] == .string("normal") }) else {
            return (.blocked, "tracking never became normal")
        }
        var longest = 0.0, start: Double?
        for frame in scan[first...] {
            let t = frame["t"]?.number ?? 0
            if frame["tracking_state"] == .string("limited:relocalizing") {
                return (.blocked, "tracking relocalized at frame \(frame["frame_id"]?.string ?? "?"): the world frame may have moved")
            }
            if frame["tracking_state"] != .string("normal") {
                start = start ?? t
            } else if let began = start {
                longest = max(longest, t - began)
                start = nil
            }
        }
        if let began = start { longest = max(longest, (scan.last?["t"]?.number ?? began) - began) }
        let gate: QualityGate = longest <= limitedWarnS + 1e-9 ? .pass : longest <= limitedBlockS + 1e-9 ? .warn : .blocked
        return (gate, "longest stretch without normal tracking \(String(format: "%.2f", longest)) s")
    }

    /// Throws unless the record's stated quality follows from its evidence. For every record: the evaluable lights
    /// (three in 0.1.0, all five in 0.2.0) are stated as the evidence gives them, and a stored north resolution is the one its candidates produce.
    /// For a record that claims more than R0: no physical contradiction either. Unknown stays unknown: missing
    /// evidence is `blocked`, never assumed.
    @discardableResult
    static func check(_ fields: [String: JSONValue]) throws -> QualityEvaluation {
        let result = evaluate(fields)
        let quality = fields["quality"]?.object
        let stated = quality?["gates"]?.object
        for light in QualityEvaluation.Light.evaluated(v2: fields["schema_version"] == .string("0.2.0")) {
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
