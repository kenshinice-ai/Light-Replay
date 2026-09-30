import Foundation
import SceneRecord

/// Turns a `CaptureLog` into a capture-only (R0, blocked) SceneRecord document that passes `SceneValidator`.
/// Visibility, north resolution and analysis are filled in by later modules; this builder never invents them.
public enum SceneRecordBuilder {
    public static let schemaVersion = "0.1.0"

    public static func build(_ log: CaptureLog, sceneID: String, createdAt: Date = Date()) throws -> SceneRecordDocument {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        stamp.timeZone = log.timezone
        func time(_ date: Date) -> JSONValue { .string(stamp.string(from: date)) }
        func num(_ value: Double?) -> JSONValue { value.map { .number($0) } ?? .null }
        func vec(_ values: [Double]) -> JSONValue { .array(values.map { .number($0) }) }

        let hero = log.heroFrame
        let anchor = hero?.position ?? SIMD3(0, 0, 0)
        let within = log.frames.filter { $0.lensOffsetM <= log.viewpointToleranceM + 1e-9 }.count   // 3 × 0.05 must count as 0.15
        let beyond = log.frames.count - within

        let frames: [JSONValue] = log.frames.map { frame in
            .object([
                "frame_id": .string(frame.frameID),
                "t": .number(frame.t),
                "camera_transform": vec(frame.cameraTransform),
                "intrinsics": vec(frame.intrinsics),
                "tracking_state": .string(frame.trackingState),
                "lens_offset_m": .number(frame.lensOffsetM),
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
                "timestamp": time(log.startedAt.addingTimeInterval(frame.t)),
                "intrinsics": vec(frame.intrinsics),
                "camera_transform": vec(frame.cameraTransform),
                "exposure": .null
            ])
        } ?? .null

        let magnetometer: JSONValue = {
            guard let heading = log.heading else {
                return .object([
                    "source": .string("magnetometer"), "group": .string("magnetic"),
                    "yaw_deg": .null, "sigma_deg": .null, "valid": .bool(false),
                    "reason": .string("no heading sample")
                ])
            }
            let valid = heading.headingAccuracy >= 0
            // Sigma rule from docs/05 §2: max(headingAccuracy, prior); group spread is a NorthResolver concern.
            let sigma = max(heading.headingAccuracy, 8.0)
            let yaw = valid ? heading.trueHeading.truncatingRemainder(dividingBy: 360) : nil
            var candidate: [String: JSONValue] = [
                "source": .string("magnetometer"), "group": .string("magnetic"),
                "yaw_deg": num(yaw.map { $0 < 0 ? $0 + 360 : $0 }),
                "sigma_deg": valid ? .number(sigma) : .null,
                "valid": .bool(valid),
                // Accuracy keys are non-negative in the schema (docs/03); CLHeading reports "invalid" as a negative
                // number, which the schema expresses as null + valid=false + reason instead of the raw negative value.
                "raw": .object([
                    "true_heading": .number(heading.trueHeading),
                    "magnetic_heading": .number(heading.magneticHeading),
                    "heading_accuracy": valid ? .number(heading.headingAccuracy) : .null,
                    "sampled_at": time(heading.sampledAt)
                ])
            ]
            if !valid { candidate["reason"] = .string("heading accuracy negative (invalid)") }
            return .object(candidate)
        }()

        let location: JSONValue = log.location.map { loc in
            .object([
                "lat": .number(loc.latitude), "lon": .number(loc.longitude),
                "alt_m": num(loc.altitudeM), "h_acc_m": num(loc.horizontalAccuracyM), "v_acc_m": num(loc.verticalAccuracyM),
                "source": .string("core_location"), "captured_at": time(loc.capturedAt)
            ])
        } ?? .null

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
                "anchor_world": vec([anchor.x, anchor.y, anchor.z]),
                "confirmed_by": .null, "notes": .null
            ]),
            "capture_session": .object([
                "session_id": .string(log.sessionID),
                "started_at": time(log.startedAt), "ended_at": time(log.endedAt),
                "world_alignment": .string("gravity"),
                "hero_frame": heroValue,
                "frames": .array(frames),
                "viewpoint_lock": .object([
                    "anchor_world": vec([anchor.x, anchor.y, anchor.z]),
                    "tolerance_m": .number(log.viewpointToleranceM),
                    "max_drift_m": num(log.maxDriftM),
                    "frames_within": .number(Double(within)), "frames_beyond": .number(Double(beyond)),
                    "handling": .string("tolerated")
                ]),
                "guidance": .object(["question": .string("custom"), "corridor_ref": .null])
            ]),
            "north": .object(["candidates": .array([magnetometer]), "resolved": .null]),
            "visibility": .null,
            "geometry": .null,
            "analysis": .array([]),
            "quality": .object([
                "level": .string("R0"),
                "gates": .object(["level": .string("pass"), "coverage": .string("blocked"),
                                  "north": .string("blocked"), "segmentation": .string("blocked"),
                                  "lens": .string("blocked")]),
                "flags": .array([.string("capture_validator"), .string("no_visibility_evidence")]),
                "false_valid_guard": .string("blocked"),
                "blocked_reason": .string("Capture validator session: poses recorded, no sky visibility or resolved north yet")
            ]),
            "sharing": .object(["include_hero": .bool(false), "precise_address": .bool(false),
                                "revoked": .bool(false), "revoked_at": .null]),
            "context": .object(["address_estimate": .null])
        ]
        return try SceneRecordDocument(fields: fields)
    }

    /// `PR-YYYYMMDD-NN` (field/README.md). `sequence` is the caller's per-day counter.
    public static func sceneID(date: Date, sequence: Int, timezone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "PR-%04d%02d%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, sequence)
    }
}
