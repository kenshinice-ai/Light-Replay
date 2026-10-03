"""QualityEvaluator checks (docs/04 §6, ADR-0009, review R08). Synthetic records; nothing is field-validated."""

import copy
import json
from pathlib import Path
import sys
import unittest

from lightreplay import quality, scenerecord

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import make_quality_fixture  # noqa: E402
from test_scenerecord import changed, ready_record  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "quality-cases.json"


def load():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def applied(data, case):
    record = copy.deepcopy(data["bases"][case["base"]])
    for path, value in case["set"]:
        record = changed(record, path, value)
    return record


class QualityCaseTests(unittest.TestCase):
    def test_every_case_gets_its_verdict(self):
        data = load()
        self.assertEqual(data["version"], quality.VERSION)
        for case in data["cases"]:
            with self.subTest(case["name"]):
                record = applied(data, case)
                self.assertEqual(quality.evaluate(record)["gates"], case["gates"])
                if case["accepted"]:
                    scenerecord.validate(record)
                    self.assertEqual(json.loads(scenerecord.dumps(record)), record)
                else:
                    with self.assertRaises(scenerecord.ValidationError) as raised:
                        scenerecord.validate(record)
                    self.assertEqual(str(raised.exception).split(": ", 1)[0], case["error_path"])

    def test_the_four_r08_probes_are_refused(self):
        refused = {case["name"] for case in load()["cases"] if not case["accepted"]}
        self.assertLessEqual({"probe_single_group_sigma_12", "probe_coverage_1_percent", "probe_glass_90_percent",
                              "probe_mismatched_anchor"}, refused)

    def test_fixture_is_current(self):
        self.assertEqual(load(), json.loads(json.dumps(make_quality_fixture.build())))


class QualityRuleTests(unittest.TestCase):
    def test_unknown_stays_unknown(self):
        # No visibility, no segmentation provenance, no usable direction: every evaluable light is blocked.
        record = ready_record()
        record["visibility"] = None
        record["north"]["candidates"][0].update(valid=False, yaw_deg=None, sigma_deg=None)
        result = quality.evaluate(record)
        self.assertEqual(result["gates"], {"coverage": "blocked", "north": "blocked", "segmentation": "blocked"})
        self.assertIsNone(result["north"]["yaw_deg"])

    def test_segmentation_without_provenance_is_blocked(self):
        record = ready_record()
        record["visibility"]["segmentation"] = None
        self.assertEqual(quality.evaluate(record)["gates"]["segmentation"], "blocked")
        record = ready_record()
        record["visibility"]["segmentation"]["model"] = None
        self.assertEqual(quality.evaluate(record)["gates"]["segmentation"], "blocked")

    def test_problems_name_the_frame(self):
        record = ready_record()
        record["capture_session"]["frames"][0]["lens_offset_m"] = 0.75
        problems = quality.evaluate(record)["problems"]
        self.assertEqual(len(problems), 1)
        self.assertIn("synthetic-frame-001", problems[0])

    def test_frames_not_used_for_visibility_are_free_to_drift(self):
        record = ready_record()
        extra = copy.deepcopy(record["capture_session"]["frames"][0])
        extra.update(frame_id="synthetic-frame-002", lens_offset_m=2.0, tracking_state="limited:initializing",
                     used_for_visibility=False, mask_ref=None)
        record["capture_session"]["frames"].append(extra)
        self.assertEqual(quality.evaluate(record)["problems"], [])
        scenerecord.validate(record)

    def test_refusal_is_a_validation_error_with_the_evidence_in_words(self):
        record = ready_record()
        record["visibility"]["coverage"].update(corridor_cells=100, unknown_cells=99, covered_cells=1, coverage_pct=0.01)
        with self.assertRaises(quality.QualityError) as raised:
            scenerecord.validate(record)
        self.assertIsInstance(raised.exception, scenerecord.ValidationError)
        self.assertIn("1 of 100 corridor cells seen", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
