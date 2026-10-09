#!/usr/bin/env python3
"""Replays saved Light scans through the app's coverage rules, from the poses and compass readings in each record.

    python3 engine/scripts/scan_postmortem.py RECORD.json [RECORD.json ...]

For every record it prints what the scan screen would have shown under the rules as first shipped (a 60-reading
compass window, readings up to 50 degrees of pitch, frames within 0.15 m) and under the rules of 2026-10-05 (the whole
session's readings up to 30 degrees, frames within the 0.40 m drift limit), for both questions; then where the compass
readings pointed by camera pitch and by turning speed, and how far the phone strayed from the viewpoint.

It reads scene records only (schema 0.1.0 or 0.2.0) and prints no place, label or coordinate. The poses are the
thinned 10 Hz log (ADR-0020), so percentages can differ from the phone's by a point or two.
"""
import datetime
import json
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from lightreplay import bands, north  # noqa: E402

AZ, ALT, MIN_ALT = bands.AZ_CELLS, bands.ALT_CELLS, bands.MIN_ALT_DEG
EDGE = 0.08              # SkySweep.add: this share of each image side is left out
FAST_TURN = 60.0         # ScanCoach.fastTurnDegPerSec


def _direction(az, alt):
    a, e = math.radians(az), math.radians(alt)
    return (math.cos(e) * math.sin(a), math.sin(e), -math.cos(e) * math.cos(a))


DIRECTIONS = [_direction(az + 0.5, MIN_ALT + alt + 0.5) for alt in range(ALT) for az in range(AZ)]


def _seconds(stamp):
    return datetime.datetime.fromisoformat(stamp).timestamp()


def _wrap(d):
    return (d + 180) % 360 - 180


def _median_yaw(yaws):
    return north.merge_group([(y, 1.0) for y in yaws])[0]


def readings(record):
    """Every compass reading tied to a pose: (seconds in, camera pitch, yaw it gives, turning speed about vertical)."""
    start = _seconds(record["capture_session"]["started_at"])
    out, previous, rate = [], None, 0.0
    for candidate in record["north"]["candidates"]:
        if candidate.get("group") != "magnetic":
            continue
        for s in candidate["raw"].get("samples", []):
            t = _seconds(s["sampled_at"]) - start
            if previous and t > previous[0]:
                rate = 0.7 * rate + 0.3 * _wrap(s["camera_az_ar_deg"] - previous[1]) / (t - previous[0])
            previous = (t, s["camera_az_ar_deg"])
            out.append((t, s["camera_pitch_deg"], s["yaw_deg"], rate))
    return out


