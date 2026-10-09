"""Sky grid, direct-sun rule, sun corridor and time bands (docs/06 §3–6): reference for the Swift SunEngine.

Mirrors `VisibilityGrid`, `DirectSun`, `LocalDay`/`SunSampler`, `SunCorridor`, `SplitMix64` and `SunBands`
operation for operation (`sunbands-0.1`). `engine/tests/fixtures/sun-bands.json` holds cases both must reproduce
exactly: the same segments to the minute, the same random draws bit for bit. Pure standard library.

Synthetic skies only. Nothing here is field-validated.
"""

from dataclasses import dataclass
from datetime import date, datetime, timedelta
import math
from zoneinfo import ZoneInfo

from . import sun

VERSION = "sunbands-0.1"

AZ_CELLS = 360
ALT_CELLS = 100
MIN_ALT_DEG = -10.0

#: Cell states (docs/03 §5).
UNKNOWN, SKY, BLOCKED, GLASS = 0, 1, 2, 3
STATE_NAMES = {UNKNOWN: "unknown", SKY: "sky", BLOCKED: "blocked", GLASS: "glassUncertain"}
STATE_BY_NAME = {name: value for value, name in STATE_NAMES.items()}

DIRECT, SENSITIVE, BLOCKED_SUN, UNKNOWN_SUN = "direct", "sensitive", "blocked", "unknown"


# ---------------------------------------------------------------- grid

def wrap_cell(az_cell):
    return az_cell % AZ_CELLS


def cell_for(az_deg, alt_deg):
    """The (az, alt) cell holding a direction, or None below −10° / at or above 90°."""
    alt = math.floor(alt_deg - MIN_ALT_DEG)
    if alt < 0:
        return None
    az = wrap_cell(math.floor(sun._wrap360(az_deg)))
    return az, min(alt, ALT_CELLS - 1)


class VisibilityGrid:
    """360 × 100 cells in the AR world frame, row-major by altitude then azimuth, like the Swift `states`."""

    def __init__(self, fill=UNKNOWN):
        self.states = [fill] * (AZ_CELLS * ALT_CELLS)

    @classmethod
    def from_rule(cls, rule):
        """`rule(az_deg, alt_deg)` on cell centres; for synthetic scenes."""
        grid = cls()
        for alt in range(ALT_CELLS):
            for az in range(AZ_CELLS):
                grid.states[alt * AZ_CELLS + az] = rule(az + 0.5, MIN_ALT_DEG + alt + 0.5)
        return grid

    @classmethod
    def from_regions(cls, regions):
        """The fixture's grid language: regions applied in order, last one wins. Each region is a dict with `state`
        and optional `alt_min`, `alt_max`, `az_min`, `az_max` (half-open ranges on cell centres)."""
        def rule(az, alt):
            state = UNKNOWN
            for r in regions:
                if (az >= r.get("az_min", -1e9) and az < r.get("az_max", 1e9)
                        and alt >= r.get("alt_min", -1e9) and alt < r.get("alt_max", 1e9)):
                    state = STATE_BY_NAME[r["state"]]
            return state
        return cls.from_rule(rule)

    def get(self, az_cell, alt_cell):
        return self.states[alt_cell * AZ_CELLS + wrap_cell(az_cell)]

    def set(self, az_cell, alt_cell, state):
        self.states[alt_cell * AZ_CELLS + wrap_cell(az_cell)] = state

    def state(self, az_deg, alt_deg):
        cell = cell_for(az_deg, alt_deg)
        return UNKNOWN if cell is None else self.get(*cell)


# ---------------------------------------------------------------- direct sun

def classify(az_ar_deg, alt_deg, grid):
    """One direction against the grid (docs/06 §4): the 3×3 cells around the sun disk. Unanimous sky is direct,
    unanimous obstruction is blocked, mixed is sensitive; unknown or glass at the centre, or as the majority, is
    unknown."""
    centre = cell_for(az_ar_deg, alt_deg)
    if centre is None:
        return UNKNOWN_SUN
    c_az, c_alt = centre
    centre_state = grid.get(c_az, c_alt)
    if centre_state not in (SKY, BLOCKED):
        return UNKNOWN_SUN
    sky = blocked = other = 0
    for d_alt in (-1, 0, 1):
        a = c_alt + d_alt
        if a < 0 or a >= ALT_CELLS:
            continue
        for d_az in (-1, 0, 1):
            s = grid.get(c_az + d_az, a)
            if s == SKY:
                sky += 1
            elif s == BLOCKED:
                blocked += 1
            else:
                other += 1
    if other > sky + blocked:
        return UNKNOWN_SUN
    if other == 0 and blocked == 0:
        return DIRECT
    if other == 0 and sky == 0:
        return BLOCKED_SUN
    return SENSITIVE


