"""Writes tests/fixtures/north-cases.json: direction candidates and what the reference NorthResolver makes of them.

The Swift NorthResolver must reproduce every case. Named cases come from docs/02 §6, docs/03 §4 and ADR-0009; the
rest are seeded random inputs. All synthetic. Run from engine/: python3 scripts/make_north_fixture.py
"""

import json
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lightreplay import north  # noqa: E402


def c(group, yaw, sigma, valid=True, source=None):
    return {"source": source or {"magnetic": "magnetometer", "map": "wall_footprint", "solar": "window_patch",
                                 "vps": "geo_tracking"}[group],
            "group": group, "yaw_deg": yaw, "sigma_deg": sigma, "valid": valid}


NAMED = {
    # docs/03 §4: the worked example, solar on the far side of the 0/360 seam.
    "three_groups_agree_across_the_seam": [c("magnetic", 8, 12), c("map", 2, 4), c("solar", 359, 2)],
    "mild_disagreement_still_agrees": [c("map", 10, 4), c("magnetic", 25, 8)],
    # ADR-0009 background 1: only the compass is off. Not a conflict.
    "magnetic_alone_is_off": [c("solar", 1, 2), c("map", 3, 4), c("magnetic", 40, 8)],
    # ADR-0009 background 2: a confident wrong reading must not win on its own.
    "trusted_group_alone_is_off": [c("solar", 20, 2), c("vps", 3, 3), c("map", 2, 4)],
    "two_groups_conflict": [c("vps", 10, 2), c("map", 60, 3)],
    "solar_against_compass_leaves_one_group": [c("solar", 10, 2), c("magnetic", 90, 8)],
    "three_way_split": [c("solar", 0, 1), c("vps", 40, 1), c("map", 80, 1)],
    # solar–map agree, map–magnetic agree, solar–magnetic do not: agreement is pairwise, not a chain.
    "agreement_is_not_a_chain": [c("solar", 0, 2), c("map", 12, 4), c("magnetic", 30, 8)],
    "single_group_small_sigma": [c("map", 123, 4)],
    "single_group_at_the_limit": [c("map", 123, 6)],
    # Review R08 probe: one compass reading with sigma 12 may not carry a result.
    "single_group_large_sigma": [c("magnetic", 77, 12)],
    "no_valid_source": [c("magnetic", None, None, valid=False)],
    # ADR-0009 rule 6: a solar candidate that failed its own residual check is marked invalid upstream.
    "solar_residual_failed_is_not_used": [c("solar", 20, 2, valid=False), c("map", 2, 4)],
    "a_reading_without_sigma_is_not_evidence": [c("map", 5, 0)],
    "compass_readings_merge_into_one_group": [c("magnetic", 350, 8), c("magnetic", 352, 9), c("magnetic", 355, 8),
                                              c("magnetic", 358, 10), c("magnetic", 2, 8)],
    "scattered_compass_readings_widen_sigma": [c("magnetic", 10, 8), c("magnetic", 40, 8), c("magnetic", 80, 8),
                                               c("magnetic", 120, 8)],
    "two_solar_readings_and_a_wall": [c("solar", 359, 2), c("solar", 1, 1.5, source="sun_disk"), c("map", 2, 4)],
    # ADR-0009's blind spot, closed by ADR-0018: a 17 degree error hides inside a compass sigma of 12, so the compass
    # agreeing says nothing and the light stays amber.
    "wide_compass_agreeing_is_not_corroboration": [c("solar", 20, 2), c("magnetic", 3, 12)],
    # Opposite compass readings give a sigma of 90 that cannot disagree with anything: agreement, no corroboration.
    "a_group_too_wide_to_disagree_does_not_corroborate": [c("map", 100, 4), c("magnetic", 0, 8), c("magnetic", 180, 8)],
    # Wall and compass agree, but 3·sqrt(16 + 64) = 26.8° > 15°: amber, not green (ADR-0018).
    "wall_and_compass_agree_without_corroborating": [c("map", 2, 4), c("magnetic", 0, 8)],
    # Two wide groups agree and their fused sigma is 7.7°: one confirmation before anything beyond R0.
    "two_wide_groups_agree_above_six": [c("map", 5, 10), c("magnetic", 0, 12)],
    # Three groups, only solar and vps tight enough to corroborate; the compass rides along in the fusion.
    "one_corroborating_pair_among_three": [c("solar", 1, 2), c("vps", 3, 3), c("magnetic", 10, 9)],
}


def random_cases(count, seed=20261001):
    rng = random.Random(seed)
    cases = {}
    for index in range(count):
        base = rng.uniform(0, 360)
        candidates = []
        for _ in range(rng.randint(1, 6)):
            group = rng.choice(north.GROUP_TRUST)
            # Mostly near a common direction, sometimes anywhere, so agreement and conflict both occur.
            yaw = (base + rng.gauss(0, 6)) % 360 if rng.random() < 0.75 else rng.uniform(0, 360)
            candidates.append(c(group, round(yaw, 3), round(rng.uniform(0.5, 15), 2), valid=rng.random() < 0.9))
        cases[f"random_{index:03d}"] = candidates
    return cases


def build():
    cases = dict(NAMED)
    cases.update(random_cases(200))
    return {"note": "Synthetic direction candidates and the reference result (engine/lightreplay/north.py). "
                    "Regenerate with engine/scripts/make_north_fixture.py.",
            "version": north.VERSION,
            "cases": [{"name": name, "candidates": candidates, "expected": north.resolve(candidates)}
                      for name, candidates in cases.items()]}


def main():
    out = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "north-cases.json"
    data = build()
    lines = ",\n".join("  " + json.dumps(case, separators=(",", ":")) for case in data["cases"])   # one case a line
    head = ",\n".join(f"{json.dumps(key)}:{json.dumps(data[key])}" for key in ("note", "version"))
    out.write_text(f'{{{head},\n"cases":[\n{lines}\n]}}\n', encoding="utf-8")
    print(f"wrote {out} ({len(NAMED)} named + 200 random cases)")


if __name__ == "__main__":
    main()
