"""NorthResolver fusion (docs/05 §3, ADR-0009, ADR-0018): reference implementation, northresolver-0.2.

A candidate is one source's reading of Δ, the true azimuth of the AR world's −Z axis, with a 1σ in degrees and
the independent group it belongs to. This module merges readings inside a group, checks the groups against each
other, fuses the largest set that agrees, and says which light the result earns. Agreeing is not corroborating:
the green light needs one pair whose agreement could have caught an hour-sized error (ADR-0018). It reads no sensors and knows
nothing about JSON beyond the candidate keys of docs/03 §4.

Synthetic software checks only; the σ model and every limit are candidates until the sundial spike (docs/07).
"""

from itertools import combinations
import math

VERSION = "northresolver-0.2"
METHOD = "robust_circular_v0"
#: Most trusted first (docs/05 §3 step 4).
GROUP_TRUST = ("solar", "vps", "map", "magnetic")
#: Two groups conflict when their circular difference exceeds K · sqrt(σ_i² + σ_j²) (docs/05 §3 step 3).
CONFLICT_K = 3.0
#: A single group above this σ needs one confirmation before anything beyond R0 (docs/05 §3 step 5, candidate).
SINGLE_GROUP_SIGMA_LIMIT_DEG = 6.0
#: Two agreeing groups corroborate each other only when their conflict limit is at most this: their agreement would
#: have caught an error of about one sun-hour of azimuth (ADR-0018, candidate until the sundial spike).
CORROBORATION_DETECTABLE_DEG = 15.0


def mod360(angle):
    """`angle` folded into [0, 360)."""
    folded = angle - 360.0 * math.floor(angle / 360.0)
    return folded - 360.0 if folded >= 360.0 else folded   # −1e-17 folds to 360.0 in floating point


def circular_difference(a, b):
    """Unsigned difference between two azimuths, 0…180."""
    d = mod360(a - b)
    return min(d, 360.0 - d)


def signed_offset(angle, reference):
    """`angle − reference` folded into [−180, 180)."""
    return mod360(angle - reference + 180.0) - 180.0


def _median(sorted_values):
    n = len(sorted_values)
    mid = n // 2
    return sorted_values[mid] if n % 2 else (sorted_values[mid - 1] + sorted_values[mid]) / 2.0


def merge_group(readings):
    """Readings of one independent group as one value (docs/05 §3 step 1).

    `readings` is a non-empty list of `(yaw_deg, sigma_deg)`. The value is the circular median. σ is the larger of
    the readings' median σ and their RMS spread about that median: readings of one sensor are not independent
    evidence, so more of them never shrinks σ.
    Returns `(yaw_deg, sigma_deg, spread_deg)`.
    """
    if len(readings) == 1:   # one reading is its own median, exactly: no trigonometry in between
        return mod360(readings[0][0]), readings[0][1], 0.0
    s = sum(math.sin(math.radians(yaw)) for yaw, _ in readings)
    c = sum(math.cos(math.radians(yaw)) for yaw, _ in readings)
    # Offsets are taken about the mean direction so the median is not split by the 0°/360° seam. Readings that
    # cancel out have no mean direction; the first one is the reference then, and the spread says the rest.
    reference = math.degrees(math.atan2(s, c)) if math.hypot(s, c) > 1e-9 else readings[0][0]
    yaw = mod360(reference + _median(sorted(signed_offset(value, reference) for value, _ in readings)))
    spread = math.sqrt(sum(signed_offset(value, yaw) ** 2 for value, _ in readings) / len(readings))
    return yaw, max(_median(sorted(sigma for _, sigma in readings)), spread), spread


def _usable(candidate):
    """Valid, with an azimuth and a positive σ. A reading that states no uncertainty cannot be weighed."""
    yaw, sigma = candidate.get("yaw_deg"), candidate.get("sigma_deg")
    return (candidate.get("valid") is True and type(yaw) in (int, float) and type(sigma) in (int, float)
            and math.isfinite(yaw) and math.isfinite(sigma) and sigma > 0)


