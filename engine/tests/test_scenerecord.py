"""Synthetic software-only checks; no scene, asset, or device is field-validated."""

import copy
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import unittest

from lightreplay import scenerecord


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).parent / "fixtures" / "scene-r0.json"
PACKAGE = ROOT / "ios" / "Packages" / "SceneRecord"


def fixture():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def changed(record, path, value):
    result = copy.deepcopy(record)
    node = result
    parts = path.split(".")
    for part in parts[:-1]:
        node = node[int(part)] if isinstance(node, list) else node[part]
    node[int(parts[-1]) if isinstance(node, list) else parts[-1]] = value
    return result


def ready_record():
    r = fixture()
    r["target"].update(height_m=1.15, confirmed_by="user")
    r["app"]["algorithms"] = dict.fromkeys(r["app"]["algorithms"], "synthetic-test-only")
    r["capture_session"]["frames"][0].update(mask_ref="masks/synthetic-frame-001.png", used_for_visibility=True)
    r["north"]["candidates"][0].update(yaw_deg=0.0, sigma_deg=2.0, valid=True)
    r["north"]["candidates"][0]["raw"].update(true_heading=0.0, magnetic_heading=0.0, heading_accuracy=2.0)
    r["north"]["resolved"] = dict(yaw_deg=0.0, sigma_deg=2.0, method="synthetic-input-not-a-resolver",
        groups_used=["magnetic"], groups_rejected=[], conflict=False, conflict_detail=None,
        resolved_at="2026-09-21T10:42:12+10:00")
    r["visibility"] = dict(
        grid=dict(az_step_deg=1, alt_step_deg=1, az_frame="ar_world", alt_range=[-10, 90]),
        states_ref="visibility/states.png", confidence_ref="visibility/confidence.png", votes={"sky": 10},
        coverage=dict(corridor_cells=10, unknown_cells=1, glass_cells=0, covered_cells=9, coverage_pct=0.9),
        segmentation=dict(model="synthetic-test-only", glass_detected=False, reflection_flags=[], manual_edits=[]),
        near_field=None)
    r["quality"].update(level="R1", gates=dict(level="pass", coverage="pass", north="warn", segmentation="pass", lens="pass"),
                        false_valid_guard="passed", blocked_reason=None)
    r["analysis"] = [dict(
        query=dict(date_from="2026-06-21", date_to="2026-06-21", time_window=["10:00", "12:00"], scenario="current"),
        bands=[dict(date="2026-06-21", segments=[dict(**{"from": "10:00", "to": "11:00", "state": "sensitive"})])],
        heatmap_ref=None, attribution=[], uncertainty=dict(yaw_sigma_deg=2, samples=1, boundary_jitter_deg=0),
        versions=dict(inputs_hash="synthetic-placeholder-not-a-real-hash", sun="synthetic-test-only"),
        computed_at="2026-09-21T10:42:13+10:00")]
    return r


