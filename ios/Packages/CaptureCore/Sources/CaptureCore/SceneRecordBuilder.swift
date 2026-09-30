import Foundation
import SceneRecord

/// Turns a `CaptureLog` into a capture-only (R0, blocked) SceneRecord document that passes `SceneValidator`.
/// Visibility, north resolution and analysis are filled in by later modules; this builder never invents them.
public enum SceneRecordBuilder {
    public static let schemaVersion = "0.1.0"
    /// The heading is taken as the true azimuth of the back camera's forward axis (portrait, CLHeading referenced
    /// to the top of the device). This mapping is an assumption until the sundial check in docs/05 §2 (truth group).
    public static let headingAxisAssumption = "CLHeading (portrait) taken as the back camera's true azimuth; verify against the sundial (docs/05)"

    public static func build(_ log: CaptureLog, sceneID: String, createdAt: Date = Date()) throws -> SceneRecordDocument {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        stamp.timeZone = log.timezone
        func time(_ date: Date) -> JSONValue { .string(stamp.string(from: date)) }
        func num(_ value: Double?) -> JSONValue { value.map { .number($0) } ?? .null }
        func vec(_ values: [Double]) -> JSONValue { .array(values.map { .number($0) }) }
        func vec3(_ v: SIMD3<Double>) -> JSONValue { vec([v.x, v.y, v.z]) }

        let hero = log.heroFrame
        let anchorLocked = log.anchor != nil
        let anchor = log.anchor ?? SIMD3(0, 0, 0)
        let offsets = log.frames.compactMap(\.lensOffsetM)
        let within = offsets.filter { $0 <= log.viewpointToleranceM + 1e-9 }.count   // 3 × 0.05 must count as 0.15
        let beyond = offsets.count - within

        let frames: [JSONValue] = log.frames.map { frame in
            .object([
                "frame_id": .string(frame.frameID),
                "t": .number(frame.t),
                "camera_transform": vec(frame.cameraTransform),
                "intrinsics": vec(frame.intrinsics),
                "tracking_state": .string(frame.trackingState),
                "lens_offset_m": num(frame.lensOffsetM),
                "depth_ref": .null,
                "depth_confidence_ref": .null,
                "mask_ref": .null,
                "exposure_offset": num(frame.exposureOffset),
                "used_for_visibility": .bool(false)
            ])
        }

        let heroValue: JSONValue = hero.map { frame in
            .object([
                "frame_id": .string(frame.frameID),
                "image_ref": .null,
                "timestamp": time(log.frameDate(frame) ?? log.startedAt),
                "intrinsics": vec(frame.intrinsics),
                "camera_transform": vec(frame.cameraTransform),
                "exposure": .null
            ])
        } ?? .null

        let magnetometer = magneticCandidate(log, time: time)

        let location: JSONValue = log.location.map { loc in
            .object([
                "lat": .number(loc.latitude), "lon": .number(loc.longitude),
                "alt_m": num(loc.altitudeM), "h_acc_m": num(loc.horizontalAccuracyM), "v_acc_m": num(loc.verticalAccuracyM),
                "source": .string("core_location"), "captured_at": time(loc.capturedAt)
            ])
        } ?? .null

        var flags: [JSONValue] = [.string("capture_validator"), .string("no_visibility_evidence")]
        if !anchorLocked { flags.append(.string("anchor_never_locked")) }
        if let reason = log.failureReason { flags.append(.string("session_failed")); _ = reason }
        var blocked = "Capture validator session: poses recorded, no sky visibility or resolved north yet"
        if let reason = log.failureReason { blocked += "; ARSession: \(reason)" }

        let fields: [String: JSONValue] = [
            "schema_version": .string(schemaVersion),
            "scene_id": .string(sceneID),
            "created_at": time(createdAt),
            "timezone": .string(log.timezone.identifier),
            "app": .object([
                "version": .string(log.appVersion), "build": .string(log.appBuild),
                "algorithms": .object(["sun": .null, "segmentation": .null, "north": .null, "visibility": .null])
            ]),
            "device": .object([
                "model": .string(log.device.model), "os": .string(log.device.os),
                "lidar": .bool(log.device.lidar), "scene_depth": .bool(log.device.sceneDepth),
                "geo_tracking": .string(log.device.geoTracking)
            ]),
            "location": location,
            "target": .object([
                "target_id": .string("T1"), "label": .string(log.targetLabel),
                "height_m": num(log.targetHeightM),
                "anchor_world": vec3(anchor),
                "confirmed_by": .null, "notes": .null
            ]),
            "capture_session": .object([
                "session_id": .string(log.sessionID),
                "started_at": time(log.startedAt), "ended_at": time(log.endedAt),
                "world_alignment": .string("gravity"),
                "hero_frame": heroValue,
                "frames": .array(frames),
                "viewpoint_lock": .object([
                    "anchor_world": vec3(anchor),
                    "tolerance_m": .number(log.viewpointToleranceM),
                    "max_drift_m": num(log.maxDriftM),
                    "frames_within": .number(Double(within)), "frames_beyond": .number(Double(beyond)),
                    "handling": .string(anchorLocked ? "tolerated" : "rejected")
                ]),
                "guidance": .object(["question": .string("custom"), "corridor_ref": .null])
            ]),
            "north": .object(["candidates": .array([magnetometer]), "resolved": .null]),
            "visibility": .null,
            "geometry": .null,
            "analysis": .array([]),
            "quality": .object([
                "level": .string("R0"),
                "gates": .object(["level": .string(anchorLocked ? "pass" : "blocked"), "coverage": .string("blocked"),
                                  "north": .string("blocked"), "segmentation": .string("blocked"),
                                  "lens": .string("blocked")]),
                "flags": .array(flags),
                "false_valid_guard": .string("blocked"),
                "blocked_reason": .string(blocked)
            ]),
            "sharing": .object(["include_hero": .bool(false), "precise_address": .bool(false),
                                "revoked": .bool(false), "revoked_at": .null]),
            "context": .object(["address_estimate": .null])
        ]
        return try SceneRecordDocument(fields: fields)
    }

