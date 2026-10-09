import CryptoKit
import Foundation
import NorthResolver
import SceneRecord

/// Turns a `CaptureLog` into a SceneRecord as it stands at Save (schema 0.2.0, ADR-0022): R0, result revision 0, no
/// grid and no analysis, every check still to run. It passes `SceneValidator`, and its lights are the ones
/// `QualityEvaluator` gives for this evidence, never ones the builder chose. Visibility, north resolution beyond the
/// compass and analysis are filled in by later modules; this builder never invents them.
public enum SceneRecordBuilder {
    public static let schemaVersion = "0.2.0"
    /// The heading is taken as the true azimuth of the back camera's forward axis (portrait, CLHeading referenced
    /// to the top of the device). This mapping is an assumption until the sundial check in docs/05 §2 (truth group).
    public static let headingAxisAssumption = "CLHeading, referenced to the interface orientation, taken as the back camera's true azimuth; verify against the sundial (docs/05)"
    /// A phone compass is never trusted below this σ, whatever it reports (docs/05 §2, candidate).
    public static let magneticPriorSigmaDeg = 8.0
    /// A heading is tied to a pose only when one with normal tracking lies this close in time.
    public static let maximumPoseGapS = 1.0

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
                "used_for_visibility": .bool(false),
                "role": .string("visibility")
            ])
        }

        // The hero's pixels go to the row; the record says how they relate to the sensor image (docs/03 §11).
        let heroImage: JSONValue = log.hero.map { hero in
            .object([
                "storage": .string("row.photo"),
                "native_size": vec([Double(hero.image.nativeWidth), Double(hero.image.nativeHeight)]),
                "encoded_size": vec([Double(hero.image.encodedWidth), Double(hero.image.encodedHeight)]),
                "scale": .number(hero.image.scale),
                "crop": vec([0, 0, Double(hero.image.nativeWidth), Double(hero.image.nativeHeight)]),
                "rotation_deg": .number(Double(hero.image.rotationDeg)),
                "byte_count": .number(Double(hero.image.byteCount)),
                "sha256": .string(hero.image.sha256)
            ])
        } ?? .null

        let heroValue: JSONValue = hero.map { frame in
            .object([
                "frame_id": .string(frame.frameID),
                "image_ref": .null,
                "timestamp": time(log.frameDate(frame) ?? log.startedAt),
                "intrinsics": vec(frame.intrinsics),
                "camera_transform": vec(frame.cameraTransform),
                "exposure": .null,
                "image": heroImage
            ])
        } ?? .null

        let candidates: JSONValue = .array([magneticCandidate(log, time: time)])
        let north = resolvedNorth([magneticCandidate(log, time: time)], time: time, at: createdAt)

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

        let notRun: JSONValue = .object([
            "rules": .string(QualityEvaluator.version2),
            "horizon": .object(["status": .string("not_run"), "residual_deg": .null, "confidence": .null, "frame_id": .null, "detector": .null]),
            "lens": .object(["status": .string("not_run"), "smudge_confidence": .null, "frame_id": .null, "detector": .null]),
            "reflection": .object(["status": .string("not_run"), "frames_checked": .number(0), "hits": .number(0), "detector": .null])
        ])
        var fields: [String: JSONValue] = [
            "schema_version": .string(schemaVersion),
            "scene_id": .string(sceneID),
            "created_at": time(createdAt),
            "timezone": .string(log.timezone.identifier),
            "app": .object([
                "version": .string(log.appVersion), "build": .string(log.appBuild),
                "algorithms": .object(["sun": .null, "segmentation": .null, "north": .string(NorthResolver.version), "visibility": .null])
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
                "guidance": .object(["question": .string("custom"), "corridor_ref": .null]),
                "keyframes": .array([])
            ]),
            "north": north.value,
            "visibility": .null,
            "geometry": .null,
            "analysis": .array([]),
            "quality": .object([
                "level": .string("R0"),
                // North is stated as NorthResolver gives it; the validator refuses a light the evidence does not give.
                "gates": .object(["level": .string(anchorLocked ? "pass" : "blocked"), "coverage": .string("blocked"),
                                  "north": .string(north.gate.rawValue), "segmentation": .string("blocked"),
                                  "lens": .string("blocked")]),
                "flags": .array(flags),
                "false_valid_guard": .string("blocked"),
                "blocked_reason": .string(blocked),
                "evidence": notRun
            ]),
            // Revision 0: saved, never analysed. The two digests are what an analysis started against (ADR-0022 §4).
            "result": .object([
                "revision": .number(0),
                "capture_digest": .string(log.spool?.digest ?? "no-frames-kept"),
                "north_digest": .string(digest(of: candidates)),
                "inputs_hash": .null,
                "computed_at": .null
            ]),
            "sharing": .object(["include_hero": .bool(false), "precise_address": .bool(false),
                                "revoked": .bool(false), "revoked_at": .null]),
            "context": .object(["address_estimate": .null])
        ]
        // State the lights as the evidence gives them, all five: the builder has no opinion of its own.
        if case .object(var quality)? = fields["quality"] {
            let evaluated = QualityEvaluator.evaluate(fields).gates
            quality["gates"] = .object(Dictionary(uniqueKeysWithValues: evaluated.map { ($0.key.rawValue, JSONValue.string($0.value.rawValue)) }))
            fields["quality"] = .object(quality)
        }
        return try SceneRecordDocument(fields: fields)
    }

    /// A stable hash of a JSON value: the same candidates always give the same digest.
    static func digest(of value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The magnetic-group candidate (docs/05 §2, §4). Every valid compass reading that can be tied to a pose gives one
    /// sample of Δ, the true azimuth of the AR −Z axis: the heading at that moment minus the camera's AR azimuth in
    /// the frame nearest to it. The candidate is their circular median, and its σ is the larger of the readings' σ
    /// and their spread across the sweep, so a compass that wanders while the phone turns says so. All samples stay
    /// in `raw.samples` for recomputation and calibration (review R08).
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
        guard let first = log.firstValidHeading else {
            if let any = log.headings.first {
                return invalid("no valid heading (accuracy or true heading negative)", raw: [
                    "true_heading": .number(any.trueHeading), "magnetic_heading": .number(any.magneticHeading),
                    "heading_accuracy": .null, "sampled_at": time(any.sampledAt)
                ])
            }
            return invalid("no heading sample")
        }
        // Only poses with normal tracking count, and only within a second of the reading.
        let tracked = log.frames.filter { $0.trackingState == "normal" }
        let valid = log.headings.filter(\.isValid)
        let samples: [CompassSample] = valid.compactMap { heading in
            guard let firstFrameAt = log.firstFrameAt,
                  let (frame, gap) = nearest(tracked, to: heading.sampledAt.timeIntervalSince(firstFrameAt)),
                  gap <= maximumPoseGapS else { return nil }
            return CompassSample(heading: heading, frame: frame, gapS: gap)
        }
        guard !samples.isEmpty else {
            return invalid("no synchronized pose within 1 s of the heading sample", raw: [
                "true_heading": .number(first.trueHeading), "magnetic_heading": .number(first.magneticHeading),
                "heading_accuracy": .number(first.headingAccuracy), "sampled_at": time(first.sampledAt)
            ])
        }
        let sampleValues: [JSONValue] = samples.map { sample in
            .object([
                "sampled_at": time(sample.heading.sampledAt),
                "true_heading": .number(sample.heading.trueHeading),
                "magnetic_heading": .number(sample.heading.magneticHeading),
                "heading_accuracy": .number(sample.heading.headingAccuracy),
                "device_orientation": .string(sample.heading.deviceOrientation),
                "frame_id": .string(sample.frame.frameID),
                "camera_az_ar_deg": .number(sample.frame.cameraAzimuthAR),
                "camera_pitch_deg": .number(sample.frame.cameraPitchDeg),
                "pose_gap_s": .number(sample.gapS),
                "yaw_deg": .number(sample.yawDeg),
                "used": .bool(sample.isLevelEnough)
            ])
        }
        let used = samples.filter(\.isLevelEnough)
        guard let lead = used.first else {
            return invalid("every heading was read with the camera pitched beyond \(Int(LiveYaw.maximumPitchDeg)) degrees",
                           raw: ["samples": .array(sampleValues)])
        }
        let merged = NorthResolver.merge(used.map { ($0.yawDeg, $0.sigmaDeg) })
        candidate["yaw_deg"] = .number(merged.yawDeg)
        candidate["sigma_deg"] = .number(merged.sigmaDeg)
        candidate["valid"] = .bool(true)
        candidate["raw"] = .object([
            // The first usable reading, as before: the session-start heading of docs/05 §4.
            "true_heading": .number(lead.heading.trueHeading),
            "magnetic_heading": .number(lead.heading.magneticHeading),
            "heading_accuracy": .number(lead.heading.headingAccuracy),
            "sampled_at": time(lead.heading.sampledAt),
            "frame_id": .string(lead.frame.frameID),
            "camera_az_ar_deg": .number(lead.frame.cameraAzimuthAR),
            "pose_gap_s": .number(lead.gapS),
            "assumption": .string(headingAxisAssumption),
            "merged": .object([
                "method": .string("circular_median"),
                // Seen: every heading the session delivered. Valid: accuracy and true heading not negative.
                // Total: valid and tied to a pose (these are in `samples`). Used: also level enough to merge.
                "readings_seen": .number(Double(log.headings.count)),
                "readings_valid": .number(Double(valid.count)),
                "samples_used": .number(Double(used.count)),
                "samples_total": .number(Double(samples.count)),
                "spread_deg": .number(merged.spreadDeg),
                "prior_sigma_deg": .number(magneticPriorSigmaDeg),
                "max_pitch_deg": .number(LiveYaw.maximumPitchDeg)
            ]),
            "samples": .array(sampleValues)
        ])
        return .object(candidate)
    }

    /// The frame nearest to `t` seconds after the first frame, and how far away it is. `frames` is in time order.
    private static func nearest(_ frames: [FrameSample], to t: Double) -> (frame: FrameSample, gapS: TimeInterval)? {
        guard !frames.isEmpty else { return nil }
        var low = 0, high = frames.count   // the first frame at or after t
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].t < t { low = mid + 1 } else { high = mid }
        }
        let index = [low - 1, low].filter(frames.indices.contains).min { abs(frames[$0].t - t) < abs(frames[$1].t - t) }!
        return (frames[index], abs(frames[index].t - t))
    }

    /// One compass reading tied to the pose nearest to it in time.
    private struct CompassSample {
        let heading: HeadingSample
        let frame: FrameSample
        let gapS: TimeInterval

        var yawDeg: Double { NorthResolver.mod360(heading.trueHeading - frame.cameraAzimuthAR) }
        /// Sigma rule from docs/05 §2: max(headingAccuracy, prior). The spread across samples is added by the merge.
        var sigmaDeg: Double { max(heading.headingAccuracy, SceneRecordBuilder.magneticPriorSigmaDeg) }
        /// Steeper than this the heading is about the phone's top edge, not the camera (docs/05 §2); kept but not merged.
        var isLevelEnough: Bool { abs(frame.cameraPitchDeg) <= LiveYaw.maximumPitchDeg }
    }

    /// What NorthResolver makes of the candidates. A direction that still needs a confirmation is not written as
    /// resolved: `resolved` stays null until the light is at least `warn` (docs/05 §3 steps 4 and 5).
    private static func resolvedNorth(_ candidates: [JSONValue], time: (Date) -> JSONValue, at date: Date) -> (value: JSONValue, gate: QualityGate) {
        let readings: [NorthReading] = candidates.compactMap { item in
            guard case .object(let c) = item, c["valid"] == .bool(true), case .string(let name)? = c["group"],
                  let group = NorthGroup(rawValue: name), case .number(let yaw)? = c["yaw_deg"],
                  case .number(let sigma)? = c["sigma_deg"] else { return nil }
            return NorthReading(group: group, yawDeg: yaw, sigmaDeg: sigma)
        }
        let resolution = NorthResolver.resolve(readings)
        var resolved = JSONValue.null
        if resolution.gate != .blocked, let yaw = resolution.yawDeg, let sigma = resolution.sigmaDeg {
            let detail = resolution.disagreements.map {
                "\($0.a.rawValue) and \($0.b.rawValue) differ by \(String(format: "%.1f", $0.differenceDeg)) (limit \(String(format: "%.1f", $0.limitDeg)))"
            }.joined(separator: "; ")
            resolved = .object([
                "yaw_deg": .number(yaw), "sigma_deg": .number(sigma), "method": .string(NorthResolver.method),
                "groups_used": .array(resolution.groupsUsed.map { .string($0.rawValue) }),
                "groups_rejected": .array(resolution.groupsRejected.map { .string($0.rawValue) }),
                "conflict": .bool(resolution.conflict),
                "conflict_detail": detail.isEmpty ? .null : .string(detail),
                "resolved_at": time(date)
            ])
        }
        return (.object(["candidates": .array(candidates), "resolved": resolved]), resolution.gate)
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
