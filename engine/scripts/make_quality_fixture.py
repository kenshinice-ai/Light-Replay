"""Writes tests/fixtures/quality-cases.json: records, one change each, and whether the quality rules accept them.

Shared by the Python and Swift tests so both hold the same line (docs/04 §6, ADR-0009, review R08). What each case
expects is written here by hand from the documents; the script refuses to write a fixture the reference
implementation disagrees with. All synthetic. Run from engine/: python3 scripts/make_quality_fixture.py
"""

import copy
import json
from pathlib import Path
import sys

ENGINE = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ENGINE), str(ENGINE / "tests")]
from lightreplay import north, quality, scenerecord  # noqa: E402
from test_scenerecord import changed, fixture, ready_record  # noqa: E402

READY_GATES = {"coverage": "pass", "north": "warn", "segmentation": "pass"}
R0_GATES = {"coverage": "blocked", "north": "blocked", "segmentation": "blocked"}


def coverage(corridor, unknown, glass):
    covered = corridor - unknown
    return {"corridor_cells": corridor, "unknown_cells": unknown, "glass_cells": glass, "covered_cells": covered,
            "coverage_pct": covered / corridor}


def candidate(group, yaw, sigma):
    return {"source": {"magnetic": "magnetometer", "map": "wall_footprint", "solar": "window_patch",
                       "vps": "geo_tracking"}[group], "group": group, "yaw_deg": yaw, "sigma_deg": sigma, "valid": True}


def resolved_for(candidates, **overrides):
    """A stored resolution as an honest app would write it: the reference result, rounded to one decimal."""
    r = north.resolve(candidates)
    stored = {"yaw_deg": round(r["yaw_deg"], 1) % 360, "sigma_deg": round(r["sigma_deg"], 1), "method": north.METHOD,
              "groups_used": r["groups_used"], "groups_rejected": r["groups_rejected"], "conflict": r["conflict"],
              "conflict_detail": None, "resolved_at": "2026-09-21T10:42:12+10:00"}
    stored.update(overrides)
    return stored


def second_frame(**overrides):
    frame = copy.deepcopy(ready_record()["capture_session"]["frames"][0])
    frame.update(frame_id="synthetic-frame-002", t=1.0, mask_ref="masks/synthetic-frame-002.png")
    frame.update(overrides)
    return frame


TWO_GROUPS = [candidate("solar", 0.0, 2.0), candidate("map", 2.0, 4.0)]            # 3·sqrt(4 + 16) = 13.4°: corroborate
UNCORROBORATED = [candidate("magnetic", 0.0, 8.0), candidate("map", 2.0, 4.0)]    # 3·sqrt(64 + 16) = 26.8°: agree only
SPLIT = [candidate("solar", 20.0, 2.0), candidate("vps", 3.0, 3.0), candidate("map", 2.0, 4.0)]

