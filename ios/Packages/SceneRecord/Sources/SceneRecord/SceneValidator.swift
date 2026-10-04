import Compression
import CryptoKit
import Foundation

private typealias Object = [String: JSONValue]

private extension Dictionary where Key == String, Value == JSONValue {
    func value(_ key: String) -> JSONValue { self[key] ?? .null }
}

internal enum SceneValidator {
    private static let timeKeys: Set<String> = ["created_at", "captured_at", "started_at", "ended_at", "sampled_at", "resolved_at", "computed_at", "revoked_at", "timestamp"]
    private static let accuracyKeys: Set<String> = ["h_acc_m", "v_acc_m", "heading_accuracy", "sigma_deg", "yaw_sigma_deg", "boundary_jitter_deg"]
    private static let groups = ["magnetic", "map", "solar", "vps"]
    /// Inline payload limits (ADR-0022). A grid is one byte a cell; a record keeps at most this many keyframe masks.
    static let maxGridBytes = 360 * 181
    static let maxMaskBytes = 400_000
    static let maxKeyframes = 5
    /// Sun-disk candidate validity, sundisk-0.1 (docs/05 §2a). Candidates until experiment 2 (docs/07 §5).
    static let sunDiskRules = "sundisk-0.1"
    static let sunAltitudeResidualDeg = 1.5
    static let sunMinAltitudeDeg = 5.0
    static let sunMinSkyRing = 0.6

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
        let v2 = try choice(r.value("schema_version"), ["0.1.0", "0.2.0"], "$.schema_version") == "0.2.0"
        if v2 { _ = try object(root, "$", "result") }
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
        let frames = r.value("capture_session") == .null ? [] : try capture(r.value("capture_session"), v2)
        try north(r.value("north"), frames: v2 ? frames : nil)
        if r.value("visibility") != .null { try visibility(r.value("visibility"), v2) }
        if r.value("geometry") != .null { try geometry(r.value("geometry")) }
        let analyses = try array(r.value("analysis"), "$.analysis")
        let q = try object(r.value("quality"), "$.quality", "level gates flags false_valid_guard blocked_reason" + (v2 ? " evidence" : ""))
        let result = v2 ? try self.result(r, analyses) : nil
        if v2 { try qualityEvidence(q.value("evidence")) }
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
            try evidence(r, v2)
        }
        try analysis(analyses, result)
        let sharing = try object(r.value("sharing"), "$.sharing", "include_hero precise_address revoked revoked_at")
        for key in ["include_hero", "precise_address", "revoked"] { try boolean(sharing.value(key), "$.sharing." + key) }
        try require(sharing.value("revoked") != .bool(true) || sharing.value("revoked_at") != .null, "$.sharing.revoked_at", "revocation requires timestamp")
        _ = try object(r.value("context"), "$.context", "address_estimate")
        // Last, once the shape is known to be sound: the stated lights must be the ones the evidence gives (R08).
        try QualityEvaluator.check(fields)
    }

    /// An inline asset: the stated length and SHA-256 must be those of the decoded bytes. Returns the bytes.
    private static func payload(_ value: JSONValue, _ path: String, _ encoding: String, _ maxBytes: Int) throws -> (bytes: Data, width: Double, height: Double) {
        let a = try object(value, path, "encoding width height byte_count sha256 data")
        try choice(a.value("encoding"), [encoding], path + ".encoding")
        let width = try number(a.value("width"), path + ".width", low: 1, integer: true)
        let height = try number(a.value("height"), path + ".height", low: 1, integer: true)
        let count = try number(a.value("byte_count"), path + ".byte_count", low: 1, integer: true)
        try require(count <= Double(maxBytes), path + ".byte_count", "payload larger than the limit")
        let hash = try text(a.value("sha256"), path + ".sha256")
        let data = try text(a.value("data"), path + ".data")
        try require(data.utf8.count <= 4 * (maxBytes / 3 + 4), path + ".data", "payload larger than the limit")
        guard var raw = Data(base64Encoded: data) else { throw SceneRecordValidationError(path + ".data", "not base64") }
        if encoding == "deflate+base64" {
            // Raw DEFLATE (RFC 1951), into a buffer one byte past the limit: a small payload cannot inflate without bound.
            var inflated = Data(count: maxBytes + 1)
            let written = inflated.withUnsafeMutableBytes { target in
                raw.withUnsafeBytes { source in
                    compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, maxBytes + 1,
                                              source.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            try require(written > 0 && written <= maxBytes, path + ".data", "payload does not inflate, or inflates past the limit")
            raw = inflated.prefix(written)
        }
        try require(Double(raw.count) == count, path + ".byte_count", "stated length is not the payload's")
        try require(SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined() == hash, path + ".sha256", "stated hash is not the payload's")
        return (raw, width, height)
    }

    /// Where the hero's pixels are and how they relate to the sensor image the intrinsics describe (review R01).
    private static func heroImage(_ value: JSONValue, _ path: String) throws {
        let i = try object(value, path, "storage native_size encoded_size scale crop rotation_deg byte_count sha256")
        try choice(i.value("storage"), ["row.photo"], path + ".storage")
        var sizes: [String: [Double]] = [:]
        for key in ["native_size", "encoded_size"] {
            try vector(i.value(key), 2, path + "." + key)
            sizes[key] = i.value(key).vector ?? []
            try require(sizes[key]!.allSatisfy { $0 >= 1 && $0.rounded(.down) == $0 }, path + "." + key, "expected whole pixels")
        }
        try vector(i.value("crop"), 4, path + ".crop")
        let crop = i.value("crop").vector ?? [], native = sizes["native_size"]!
        try require(crop[0] >= 0 && crop[1] >= 0 && crop[2] > 0 && crop[3] > 0 && crop[0] + crop[2] <= native[0] && crop[1] + crop[3] <= native[1],
                    path + ".crop", "crop outside the native image")
        let scale = try number(i.value("scale"), path + ".scale", low: 0)
        try require(scale > 0, path + ".scale", "scale must be positive")
        guard case .number(let rotation) = i.value("rotation_deg"), [0, 90, 180, 270].contains(rotation) else {
            throw SceneRecordValidationError(path + ".rotation_deg", "unsupported value")
        }
        var expected = [crop[2] * scale, crop[3] * scale]
        if rotation == 90 || rotation == 270 { expected.reverse() }
        try require(zip(expected, sizes["encoded_size"]!).allSatisfy { abs($0 - $1) <= 1 }, path + ".encoded_size", "encoded size does not follow from crop, scale and rotation")
        try number(i.value("byte_count"), path + ".byte_count", low: 1, integer: true)
        try text(i.value("sha256"), path + ".sha256")
    }

    /// Returns the frame ids, for the checks that point at frames.
    private static func capture(_ value: JSONValue, _ v2: Bool) throws -> Set<String> {
        let p = "$.capture_session"
        let s = try object(value, p, "session_id started_at ended_at world_alignment hero_frame frames viewpoint_lock guidance" + (v2 ? " keyframes" : ""))
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
            if v2 {
                try require(h["image"] != nil, p + ".hero_frame", "missing image")
                if h.value("image") != .null { try heroImage(h.value("image"), p + ".hero_frame.image") }
            }
        }
        var ids = Set<String>()
        var used = Set<String>()
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
            if v2 {
                try require(f["role"] != nil, fp, "missing role")
                let role = try choice(f.value("role"), ["visibility", "calibration"], fp + ".role")
                // A frame taken while confirming the direction is not evidence about the target point's sky (review V2-02).
                try require(role == "visibility" || f.value("used_for_visibility") == .bool(false), fp, "a calibration frame cannot be used for visibility")
                if f.value("used_for_visibility") == .bool(true) { used.insert(id) }
            }
        }
        if v2 {
            let keyframes = try array(s.value("keyframes"), p + ".keyframes")
            try require(keyframes.count <= maxKeyframes, p + ".keyframes", "too many keyframes")
            for (i, item) in keyframes.enumerated() {
                let kp = "\(p).keyframes[\(i)]"
                let k = try object(item, kp, "frame_id mask")
                let id = try text(k.value("frame_id"), kp + ".frame_id")
                try require(ids.contains(id), kp + ".frame_id", "keyframe is not one of the frames")
                try require(used.contains(id), kp + ".frame_id", "keyframe was not used for visibility")
                let mask = try payload(k.value("mask"), kp + ".mask", "png+base64", maxMaskBytes)
                let png = [UInt8](mask.bytes)
                try require(png.count >= 24 && Array(png[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] && Array(png[12..<16]) == Array("IHDR".utf8),
                            kp + ".mask.data", "not a PNG")
                func big(_ at: Int) -> Double { Double(png[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) }) }
                try require(big(16) == mask.width && big(20) == mask.height, kp + ".mask", "stated size is not the image's")
            }
        }
        let lock = try object(s.value("viewpoint_lock"), p + ".viewpoint_lock", "anchor_world tolerance_m max_drift_m frames_within frames_beyond handling")
        try vector(lock.value("anchor_world"), 3, p + ".viewpoint_lock.anchor_world")
        for key in ["tolerance_m", "max_drift_m"] { try optionalNumber(lock.value(key), p + ".viewpoint_lock." + key, low: 0) }
        for key in ["frames_within", "frames_beyond"] { try number(lock.value(key), p + ".viewpoint_lock." + key, low: 0, integer: true) }
        try choice(lock.value("handling"), ["depth_recentered", "tolerated", "rejected"], p + ".viewpoint_lock.handling")
        let g = try object(s.value("guidance"), p + ".guidance", "question corridor_ref")
        try choice(g.value("question"), ["winter_breakfast", "full_year", "west_afternoon", "custom"], p + ".guidance.question")
        return ids
    }

    /// A sun-disk candidate stated valid must carry evidence that passes sundisk-0.1 (docs/05 §2a). Passing does not
    /// prove the bright spot was the sun (a vertical mirror keeps the altitude, review V2-01); it refuses the
    /// candidates that certainly were not.
    private static func sunDisk(_ c: Object, _ p: String, valid: Bool, frames: Set<String>) throws {
        let e = try object(c.value("evidence"), p + ".evidence", "rules frame_id time altitude_measured_deg altitude_expected_deg azimuth_expected_deg depth_m sky_ring_fraction user_confirmed tracking_continuous")
        try choice(e.value("rules"), [sunDiskRules], p + ".evidence.rules")
        let frame = try text(e.value("frame_id"), p + ".evidence.frame_id")
        try require(frames.contains(frame), p + ".evidence.frame_id", "evidence frame is not one of the frames")
        try timestamp(e.value("time"), p + ".evidence.time")
        let measured = try number(e.value("altitude_measured_deg"), p + ".evidence.altitude_measured_deg", low: -90, high: 90)
        let expected = try number(e.value("altitude_expected_deg"), p + ".evidence.altitude_expected_deg", low: -90, high: 90)
        try number(e.value("azimuth_expected_deg"), p + ".evidence.azimuth_expected_deg", low: 0, high: 360)
        try optionalNumber(e.value("depth_m"), p + ".evidence.depth_m", low: 0)
        try optionalNumber(e.value("sky_ring_fraction"), p + ".evidence.sky_ring_fraction", low: 0, high: 1)
        let confirmed = try boolean(e.value("user_confirmed"), p + ".evidence.user_confirmed")
        let continuous = try boolean(e.value("tracking_continuous"), p + ".evidence.tracking_continuous")
        guard valid else { return }
        var failed: [String] = []
        if abs(measured - expected) > sunAltitudeResidualDeg + 1e-9 { failed.append("the bright spot is not at the sun's altitude") }
        if expected < sunMinAltitudeDeg { failed.append("the sun is too low") }
        if e.value("depth_m") != .null { failed.append("there is a surface at the bright spot: a lamp or a reflection, not the sky") }
        if (e.value("sky_ring_fraction").number ?? -1) < sunMinSkyRing { failed.append("the bright spot is not surrounded by sky") }
        if !confirmed { failed.append("nobody confirmed it was the sun") }
        if !continuous { failed.append("tracking was interrupted between the scan and the confirmation") }
        try require(failed.isEmpty, p, "stated valid, but " + (failed.first ?? ""))
    }

    private static func north(_ value: JSONValue, frames: Set<String>?) throws {
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
            if let frames, c.value("source") == .string("sun_disk"), valid || c.value("evidence") != .null {
                try sunDisk(c, p, valid: valid, frames: frames)
            }
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

    private static func visibility(_ value: JSONValue, _ v2: Bool) throws {
        let p = "$.visibility"
        let v = try object(value, p, "grid votes coverage segmentation near_field " + (v2 ? "states confidence" : "states_ref confidence_ref"))
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
        if v2 {
            try gridPayloads(v, p, width: 360 / (grid.value("az_step_deg").number ?? 1), height: (hi - lo) / (grid.value("alt_step_deg").number ?? 1))
        } else if v.value("votes") != .null {
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

    /// 0.2: the grid travels inside the record. One byte a cell, row-major from the lowest altitude, azimuth 0 first:
    /// 0 unknown, 1 sky, 2 blocked, 3 glass-uncertain. `votes.cells` must be the grid's own histogram.
    private static func gridPayloads(_ v: Object, _ p: String, width: Double, height: Double) throws {
        try require(width.rounded(.down) == width && height.rounded(.down) == height, p + ".grid", "steps do not divide the ranges")
        var states: Data?
        for key in ["states", "confidence"] where v.value(key) != .null {
            let loaded = try payload(v.value(key), "\(p).\(key)", "deflate+base64", maxGridBytes)
            try require(loaded.width == width && loaded.height == height && Double(loaded.bytes.count) == width * height, "\(p).\(key)", "payload is not the size of the grid")
            if key == "states" { states = loaded.bytes }
        }
        try require((v.value("states") == .null) == (v.value("confidence") == .null), p, "states and confidence travel together")
        let names = ["unknown", "sky", "blocked", "glass"]
        if v.value("votes") != .null {
            let votes = try object(v.value("votes"), p + ".votes", "frames_used min_distinct_frames cells")
            try number(votes.value("frames_used"), p + ".votes.frames_used", low: 0, integer: true)
            try number(votes.value("min_distinct_frames"), p + ".votes.min_distinct_frames", low: 1, integer: true)
            let cells = try object(votes.value("cells"), p + ".votes.cells", "unknown sky blocked glass")
            for key in names { try number(cells.value(key), p + ".votes.cells." + key, low: 0, integer: true) }
        }
        if let states {
            try require((states.max() ?? 0) <= 3, p + ".states", "unknown cell state")
            let cells = try object(try object(v.value("votes"), p + ".votes", "cells").value("cells"), p + ".votes.cells")
            var histogram = [Double](repeating: 0, count: 4)
            for state in states { histogram[Int(state)] += 1 }
            try require(names.map { cells.value($0).number ?? -1 } == histogram, p + ".votes.cells", "cell counts are not the grid's")
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

    /// 0.2: which analysis this record carries. Revision 0 is the record as saved, before any analysis.
    private static func result(_ r: Object, _ analyses: [JSONValue]) throws -> Object {
        let p = "$.result"
        let result = try object(r.value("result"), p, "revision capture_digest north_digest inputs_hash computed_at")
        let revision = try number(result.value("revision"), p + ".revision", low: 0, integer: true)
        for key in ["capture_digest", "north_digest"] { try text(result.value(key), p + "." + key) }
        try optionalText(result.value("inputs_hash"), p + ".inputs_hash")
        if revision == 0 {
            try require(result.value("inputs_hash") == .null && result.value("computed_at") == .null, p, "a record that was never analysed has no inputs hash")
            try require(r.value("visibility") == .null && analyses.isEmpty, p, "a record that was never analysed carries no grid and no analysis")
        } else {
            try require(result.value("inputs_hash") != .null && result.value("computed_at") != .null, p, "an analysed record states its inputs hash and when")
        }
        return result
    }

    /// 0.2: what the detectors reported, so that every light can be worked out again (rules in QualityEvaluator).
    private static func qualityEvidence(_ value: JSONValue) throws {
        let p = "$.quality.evidence"
        let e = try object(value, p, "rules horizon lens reflection")
        try choice(e.value("rules"), [QualityEvaluator.version2], p + ".rules")
        let h = try object(e.value("horizon"), p + ".horizon", "status residual_deg confidence frame_id detector")
        let horizonMeasured = try choice(h.value("status"), ["measured", "not_found", "not_run"], p + ".horizon.status") == "measured"
        if horizonMeasured { try number(h.value("residual_deg"), p + ".horizon.residual_deg", low: 0, high: 180) } else { try optionalNumber(h.value("residual_deg"), p + ".horizon.residual_deg", low: 0, high: 180) }
        if horizonMeasured { try number(h.value("confidence"), p + ".horizon.confidence", low: 0, high: 1) } else { try optionalNumber(h.value("confidence"), p + ".horizon.confidence", low: 0, high: 1) }
        let lens = try object(e.value("lens"), p + ".lens", "status smudge_confidence frame_id detector")
        let lensMeasured = try choice(lens.value("status"), ["measured", "unusable_input", "not_run"], p + ".lens.status") == "measured"
        if lensMeasured { try number(lens.value("smudge_confidence"), p + ".lens.smudge_confidence", low: 0, high: 1) } else { try optionalNumber(lens.value("smudge_confidence"), p + ".lens.smudge_confidence", low: 0, high: 1) }
        for (name, part, measured) in [("horizon", h, horizonMeasured), ("lens", lens, lensMeasured)] {
            for key in ["frame_id", "detector"] {
                if measured { try text(part.value(key), "\(p).\(name).\(key)") } else { try optionalText(part.value(key), "\(p).\(name).\(key)") }
            }
        }
        let reflection = try object(e.value("reflection"), p + ".reflection", "status frames_checked hits detector")
        let status = try choice(reflection.value("status"), ["none_found", "suspected", "undetermined", "not_run"], p + ".reflection.status")
        let checked = try number(reflection.value("frames_checked"), p + ".reflection.frames_checked", low: 0, integer: true)
        let hits = try number(reflection.value("hits"), p + ".reflection.hits", low: 0, integer: true)
        let ran = status != "not_run"
        if ran { try text(reflection.value("detector"), p + ".reflection.detector") } else { try optionalText(reflection.value("detector"), p + ".reflection.detector") }
        try require(ran == (checked > 0), p + ".reflection", "a check that ran looked at frames; one that did not, did not")
        try require((status == "suspected") == (hits > 0), p + ".reflection", "hits and status disagree")
    }

    private static func minutes(_ clock: String) -> Int { (Int(clock.prefix(2)) ?? 0) * 60 + (Int(clock.suffix(2)) ?? 0) }

    private static func analysis(_ values: [JSONValue], _ result: Object?) throws {
        for item in values {
            let a = try object(item, "$.analysis[]", "query bands heatmap_ref attribution uncertainty versions computed_at" + (result == nil ? "" : " revision totals"))
            let q = try object(a.value("query"), "$.analysis[].query", "date_from date_to time_window scenario" + (result == nil ? "" : " representative"))
            var summed = ["direct": 0, "sensitive": 0, "blocked": 0, "unknown": 0]
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
                    let state = try choice(segment.value("state"), ["direct", "blocked", "unknown", "sensitive"], "$.analysis[].bands[].segments[].state")
                    summed[state, default: 0] += minutes(end) - minutes(start)
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
            if let result {
                try boolean(q.value("representative"), "$.analysis[].query.representative")
                try require(a.value("revision") == result.value("revision"), "$.analysis[].revision", "not the record's result revision")
                try require(versions.value("inputs_hash") == result.value("inputs_hash"), "$.analysis[].versions.inputs_hash", "not the record's inputs hash")
                // Minutes a state is shown for are the segments' own: an unknown stretch can never be counted as sun.
                let totals = try object(a.value("totals"), "$.analysis[].totals", "direct_min sensitive_min blocked_min unknown_min")
                for state in ["direct", "sensitive", "blocked", "unknown"] {
                    let stated = try number(totals.value(state + "_min"), "$.analysis[].totals.\(state)_min", low: 0, integer: true)
                    try require(stated == Double(summed[state] ?? 0), "$.analysis[].totals.\(state)_min", "not the sum of the segments")
                }
            }
        }
    }

    private static func evidence(_ r: Object, _ v2: Bool) throws {
        for key in ["location", "target", "capture_session", "visibility"] { try require(r.value(key) != .null, "$." + key, "analysis-ready record requires input evidence") }
        let loc = try object(r.value("location"), "$.location")
        try require(loc.value("lat") != .null && loc.value("lon") != .null, "$.location", "coordinates required")
        let target = try object(r.value("target"), "$.target")
        try require(target.value("height_m") != .null && target.value("confirmed_by") == .string("user"), "$.target", "user-confirmed target height required")
        let s = try object(r.value("capture_session"), "$.capture_session")
        let lock = try object(s.value("viewpoint_lock"), "$.capture_session.viewpoint_lock")
        try require(lock.value("handling") != .string("rejected"), "$.capture_session.viewpoint_lock", "rejected viewpoint")
        let frames = try array(s.value("frames"), "$.capture_session.frames").map { try object($0, "$.capture_session.frames[]") }
        let usable = Set(frames.filter { $0.value("used_for_visibility") == .bool(true) && $0.value("tracking_state") == .string("normal") && $0.value("lens_offset_m") != .null
            && (v2 || $0.value("mask_ref") != .null) }.compactMap { $0.value("frame_id").string })
        try require(!usable.isEmpty, "$.capture_session.frames", "no usable visibility frame evidence")
        if v2 {
            let keyframes = try array(s.value("keyframes"), "$.capture_session.keyframes").compactMap { $0.object?["frame_id"]?.string }
            try require(keyframes.contains(where: usable.contains), "$.capture_session.keyframes", "no keyframe mask to check the grid against")
        }
        let n = try object(r.value("north"), "$.north")
        try require(n.value("resolved") != .null, "$.north.resolved", "unresolved north")
        let resolved = try object(n.value("resolved"), "$.north.resolved")
        let used = try strings(resolved.value("groups_used"), "$.north.resolved.groups_used")
        try require(resolved.value("conflict") == .bool(false) && !used.isEmpty, "$.north.resolved", "unresolved or conflicting north")
        let candidates = try array(n.value("candidates"), "$.north.candidates").map { try object($0, "$.north.candidates[]") }
        let validGroups = try candidates.filter { $0.value("valid") == .bool(true) }.map { try text($0.value("group"), "$.north.candidates[].group") }
        try require(Set(used).isSubset(of: Set(validGroups)), "$.north", "resolved north has no matching valid candidate evidence")
        let v = try object(r.value("visibility"), "$.visibility")
        try require((v2 ? ["states", "confidence"] : ["states_ref", "confidence_ref"]).allSatisfy { v.value($0) != .null }, "$.visibility", "visibility assets required")
        let coverage = try object(v.value("coverage"), "$.visibility.coverage")
        let corridor = try number(coverage.value("corridor_cells"), "$.visibility.coverage.corridor_cells"), covered = try number(coverage.value("covered_cells"), "$.visibility.coverage.covered_cells")
        try require(corridor > 0 && covered > 0, "$.visibility.coverage", "empty visibility evidence")
        try require(v.value("segmentation") != .null, "$.visibility.segmentation", "segmentation provenance required")
        let segmentation = try object(v.value("segmentation"), "$.visibility.segmentation")
        try require(segmentation.value("model") != .null, "$.visibility.segmentation.model", "segmentation provenance required")
    }
}
