import Foundation

private typealias Object = [String: JSONValue]

private extension Dictionary where Key == String, Value == JSONValue {
    func value(_ key: String) -> JSONValue { self[key] ?? .null }
}

internal enum SceneValidator {
    private static let timeKeys: Set<String> = ["created_at", "captured_at", "started_at", "ended_at", "sampled_at", "resolved_at", "computed_at", "revoked_at", "timestamp"]
    private static let accuracyKeys: Set<String> = ["h_acc_m", "v_acc_m", "heading_accuracy", "sigma_deg", "yaw_sigma_deg", "boundary_jitter_deg"]
    private static let groups = ["magnetic", "map", "solar", "vps"]

    private static func require(_ condition: Bool, _ path: String, _ reason: String) throws {
        if !condition { throw SceneRecordValidationError(path, reason) }
    }

    private static func object(_ value: JSONValue, _ path: String, _ keys: String = "") throws -> Object {
        guard case .object(let result) = value else { throw SceneRecordValidationError(path, "expected object") }
        for key in keys.split(separator: " ").map(String.init) {
            try require(result[key] != nil, path, "missing \(key)")
        }
        return result
    }

    private static func array(_ value: JSONValue, _ path: String) throws -> [JSONValue] {
        guard case .array(let result) = value else { throw SceneRecordValidationError(path, "expected array") }
        return result
    }