def invalid_mutations():
    r = fixture()
    cases = [
        ("schema_version", "0.2.0"), ("scene_id", ""), ("timezone", "Mars/Olympus"),
        ("analysis", {}), ("north", None), ("app.algorithms", []),
        ("device.lidar", 1), ("location.lat", 90.1), ("location.lon", -180.1),
        ("location.h_acc_m", -1), ("location.v_acc_m", True), ("location.alt_m", "unknown"),
        ("target.height_m", -1), ("target.anchor_world", [0, 1]),
        ("capture_session.hero_frame.camera_transform", [1] * 15),
        ("capture_session.frames.0.camera_transform", [[1] * 4] * 4),
        ("capture_session.frames.0.intrinsics", [1] * 8),
        ("capture_session.frames.0.intrinsics", [True] * 9),
        ("capture_session.frames.0.used_for_visibility", 1),
        ("capture_session.frames.0.tracking_state", "limited:"),
        ("capture_session.frames.0.t", -1), ("capture_session.frames.0.lens_offset_m", -1),
        ("capture_session.world_alignment", "north"),
        ("capture_session.guidance.question", "made-up"),
        ("capture_session.viewpoint_lock.frames_within", 0.5),
        ("north.candidates.0.valid", True), ("north.candidates.0.group", "imaginary"),
        ("north.candidates.0.raw.heading_accuracy", -1),
        ("quality.gates.coverage", "green"), ("quality.gates.lens", "green"), ("quality.false_valid_guard", "pass"),
        ("capture_session.frames.0.t", 999),
        ("quality.level", "R4"), ("quality.flags", "ok"),
        ("sharing.revoked", True), ("context", None),
    ]
    for path, value in cases:
        yield path, changed(r, path, value)
    for analysis in ([{"hours": 8}], [{"nested": {"duration_seconds": 900}}], [{"bands": []}], [None]):
        yield "R0 injected analysis", changed(r, "analysis", analysis)
    ready = ready_record()
    for path, value in [
        ("quality.false_valid_guard", "blocked"), ("quality.level", "R0"),
        ("quality.gates.north", "blocked"), ("quality.gates.extra", "blocked"),
        ("quality.blocked_reason", "unresolved"),
        ("location", None), ("location.lat", None), ("target", None),
        ("target.height_m", None), ("target.confirmed_by", "algorithm"),
        ("capture_session", None), ("capture_session.frames", []),
        ("capture_session.frames.0.mask_ref", None),
        ("capture_session.frames.0.used_for_visibility", False),
        ("capture_session.frames.0.tracking_state", "limited:synthetic"),
        ("capture_session.viewpoint_lock.handling", "rejected"),
        ("north.resolved", None), ("north.resolved.conflict", True),
        ("north.resolved.groups_used", []), ("north.resolved.groups_used", ["solar"]),
        ("north.resolved.groups_rejected", ["magnetic"]), ("north.candidates", []),
        ("north.candidates.0.valid", False), ("visibility", None),
        ("visibility.states_ref", None), ("visibility.confidence_ref", None),
        ("visibility.segmentation", None), ("visibility.coverage.covered_cells", 10),
        ("visibility.coverage.coverage_pct", 90), ("visibility.coverage.glass_cells", 10),
        ("visibility.grid.alt_range", [90, -10]), ("visibility.grid.az_step_deg", 0),
        ("analysis.0.bands.0.date", "2026-02-30"),
        ("analysis.0.bands.0.segments.0.state", "certain"),
        ("analysis.0.bands.0.segments.0.to", "09:00"),
        ("analysis.0.versions.inputs_hash", None),
    ]:
        yield "R1 " + path, changed(ready, path, value)