# name, base, changes, accepted, path of the refusal, the lights the evidence gives
CASES = [
    ("ready_record", "ready", [], True, None, READY_GATES),

    # The four probes of review R08 that the shape checks let through.
    ("probe_single_group_sigma_12", "ready",
     [["north.candidates.0.sigma_deg", 12], ["north.resolved.sigma_deg", 12]],
     False, "$.quality.gates.north", dict(READY_GATES, north="blocked")),
    ("probe_coverage_1_percent", "ready", [["visibility.coverage", coverage(100, 99, 0)]],
     False, "$.quality.gates.coverage", dict(READY_GATES, coverage="blocked")),
    ("probe_glass_90_percent", "ready", [["visibility.coverage.glass_cells", 9]],
     False, "$.quality.gates.segmentation", dict(READY_GATES, segmentation="blocked")),
    ("probe_mismatched_anchor", "ready", [["target.anchor_world", [7, 0, 0]]],
     False, "$.quality.level", READY_GATES),

    # Coverage: at least 90% passes, at least 70% warns (docs/04 §6).
    ("coverage_exactly_70_warns", "ready",
     [["visibility.coverage", coverage(10, 3, 0)], ["quality.gates.coverage", "warn"]],
     True, None, dict(READY_GATES, coverage="warn")),
    ("coverage_63_of_90_is_exactly_70", "ready",
     [["visibility.coverage", coverage(90, 27, 0)], ["quality.gates.coverage", "warn"]],
     True, None, dict(READY_GATES, coverage="warn")),
    ("coverage_69_stated_warn", "ready",
     [["visibility.coverage", coverage(100, 31, 0)], ["quality.gates.coverage", "warn"]],
     False, "$.quality.gates.coverage", dict(READY_GATES, coverage="blocked")),
    ("coverage_89_stated_pass", "ready", [["visibility.coverage", coverage(100, 11, 0)]],
     False, "$.quality.gates.coverage", dict(READY_GATES, coverage="warn")),
    ("coverage_89_stated_warn", "ready",
     [["visibility.coverage", coverage(100, 11, 0)], ["quality.gates.coverage", "warn"]],
     True, None, dict(READY_GATES, coverage="warn")),
    ("understating_coverage_is_refused_too", "ready",
     [["visibility.coverage", coverage(10, 0, 0)], ["quality.gates.coverage", "warn"]],
     False, "$.quality.gates.coverage", READY_GATES),

    # Segmentation: glass-uncertain below 10% of the corridor passes, up to 25% warns.
    ("glass_9_percent_passes", "ready", [["visibility.coverage", coverage(100, 0, 9)]], True, None, READY_GATES),
    ("glass_10_percent_stated_pass", "ready", [["visibility.coverage", coverage(100, 0, 10)]],
     False, "$.quality.gates.segmentation", dict(READY_GATES, segmentation="warn")),
    ("glass_10_percent_stated_warn", "ready",
     [["visibility.coverage", coverage(100, 0, 10)], ["quality.gates.segmentation", "warn"]],
     True, None, dict(READY_GATES, segmentation="warn")),
    ("glass_25_percent_stated_warn", "ready",
     [["visibility.coverage", coverage(100, 0, 25)], ["quality.gates.segmentation", "warn"]],
     True, None, dict(READY_GATES, segmentation="warn")),
    ("glass_26_percent_stated_warn", "ready",
     [["visibility.coverage", coverage(100, 0, 26)], ["quality.gates.segmentation", "warn"]],
     False, "$.quality.gates.segmentation", dict(READY_GATES, segmentation="blocked")),

    # One viewpoint: frames merged into the grid sit inside the drift limit with normal tracking (docs/04 §4).
    ("used_frame_at_the_drift_limit", "ready", [["capture_session.frames.0.lens_offset_m", 0.4]], True, None, READY_GATES),
    ("used_frame_beyond_the_drift_limit", "ready", [["capture_session.frames.0.lens_offset_m", 0.5]],
     False, "$.quality.level", READY_GATES),
    ("used_frame_without_normal_tracking", "ready",
     [["capture_session.frames", [ready_record()["capture_session"]["frames"][0],
                                  second_frame(tracking_state="limited:excessive_motion")]],
      ["capture_session.ended_at", "2026-09-21T10:42:14+10:00"]],
     False, "$.quality.level", READY_GATES),

    # North: the stored resolution has to be the one the candidates give (docs/05 §3, ADR-0009).
    ("resolved_does_not_follow_from_candidates", "ready", [["north.resolved.yaw_deg", 30]],
     False, "$.north.resolved", READY_GATES),
    ("resolved_sigma_understated", "ready", [["north.resolved.sigma_deg", 1.0]],
     False, "$.north.resolved", READY_GATES),
    ("resolved_rounded_to_one_decimal_is_fine", "ready", [["north.candidates.0.yaw_deg", 0.04]], True, None, READY_GATES),
    ("two_groups_agree", "ready",
     [["north.candidates", TWO_GROUPS], ["north.resolved", resolved_for(TWO_GROUPS)], ["quality.gates.north", "pass"]],
     True, None, dict(READY_GATES, north="pass")),
    ("two_groups_agree_stated_warn", "ready",
     [["north.candidates", TWO_GROUPS], ["north.resolved", resolved_for(TWO_GROUPS)]],
     False, "$.quality.gates.north", dict(READY_GATES, north="pass")),
    ("agreement_without_corroboration_is_amber", "ready",
     [["north.candidates", UNCORROBORATED], ["north.resolved", resolved_for(UNCORROBORATED)]],
     True, None, READY_GATES),
    ("agreement_without_corroboration_stated_pass", "ready",
     [["north.candidates", UNCORROBORATED], ["north.resolved", resolved_for(UNCORROBORATED)], ["quality.gates.north", "pass"]],
     False, "$.quality.gates.north", READY_GATES),
    ("a_conflict_cannot_be_stated_away", "ready",
     [["north.candidates", SPLIT], ["north.resolved", resolved_for(SPLIT, conflict=False)], ["quality.gates.north", "pass"]],
     False, "$.quality.gates.north", dict(READY_GATES, north="blocked")),

    # R0 records claim nothing beyond capture, and still may not state a light they have no evidence for.
    ("r0_fixture", "r0", [], True, None, R0_GATES),
    ("r0_stating_coverage_without_evidence", "r0", [["quality.gates.coverage", "pass"]],
     False, "$.quality.gates.coverage", R0_GATES),
    ("r0_stating_north_without_a_source", "r0", [["quality.gates.north", "warn"]],
     False, "$.quality.gates.north", R0_GATES),
    ("r0_with_two_anchors_stays_r0", "r0", [["target.anchor_world", [7, 0, 0]]], True, None, R0_GATES),
]


def apply(base, changes):
    record = copy.deepcopy(base)
    for path, value in changes:
        record = changed(record, path, value)
    return record


def build():
    bases = {"ready": ready_record(), "r0": fixture()}
    cases = []
    for name, base, changes, accepted, path, gates in CASES:
        record = apply(bases[base], changes)
        try:
            scenerecord.validate(record)
            outcome = None
        except scenerecord.ValidationError as error:
            outcome = str(error).split(": ", 1)[0]
        assert (outcome is None) == accepted and outcome == path, f"{name}: reference says {outcome!r}"
        assert quality.evaluate(record)["gates"] == gates, f"{name}: reference gives {quality.evaluate(record)['gates']}"
        cases.append({"name": name, "base": base, "set": changes, "accepted": accepted, "error_path": path, "gates": gates})
    return {"note": "Synthetic records and the quality verdict each must get (engine/scripts/make_quality_fixture.py). "
                    "Expectations are written by hand from docs/04 §6 and ADR-0009.",
            "version": quality.VERSION, "bases": bases, "cases": cases}


def main():
    out = ENGINE / "tests" / "fixtures" / "quality-cases.json"
    data = build()
    compact = {"separators": (",", ":")}
    bases = ",\n".join(f"  {json.dumps(name)}:{json.dumps(record, **compact)}" for name, record in data["bases"].items())
    cases = ",\n".join("  " + json.dumps(case, **compact) for case in data["cases"])   # one case a line
    head = ",\n".join(f"{json.dumps(key)}:{json.dumps(data[key])}" for key in ("note", "version"))
    out.write_text(f'{{{head},\n"bases":{{\n{bases}\n}},\n"cases":[\n{cases}\n]}}\n', encoding="utf-8")
    print(f"wrote {out} ({len(CASES)} cases)")


if __name__ == "__main__":
    main()
