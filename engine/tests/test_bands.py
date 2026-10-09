"""Sky grid, corridor and band checks (docs/06 §3–6, §9). Synthetic skies with analytic answers; expectations are
written from the documents, as in the Swift SunBandsTests. Nothing here is field-validated."""

import json
from pathlib import Path
import sys
import unittest

from lightreplay import bands, sun

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import make_bands_fixture  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "sun-bands.json"
MEL = (-37.8136, 144.9631, "Australia/Melbourne")
WINTER = bands.LocalDay(2026, 6, 21)


def grid(rule):
    return bands.VisibilityGrid.from_rule(rule)


OPEN = grid(lambda az, alt: bands.SKY if alt >= 0 else bands.BLOCKED)
EAST_BLOCKED = grid(lambda az, alt: bands.BLOCKED if alt < 0 else (bands.BLOCKED if az < 180 else bands.SKY))


def day_bands(g, delta=0, sigma=0, day=WINTER, **options):
    options.setdefault("boundary_jitter_deg", 0)
    return bands.SunBands(g, *MEL, delta, sigma, **options).bands(day)


def first_minute(day, condition):
    start, end = day.interval(MEL[2])
    for t in range(start, end, 60):
        if condition(sun.position(t, MEL[0], MEL[1])):
            return t
    return None


def segment(b, state):
    return next((s for s in b.segments if s.state == state), None)


class GridTests(unittest.TestCase):
    def test_cells_and_the_seam(self):
        self.assertEqual(bands.cell_for(0.5, -9.5), (0, 0))
        self.assertEqual(bands.cell_for(359.9, 89.9), (359, 99))
        self.assertEqual(bands.cell_for(-0.5, 0), (359, 10))
        self.assertEqual(bands.cell_for(720.2, 95), (0, 99), "above 90 clamps to the top row")
        self.assertIsNone(bands.cell_for(10, -10.5))
        g = bands.VisibilityGrid()
        g.set(-1, 5, bands.SKY)
        self.assertEqual(g.get(359, 5), bands.SKY)

    def test_regions_apply_in_order(self):
        g = bands.VisibilityGrid.from_regions(make_bands_fixture.GRIDS["unknown_quadrant_glass_zenith"])
        self.assertEqual(g.state(100, 30), bands.SKY)
        self.assertEqual(g.state(300, 30), bands.UNKNOWN)
        self.assertEqual(g.state(300, 70), bands.GLASS, "the later region wins")
        self.assertEqual(g.state(100, -5), bands.BLOCKED)

    def test_classifier_disk_rule(self):
        g = bands.VisibilityGrid(bands.SKY)
        self.assertEqual(bands.classify(100.5, 30.5, g), "direct")
        g.set(101, 40, bands.BLOCKED)   # neighbour of (100, 30°) = cell (100, 40)
        self.assertEqual(bands.classify(100.5, 30.5, g), "sensitive")
        g.set(100, 40, bands.GLASS)
        self.assertEqual(bands.classify(100.5, 30.5, g), "unknown", "glass at the centre")
        self.assertEqual(bands.classify(359.5, 30.5, bands.VisibilityGrid(bands.BLOCKED)), "blocked")
        self.assertEqual(bands.classify(10, 30, bands.VisibilityGrid()), "unknown")


class DayTests(unittest.TestCase):
    def test_daylight_saving_day_has_23_hours(self):
        change, before = bands.LocalDay(2026, 10, 4), bands.LocalDay(2026, 10, 3)
        self.assertEqual(change.interval(MEL[2])[1] - change.interval(MEL[2])[0], 23 * 3600)
        self.assertEqual(before.interval(MEL[2])[1] - before.interval(MEL[2])[0], 24 * 3600)
        rise = lambda d: bands.local_minutes(day_bands(OPEN, day=d).segments[0].start, MEL[2])
        self.assertAlmostEqual(rise(change) - rise(before), 60, delta=3, msg="sunrise clock time jumps by an hour")

    def test_leap_day_and_year_boundaries(self):
        days = bands.LocalDay(2028, 2, 28).through(bands.LocalDay(2028, 3, 1))
        self.assertEqual([str(d) for d in days], ["2028-02-28", "2028-02-29", "2028-03-01"])
        self.assertEqual(str(bands.LocalDay(2026, 12, 31).adding(1)), "2027-01-01")

    def test_winter_follows_the_hemisphere(self):
        self.assertEqual(bands.winter_solstice(2026, -37.8).month, 6)
        self.assertEqual(bands.winter_solstice(2026, 51.5).month, 12)
        winter = bands.corridor_days("winter", 2026, -37.8)
        self.assertEqual((str(winter[0]), str(winter[-1]), len(winter)), ("2026-05-10", "2026-08-02", 13))
        self.assertGreater(len(bands.corridor_days("allYear", 2026, -37.8)), 50)