    /// The magnetic-group candidate for NorthResolver (docs/05 §2, §4). `yaw_deg` is Δ, the true azimuth of the
    /// AR −Z axis: the heading of the camera at the sample time minus the camera's AR azimuth in that frame.
    private static func magneticCandidate(_ log: CaptureLog, time: (Date) -> JSONValue) -> JSONValue {
        var candidate: [String: JSONValue] = ["source": .string("magnetometer"), "group": .string("magnetic")]
        func invalid(_ reason: String, raw: [String: JSONValue] = [:]) -> JSONValue {
            candidate["yaw_deg"] = .null
            candidate["sigma_deg"] = .null
            candidate["valid"] = .bool(false)
            candidate["reason"] = .string(reason)
            if !raw.isEmpty { candidate["raw"] = .object(raw) }
            return .object(candidate)
        }
        guard let heading = log.firstValidHeading else {
            if let any = log.headings.first {
                return invalid("no valid heading (accuracy or true heading negative)", raw: [
                    "true_heading": .number(any.trueHeading), "magnetic_heading": .number(any.magneticHeading),
                    "heading_accuracy": .null, "sampled_at": time(any.sampledAt)
                ])
            }
            return invalid("no heading sample")
        }
        // Synchronise with the pose closest to the reading; only frames with normal tracking count.
        let synced = log.frames
            .filter { $0.trackingState == "normal" }
            .compactMap { frame -> (FrameSample, TimeInterval)? in
                guard let date = log.frameDate(frame) else { return nil }
                return (frame, abs(date.timeIntervalSince(heading.sampledAt)))
            }
            .min { $0.1 < $1.1 }
        guard let (frame, gap) = synced, gap <= 1.0 else {
            return invalid("no synchronized pose within 1 s of the heading sample", raw: [
                "true_heading": .number(heading.trueHeading), "magnetic_heading": .number(heading.magneticHeading),
                "heading_accuracy": .number(heading.headingAccuracy), "sampled_at": time(heading.sampledAt)
            ])
        }
        let cameraAz = frame.cameraAzimuthAR
        var yaw = (heading.trueHeading - cameraAz).truncatingRemainder(dividingBy: 360)
        if yaw < 0 { yaw += 360 }
        // Sigma rule from docs/05 §2: max(headingAccuracy, prior); group spread is a NorthResolver concern.
        let sigma = max(heading.headingAccuracy, 8.0)
        candidate["yaw_deg"] = .number(yaw)
        candidate["sigma_deg"] = .number(sigma)
        candidate["valid"] = .bool(true)
        candidate["raw"] = .object([
            "true_heading": .number(heading.trueHeading),
            "magnetic_heading": .number(heading.magneticHeading),
            "heading_accuracy": .number(heading.headingAccuracy),
            "sampled_at": time(heading.sampledAt),
            "frame_id": .string(frame.frameID),
            "camera_az_ar_deg": .number(cameraAz),
            "pose_gap_s": .number(gap),
            "assumption": .string(headingAxisAssumption)
        ])
        return .object(candidate)
    }

    /// `PR-YYYYMMDD-NN` (field/README.md). `sequence` is the caller's per-day counter.
    public static func sceneID(date: Date, sequence: Int, timezone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "PR-%04d%02d%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, sequence)
    }

    /// Next unused id for the day, read from what is already on disk so two screens can never collide.
    public static func nextSceneID(in root: URL, date: Date, timezone: TimeZone) throws -> String {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return nextSceneID(taken: Set(existing), date: date, timezone: timezone)
    }

    /// The next id for the local day after every id in `taken` (rows, pending captures, legacy folders).
    public static func nextSceneID(taken: Set<String>, date: Date, timezone: TimeZone) -> String {
        let prefix = String(sceneID(date: date, sequence: 0, timezone: timezone).dropLast(2))   // "PR-YYYYMMDD-"
        let used = taken.filter { $0.hasPrefix(prefix) }.compactMap { Int($0.dropFirst(prefix.count)) }
        return sceneID(date: date, sequence: (used.max() ?? 0) + 1, timezone: timezone)
    }
}