def replay(record, question, window, max_pitch, max_offset):
    """Coverage as the scan screen counts it. `window` is how many recent readings place the path; None = all."""
    session = record["capture_session"]
    frames = session["frames"]
    lat, lon = record["location"]["lat"], record["location"]["lon"]
    year = datetime.datetime.fromisoformat(session["started_at"]).year
    corridor = bands.SunCorridor(bands.corridor_days(question, year, lat), lat, lon, record["timezone"], 0.0)
    cells = [(i % AZ, i // AZ) for i, inside in enumerate(corridor.cells) if inside]
    anchor = session["viewpoint_lock"]["anchor_world"]
    hero = (session.get("hero_frame") or {}).get("image") or {}
    width, height = hero.get("native_size") or (1920, 1440)
    compass = readings(record)

    seen = [False] * (AZ * ALT)
    yaws, yaw, next_reading = [], None, 0
    last, rate = None, 0.0
    coverage = peak = 0.0
    reached = None
    for frame in frames:
        m, t, k = frame["camera_transform"], frame["t"], frame["intrinsics"]
        x_axis, y_axis, z_axis, position = m[0:3], m[4:7], m[8:11], m[12:15]
        forward = (-z_axis[0], -z_axis[1], -z_axis[2])
        if last and t > last[1]:
            dot = max(-1.0, min(1.0, sum(a * b for a, b in zip(last[0], forward))))
            rate = 0.8 * rate + 0.2 * math.degrees(math.acos(dot)) / (t - last[1])
        last = (forward, t)
        fresh = False
        while next_reading < len(compass) and compass[next_reading][0] <= t:
            _, pitch, value, _ = compass[next_reading]
            next_reading += 1
            if abs(pitch) <= max_pitch:
                yaws.append(value)
                fresh = True
        if fresh and len(yaws) >= 3:
            if window:
                recent = yaws[-window:]
                yaw = math.degrees(math.atan2(sum(math.sin(math.radians(y)) for y in recent),
                                              sum(math.cos(math.radians(y)) for y in recent))) % 360
            else:
                yaw = _median_yaw(yaws)
        if frame["tracking_state"] == "normal" and math.dist(position, anchor) <= max_offset and rate <= FAST_TURN:
            mx, my = width * EDGE, height * EDGE
            for i, d in enumerate(DIRECTIONS):
                if seen[i] or d[0] * forward[0] + d[1] * forward[1] + d[2] * forward[2] < 0.5:
                    continue
                z = z_axis[0] * d[0] + z_axis[1] * d[1] + z_axis[2] * d[2]
                if z >= -1e-9:
                    continue
                u = k[6] + k[0] * (x_axis[0] * d[0] + x_axis[1] * d[1] + x_axis[2] * d[2]) / -z
                v = k[7] - k[4] * (y_axis[0] * d[0] + y_axis[1] * d[1] + y_axis[2] * d[2]) / -z
                if mx <= u <= width - mx and my <= v <= height - my:
                    seen[i] = True
        if yaw is not None:
            hits = sum(seen[alt * AZ + int(math.floor((az + 0.5 - yaw) % 360)) % 360] for az, alt in cells)
            coverage = hits / len(cells)
            peak = max(peak, coverage)
            if reached is None and coverage >= 0.9:
                reached = t
    return coverage, peak, reached


def compass_by(record, key, edges, max_pitch_for_rate=30.0):
    """Median offset of the readings from the calm ones (level, barely turning), per bin, and how many are turned round."""
    rows = readings(record)
    calm = [r[2] for r in rows if abs(r[1]) < 20 and abs(r[3]) < 10] or [r[2] for r in rows]
    reference = _median_yaw(calm)
    out = []
    for low, high in zip(edges, edges[1:]):
        if key == "pitch":
            offsets = sorted(_wrap(r[2] - reference) for r in rows if low <= r[1] < high)
        else:
            offsets = sorted(_wrap(r[2] - reference) for r in rows if low <= r[3] < high and abs(r[1]) < max_pitch_for_rate)
        if offsets:
            out.append((low, high, len(offsets), offsets[len(offsets) // 2], sum(1 for o in offsets if abs(o) > 90)))
    return out


def offsets_from_viewpoint(record):
    session = record["capture_session"]
    anchor = session["viewpoint_lock"]["anchor_world"]
    return [math.dist(f["camera_transform"][12:15], anchor) for f in session["frames"] if f["tracking_state"] == "normal"]


def main(paths):
    records = sorted((json.load(open(p)) for p in paths), key=lambda r: r["scene_id"])
    rules = [("as first shipped", 60, 50.0, 0.15), ("rules of 2026-10-05", None, 30.0, 0.40)]
    for record in records:
        frames = record["capture_session"]["frames"]
        print(f"\n{record['scene_id']}  {frames[-1]['t']:.0f} s, {len(frames)} poses")
        for name, window, pitch, offset in rules:
            for question in ("allYear", "winter"):
                final, peak, reached = replay(record, question, window, pitch, offset)
                when = f"{reached:.0f} s" if reached is not None else "never"
                print(f"  {name:20s} {question:8s} ends {final * 100:3.0f}%  peak {peak * 100:3.0f}%  reaches 90%: {when}")
        d = offsets_from_viewpoint(record)
        share = lambda limit: 100 * sum(1 for x in d if x <= limit) / len(d)  # noqa: E731
        print(f"  from the viewpoint: within 0.15 m {share(0.15):.0f}%, 0.25 m {share(0.25):.0f}%, 0.40 m {share(0.40):.0f}%, "
              f"0.50 m {share(0.50):.0f}%; furthest {max(d):.2f} m")
        print("  compass by camera pitch (bin, readings, median offset, turned round):")
        for low, high, n, median, flipped in compass_by(record, "pitch", [-90, 0, 10, 20, 30, 40, 50, 91]):
            print(f"    {low:+4d}..{high:+4d}°  n={n:4d}  {median:+7.1f}°  {flipped}")
        print("  compass by turning speed, level readings (bin °/s, readings, median offset):")
        for low, high, n, median, _ in compass_by(record, "rate", [-400, -40, -20, -8, 8, 20, 40, 400]):
            print(f"    {low:+4d}..{high:+4d}  n={n:4d}  {median:+6.1f}°")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