class SceneRecordTests(unittest.TestCase):
    def test_shared_synthetic_fixture(self):
        r = scenerecord.loads(FIXTURE.read_bytes())
        self.assertTrue(r["context"]["synthetic"])
        self.assertIn("Never field-validated", r["context"]["notice"])
        self.assertEqual(r["quality"]["level"], "R0")

    def test_null_and_unknown_source_roundtrip(self):
        r = fixture()
        r["north"]["candidates"][0]["raw"]["future_source"] = {"missing": None, "samples": [None, 0, False, "fictional"]}
        r["unknown_root"] = [None, {"custom": "retained"}]
        for pretty in (True, False):
            self.assertEqual(scenerecord.loads(scenerecord.dumps(r, pretty)), r)

    def test_partial_r0_null_roots(self):
        r = fixture()
        for key in ("geometry", "location", "target", "capture_session", "visibility"):
            r[key] = None
        scenerecord.validate(r)
        self.assertEqual(scenerecord.loads(scenerecord.dumps(r)), r)

    def test_null_algorithm_versions_and_frame_refs(self):
        r = fixture()
        r["capture_session"]["hero_frame"]["image_ref"] = None
        r["capture_session"]["frames"][0]["image_ref"] = None
        scenerecord.validate(r)
        self.assertEqual(scenerecord.loads(scenerecord.dumps(r)), r)

    def test_all_required_root_keys(self):
        for key in fixture():
            with self.subTest(key=key):
                r = fixture()
                del r[key]
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(r)

    def test_missing_explicit_sensor_null_is_not_defaulted(self):
        for key in ("mask_ref", "depth_ref", "depth_confidence_ref"):
            with self.subTest(key=key):
                r = fixture()
                del r["capture_session"]["frames"][0][key]
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(r)

    def test_invalid_shapes_vocabulary_and_false_valid_payloads(self):
        for name, r in invalid_mutations():
            with self.subTest(case=name):
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(r)

    def test_synthetic_r1_with_complete_input_evidence(self):
        r = ready_record()
        self.assertEqual(scenerecord.loads(scenerecord.dumps(r)), r)

    def test_r1_empty_analysis_still_requires_evidence(self):
        r = fixture()
        r["quality"].update(level="R1", false_valid_guard="passed", blocked_reason=None,
                            gates=dict.fromkeys(r["quality"]["gates"], "pass"))
        with self.assertRaises(scenerecord.ValidationError):
            scenerecord.validate(r)

    def test_r0_passed_guard_is_inconsistent(self):
        r = changed(fixture(), "quality.false_valid_guard", "passed")
        with self.assertRaises(scenerecord.ValidationError):
            scenerecord.validate(r)

    def test_paths_reject_traversal_schemes_and_ambiguous_encoding(self):
        bad = ("/tmp/hero.heic", "../hero.heic", "masks/../../x", "./x", "a/./x", "a//b", "a/", "",
               "https://example.invalid/x", "file:hero.heic", "C:\\x", "a\\b", "%2e%2e/x", "a%2fb",
               "hero.heic?q=x", "hero.heic#x", "a\x00b", "a\nb")
        for path in bad:
            with self.subTest(path=path):
                r = changed(fixture(), "capture_session.hero_frame.image_ref", path)
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(r)

    def test_valid_relative_paths_and_null_refs(self):
        for path in (None, "hero.heic", "masks/frame-001.png", "depth/frame-001.bin.conf", "fictional assets/hero.heic"):
            with self.subTest(path=path):
                scenerecord.validate(changed(fixture(), "capture_session.hero_frame.image_ref", path))

    def test_known_and_future_asset_refs_are_checked(self):
        for path in ("capture_session.guidance.corridor_ref", "capture_session.frames.0.depth_ref",
                     "capture_session.frames.0.mask_ref", "context.future_ref"):
            with self.subTest(path=path):
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(changed(fixture(), path, "../unsafe"))

    def test_valid_timestamps_offsets_and_leap_dates(self):
        for value in ("2024-02-29T12:30:00Z", "2000-02-29T00:00:00+00:00", "2026-01-01T00:00:00+05:45",
                      "2026-01-01T00:00:00-03:30", "2026-01-01T00:00:00.123456789+14:00"):
            with self.subTest(value=value):
                scenerecord.validate(changed(fixture(), "created_at", value))

    def test_invalid_timestamps_real_dates_and_offsets(self):
        for value in ("2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2026-04-31T00:00:00Z",
                      "2026-01-01T00:00:00", "2026-01-01", "2026-01-01T24:00:00Z", "2026-01-01T00:00:60Z",
                      "2026-01-01T00:00:00+24:00", "2026-01-01T00:00:00+10:60", "0000-01-01T00:00:00Z",
                      "2026-01-01T00:00:00Z\n", "2026-01-01T00:00:00.1234567890Z"):
            with self.subTest(value=value):
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(changed(fixture(), "created_at", value))

    def test_iana_timezones_not_fixed_offsets(self):
        for value in ("UTC", "Etc/UTC", "Australia/Melbourne", "Asia/Kolkata", "America/St_Johns"):
            with self.subTest(valid=value):
                scenerecord.validate(changed(fixture(), "timezone", value))
        for value in ("UTC+10", "+10:00", "Mars/Olympus", "../Australia/Melbourne", "", "PST"):
            with self.subTest(invalid=value):
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(changed(fixture(), "timezone", value))

    def test_session_order_uses_utc_offsets(self):
        r = fixture()
        r["capture_session"].update(started_at="2026-01-01T11:00:00+02:00", ended_at="2026-01-01T10:01:00+01:00")
        scenerecord.validate(r)
        r["capture_session"]["ended_at"] = "2026-01-01T10:59:59+02:00"
        with self.assertRaises(scenerecord.ValidationError):
            scenerecord.validate(r)

    def test_finite_numerics_including_unknown_fields(self):
        for value in (math.nan, math.inf, -math.inf, 10 ** 400):
            for path in ("location.lat", "capture_session.frames.0.intrinsics.0", "context.future_numeric"):
                with self.subTest(value=str(value), path=path):
                    with self.assertRaises(scenerecord.ValidationError):
                        scenerecord.validate(changed(fixture(), path, value))

    def test_non_json_number_tokens(self):
        for token in ("NaN", "Infinity", "-Infinity", "1e400"):
            with self.subTest(token=token):
                data = FIXTURE.read_text().replace('"alt_m": null', '"alt_m": ' + token)
                with self.assertRaises(ValueError):
                    scenerecord.loads(data)

    def test_lat_lon_boundaries_and_nullable_accuracy(self):
        r = fixture()
        for lat, lon in ((-90, -180), (90, 180), (None, None)):
            r["location"].update(lat=lat, lon=lon, h_acc_m=0, v_acc_m=None)
            scenerecord.validate(r)

    def test_column_major_matrix_order_is_preserved(self):
        values = [float(i) for i in range(16)]
        r = changed(fixture(), "capture_session.frames.0.camera_transform", values)
        self.assertEqual(scenerecord.loads(scenerecord.dumps(r))["capture_session"]["frames"][0]["camera_transform"], values)

    def test_duplicate_frame_ids(self):
        r = fixture()
        r["capture_session"]["frames"] *= 2
        with self.assertRaises(scenerecord.ValidationError):
            scenerecord.validate(r)

    def test_duplicate_json_keys_including_escaped_alias(self):
        for data in ('{"quality":{},"quality":{}}', '{"x":1,"\\u0078":2}', '{"nested":{"x":1,"x":2}}'):
            with self.subTest(data=data):
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.loads(data)

    def test_non_object_root_and_malformed_json(self):
        for data in ("[]", "null", "true", "1", "{", '{"x":1,}', "{} {}", '{"x":"\\ud800"}'):
            with self.subTest(data=data):
                with self.assertRaises(ValueError):
                    scenerecord.loads(data)

    def test_deep_nesting_rejected(self):
        r = fixture()
        value = None
        for _ in range(130):
            value = [value]
        r["context"]["nested"] = value
        with self.assertRaises(scenerecord.ValidationError):
            scenerecord.validate(r)

    def test_python_cli_help_and_stdin(self):
        command = [sys.executable, "-B", "-m", "lightreplay.scenerecord"]
        help_result = subprocess.run(command + ["--help"], capture_output=True, text=True)
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        result = subprocess.run(command + ["--compact", "-"], input=FIXTURE.read_text(), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), fixture())


class SwiftParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cli = Path(os.environ.get("SCENE_RECORD_CHECK", PACKAGE / ".build" / "debug" / "scene-record-check"))
        if not cls.cli.is_file():
            raise RuntimeError("Build SceneRecord first with swift test --package-path " + str(PACKAGE))

    def swift(self, value):
        return subprocess.run([str(self.cli), "--compact", "-"], input=json.dumps(value), text=True, capture_output=True)

    def test_shared_fixture_and_r1_roundtrip(self):
        for r in (fixture(), ready_record()):
            with self.subTest(level=r["quality"]["level"]):
                result = self.swift(r)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(scenerecord.loads(result.stdout), r)

    def test_all_adversarial_mutations_rejected_in_both_languages(self):
        for name, r in invalid_mutations():
            with self.subTest(case=name):
                with self.assertRaises(scenerecord.ValidationError):
                    scenerecord.validate(r)
                result = self.swift(r)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(result.stdout, "")

    def test_offsets_timezones_paths_and_finite_number_parity(self):
        cases = [
            ("created_at", "2024-02-29T12:30:00.123456789+05:45", True),
            ("created_at", "1900-02-29T00:00:00Z", False),
            ("created_at", "2026-01-01T00:00:00+24:00", False),
            ("timezone", "Etc/UTC", True), ("timezone", "Asia/Kolkata", True),
            ("timezone", "Mars/Olympus", False),
            ("capture_session.hero_frame.image_ref", "../escape", False),
            ("capture_session.hero_frame.image_ref", "file:escape", False),
            ("capture_session.hero_frame.image_ref", None, True),
            ("context.future_numeric", math.nan, False), ("context.future_numeric", math.inf, False),
        ]
        for path, value, valid in cases:
            with self.subTest(path=path, value=value):
                r = changed(fixture(), path, value)
                if valid:
                    scenerecord.validate(r)
                else:
                    with self.assertRaises(scenerecord.ValidationError):
                        scenerecord.validate(r)
                result = self.swift(r)
                self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_cli_help_file_input_and_invalid_input(self):
        help_result = subprocess.run([str(self.cli), "--help"], text=True, capture_output=True)
        self.assertEqual(help_result.returncode, 0)
        self.assertIn("--output", help_result.stdout)
        result = subprocess.run([str(self.cli), str(FIXTURE)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(scenerecord.loads(result.stdout), fixture())
        for data in ('{"x":1,"\\u0078":2}', "{} {}", "{", "[]"):
            bad = subprocess.run([str(self.cli), "-"], input=data, text=True, capture_output=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertEqual(bad.stdout, "")


if __name__ == "__main__":
    unittest.main()