    @discardableResult private static func text(_ value: JSONValue, _ path: String) throws -> String {
        guard case .string(let result) = value, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SceneRecordValidationError(path, "expected nonempty string")
        }
        return result
    }

    private static func optionalText(_ value: JSONValue, _ path: String) throws {
        if value != .null { try text(value, path) }
    }

    @discardableResult private static func number(_ value: JSONValue, _ path: String, low: Double? = nil, high: Double? = nil, integer: Bool = false) throws -> Double {
        guard case .number(let result) = value, result.isFinite else {
            throw SceneRecordValidationError(path, "expected finite number, not bool")
        }
        try require(low == nil || result >= low!, path, "number below range")
        try require(high == nil || result <= high!, path, "number above range")
        try require(!integer || result.rounded(.down) == result, path, "expected integer")
        return result
    }

    private static func optionalNumber(_ value: JSONValue, _ path: String, low: Double? = nil, high: Double? = nil) throws {
        if value != .null { try number(value, path, low: low, high: high) }
    }

    @discardableResult private static func boolean(_ value: JSONValue, _ path: String) throws -> Bool {
        guard case .bool(let result) = value else { throw SceneRecordValidationError(path, "expected boolean") }
        return result
    }

    @discardableResult private static func choice(_ value: JSONValue, _ choices: [String], _ path: String) throws -> String {
        let result = try text(value, path)
        try require(choices.contains(result), path, "unsupported value")
        return result
    }

    private static func vector(_ value: JSONValue, _ count: Int, _ path: String) throws {
        let values = try array(value, path)
        try require(values.count == count, path, "expected \(count) numbers")
        for (index, item) in values.enumerated() { try number(item, "\(path)[\(index)]") }
    }

    private static func strings(_ value: JSONValue, _ path: String) throws -> [String] {
        try array(value, path).map { try text($0, path) }
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    @discardableResult private static func timestamp(_ value: JSONValue, _ path: String) throws -> Double {
        let s = try text(value, path)
        try require(matches(s, "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,9})?(?:Z|[+-][0-9]{2}:[0-9]{2})\\z"), path, "expected ISO 8601 timestamp with explicit offset")
        let bytes = Array(s.utf8)
        func part(_ from: Int, _ to: Int) -> Int { Int(String(decoding: bytes[from..<to], as: UTF8.self))! }
        let year = part(0, 4), month = part(5, 7), day = part(8, 10)
        let hour = part(11, 13), minute = part(14, 16), second = part(17, 19)
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        try require(year >= 1 && month >= 1 && month <= 12, path, "invalid calendar date")
        try require(day >= 1 && day <= days[month - 1] && hour <= 23 && minute <= 59 && second <= 59, path, "invalid calendar timestamp")
        var offset = 0
        let suffixStart = bytes.last == 90 ? bytes.count - 1 : bytes.count - 6
        if bytes.last != 90 {
            let hh = part(suffixStart + 1, suffixStart + 3), mm = part(suffixStart + 4, suffixStart + 6)
            try require(hh <= 23 && mm <= 59, path, "invalid UTC offset")
            offset = (hh * 3600 + mm * 60) * (bytes[suffixStart] == 43 ? 1 : -1)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let result = calendar.date(from: components) else { throw SceneRecordValidationError(path, "invalid date") }
        var fraction = 0.0
        if suffixStart > 19 {
            fraction = Double("0" + String(decoding: bytes[19..<suffixStart], as: UTF8.self))!
        }
        return result.timeIntervalSince1970 + fraction - Double(offset)
    }

    private static func date(_ value: JSONValue, _ path: String) throws {
        let s = try text(value, path)
        try require(matches(s, "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}\\z"), path, "invalid date")
        try timestamp(.string(s + "T00:00:00Z"), path)
    }

    private static func assetPath(_ value: JSONValue, _ path: String) throws {
        if value == .null { return }
        let s = try text(value, path)
        try require(!s.contains(where: { "\\:%?#".contains($0) }) && !s.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }), path, "unsafe asset reference")
        try require(s.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, path, "expected safe relative asset path")
    }

    private static func walk(_ value: JSONValue, _ path: String = "$", depth: Int = 0) throws {
        try require(depth <= 128, path, "JSON nesting exceeds 128")
        switch value {
        case .object(let values):
            for (key, child) in values {
                let p = path + "." + key
                if key.hasSuffix("_ref") { try assetPath(child, p) }
                if timeKeys.contains(key) && child != .null { try timestamp(child, p) }
                if accuracyKeys.contains(key) { try optionalNumber(child, p, low: 0) }
                try walk(child, p, depth: depth + 1)
            }
        case .array(let values):
            for (i, child) in values.enumerated() { try walk(child, "\(path)[\(i)]", depth: depth + 1) }
        case .number: try number(value, path)
        default: break
        }
    }

    static func validate(_ fields: [String: JSONValue]) throws {
        let root = JSONValue.object(fields)
        try walk(root)
        let r = try object(root, "$", "schema_version scene_id created_at timezone app device location target capture_session north visibility geometry analysis quality sharing context")
        try choice(r.value("schema_version"), ["0.1.0"], "$.schema_version")
        try text(r.value("scene_id"), "$.scene_id")
        try timestamp(r.value("created_at"), "$.created_at")
        let zone = try text(r.value("timezone"), "$.timezone")
        // TimeZone(identifier:) resolves IANA links such as Etc/UTC and Asia/Kolkata, matching Python's ZoneInfo.
        try require(zone == "UTC" || (zone.contains("/") && TimeZone(identifier: zone) != nil), "$.timezone", "unknown IANA timezone")
        let app = try object(r.value("app"), "$.app", "version build algorithms")
        for key in ["version", "build"] { try text(app.value(key), "$.app." + key) }
        let algorithms = try object(app.value("algorithms"), "$.app.algorithms", "sun segmentation north visibility")
        for (key, value) in algorithms { try optionalText(value, "$.app.algorithms." + key) }
        let device = try object(r.value("device"), "$.device", "model os lidar scene_depth geo_tracking")
        for key in ["model", "os", "geo_tracking"] { try text(device.value(key), "$.device." + key) }
        for key in ["lidar", "scene_depth"] { try boolean(device.value(key), "$.device." + key) }
        if r.value("location") != .null {
            let loc = try object(r.value("location"), "$.location", "lat lon alt_m h_acc_m v_acc_m source captured_at")
            try optionalNumber(loc.value("lat"), "$.location.lat", low: -90, high: 90)
            try optionalNumber(loc.value("lon"), "$.location.lon", low: -180, high: 180)
            try optionalNumber(loc.value("alt_m"), "$.location.alt_m")
            try text(loc.value("source"), "$.location.source")
            try timestamp(loc.value("captured_at"), "$.location.captured_at")
        }
        if r.value("target") != .null {
            let target = try object(r.value("target"), "$.target", "target_id label height_m anchor_world confirmed_by notes")
            for key in ["target_id", "label"] { try text(target.value(key), "$.target." + key) }
            try optionalNumber(target.value("height_m"), "$.target.height_m", low: 0)
            try vector(target.value("anchor_world"), 3, "$.target.anchor_world")
            for key in ["confirmed_by", "notes"] { try optionalText(target.value(key), "$.target." + key) }
        }
        if r.value("capture_session") != .null { try capture(r.value("capture_session")) }
        try north(r.value("north"))
        if r.value("visibility") != .null { try visibility(r.value("visibility")) }
        if r.value("geometry") != .null { try geometry(r.value("geometry")) }
        let analyses = try array(r.value("analysis"), "$.analysis")
        let q = try object(r.value("quality"), "$.quality", "level gates flags false_valid_guard blocked_reason")
        let level = try choice(q.value("level"), ["R0", "R1", "R2", "R3"], "$.quality.level")
        let guardState = try choice(q.value("false_valid_guard"), ["blocked", "passed"], "$.quality.false_valid_guard")
        let gates = try object(q.value("gates"), "$.quality.gates", "level coverage north segmentation lens")
        for (key, value) in gates { try choice(value, ["pass", "warn", "blocked"], "$.quality.gates." + key) }
        _ = try strings(q.value("flags"), "$.quality.flags")
        try optionalText(q.value("blocked_reason"), "$.quality.blocked_reason")
        if level == "R0" || guardState == "blocked" {
            try require(analyses.isEmpty, "$.analysis", "R0 or blocked records must have empty analysis")
        }
        if level != "R0" || guardState == "passed" {
            try require(level != "R0" && guardState == "passed", "$.quality", "inconsistent level/guard")
            try require(!gates.values.contains(.string("blocked")), "$.quality.gates", "blocked gate forbids analysis-ready status")
            try require(q.value("blocked_reason") == .null, "$.quality.blocked_reason", "passed guard cannot retain a blocked reason")
            try evidence(r)
        }
        try analysis(analyses)
        let sharing = try object(r.value("sharing"), "$.sharing", "include_hero precise_address revoked revoked_at")
        for key in ["include_hero", "precise_address", "revoked"] { try boolean(sharing.value(key), "$.sharing." + key) }
        try require(sharing.value("revoked") != .bool(true) || sharing.value("revoked_at") != .null, "$.sharing.revoked_at", "revocation requires timestamp")
        _ = try object(r.value("context"), "$.context", "address_estimate")
    }

    private static func capture(_ value: JSONValue) throws {
        let p = "$.capture_session"
        let s = try object(value, p, "session_id started_at ended_at world_alignment hero_frame frames viewpoint_lock guidance")
        try text(s.value("session_id"), p + ".session_id")
        let start = try timestamp(s.value("started_at"), p + ".started_at")
        let end = try timestamp(s.value("ended_at"), p + ".ended_at")
        try require(end >= start, p, "session ends before it starts")
        try choice(s.value("world_alignment"), ["gravity", "gravityAndHeading"], p + ".world_alignment")
        if s.value("hero_frame") != .null {
            let h = try object(s.value("hero_frame"), p + ".hero_frame", "frame_id image_ref timestamp intrinsics camera_transform exposure")
            try text(h.value("frame_id"), p + ".hero_frame.frame_id")
            try timestamp(h.value("timestamp"), p + ".hero_frame.timestamp")
            try vector(h.value("intrinsics"), 9, p + ".hero_frame.intrinsics")
            // Flat column-major storage is preserved, never transposed or resolved.
            try vector(h.value("camera_transform"), 16, p + ".hero_frame.camera_transform")
        }
        var ids = Set<String>()
        for (i, item) in try array(s.value("frames"), p + ".frames").enumerated() {
            let fp = "\(p).frames[\(i)]"
            let f = try object(item, fp, "frame_id t camera_transform intrinsics tracking_state lens_offset_m depth_ref depth_confidence_ref mask_ref exposure_offset used_for_visibility")
            let id = try text(f.value("frame_id"), fp + ".frame_id")
            try require(ids.insert(id).inserted, fp, "duplicate frame_id")
            try vector(f.value("camera_transform"), 16, fp + ".camera_transform")
            try vector(f.value("intrinsics"), 9, fp + ".intrinsics")
            try number(f.value("t"), fp + ".t", low: 0, high: end - start)
            try optionalNumber(f.value("lens_offset_m"), fp + ".lens_offset_m", low: 0)
            try optionalNumber(f.value("exposure_offset"), fp + ".exposure_offset")
            try boolean(f.value("used_for_visibility"), fp + ".used_for_visibility")
            let state = try text(f.value("tracking_state"), fp + ".tracking_state")
            try require(["normal", "not_available"].contains(state) || (state.hasPrefix("limited:") && !state.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), fp, "invalid tracking state")
        }
        let lock = try object(s.value("viewpoint_lock"), p + ".viewpoint_lock", "anchor_world tolerance_m max_drift_m frames_within frames_beyond handling")
        try vector(lock.value("anchor_world"), 3, p + ".viewpoint_lock.anchor_world")
        for key in ["tolerance_m", "max_drift_m"] { try optionalNumber(lock.value(key), p + ".viewpoint_lock." + key, low: 0) }
        for key in ["frames_within", "frames_beyond"] { try number(lock.value(key), p + ".viewpoint_lock." + key, low: 0, integer: true) }
        try choice(lock.value("handling"), ["depth_recentered", "tolerated", "rejected"], p + ".viewpoint_lock.handling")
        let g = try object(s.value("guidance"), p + ".guidance", "question corridor_ref")
        try choice(g.value("question"), ["winter_breakfast", "full_year", "west_afternoon", "custom"], p + ".guidance.question")
    }

    private static func north(_ value: JSONValue) throws {
        let n = try object(value, "$.north", "candidates resolved")
        for (i, item) in try array(n.value("candidates"), "$.north.candidates").enumerated() {
            let p = "$.north.candidates[\(i)]"
            let c = try object(item, p, "source group yaw_deg sigma_deg valid")
            try text(c.value("source"), p + ".source")
            try choice(c.value("group"), groups, p + ".group")
            let valid = try boolean(c.value("valid"), p + ".valid")
            if valid || c.value("yaw_deg") != .null {
                let yaw = try number(c.value("yaw_deg"), p + ".yaw_deg", low: 0, high: 360)
                try require(yaw < 360, p, "yaw must be less than 360")
            }
            if valid || c.value("sigma_deg") != .null { try number(c.value("sigma_deg"), p + ".sigma_deg", low: 0) }
        }
        if n.value("resolved") != .null {
            let p = "$.north.resolved"
            let r = try object(n.value("resolved"), p, "yaw_deg sigma_deg method groups_used groups_rejected conflict conflict_detail resolved_at")
            let yaw = try number(r.value("yaw_deg"), p + ".yaw_deg", low: 0, high: 360)
            try require(yaw < 360, p, "yaw must be less than 360")
            try number(r.value("sigma_deg"), p + ".sigma_deg", low: 0)
            try text(r.value("method"), p + ".method")
            try boolean(r.value("conflict"), p + ".conflict")
            try optionalText(r.value("conflict_detail"), p + ".conflict_detail")
            try timestamp(r.value("resolved_at"), p + ".resolved_at")
            for key in ["groups_used", "groups_rejected"] {
                let items = try strings(r.value(key), p + "." + key)
                try require(items.count == Set(items).count, p + "." + key, "duplicate group")
                for group in items { try choice(.string(group), groups, p + "." + key) }
            }
            let used = try strings(r.value("groups_used"), p + ".groups_used")
            let rejected = try strings(r.value("groups_rejected"), p + ".groups_rejected")
            try require(Set(used).isDisjoint(with: rejected), p, "used/rejected groups overlap")
        }
    }

    private static func visibility(_ value: JSONValue) throws {
        let p = "$.visibility"
        let v = try object(value, p, "grid states_ref confidence_ref votes coverage segmentation near_field")
        let grid = try object(v.value("grid"), p + ".grid", "az_step_deg alt_step_deg az_frame alt_range")
        for key in ["az_step_deg", "alt_step_deg"] {
            let step = try number(grid.value(key), p + ".grid." + key, low: 0, high: 360)
            try require(step > 0, p + ".grid." + key, "step must be positive")
        }
        try choice(grid.value("az_frame"), ["ar_world"], p + ".grid.az_frame")
        try vector(grid.value("alt_range"), 2, p + ".grid.alt_range")
        let range = try array(grid.value("alt_range"), p)
        let lo = try number(range[0], p), hi = try number(range[1], p)
        try require(lo >= -90 && lo < hi && hi <= 90, p, "invalid altitude range")
        if v.value("votes") != .null {
            for (key, count) in try object(v.value("votes"), p + ".votes") { try number(count, p + ".votes." + key, low: 0, integer: true) }
        }
        let c = try object(v.value("coverage"), p + ".coverage", "corridor_cells unknown_cells glass_cells covered_cells coverage_pct")
        var counts: [String: Double] = [:]
        for key in ["corridor_cells", "unknown_cells", "glass_cells", "covered_cells"] { counts[key] = try number(c.value(key), p + ".coverage." + key, low: 0, integer: true) }
        let corridor = counts["corridor_cells"]!, covered = counts["covered_cells"]!
        try require(covered == corridor - counts["unknown_cells"]!, p, "inconsistent covered_cells")
        try require(counts["glass_cells"]! <= covered, p, "glass exceeds covered cells")
        if corridor > 0 {
            let fraction = try number(c.value("coverage_pct"), p + ".coverage.coverage_pct", low: 0, high: 1)
            try require(abs(fraction - covered / corridor) <= 1e-9, p, "inconsistent coverage fraction")
        } else { try require(c.value("coverage_pct") == .null, p, "empty corridor must have null coverage fraction") }
        if v.value("segmentation") != .null {
            let s = try object(v.value("segmentation"), p + ".segmentation", "model glass_detected reflection_flags manual_edits")
            try optionalText(s.value("model"), p + ".segmentation.model")
            if s.value("glass_detected") != .null { try boolean(s.value("glass_detected"), p + ".segmentation.glass_detected") }
            _ = try strings(s.value("reflection_flags"), p + ".segmentation.reflection_flags")
        }
        if v.value("near_field") != .null {
            let n = try object(v.value("near_field"), p + ".near_field", "d_near_m recentered_cells source")
            try optionalNumber(n.value("d_near_m"), p + ".near_field.d_near_m", low: 0)
            try number(n.value("recentered_cells"), p + ".near_field.recentered_cells", low: 0, integer: true)
            try choice(n.value("source"), ["lidar"], p + ".near_field.source")
        }
    }

    private static func geometry(_ value: JSONValue) throws {
        let g = try object(value, "$.geometry", "windows planes level")
        try choice(g.value("level"), ["R1_only", "R2_available"], "$.geometry.level")
        for item in try array(g.value("windows"), "$.geometry.windows") {
            let w = try object(item, "$.geometry.windows[]", "id corners_world source")
            try text(w.value("id"), "$.geometry.windows[].id")
            try choice(w.value("source"), ["roomplan", "manual"], "$.geometry.windows[].source")
            let corners = try array(w.value("corners_world"), "$.geometry.windows[].corners_world")
            try require(corners.count == 4, "$.geometry.windows[]", "expected four corners")
            for corner in corners { try vector(corner, 3, "$.geometry.windows[].corners_world[]") }
        }
        for item in try array(g.value("planes"), "$.geometry.planes") {
            let p = try object(item, "$.geometry.planes[]", "id normal point extent source")
            for key in ["id", "source"] { try text(p.value(key), "$.geometry.planes[]." + key) }
            for key in ["normal", "point"] { try vector(p.value(key), 3, "$.geometry.planes[]." + key) }
            let extent = try array(p.value("extent"), "$.geometry.planes[].extent")
            try require([2, 3].contains(extent.count), "$.geometry.planes[].extent", "expected two or three dimensions")
            for dimension in extent { try number(dimension, "$.geometry.planes[].extent", low: 0) }
        }
    }

    private static func analysis(_ values: [JSONValue]) throws {
        for item in values {
            let a = try object(item, "$.analysis[]", "query bands heatmap_ref attribution uncertainty versions computed_at")
            let q = try object(a.value("query"), "$.analysis[].query", "date_from date_to time_window scenario")
            try choice(q.value("scenario"), ["current"], "$.analysis[].query.scenario")
            for key in ["date_from", "date_to"] { try date(q.value(key), "$.analysis[].query." + key) }
            let from = try text(q.value("date_from"), "$.analysis[].query.date_from"), to = try text(q.value("date_to"), "$.analysis[].query.date_to")
            try require(from <= to, "$.analysis[].query", "reversed date range")
            for item in try array(a.value("bands"), "$.analysis[].bands") {
                let band = try object(item, "$.analysis[].bands[]", "date segments")
                try date(band.value("date"), "$.analysis[].bands[].date")
                for item in try array(band.value("segments"), "$.analysis[].bands[].segments") {
                    let segment = try object(item, "$.analysis[].bands[].segments[]", "from to state")
                    for key in ["from", "to"] {
                        let time = try text(segment.value(key), "$.analysis[].bands[].segments[]." + key)
                        try require(matches(time, "\\A(?:[01][0-9]|2[0-3]):[0-5][0-9]\\z"), "$.analysis[].bands[].segments[]." + key, "invalid local time")
                    }
                    let start = try text(segment.value("from"), "$.analysis[].bands[].segments[].from"), end = try text(segment.value("to"), "$.analysis[].bands[].segments[].to")
                    try require(start < end, "$.analysis[].bands[].segments[]", "reversed segment")
                    try choice(segment.value("state"), ["direct", "blocked", "unknown", "sensitive"], "$.analysis[].bands[].segments[].state")
                }
            }
            for item in try array(a.value("attribution"), "$.analysis[].attribution") {
                let entry = try object(item, "$.analysis[].attribution[]", "from to cause az_range alt_range")
                for key in ["from", "to", "cause"] { try text(entry.value(key), "$.analysis[].attribution[]." + key) }
                for key in ["az_range", "alt_range"] { try vector(entry.value(key), 2, "$.analysis[].attribution[]." + key) }
            }
            let u = try object(a.value("uncertainty"), "$.analysis[].uncertainty", "yaw_sigma_deg samples boundary_jitter_deg")
            try number(u.value("samples"), "$.analysis[].uncertainty.samples", low: 1, integer: true)
            let versions = try object(a.value("versions"), "$.analysis[].versions", "inputs_hash")
            try text(versions.value("inputs_hash"), "$.analysis[].versions.inputs_hash")
            try timestamp(a.value("computed_at"), "$.analysis[].computed_at")
        }
    }

    private static func evidence(_ r: Object) throws {
        for key in ["location", "target", "capture_session", "visibility"] { try require(r.value(key) != .null, "$." + key, "analysis-ready record requires input evidence") }
        let loc = try object(r.value("location"), "$.location")
        try require(loc.value("lat") != .null && loc.value("lon") != .null, "$.location", "coordinates required")
        let target = try object(r.value("target"), "$.target")
        try require(target.value("height_m") != .null && target.value("confirmed_by") == .string("user"), "$.target", "user-confirmed target height required")
        let s = try object(r.value("capture_session"), "$.capture_session")
        let lock = try object(s.value("viewpoint_lock"), "$.capture_session.viewpoint_lock")
        try require(lock.value("handling") != .string("rejected"), "$.capture_session.viewpoint_lock", "rejected viewpoint")
        let frames = try array(s.value("frames"), "$.capture_session.frames").map { try object($0, "$.capture_session.frames[]") }
        try require(frames.contains { $0.value("used_for_visibility") == .bool(true) && $0.value("tracking_state") == .string("normal") && $0.value("mask_ref") != .null && $0.value("lens_offset_m") != .null }, "$.capture_session.frames", "no usable visibility frame evidence")
        let n = try object(r.value("north"), "$.north")
        try require(n.value("resolved") != .null, "$.north.resolved", "unresolved north")
        let resolved = try object(n.value("resolved"), "$.north.resolved")
        let used = try strings(resolved.value("groups_used"), "$.north.resolved.groups_used")
        try require(resolved.value("conflict") == .bool(false) && !used.isEmpty, "$.north.resolved", "unresolved or conflicting north")
        let candidates = try array(n.value("candidates"), "$.north.candidates").map { try object($0, "$.north.candidates[]") }
        let validGroups = try candidates.filter { $0.value("valid") == .bool(true) }.map { try text($0.value("group"), "$.north.candidates[].group") }
        try require(Set(used).isSubset(of: Set(validGroups)), "$.north", "resolved north has no matching valid candidate evidence")
        let v = try object(r.value("visibility"), "$.visibility")
        try require(v.value("states_ref") != .null && v.value("confidence_ref") != .null, "$.visibility", "visibility assets required")
        let coverage = try object(v.value("coverage"), "$.visibility.coverage")
        let corridor = try number(coverage.value("corridor_cells"), "$.visibility.coverage.corridor_cells"), covered = try number(coverage.value("covered_cells"), "$.visibility.coverage.covered_cells")
        try require(corridor > 0 && covered > 0, "$.visibility.coverage", "empty visibility evidence")
        try require(v.value("segmentation") != .null, "$.visibility.segmentation", "segmentation provenance required")
        let segmentation = try object(v.value("segmentation"), "$.visibility.segmentation")
        try require(segmentation.value("model") != .null, "$.visibility.segmentation.model", "segmentation provenance required")
    }
}