def resolve(candidates):
    """Fuse direction candidates (docs/03 §4 objects) into Δ with its σ and the north light.

    Returns a dict:
      `yaw_deg`, `sigma_deg`      fused Δ and 1σ, or None when no group is usable
      `groups`                    per usable group: `yaw_deg`, `sigma_deg`, `spread_deg`, `readings`
      `groups_used`, `groups_rejected`   most trusted first
      `conflict`                  True when a group other than `magnetic` was rejected (ADR-0009 rule 4)
      `corroborated`              True when two used groups agree closely enough to have caught a 15° error
      `disagreements`             every conflicting pair: `a`, `b`, `difference_deg`, `limit_deg`
      `gate`                      `pass` / `warn` / `blocked` (docs/04 §6)
      `needs_confirmation`        True when one minimal confirmation is required before anything beyond R0
      `reason`                    one line saying why the gate is what it is
    """
    readings = {}
    for candidate in candidates:
        if _usable(candidate):
            readings.setdefault(candidate["group"], []).append((float(candidate["yaw_deg"]), float(candidate["sigma_deg"])))
    order = [group for group in GROUP_TRUST if group in readings]
    merged = {group: merge_group(readings[group]) for group in order}
    groups = {group: {"yaw_deg": merged[group][0], "sigma_deg": merged[group][1], "spread_deg": merged[group][2],
                      "readings": len(readings[group])} for group in order}
    result = {"version": VERSION, "method": METHOD, "yaw_deg": None, "sigma_deg": None, "groups": groups,
              "groups_used": [], "groups_rejected": [], "conflict": False, "corroborated": False, "disagreements": [],
              "gate": "blocked", "needs_confirmation": False, "reason": "no valid direction source"}
    if not order:
        return result

    def limit(a, b):
        return CONFLICT_K * math.hypot(merged[a][1], merged[b][1])

    def agree(a, b):
        return circular_difference(merged[a][0], merged[b][0]) <= limit(a, b)

    result["disagreements"] = [
        {"a": a, "b": b, "difference_deg": circular_difference(merged[a][0], merged[b][0]), "limit_deg": limit(a, b)}
        for a, b in combinations(order, 2) if not agree(a, b)]
    # The largest set whose members all agree with each other. `order` is most trusted first and combinations come
    # out in that order, so among sets of one size the first is the one with the most trusted members (step 4).
    used = next(list(combo) for size in range(len(order), 0, -1) for combo in combinations(order, size)
                if all(agree(a, b) for a, b in combinations(combo, 2)))
    weights = [1.0 / merged[group][1] ** 2 for group in used]
    s = sum(w * math.sin(math.radians(merged[group][0])) for w, group in zip(weights, used))
    c = sum(w * math.cos(math.radians(merged[group][0])) for w, group in zip(weights, used))
    rejected = [group for group in order if group not in used]
    sigma = math.sqrt(1.0 / sum(weights))
    # The most trusted pair whose agreement means something: a pair this tight would have disagreed over a 15° error.
    corroborating = next(((a, b) for a, b in combinations(used, 2) if limit(a, b) <= CORROBORATION_DETECTABLE_DEG), None)
    result.update(yaw_deg=mod360(math.degrees(math.atan2(s, c))), sigma_deg=sigma, groups_used=used,
                  groups_rejected=rejected, conflict=any(group != "magnetic" for group in rejected),
                  corroborated=corroborating is not None)
    if result["conflict"]:
        result.update(gate="blocked", needs_confirmation=True,
                      reason="sources disagree: " + ", ".join(g for g in rejected if g != "magnetic") + " rejected")
    elif corroborating:
        result.update(gate="pass", reason=f"{len(used)} independent groups agree; "
                                          f"{corroborating[0]} and {corroborating[1]} corroborate each other")
    elif len(used) >= 2 and sigma <= SINGLE_GROUP_SIGMA_LIMIT_DEG:
        result.update(gate="warn", reason=f"{len(used)} groups agree, but none closely enough to corroborate")
    elif len(used) >= 2:
        result.update(gate="blocked", needs_confirmation=True,
                      reason=f"{len(used)} groups agree, none closely enough to corroborate, and the fused sigma is above "
                             f"{SINGLE_GROUP_SIGMA_LIMIT_DEG:g} degrees")
    elif sigma <= SINGLE_GROUP_SIGMA_LIMIT_DEG:
        result.update(gate="warn", reason="one group only")
    else:
        result.update(gate="blocked", needs_confirmation=True,
                      reason=f"one group only, and its sigma is above {SINGLE_GROUP_SIGMA_LIMIT_DEG:g} degrees")
    return result
