"""QualityEvaluator (docs/04 §6, ADR-0009, ADR-0022): what the evidence in a SceneRecord supports. Reference.

The gates a record states are claims. This module works them out again from the evidence the record carries and
refuses a record whose claims differ from it (reviews F05 and R08).

quality-0.1, for schema 0.1.0: coverage, north and segmentation are recomputed. `level` (tracking) and `lens` have
no evidence in that schema and stay as recorded; what can be checked about them is checked: a frame used for
visibility must have normal tracking and sit inside the drift limit.

quality-0.2, for schema 0.2.0: all five. Tracking is read from the frames themselves; the horizon, lens and
reflection checks are read from `quality.evidence`. A check that did not run is missing evidence, and missing
evidence blocks. A check that ran and found nothing is not proof of absence, and nothing here says it is.

Every limit here is a candidate from docs/04 until the spike (docs/07) confirms it. Synthetic software checks only.
"""

import math

from . import north as north_resolver
from .scenerecord import ValidationError

VERSION = "quality-0.1"
VERSION_2 = "quality-0.2"
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
#: The lights this module can recompute from a 0.1.0 record, and from a 0.2.0 record.
EVALUATED = ("coverage", "north", "segmentation")
EVALUATED_2 = ("coverage", "north", "segmentation", "level", "lens")
#: Tracking (quality-0.2): the longest stretch without normal tracking after it first became normal. Candidates.
LIMITED_WARN_S = 0.5
LIMITED_BLOCK_S = 2.0
#: Horizon against gravity, both as angles in the image (quality-0.2). Candidates.
HORIZON_PASS_DEG = 2.0
HORIZON_WARN_DEG = 5.0
#: Lens smudge confidence from the detector, 0…1 (quality-0.2). Candidates until calibrated on the device.
SMUDGE_WARN = 0.3
SMUDGE_BLOCK = 0.6
_ORDER = ("pass", "warn", "blocked")


def _worst(*gates):
    return max(gates, key=_ORDER.index)


def tracking(frames):
    """The tracking light from the frames of the scan itself: `(gate, reason, longest_limited_s)`.

    Frames taken while confirming the direction (`role: calibration`) are not part of the scan. What happens before
    tracking first becomes normal is start-up and does not count. The recorder keeps every change of tracking state
    (ADR-0020), so a stretch runs from its first frame to the next normal one."""
    scan = [f for f in frames if f.get("role", "visibility") == "visibility"]
    first = next((i for i, f in enumerate(scan) if f["tracking_state"] == "normal"), None)
    if first is None:
        return "blocked", "tracking never became normal", None
    longest, start = 0.0, None
    for frame in scan[first:]:
        if frame["tracking_state"] == "limited:relocalizing":
            return "blocked", f"tracking relocalized at frame {frame['frame_id']}: the world frame may have moved", None
        if frame["tracking_state"] != "normal":
            start = frame["t"] if start is None else start
        elif start is not None:
            longest, start = max(longest, frame["t"] - start), None
    if start is not None:
        longest = max(longest, scan[-1]["t"] - start)
    gate = "pass" if longest <= LIMITED_WARN_S + 1e-9 else "warn" if longest <= LIMITED_BLOCK_S + 1e-9 else "blocked"
    return gate, f"longest stretch without normal tracking {longest:.2f} s", longest


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

    v2 = record["schema_version"] == "0.2.0"
    if v2:
        evidence = record["quality"]["evidence"]
        reflection = evidence["reflection"]["status"]
        if corridor > 0 and segmentation is not None and segmentation["model"] is not None:
            # "Reflections not identified" blocks (docs/04 §6). Looking and finding nothing lets the glass share
            # stand; it does not say there is no glass.
            if reflection == "not_run":
                gates["segmentation"], reasons["segmentation"] = "blocked", "reflections were not checked"
            elif reflection in ("undetermined", "suspected"):
                gates["segmentation"] = _worst(gates["segmentation"], "warn")
                reasons["segmentation"] += "; reflections " + ("could not be ruled out" if reflection == "undetermined" else "suspected")
        frames = record["capture_session"]["frames"] if record["capture_session"] is not None else []
        tracked, why, _ = tracking(frames)
        horizon = evidence["horizon"]
        if horizon["status"] == "measured":
            seen = "pass" if horizon["residual_deg"] <= HORIZON_PASS_DEG else "warn" if horizon["residual_deg"] <= HORIZON_WARN_DEG else "blocked"
            why += f"; horizon {horizon['residual_deg']:g} degrees off gravity"
        elif horizon["status"] == "not_found":   # most indoor frames have no horizon: nothing to compare, nothing held against the scan
            seen = "pass"
            why += "; no horizon in view"
        else:
            seen = "blocked"
            why += "; horizon not checked"
        gates["level"], reasons["level"] = _worst(tracked, seen), why
        lens = evidence["lens"]
        if lens["status"] == "measured":
            smudge = lens["smudge_confidence"]
            gates["lens"] = "pass" if smudge < SMUDGE_WARN else "warn" if smudge < SMUDGE_BLOCK else "blocked"
            reasons["lens"] = f"lens smudge confidence {smudge:g}"
        else:
            gates["lens"] = "blocked"
            reasons["lens"] = "lens not checked" if lens["status"] == "not_run" else "no frame steady enough to check the lens"

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
    return {"version": VERSION_2 if v2 else VERSION, "gates": gates, "reasons": reasons, "north": resolution, "problems": problems}


def check(record):
    """Raise `QualityError` unless the record's stated quality follows from its evidence.

    For every record: the evaluable lights (three in 0.1.0, all five in 0.2.0) must be stated as the evidence gives
    them, and a stored north resolution must be the one its candidates produce. For a record that claims more than R0: no physical
    contradiction either. Unknown stays unknown: missing evidence is `blocked`, never assumed.
    """
    result = evaluate(record)
    stated = record["quality"]["gates"]
    for gate in (EVALUATED_2 if record["schema_version"] == "0.2.0" else EVALUATED):
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
