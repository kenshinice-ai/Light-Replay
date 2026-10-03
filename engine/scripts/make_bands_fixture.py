"""Writes tests/fixtures/sun-bands.json: synthetic skies, direction estimates and days, with the segments, corridor
counts, classifier verdicts and random draws the reference `bands.py` produces. The Swift SunEngine must reproduce
every one exactly: the same minute, the same state, the same bits.

Grids are written in a small region language (applied in order, last wins, half-open bounds on cell centres) so both
implementations build them the same way. Coordinates are city centres used as arbitrary inputs, not properties.
Run from engine/: python3 scripts/make_bands_fixture.py
"""

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lightreplay import bands  # noqa: E402

PLACES = {
    "melbourne": {"lat": -37.8136, "lon": 144.9631, "tz": "Australia/Melbourne"},
    "london": {"lat": 51.4779, "lon": 0.0, "tz": "Europe/London"},
    "longyearbyen": {"lat": 78.2232, "lon": 15.6267, "tz": "Arctic/Longyearbyen"},
}

GRIDS = {
    "open": [{"state": "blocked", "alt_max": 0}, {"state": "sky", "alt_min": 0}],
    "horizon_10": [{"state": "blocked", "alt_max": 10}, {"state": "sky", "alt_min": 10}],
    "east_blocked": [{"state": "blocked", "alt_max": 0}, {"state": "sky", "alt_min": 0, "az_min": 180},
                     {"state": "blocked", "alt_min": 0, "az_max": 180}],
    "unknown_quadrant_glass_zenith": [{"state": "blocked", "alt_max": 0}, {"state": "sky", "alt_min": 0},
                                      {"state": "unknown", "alt_min": 0, "az_min": 270, "az_max": 330},
                                      {"state": "glassUncertain", "alt_min": 60}],
    "all_unknown": [],
    "all_sky": [{"state": "sky"}],
    "all_blocked": [{"state": "blocked"}],
    "all_glass": [{"state": "glassUncertain"}],
    "west_half_unknown": [{"state": "unknown", "az_max": 180}, {"state": "sky", "az_min": 180}],
}

EXACT = {"boundary_jitter_deg": 0}

BAND_CASES = [
    ("open_sky_exact", "open", "melbourne", 0, 0, EXACT, ["2026-06-21", "2026-12-21"]),
    ("horizon_10_exact", "horizon_10", "melbourne", 0, 0, EXACT, ["2026-06-21"]),
    ("east_blocked_exact", "east_blocked", "melbourne", 0, 0, EXACT, ["2026-06-21"]),
    ("east_blocked_turned_30", "east_blocked", "melbourne", 30, 0, EXACT, ["2026-06-21"]),
    ("east_blocked_sigma_8", "east_blocked", "melbourne", 0, 8, EXACT, ["2026-06-21"]),
    ("east_blocked_default_options", "east_blocked", "melbourne", 5, 6, {}, ["2026-06-21"]),
    ("east_blocked_sixteen_draws", "east_blocked", "melbourne", 5, 6, {"samples": 16, "seed": 7}, ["2026-06-21"]),
    ("east_blocked_step_1", "east_blocked", "melbourne", 0, 0, dict(EXACT, step_minutes=1), ["2026-06-21"]),
    ("unknown_and_glass_default", "unknown_quadrant_glass_zenith", "melbourne", 0, 3, {}, ["2026-06-21", "2026-12-21"]),
    ("daylight_saving_change", "open", "melbourne", 0, 0, EXACT, ["2026-10-03", "2026-10-04"]),
    ("london_winter_exact", "open", "london", 0, 0, EXACT, ["2026-12-21"]),
    ("polar_night_and_midnight_sun", "open", "longyearbyen", 0, 0, EXACT, ["2026-12-21", "2026-06-21"]),
]

CORRIDOR_CASES = [
    ("winter_open", "winter", None, "melbourne", 0, None, "open"),
    ("winter_unknown", "winter", None, "melbourne", 0, None, "all_unknown"),
    ("winter_west_half_unknown", "winter", None, "melbourne", 0, None, "west_half_unknown"),
    ("winter_glass", "winter", None, "melbourne", 0, None, "all_glass"),
    ("winter_turned_90", "winter", None, "melbourne", 90, None, "west_half_unknown"),
    ("solstice_day_only", None, ["2026-06-21"], "melbourne", 0, None, "open"),
    ("solstice_breakfast", None, ["2026-06-21"], "melbourne", 0, [420, 600], "open"),
    ("all_year_open", "allYear", None, "melbourne", 0, None, "open"),
    ("london_winter_open", "winter", None, "london", 0, None, "open"),
]

