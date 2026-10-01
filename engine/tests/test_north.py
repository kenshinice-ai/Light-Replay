"""NorthResolver fusion checks (docs/05 §3, ADR-0009, docs/02 §6). Synthetic candidates; nothing is field-validated.

Expected values are written from the documents, not from the implementation. The fixture then pins the numbers so
the Swift implementation can be held to the same results.
"""

import json
from pathlib import Path
import random
import sys
import unittest

from lightreplay import north

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import make_north_fixture  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "north-cases.json"
NAMED = make_north_fixture.NAMED


def c(group, yaw, sigma, valid=True):
    return {"source": "synthetic", "group": group, "yaw_deg": yaw, "sigma_deg": sigma, "valid": valid}


class CircularTests(unittest.TestCase):
    def test_differences_cross_the_seam(self):
        self.assertAlmostEqual(north.circular_difference(359, 2), 3)   # blueprint review #4: not 357
        self.assertAlmostEqual(north.circular_difference(2, 359), 3)
        self.assertAlmostEqual(north.circular_difference(0, 180), 180)
        self.assertAlmostEqual(north.signed_offset(359, 1), -2)
        self.assertAlmostEqual(north.signed_offset(1, 359), 2)

    def test_folding_never_returns_360(self):
        for angle in (-1e-17, 360.0, 720.0, -360.0, 359.99999999999994):
            self.assertTrue(0 <= north.mod360(angle) < 360, angle)

    def test_group_median_is_not_split_by_the_seam(self):
        yaw, sigma, spread = north.merge_group([(359, 8), (1, 8), (3, 8)])
        self.assertAlmostEqual(yaw, 1)
        self.assertAlmostEqual(spread, (8 / 3) ** 0.5)   # offsets −2, 0, +2
        self.assertEqual(sigma, 8)                       # the readings' own sigma is the larger

    def test_more_readings_of_one_sensor_never_shrink_sigma(self):
        one = north.merge_group([(100, 8)])
        many = north.merge_group([(100, 8)] * 50)
        self.assertEqual(one[1], 8)
        self.assertEqual(many[1], 8)


class ResolveTests(unittest.TestCase):
    def resolve(self, name):
        return north.resolve(NAMED[name])

    def test_worked_example_of_docs_03(self):
        r = self.resolve("three_groups_agree_across_the_seam")
        self.assertEqual(round(r["yaw_deg"], 2), 359.78)
        self.assertEqual(round(r["sigma_deg"], 2), 1.77)
        self.assertEqual(r["groups_used"], ["solar", "map", "magnetic"])
        self.assertEqual((r["gate"], r["conflict"], r["groups_rejected"]), ("pass", False, []))

    def test_mild_disagreement_is_fused_by_inverse_variance(self):
        # map 10±4 and magnetic 25±8 differ by 15, inside 3·sqrt(16 + 64) = 26.8. Weights 1/16 and 1/64 give 13.
        r = self.resolve("mild_disagreement_still_agrees")
        self.assertEqual((r["groups_used"], r["groups_rejected"], r["gate"]), (["map", "magnetic"], [], "pass"))
        self.assertAlmostEqual(r["yaw_deg"], 13.0, delta=0.05)
        self.assertAlmostEqual(r["sigma_deg"], (1 / (1 / 16 + 1 / 64)) ** 0.5)
        self.assertEqual(r["disagreements"], [])

    def test_every_named_case_has_a_hand_written_expectation(self):
        source = Path(__file__).read_text(encoding="utf-8")
        for name in NAMED:
            self.assertIn(f'"{name}"', source, "a named case nobody states an expectation for only tests itself")

    def test_compass_alone_off_is_not_a_conflict(self):
        r = self.resolve("magnetic_alone_is_off")
        self.assertEqual((r["groups_used"], r["groups_rejected"]), (["solar", "map"], ["magnetic"]))
        self.assertEqual((r["gate"], r["conflict"], r["needs_confirmation"]), ("pass", False, False))
        self.assertEqual(len(r["disagreements"]), 2, "the rejected reading's disagreements are still recorded")

    def test_confident_wrong_reading_does_not_win(self):
        r = self.resolve("trusted_group_alone_is_off")
        self.assertEqual((r["groups_used"], r["groups_rejected"]), (["vps", "map"], ["solar"]))
        self.assertEqual((r["gate"], r["conflict"], r["needs_confirmation"]), ("blocked", True, True))

    def test_two_groups_in_conflict_block(self):
        r = self.resolve("two_groups_conflict")
        self.assertEqual((r["groups_used"], r["groups_rejected"]), (["vps"], ["map"]))
        self.assertEqual((r["gate"], r["conflict"]), ("blocked", True))

    def test_rejecting_only_the_compass_leaves_a_single_group(self):
        r = self.resolve("solar_against_compass_leaves_one_group")
        self.assertEqual((r["groups_used"], r["groups_rejected"], r["conflict"]), (["solar"], ["magnetic"], False))
        self.assertEqual(r["gate"], "warn")

    def test_three_way_split_blocks(self):
        r = self.resolve("three_way_split")
        self.assertEqual((r["groups_used"], r["gate"], r["conflict"]), (["solar"], "blocked", True))

    def test_agreement_is_pairwise(self):
        r = self.resolve("agreement_is_not_a_chain")
        self.assertEqual((r["groups_used"], r["groups_rejected"]), (["solar", "map"], ["magnetic"]))
        self.assertEqual(r["gate"], "pass")

    def test_single_group_lights(self):
        self.assertEqual(self.resolve("single_group_small_sigma")["gate"], "warn")
        self.assertEqual(self.resolve("single_group_at_the_limit")["gate"], "warn")
        r = self.resolve("single_group_large_sigma")
        self.assertEqual((r["gate"], r["needs_confirmation"]), ("blocked", True))

    def test_nothing_usable_is_blocked_and_unresolved(self):
        for name in ("no_valid_source", "a_reading_without_sigma_is_not_evidence"):
            r = self.resolve(name)
            self.assertEqual((r["gate"], r["yaw_deg"], r["sigma_deg"], r["groups_used"]), ("blocked", None, None, []), name)

    def test_invalid_solar_candidate_is_ignored(self):
        r = self.resolve("solar_residual_failed_is_not_used")
        self.assertEqual((r["groups_used"], r["groups_rejected"], r["gate"]), (["map"], [], "warn"))
        self.assertAlmostEqual(r["yaw_deg"], 2)

    def test_compass_readings_are_one_group(self):
        r = self.resolve("compass_readings_merge_into_one_group")
        self.assertEqual(r["groups"]["magnetic"]["readings"], 5)
        self.assertAlmostEqual(r["yaw_deg"], 355)             # the middle reading
        self.assertAlmostEqual(r["sigma_deg"], 8)             # median of the readings' sigma; the spread is smaller
        self.assertEqual(r["gate"], "blocked")
        scattered = self.resolve("scattered_compass_readings_widen_sigma")
        self.assertGreater(scattered["sigma_deg"], 35)
        self.assertEqual(scattered["gate"], "blocked")

    def test_two_solar_readings_count_once(self):
        r = self.resolve("two_solar_readings_and_a_wall")
        self.assertEqual(r["groups_used"], ["solar", "map"])
        self.assertAlmostEqual(r["groups"]["solar"]["yaw_deg"], 0)
        self.assertAlmostEqual(r["groups"]["solar"]["sigma_deg"], 1.75)
        self.assertEqual(r["gate"], "pass")

    def test_known_blind_spots_are_what_adr_0009_says(self):
        # Not a goal: the accepted rule cannot see these. Pinned so a change to them is a decision, not an accident.
        hidden = self.resolve("known_blind_spot_wide_compass_hides_an_error")
        self.assertEqual((hidden["groups_used"], hidden["gate"]), (["solar", "magnetic"], "pass"))
        vacuous = self.resolve("known_blind_spot_a_group_too_wide_to_disagree")
        self.assertAlmostEqual(vacuous["groups"]["magnetic"]["sigma_deg"], 90)
        self.assertEqual((vacuous["groups_used"], vacuous["gate"]), (["map", "magnetic"], "pass"))