# ---------------------------------------------------------------- days and samples

@dataclass(frozen=True, order=True)
class LocalDay:
    """A calendar day in the scene's own zone (docs/06 §1)."""
    year: int
    month: int
    day: int

    def __str__(self):
        return f"{self.year:04d}-{self.month:02d}-{self.day:02d}"

    @classmethod
    def parse(cls, text):
        y, m, d = (int(x) for x in text.split("-"))
        return cls(y, m, d)

    def interval(self, tz):
        """Local midnight to the next local midnight as unix seconds: 23 or 25 hours on daylight-saving changes."""
        zone = ZoneInfo(tz)
        start = datetime(self.year, self.month, self.day, tzinfo=zone)
        nxt = date(self.year, self.month, self.day) + timedelta(days=1)
        end = datetime(nxt.year, nxt.month, nxt.day, tzinfo=zone)
        return int(start.timestamp()), int(end.timestamp())

    def adding(self, days):
        d = date(self.year, self.month, self.day) + timedelta(days=days)
        return LocalDay(d.year, d.month, d.day)

    def through(self, last):
        days, d = [], self
        while d <= last:
            days.append(d)
            d = d.adding(1)
        return days


def samples(day, lat, lon, tz, step_minutes=5):
    """`(unix, SunPosition)` every `step_minutes` from local midnight, only while the sun is up (docs/06 §3)."""
    start, end = day.interval(tz)
    out = []
    for t in range(start, end, step_minutes * 60):
        p = sun.position(t, lat, lon)
        if p.elevation_deg > 0:
            out.append((t, p))
    return out


def clock(unix, tz):
    """'HH:MM' in the scene's zone."""
    return datetime.fromtimestamp(unix, ZoneInfo(tz)).strftime("%H:%M")


def local_minutes(unix, tz):
    local = datetime.fromtimestamp(unix, ZoneInfo(tz))
    return local.hour * 60 + local.minute


# ---------------------------------------------------------------- questions

def winter_solstice(year, lat):
    return LocalDay(year, 6, 21) if lat < 0 else LocalDay(year, 12, 21)


def summer_solstice(year, lat):
    return LocalDay(year, 12, 21) if lat < 0 else LocalDay(year, 6, 21)


def corridor_days(question, year, lat):
    """The days whose sun paths make a question's corridor (`LightQuestion.corridorDays`)."""
    if question == "winter":
        solstice = winter_solstice(year, lat)
        return [solstice.adding(k) for k in range(-42, 43, 7)]
    if question == "allYear":
        first = LocalDay(year, 1, 1)
        days = [first.adding(k) for k in range(0, 365, 7)]
        return days + [winter_solstice(year, lat), summer_solstice(year, lat)]
    raise ValueError(question)


# ---------------------------------------------------------------- corridor

CORRIDOR_MARGIN = 3


class SunCorridor:
    """The cells the sun passes through for some days, widened by 3° (docs/06 §5). `delta_deg` is NorthResolver's Δ:
    `az_ar = az_true − Δ`. `local_minutes_range` is `(from, to)` in minutes of the local day, half-open."""

    def __init__(self, days, lat, lon, tz, delta_deg, local_minutes_range=None, step_minutes=5):
        cells = [False] * (AZ_CELLS * ALT_CELLS)
        for day in days:
            for t, p in samples(day, lat, lon, tz, step_minutes):
                if local_minutes_range is not None:
                    m = local_minutes(t, tz)
                    if not (local_minutes_range[0] <= m < local_minutes_range[1]):
                        continue
                centre = cell_for(p.azimuth_deg - delta_deg, p.elevation_deg)
                if centre is None:
                    continue
                c_az, c_alt = centre
                for alt in range(max(0, c_alt - CORRIDOR_MARGIN), min(ALT_CELLS - 1, c_alt + CORRIDOR_MARGIN) + 1):
                    for az in range(c_az - CORRIDOR_MARGIN, c_az + CORRIDOR_MARGIN + 1):
                        cells[alt * AZ_CELLS + wrap_cell(az)] = True
        self.cells = cells

    def coverage(self, grid):
        """`(corridor_cells, unknown_cells, glass_cells)`; covered is corridor − unknown (docs/03 §5)."""
        total = unknown = glass = 0
        for index, inside in enumerate(self.cells):
            if not inside:
                continue
            total += 1
            s = grid.states[index]
            if s == UNKNOWN:
                unknown += 1
            elif s == GLASS:
                glass += 1
        return total, unknown, glass


