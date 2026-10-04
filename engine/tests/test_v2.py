"""Schema 0.2.0 and quality-0.2 (ADR-0022, docs/03 §11, docs/04 §6, docs/05 §2a). Synthetic records only."""

import base64
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest
import zlib

from lightreplay import quality, scenerecord

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import make_v2_fixture  # noqa: E402
from test_scenerecord import changed, fixture, ready_record  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "scene-v2-cases.json"


def load():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def applied(data, case):
    record = copy.deepcopy(data["bases"][case["base"]])
    for path, value in case["set"]:
        record = changed(record, path, value)
    return record


def without_compressor_choices(value):
    """Two zlib builds may deflate the same bytes differently. Compare what the payloads hold, not how it was packed."""
    if isinstance(value, dict):
        if value.get("encoding") == "deflate+base64" and isinstance(value.get("data"), str):
            try:
                raw = zlib.decompressobj(wbits=-15).decompress(base64.b64decode(value["data"]), 4_000_000)
                return dict(value, data="sha256:" + hashlib.sha256(raw).hexdigest())
            except (zlib.error, ValueError):
                return value
        return {key: without_compressor_choices(child) for key, child in value.items()}
    if isinstance(value, list):
        return [without_compressor_choices(child) for child in value]
    return value


class V2CaseTests(unittest.TestCase):
    def test_every_case_gets_its_verdict(self):
        data = load()
        self.assertEqual(data["version"], quality.VERSION_2)
        self.assertGreater(len(data["cases"]), 50)
        for case in data["cases"]:
            with self.subTest(case["name"]):
                record = applied(data, case)
                if case["accepted"]:
                    scenerecord.validate(record)
                    self.assertEqual(json.loads(scenerecord.dumps(record)), record)
                    self.assertEqual(quality.evaluate(record)["gates"], case["gates"])
                else:
                    with self.assertRaises(scenerecord.ValidationError) as raised:
                        scenerecord.validate(record)
                    self.assertEqual(str(raised.exception).split(": ", 1)[0], case["error_path"])

    def test_fixture_is_current(self):
        self.assertEqual(without_compressor_choices(load()), without_compressor_choices(json.loads(json.dumps(make_v2_fixture.build()))))

    def test_the_review_probes_are_in_the_fixture(self):
        cases = {case["name"]: case for case in load()["cases"]}
        for refused in ("calibration_frame_used_for_visibility", "a_surface_at_the_bright_spot", "lens_not_checked_stated_pass",
                        "reflections_not_checked", "unknown_minutes_counted_as_sun", "never_analysed_but_carrying_a_grid"):
            self.assertFalse(cases[refused]["accepted"], refused)
        # Review V2-01: a vertical mirror keeps the sun's altitude. The stated checks pass and the record is accepted;
        # the fixture holds that on purpose, so the limit of sundisk-0.1 stays in plain sight.
        self.assertTrue(cases["a_mirror_at_the_suns_altitude_is_not_caught"]["accepted"])


class V2RuleTests(unittest.TestCase):
    def test_old_records_are_judged_by_the_old_rules(self):
        for record in (fixture(), ready_record()):
            scenerecord.validate(record)
            result = quality.evaluate(record)
            self.assertEqual(result["version"], quality.VERSION)
            self.assertEqual(set(result["gates"]), {"coverage", "north", "segmentation"})

    def test_all_five_lights_for_a_new_record(self):
        result = quality.evaluate(make_v2_fixture.analysed())
        self.assertEqual(result["version"], quality.VERSION_2)
        self.assertEqual(set(result["gates"]), {"coverage", "north", "segmentation", "level", "lens"})

    def test_tracking_is_read_from_the_scan_frames_only(self):
        def frames(*states):
            return [{"frame_id": f"f{i}", "t": 0.1 * i, "tracking_state": state, "role": role}
                    for i, (state, role) in enumerate(states)]
        scan = lambda *states: frames(*[(state, "visibility") for state in states])  # noqa: E731
        self.assertEqual(quality.tracking(scan("limited:initializing", "limited:initializing"))[0], "blocked")
        self.assertEqual(quality.tracking(scan("limited:initializing", "normal", "normal"))[0], "pass")   # start-up does not count
        gate, _, longest = quality.tracking(scan("normal", "limited:excessive_motion", "limited:excessive_motion", "normal"))
        self.assertEqual((gate, round(longest, 6)), ("pass", 0.2))
        gate, _, longest = quality.tracking(scan("normal", *["limited:insufficient_features"] * 9))
        self.assertEqual((gate, round(longest, 6)), ("warn", 0.8))   # a stretch that never ends runs to the last frame
        self.assertEqual(quality.tracking(scan("normal", "limited:relocalizing", "normal"))[0], "blocked")
        walking = frames(("normal", "visibility"), ("limited:relocalizing", "calibration"))
        self.assertEqual(quality.tracking(walking)[0], "pass")

    def test_sun_disk_failures_are_named_in_order(self):
        evidence = dict(make_v2_fixture.SUN_EVIDENCE)
        self.assertEqual(scenerecord.sun_disk_failures(evidence), [])
        evidence.update(altitude_measured_deg=10.0, depth_m=1.0, user_confirmed=False)
        failures = scenerecord.sun_disk_failures(evidence)
        self.assertEqual(len(failures), 3)
        self.assertIn("altitude", failures[0])

    def test_a_payload_cannot_inflate_past_what_it_states(self):
        record = make_v2_fixture.analysed()
        bomb = zlib.compressobj(9, zlib.DEFLATED, -15)
        record["visibility"]["states"]["data"] = base64.b64encode(bomb.compress(bytes(3_000_000)) + bomb.flush()).decode()
        with self.assertRaises(scenerecord.ValidationError) as raised:
            scenerecord.validate(record)
        self.assertIn("$.visibility.states.data", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