class InvarianceTests(unittest.TestCase):
    def test_turning_every_candidate_turns_the_answer(self):
        rng = random.Random(7)
        for name, candidates in make_north_fixture.random_cases(60, seed=99).items():
            base = north.resolve(candidates)
            turn = rng.uniform(0, 360)
            turned = north.resolve([dict(x, yaw_deg=None if x["yaw_deg"] is None else (x["yaw_deg"] + turn) % 360)
                                    for x in candidates])
            self.assertEqual((turned["gate"], turned["groups_used"], turned["groups_rejected"], turned["conflict"]),
                             (base["gate"], base["groups_used"], base["groups_rejected"], base["conflict"]), name)
            if base["yaw_deg"] is not None:
                self.assertLess(north.circular_difference(turned["yaw_deg"], base["yaw_deg"] + turn), 1e-6, name)
                self.assertAlmostEqual(turned["sigma_deg"], base["sigma_deg"], places=6, msg=name)

    def test_candidate_order_does_not_matter(self):
        rng = random.Random(11)
        for name, candidates in make_north_fixture.random_cases(60, seed=5).items():
            base = north.resolve(candidates)
            shuffled = candidates[:]
            rng.shuffle(shuffled)
            again = north.resolve(shuffled)
            self.assertEqual((again["gate"], again["groups_used"], again["groups_rejected"]),
                             (base["gate"], base["groups_used"], base["groups_rejected"]), name)
            if base["yaw_deg"] is not None:
                self.assertLess(north.circular_difference(again["yaw_deg"], base["yaw_deg"]), 1e-9, name)


class FixtureTests(unittest.TestCase):
    def test_fixture_is_current(self):
        stored = json.loads(FIXTURE.read_text(encoding="utf-8"))
        fresh = json.loads(json.dumps(make_north_fixture.build()))
        self.assertEqual(stored["version"], north.VERSION)
        self.assertEqual([case["name"] for case in stored["cases"]], [case["name"] for case in fresh["cases"]])
        for old, new in zip(stored["cases"], fresh["cases"]):
            self.assertEqual(old["candidates"], new["candidates"], old["name"])
            for key in ("groups_used", "groups_rejected", "conflict", "gate", "needs_confirmation", "reason"):
                self.assertEqual(old["expected"][key], new["expected"][key], old["name"])
            for key in ("yaw_deg", "sigma_deg"):
                if new["expected"][key] is None:
                    self.assertIsNone(old["expected"][key], old["name"])
                else:
                    self.assertAlmostEqual(old["expected"][key], new["expected"][key], places=9, msg=old["name"])

    def test_fixture_covers_every_light_and_a_conflict(self):
        cases = json.loads(FIXTURE.read_text(encoding="utf-8"))["cases"]
        self.assertEqual({case["expected"]["gate"] for case in cases}, {"pass", "warn", "blocked"})
        self.assertTrue(any(case["expected"]["conflict"] for case in cases))
        self.assertTrue(any(case["expected"]["groups_rejected"] == ["magnetic"] for case in cases))


if __name__ == "__main__":
    unittest.main()