def coverage_pct(corridor_cells, unknown_cells):
    return 0.0 if corridor_cells == 0 else 100.0 * (corridor_cells - unknown_cells) / corridor_cells


# ---------------------------------------------------------------- random draws

MASK64 = (1 << 64) - 1
LEAST_NONZERO = 5e-324   # Double.leastNonzeroMagnitude


class SplitMix64:
    """The Swift generator, bit for bit, so the draws (and therefore the bands) match across the two implementations."""

    def __init__(self, seed):
        self.state = seed & MASK64

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)

    def next_unit(self):
        return (self.next() >> 11) / float(1 << 53)

    def next_uniform(self, low, high):
        return low + (high - low) * self.next_unit()

    def next_gaussian(self):
        u1 = max(self.next_unit(), LEAST_NONZERO)
        u2 = self.next_unit()
        return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)


# ---------------------------------------------------------------- bands

@dataclass(frozen=True)
class Segment:
    start: int
    end: int
    state: str

    @property
    def minutes(self):
        return int(round((self.end - self.start) / 60))


@dataclass(frozen=True)
class DayBands:
    day: LocalDay
    segments: tuple

    def minutes(self, state):
        return sum(s.minutes for s in self.segments if s.state == state)

    @property
    def daylight_minutes(self):
        return sum(s.minutes for s in self.segments)

    @property
    def direct_minutes(self):
        return self.minutes(DIRECT)

    @property
    def upper_bound_minutes(self):
        return self.daylight_minutes - self.minutes(BLOCKED_SUN)


class SunBands:
    """Time bands for one target point (docs/06 §6): every instant is judged under K draws of the direction
    uncertainty. p ≥ 0.95 direct is direct, p ≤ 0.05 is blocked, anything between is sensitive, and one draw on an
    unknown or glass cell makes the instant unknown."""

    def __init__(self, grid, lat, lon, tz, delta_deg, sigma_deg, samples=64, boundary_jitter_deg=1.0,
                 step_minutes=5, seed=0x5EED2026):
        self.grid, self.lat, self.lon, self.tz = grid, lat, lon, tz
        self.delta_deg, self.sigma_deg, self.step_minutes = delta_deg, sigma_deg, step_minutes
        if sigma_deg == 0 and boundary_jitter_deg == 0:
            self.draws = [(0.0, 0.0, 0.0)]
        else:
            rng = SplitMix64(seed)
            j = boundary_jitter_deg
            self.draws = [(rng.next_gaussian() * sigma_deg, rng.next_uniform(-j, j), rng.next_uniform(-j, j))
                          for _ in range(max(1, samples))]

    def state(self, unix):
        """None while the sun is below the horizon."""
        p = sun.position(unix, self.lat, self.lon)
        if p.elevation_deg <= 0:
            return None
        direct = 0.0
        for d_yaw, d_az, d_alt in self.draws:
            c = classify(p.azimuth_deg - self.delta_deg - d_yaw + d_az, p.elevation_deg + d_alt, self.grid)
            if c == UNKNOWN_SUN:
                return UNKNOWN_SUN
            if c == DIRECT:
                direct += 1
            elif c == SENSITIVE:
                direct += 0.5
        share = direct / len(self.draws)
        if share >= 0.95:
            return DIRECT
        if share <= 0.05:
            return BLOCKED_SUN
        return SENSITIVE

    def bands(self, day):
        """Segments at whole minutes: sampled every step, with every minute between two differing samples evaluated so
        entry and exit are exact to the minute (docs/06 §3)."""
        start, end = day.interval(self.tz)
        step = self.step_minutes * 60
        segments = []
        state = {"start": start, "state": self.state(start)}

        def close(t, nxt):
            if state["state"] is not None and t > state["start"]:
                segments.append(Segment(state["start"], t, state["state"]))
            state["start"], state["state"] = t, nxt

        previous = start
        t = start + step
        while t <= end:
            s = self.state(t) if t < end else None
            if s != state["state"] or t == end:
                m = previous + 60
                while m < t:
                    sm = self.state(m)
                    if sm != state["state"]:
                        close(m, sm)
                    m += 60
                if s != state["state"] or t == end:
                    close(t, s)
            previous = t
            t += step
        return DayBands(day, tuple(segments))