class BandTests(unittest.TestCase):
    def test_open_sky_is_direct_from_sunrise_to_sunset(self):
        b = day_bands(OPEN)
        self.assertEqual((b.minutes("unknown"), b.minutes("blocked")), (0, 0))
        self.assertTrue(560 <= b.daylight_minutes <= 575, b.daylight_minutes)
        self.assertGreater(b.direct_minutes, b.daylight_minutes - 40, "only the disk-on-horizon minutes are sensitive")
        self.assertTrue(bands.clock(b.segments[0].start, MEL[2]).startswith("07:3"))

    def test_ten_degree_horizon_switches_where_the_sun_crosses_it(self):
        b = day_bands(grid(lambda az, alt: bands.SKY if alt >= 10 else bands.BLOCKED))
        # 3×3 disk rule: blocked below 9°, sensitive between 9° and 11°, direct from 11°.
        t9 = first_minute(WINTER, lambda p: p.elevation_deg >= 9)
        t11 = first_minute(WINTER, lambda p: p.elevation_deg >= 11)
        self.assertAlmostEqual(segment(b, "blocked").end, t9, delta=60)
        self.assertAlmostEqual(segment(b, "direct").start, t11, delta=60)

    def test_azimuth_half_sky_turns_direct_when_the_sun_passes_north(self):
        b = day_bands(EAST_BLOCKED)
        crosses = first_minute(WINTER, lambda p: p.elevation_deg > 0 and 180 < p.azimuth_deg < 359)
        self.assertAlmostEqual(segment(b, "direct").start, crosses, delta=60)
        self.assertLess(segment(b, "blocked").start, segment(b, "direct").start, "morning is blocked")
        turned = day_bands(EAST_BLOCKED, delta=30)
        crosses29 = first_minute(WINTER, lambda p: p.elevation_deg > 0 and p.azimuth_deg < 29)
        self.assertAlmostEqual(segment(turned, "direct").start, crosses29, delta=60)

    def test_direction_uncertainty_widens_the_sensitive_band(self):
        sure, unsure = day_bands(EAST_BLOCKED), day_bands(EAST_BLOCKED, sigma=8)
        self.assertGreater(unsure.minutes("sensitive"), sure.minutes("sensitive") + 30)
        self.assertLess(unsure.direct_minutes, sure.direct_minutes)
        self.assertEqual(unsure.daylight_minutes, sure.daylight_minutes)

    def test_unknown_sky_is_never_reported_as_direct(self):
        g = bands.VisibilityGrid.from_regions(make_bands_fixture.GRIDS["unknown_quadrant_glass_zenith"])
        sb = bands.SunBands(g, *MEL, 0, 3)
        for day in (WINTER, bands.LocalDay(2026, 12, 21)):
            start, end = day.interval(MEL[2])
            for t in range(start, end, 300):
                p = sun.position(t, MEL[0], MEL[1])
                if p.elevation_deg <= 0 or g.state(p.azimuth_deg, p.elevation_deg) == bands.SKY:
                    continue
                self.assertNotEqual(sb.state(t), "direct", (day, bands.clock(t, MEL[2])))
        b = sb.bands(WINTER)
        self.assertGreater(b.minutes("unknown"), 60)
        self.assertGreater(b.upper_bound_minutes, b.direct_minutes, "unknown counts toward the upper bound only")

    def test_minute_refinement_equals_sampling_every_minute(self):
        # The five-minute sampler fills in the minutes between two differing samples, so it must land on the same
        # segments as sampling every minute from the start.
        five, one = day_bands(EAST_BLOCKED, delta=5, sigma=6), day_bands(EAST_BLOCKED, delta=5, sigma=6, step_minutes=1)
        self.assertEqual(five.segments, one.segments)

    def test_bands_are_reproducible_and_seeded(self):
        a = bands.SunBands(EAST_BLOCKED, *MEL, 5, 6).bands(WINTER)
        b = bands.SunBands(EAST_BLOCKED, *MEL, 5, 6).bands(WINTER)
        self.assertEqual(a, b)
        other = bands.SunBands(EAST_BLOCKED, *MEL, 5, 6, seed=1).bands(WINTER)
        self.assertEqual(other.daylight_minutes, a.daylight_minutes, "a different seed moves boundaries, not the sun")

    def test_polar_days(self):
        night = bands.SunBands(OPEN, 78.2232, 15.6267, "Arctic/Longyearbyen", 0, 0, boundary_jitter_deg=0)
        self.assertEqual(night.bands(bands.LocalDay(2026, 12, 21)).segments, ())
        midsummer = night.bands(bands.LocalDay(2026, 6, 21))
        self.assertEqual(midsummer.daylight_minutes, 24 * 60, "the midnight sun never sets")


