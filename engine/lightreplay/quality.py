"""QualityEvaluator (docs/04 §6, ADR-0009): what the evidence in a SceneRecord supports. Reference, quality-0.1.

The gates a record states are claims. This module works them out again from the evidence the record carries and
refuses a record whose claims differ from it (reviews F05 and R08). Three of the five lights can be recomputed from
schema 0.1.0: coverage, north and segmentation. `level` (tracking) and `lens` are decided by on-device detectors
whose evidence the schema does not carry, so they stay as recorded; what can be checked about them is checked:
a frame used for visibility must have normal tracking and sit inside the drift limit.

Every limit here is a candidate from docs/04 until the spike (docs/07) confirms it. Synthetic software checks only.
"""

import math

from . import north as north_resolver
from .scenerecord import ValidationError

VERSION = "quality-0.1"
#: Share of the sun corridor seen: at least this passes, at least COVERAGE_WARN warns (docs/04 §6).
COVERAGE_PASS_PCT = 90
COVERAGE_WARN_PCT = 70
#: Share of the corridor that is glass-uncertain: below WARN passes, up to BLOCK warns (docs/04 §6).
GLASS_WARN_PCT = 10
GLASS_BLOCK_PCT = 25
#: A frame further than this from the anchor is not merged into the visibility grid (docs/04 §4).
DRIFT_LIMIT_M = 0.40
#: Numerical slack for "the same point" and for one-decimal rounding of a stored resolution. Not product limits.
ANCHOR_MATCH_M = 1e-6
RESOLVED_MATCH_DEG = 0.1
#: The lights this module can recompute from the record.
EVALUATED = ("coverage", "north", "segmentation")


class QualityError(ValidationError):
    """A record whose stated quality goes beyond, or disagrees with, its own evidence."""


def evaluate(record):
    """Recompute the evaluable lights of a shape-valid record.

    Returns `gates` and `reasons` for coverage, north and segmentation, the `north` resolution they rest on, and
    `problems`: physical contradictions that forbid anything beyond R0 whatever the lights say.
    """
    gates, reasons = {}, {}
    visibility = record["visibility"]
    coverage = visibility["coverage"] if visibility else None
    corridor = coverage["corridor_cells"] if coverage else 0
    # Cell counts are integers, so the limits are compared without division: 63 of 90 is exactly 70%.
    if corridor <= 0:
        gates["coverage"], reasons["coverage"] = "blocked", "no sun corridor evidence"
    else:
        covered = coverage["covered_cells"]
        gates["coverage"] = ("pass" if covered * 100 >= COVERAGE_PASS_PCT * corridor
                             else "warn" if covered * 100 >= COVERAGE_WARN_PCT * corridor else "blocked")
        reasons["coverage"] = f"{int(covered)} of {int(corridor)} corridor cells seen"

    segmentation = visibility["segmentation"] if visibility else None
    if corridor <= 0 or segmentation is None or segmentation["model"] is None:
        gates["segmentation"], reasons["segmentation"] = "blocked", "no segmentation evidence"
    else:
        glass = coverage["glass_cells"]
        gates["segmentation"] = ("pass" if glass * 100 < GLASS_WARN_PCT * corridor
                                 else "warn" if glass * 100 <= GLASS_BLOCK_PCT * corridor else "blocked")
        reasons["segmentation"] = f"{int(glass)} of {int(corridor)} corridor cells are glass-uncertain"

    resolution = north_resolver.resolve(record["north"]["candidates"])
    gates["north"], reasons["north"] = resolution["gate"], resolution["reason"]

    problems = []
    target, session = record["target"], record["capture_session"]
    if target is not None and session is not None:
        gap = math.dist(target["anchor_world"], session["viewpoint_lock"]["anchor_world"])
        if gap > ANCHOR_MATCH_M:
            problems.append(f"target anchor and viewpoint lock anchor are {gap:.3f} m apart: not one viewpoint")
    for frame in (session["frames"] if session is not None else []):
        if not frame["used_for_visibility"]:
            continue
        if frame["tracking_state"] != "normal":
            problems.append(f"frame {frame['frame_id']} is used for visibility without normal tracking")
        elif frame["lens_offset_m"] is None or frame["lens_offset_m"] > DRIFT_LIMIT_M + 1e-9:
            problems.append(f"frame {frame['frame_id']} is used for visibility beyond the {DRIFT_LIMIT_M:g} m drift limit")
    return {"version": VERSION, "gates": gates, "reasons": reasons, "north": resolution, "problems": problems}


def check(record):
    """Raise `QualityError` unless the record's stated quality follows from its evidence.

    For every record: the three evaluable lights must be stated as the evidence gives them, and a stored north
    resolution must be the one its candidates produce. For a record that claims more than R0: no physical
    contradiction either. Unknown stays unknown: missing evidence is `blocked`, never assumed.
    """
    result = evaluate(record)
    stated = record["quality"]["gates"]
    for gate in EVALUATED:
        if stated[gate] != result["gates"][gate]:
            raise QualityError(f"$.quality.gates.{gate}: stated {stated[gate]}, but the evidence gives "
                               f"{result['gates'][gate]} ({result['reasons'][gate]})")
    resolved, computed = record["north"]["resolved"], result["north"]
    if resolved is not None:
        same = (computed["yaw_deg"] is not None
                and set(resolved["groups_used"]) == set(computed["groups_used"])
                and set(resolved["groups_rejected"]) == set(computed["groups_rejected"])
                and resolved["conflict"] == computed["conflict"]
                and north_resolver.circular_difference(resolved["yaw_deg"], computed["yaw_deg"]) <= RESOLVED_MATCH_DEG
                and abs(resolved["sigma_deg"] - computed["sigma_deg"]) <= RESOLVED_MATCH_DEG)
        if not same:
            raise QualityError("$.north.resolved: does not follow from the candidates")
    if record["quality"]["level"] != "R0" and result["problems"]:
        raise QualityError("$.quality.level: " + result["problems"][0])
    return result
