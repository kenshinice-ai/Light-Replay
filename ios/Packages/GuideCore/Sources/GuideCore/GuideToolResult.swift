import Foundation

/// What SunEngine and NorthResolver hand to Guide for one TargetPoint (ADR-0010 "允许" 4).
///
/// Field names follow SceneRecord (`docs/03-scene-record.md` §4, §5, §7, §8) so a future
/// SunEngine package can map its `AnalysisResult` onto this type one field at a time.
/// Every number is a display string, exactly as the tool renders it: Guide must quote it
/// character for character, so "0" and "0.0" are different facts.
public struct GuideToolResult: Codable, Equatable, Sendable {
    public enum Hemisphere: String, Codable, Sendable { case north, south }
    public enum Level: String, Codable, Sendable { case r0 = "R0", r1 = "R1", r2 = "R2", r3 = "R3" }
    public enum FalseValidGuard: String, Codable, Sendable { case passed, blocked }
    /// Same states as `analysis[].bands[].segments[].state`.
    public enum State: String, Codable, Sendable { case direct, sensitive, blocked, unknown }

    public struct Bearing: Codable, Equatable, Sendable {
        /// True bearing, clockwise from true north.
        public var deg: String
        public var labelZh: String
        public var labelEn: String
        public init(deg: String, labelZh: String, labelEn: String) { self.deg = deg; self.labelZh = labelZh; self.labelEn = labelEn }
    }

    public struct North: Codable, Equatable, Sendable {
        /// `05-north-resolver.md` §6: agreed, single group, conflict, or no valid source.
        public enum Status: String, Codable, Sendable { case agreed, singleGroup = "single_group", conflict, none }
        public var status: Status
        public var sigmaDeg: String?
        public init(status: Status, sigmaDeg: String?) { self.status = status; self.sigmaDeg = sigmaDeg }
    }

    public struct Segment: Codable, Equatable, Sendable {
        public var from: String
        public var to: String
        public var state: State
        public init(from: String, to: String, state: State) { self.from = from; self.to = to; self.state = state }
    }

    /// One queried date (a solstice, an equinox, or any day), with its stable direct hours.
    public struct Period: Codable, Equatable, Sendable {
        public var labelZh: String
        public var labelEn: String
        public var date: String
        public var state: State
        /// Stable direct hours. `nil` when the period is Unknown: the tool has no number.
        public var directHours: String?
        /// The "上界" of `06-sun-engine.md` §6 step 4: Unknown cells counted as sky. Never a fact.
        public var upperBoundHours: String?
        public var segments: [Segment]
        public init(labelZh: String, labelEn: String, date: String, state: State, directHours: String?, upperBoundHours: String? = nil, segments: [Segment]) {
            self.labelZh = labelZh; self.labelEn = labelEn; self.date = date; self.state = state
            self.directHours = directHours; self.upperBoundHours = upperBoundHours; self.segments = segments
        }
    }

    /// `analysis[].attribution[]`, with the cause already named by the tool.
    public struct Attribution: Codable, Equatable, Sendable {
        public var from: String
        public var to: String
        public var causeZh: String
        public var causeEn: String
        public var azRangeDeg: [String]
        public init(from: String, to: String, causeZh: String, causeEn: String, azRangeDeg: [String]) {
            self.from = from; self.to = to; self.causeZh = causeZh; self.causeEn = causeEn; self.azRangeDeg = azRangeDeg
        }
    }

    public var hemisphere: Hemisphere
    public var level: Level
    public var falseValidGuard: FalseValidGuard
    public var facing: Bearing?
    public var north: North
    public var coveragePct: String?
    /// `quality.flags` contains `glass_present` and the glass cells were not resolved.
    public var glassUncertain: Bool
    /// `quality.assist.degraded`: `fm_unavailable`, `seg_assets_missing`, `pcc_quota`.
    public var degraded: [String]
    public var periods: [Period]
    public var attribution: [Attribution]

    public init(hemisphere: Hemisphere, level: Level, falseValidGuard: FalseValidGuard, facing: Bearing?, north: North,
                coveragePct: String?, glassUncertain: Bool, degraded: [String], periods: [Period], attribution: [Attribution]) {
        self.hemisphere = hemisphere; self.level = level; self.falseValidGuard = falseValidGuard; self.facing = facing
        self.north = north; self.coveragePct = coveragePct; self.glassUncertain = glassUncertain; self.degraded = degraded
        self.periods = periods; self.attribution = attribution
    }

    /// R0 or a blocked false-valid guard: the record may not carry hours (`03` §8, `01` §12).
    public var isAllUnknown: Bool { level == .r0 || falseValidGuard == .blocked }

    /// Decoder for the snake_case JSON used by fixtures and SceneRecord.
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }()
}