class CorridorTests(unittest.TestCase):
    def test_corridor_coverage(self):
        corridor = bands.SunCorridor([WINTER], *MEL, 0)
        total, unknown, glass = corridor.coverage(OPEN)
        self.assertGreater(total, 100)
        self.assertEqual(bands.coverage_pct(total, unknown), 100)
        self.assertEqual(bands.coverage_pct(*corridor.coverage(bands.VisibilityGrid())[:2]), 0)
        half = corridor.coverage(grid(lambda az, alt: bands.UNKNOWN if az < 180 else bands.SKY))
        self.assertTrue(20 < bands.coverage_pct(half[0], half[1]) < 80, half)
        all_glass = corridor.coverage(bands.VisibilityGrid(bands.GLASS))
        self.assertEqual(bands.coverage_pct(all_glass[0], all_glass[1]), 100, "glass counts as covered; the segmentation gate limits it")
        self.assertEqual(all_glass[2], all_glass[0])
        breakfast = bands.SunCorridor([WINTER], *MEL, 0, (420, 600))
        inside = [i for i, c in enumerate(breakfast.cells) if c]
        self.assertTrue(inside)
        self.assertTrue(all(corridor.cells[i] for i in inside), "a time window is a subset of the whole day")


class RandomDrawTests(unittest.TestCase):
    def test_generator_is_deterministic_and_in_range(self):
        a, b = bands.SplitMix64(42), bands.SplitMix64(42)
        self.assertEqual([a.next() for _ in range(5)], [b.next() for _ in range(5)])
        c = bands.SplitMix64(42)
        for _ in range(1000):
            self.assertTrue(0 <= c.next_unit() < 1)
        rng = bands.SplitMix64(3)
        self.assertLess(abs(sum(rng.next_gaussian() for _ in range(4000)) / 4000), 0.1)


class FixtureTests(unittest.TestCase):
    def test_fixture_is_current(self):
        stored = json.loads(FIXTURE.read_text(encoding="utf-8"))
        fresh = json.loads(json.dumps(make_bands_fixture.build()))
        self.assertEqual(stored["version"], bands.VERSION)
        for key in ("rng", "classify", "corridors"):
            self.assertEqual(stored[key], fresh[key], key)
        self.assertEqual([c["name"] for c in stored["bands"]], [c["name"] for c in fresh["bands"]])
        for old, new in zip(stored["bands"], fresh["bands"]):
            self.assertEqual(old["days"], new["days"], old["name"])

    def test_fixture_covers_every_state_and_both_hemispheres(self):
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        states = {seg["state"] for case in data["bands"] for day in case["days"] for seg in day["segments"]}
        self.assertEqual(states, {"direct", "sensitive", "blocked", "unknown"})
        self.assertEqual({case["place"] for case in data["bands"]}, {"melbourne", "london", "longyearbyen"})
        self.assertTrue(any(day["segments"] == [] for case in data["bands"] for day in case["days"]), "a day without sun")


if __name__ == "__main__":
    unittest.main()