CLASSIFY_PROBES = [
    ("open_sky_mid", "all_sky", [], 100.5, 30.5),
    ("neighbour_blocked", "all_sky", [(101, 40, "blocked")], 100.5, 30.5),
    ("glass_at_centre", "all_sky", [(100, 40, "glassUncertain")], 100.5, 30.5),
    ("all_blocked_seam", "all_blocked", [], 359.5, 30.5),
    ("nothing_seen", "all_unknown", [], 10, 30),
    ("below_the_grid", "all_sky", [], 10, -10.5),
    ("top_row", "all_sky", [], 10, 89.9),
    ("one_unknown_neighbour", "all_sky", [(11, 41, "unknown")], 10.5, 30.5),
    ("majority_unknown", "all_sky", [(9, 39, "unknown"), (10, 39, "unknown"), (11, 39, "unknown"), (9, 40, "unknown"), (11, 40, "unknown")], 10.5, 30.5),
]


def grid_for(name, sets=()):
    grid = bands.VisibilityGrid.from_regions(GRIDS[name])
    for az, alt, state in sets:
        grid.set(az, alt, bands.STATE_BY_NAME[state])
    return grid


def build():
    out = {"note": "Synthetic skies and the reference results (engine/lightreplay/bands.py); regenerate with "
                   "engine/scripts/make_bands_fixture.py. Both implementations must match exactly.",
           "version": bands.VERSION, "places": PLACES, "grids": GRIDS}

    rng = bands.SplitMix64(0x5EED2026)
    raw = [f"{rng.next():016x}" for _ in range(8)]
    rng = bands.SplitMix64(0x5EED2026)
    units = [rng.next_unit() for _ in range(4)]
    rng = bands.SplitMix64(0x5EED2026)
    draws = [[rng.next_gaussian(), rng.next_uniform(-1, 1), rng.next_uniform(-1, 1)] for _ in range(4)]
    out["rng"] = {"seed": "5eed2026", "raw": raw, "units": units, "draws": draws}

    out["classify"] = [{"name": n, "grid": g, "set": [{"az": a, "alt": e, "state": s} for a, e, s in sets],
                        "az": az, "alt": alt, "state": bands.classify(az, alt, grid_for(g, sets))}
                       for n, g, sets, az, alt in CLASSIFY_PROBES]

    cases = []
    for name, grid, place, delta, sigma, options, days in BAND_CASES:
        p = PLACES[place]
        sb = bands.SunBands(grid_for(grid), p["lat"], p["lon"], p["tz"], delta, sigma, **options)
        per_day = []
        for text in days:
            b = sb.bands(bands.LocalDay.parse(text))
            per_day.append({"day": text, "segments": [{"from": s.start, "to": s.end, "state": s.state} for s in b.segments],
                            "minutes": {st: b.minutes(st) for st in ("direct", "sensitive", "blocked", "unknown")},
                            "daylight": b.daylight_minutes})
        cases.append({"name": name, "grid": grid, "place": place, "delta_deg": delta, "sigma_deg": sigma,
                      "options": options, "days": per_day})
    out["bands"] = cases

    corridors = []
    for name, question, days, place, delta, window, grid in CORRIDOR_CASES:
        p = PLACES[place]
        day_list = bands.corridor_days(question, 2026, p["lat"]) if question else [bands.LocalDay.parse(d) for d in days]
        corridor = bands.SunCorridor(day_list, p["lat"], p["lon"], p["tz"], delta, tuple(window) if window else None)
        total, unknown, glass = corridor.coverage(grid_for(grid))
        corridors.append({"name": name, "question": question, "days": [str(d) for d in day_list], "place": place,
                          "delta_deg": delta, "local_minutes": window, "grid": grid,
                          "corridor_cells": total, "unknown_cells": unknown, "glass_cells": glass,
                          "coverage_pct": bands.coverage_pct(total, unknown)})
    out["corridors"] = corridors
    return out


def main():
    out = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "sun-bands.json"
    data = build()
    head = ",\n".join(f"{json.dumps(k)}:{json.dumps(data[k])}" for k in ("note", "version", "places", "grids", "rng"))
    def lines(items):
        return ",\n".join("  " + json.dumps(item, separators=(",", ":")) for item in items)
    out.write_text(f'{{{head},\n"classify":[\n{lines(data["classify"])}\n],\n"bands":[\n{lines(data["bands"])}\n],\n'
                   f'"corridors":[\n{lines(data["corridors"])}\n]}}\n', encoding="utf-8")
    print(f"wrote {out} ({len(data['bands'])} band cases, {len(data['corridors'])} corridors, {len(data['classify'])} probes)")


if __name__ == "__main__":
    main()
