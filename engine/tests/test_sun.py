"""Solar position checks (docs/06 §1, §9). Synthetic inputs; nothing here is field-validated."""

import calendar
import json
import math
from pathlib import Path
import unittest

from lightreplay import sun

FIXTURE = Path(__file__).parent / "fixtures" / "sun-positions.json"


def daily_max_elevation(y, mo, d, lat, lon, utc_offset_h):
    midnight = calendar.timegm((y, mo, d, 0, 0, 0)) - utc_offset_h * 3600
    return max(sun.position(midnight + m * 60, lat, lon).elevation_deg for m in range(1440))


class SunPositionTests(unittest.TestCase):
    def test_nrel_spa_published_example(self):
        # Reda & Andreas (2004), NREL/TP-560-34302 Table A5.1: 2003-10-17 12:30:30 UTC-7, 39.742476 N 105.1786 W,
        # 820 hPa, 11 C -> topocentric zenith 50.11162, azimuth 194.34024.
        t = calendar.timegm((2003, 10, 17, 19, 30, 30))
        p = sun.position(t, 39.742476, -105.1786, 820.0, 11.0)
        self.assertAlmostEqual(90.0 - p.elevation_deg, 50.11162, delta=0.01)
        self.assertAlmostEqual(p.azimuth_deg, 194.34024, delta=0.01)

    def test_solstice_noon_elevation_matches_the_flat_formula(self):
        # docs/06 §2: 90 - |phi - delta|. Melbourne 28.8 / 75.6, Sydney 32.7 / 79.5 (AEST, UTC+10).
        self.assertAlmostEqual(daily_max_elevation(2026, 6, 21, -37.8136, 144.9631, 10), 28.8, delta=0.15)
        self.assertAlmostEqual(daily_max_elevation(2026, 12, 21, -37.8136, 144.9631, 10), 75.6, delta=0.15)
        self.assertAlmostEqual(daily_max_elevation(2026, 6, 21, -33.8688, 151.2093, 10), 32.7, delta=0.15)
        self.assertAlmostEqual(daily_max_elevation(2026, 12, 21, -33.8688, 151.2093, 10), 79.5, delta=0.15)

    def test_independent_almanac_agrees_within_spec(self):
        # docs/06 §1 accepts 0.05 deg against a reference. Geometric positions, sun above the horizon.
        points = json.loads(FIXTURE.read_text(encoding="utf-8"))["points"]
        checked = 0
        for p in points:
            if p["true_elevation_deg"] <= 0:
                continue
            checked += 1
            self.assertLess(abs(p["true_elevation_deg"] - p["almanac_elevation_deg"]), 0.05, p)
            d_az = abs((p["azimuth_deg"] - p["almanac_azimuth_deg"] + 180.0) % 360.0 - 180.0)
            self.assertLess(d_az * math.cos(math.radians(p["true_elevation_deg"])), 0.05, p)
        self.assertGreater(checked, 300)

    def test_fixture_is_current(self):
        # The Swift parity test reads this file; it must be what the reference produces today.
        for p in json.loads(FIXTURE.read_text(encoding="utf-8"))["points"][::37]:
            q = sun.position(p["unix"], p["lat"], p["lon"])
            self.assertEqual(q.azimuth_deg, p["azimuth_deg"])
            self.assertEqual(q.elevation_deg, p["elevation_deg"])

    def test_refraction_lifts_the_horizon_and_vanishes_high_up(self):
        self.assertAlmostEqual(sun.refraction_deg(0.0), 0.48, delta=0.03)
        self.assertLess(sun.refraction_deg(45.0), 0.02)
        self.assertEqual(sun.refraction_deg(-5.0), 0.0)

    def test_azimuth_convention_true_north_clockwise(self):
        # Southern winter morning in Melbourne: the sun rises north of east (azimuth below 90) and is due north at noon.
        morning = sun.position(calendar.timegm((2026, 6, 21, 22, 0, 0)), -37.8136, 144.9631)   # 08:00 AEST
        self.assertTrue(40 < morning.azimuth_deg < 90, morning)
        noon = sun.position(calendar.timegm((2026, 6, 21, 2, 22, 0)), -37.8136, 144.9631)
        self.assertLess(min(noon.azimuth_deg, 360 - noon.azimuth_deg), 2.0, noon)


if __name__ == "__main__":
    unittest.main()
