"""Capture-first SceneRecord 0.1.0 validation; synthetic software checks, not field validation.

Unknown fields and explicit nulls survive loads/dumps. Asset paths are lexical
references only: no asset is opened, no orientation is resolved, and no result is
certified. Matrices are flat column-major arrays and are never transposed.
"""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
import math
from pathlib import Path
import re
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


class ValidationError(ValueError):
    """A malformed or unsupported SceneRecord."""


_ROOT = "schema_version scene_id created_at timezone app device location target capture_session north visibility geometry analysis quality sharing context".split()
_TIMESTAMP = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})\Z")
_TIME_KEYS = set("created_at captured_at started_at ended_at sampled_at resolved_at computed_at revoked_at timestamp".split())
_ACCURACY_KEYS = set("h_acc_m v_acc_m heading_accuracy sigma_deg yaw_sigma_deg boundary_jitter_deg".split())


def _require(condition, path, message):
    if not condition:
        raise ValidationError(f"{path}: {message}")


def _object(value, path, keys=()):
    _require(isinstance(value, dict), path, "expected object")
    for key in keys.split() if isinstance(keys, str) else keys:
        _require(key in value, path, f"missing {key}")
    return value


def _array(value, path):
    _require(isinstance(value, list), path, "expected array")
    return value


def _string(value, path, nullable=False):
    if nullable and value is None:
        return
    _require(isinstance(value, str) and bool(value.strip()), path, "expected nonempty string")


def _number(value, path, low=None, high=None, nullable=False, integer=False):
    if nullable and value is None:
        return
    _require(type(value) in (int, float), path, "expected number, not bool")
    try:
        finite = math.isfinite(value)
    except OverflowError:
        finite = False
    _require(finite, path, "number must be finite and representable as Double")
    _require(low is None or value >= low, path, "number below range")
    _require(high is None or value <= high, path, "number above range")
    _require(not integer or value == math.floor(value), path, "expected integer")


def _bool(value, path):
    _require(type(value) is bool, path, "expected boolean")


def _enum(value, choices, path):
    _require(isinstance(value, str) and value in choices, path, "unsupported value")


def _vector(value, count, path):
    _array(value, path)
    _require(len(value) == count, path, f"expected {count} numbers")
    for index, number in enumerate(value):
        _number(number, f"{path}[{index}]")


def _strings(value, path):
    for item in _array(value, path):
        _string(item, path)


def _timestamp(value, path):
    _string(value, path)
    match = _TIMESTAMP.fullmatch(value)
    _require(match is not None, path, "expected ISO 8601 timestamp with explicit offset")
    year, month, day, hour, minute, second = map(int, match.group(*range(1, 7)))
    zone = match[8]
    offset = 0
    if zone != "Z":
        hh, mm = int(zone[1:3]), int(zone[4:6])
        _require(hh <= 23 and mm <= 59, path, "invalid UTC offset")
        offset = (hh * 60 + mm) * (1 if zone[0] == "+" else -1)
    try:
        return datetime(year, month, day, hour, minute, second,
                        int((match[7] or "").ljust(6, "0")[:6]),
                        timezone(timedelta(minutes=offset))).timestamp()
    except (ValueError, OverflowError) as error:
        raise ValidationError(f"{path}: invalid calendar timestamp") from error


def _path(value, path):
    if value is None:
        return
    _string(value, path)
    _require(not any(c in value for c in "\\:%?#") and not any(ord(c) < 32 or ord(c) == 127 for c in value), path, "unsafe asset reference")
    _require(all(part not in ("", ".", "..") for part in value.split("/")), path, "expected safe relative asset path")


def _walk(value, path="$", depth=0):
    _require(depth <= 128, path, "JSON nesting exceeds 128")
    if isinstance(value, dict):
        for key, child in value.items():
            _require(isinstance(key, str), path, "object keys must be strings")
            child_path = f"{path}.{key}"
            if key.endswith("_ref"):
                _path(child, child_path)
            if key in _TIME_KEYS and child is not None:
                _timestamp(child, child_path)
            if key in _ACCURACY_KEYS:
                _number(child, child_path, low=0, nullable=True)
            _walk(child, child_path, depth + 1)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _walk(child, f"{path}[{index}]", depth + 1)
    elif type(value) in (int, float):
        _number(value, path)
    else:
        _require(value is None or type(value) in (str, bool), path, "expected JSON value")


def _capture(value):
    p = "$.capture_session"
    s = _object(value, p, "session_id started_at ended_at world_alignment hero_frame frames viewpoint_lock guidance")
    _string(s["session_id"], p + ".session_id")
    start = _timestamp(s["started_at"], p + ".started_at")
    end = _timestamp(s["ended_at"], p + ".ended_at")
    _require(end >= start, p, "session ends before it starts")
    _enum(s["world_alignment"], ("gravity", "gravityAndHeading"), p + ".world_alignment")
    if s["hero_frame"] is not None:
        h = _object(s["hero_frame"], p + ".hero_frame", "frame_id image_ref timestamp intrinsics camera_transform exposure")
        _string(h["frame_id"], p + ".hero_frame.frame_id")
        _timestamp(h["timestamp"], p + ".hero_frame.timestamp")
        _vector(h["intrinsics"], 9, p + ".hero_frame.intrinsics")
        _vector(h["camera_transform"], 16, p + ".hero_frame.camera_transform")
    ids = set()
    for i, item in enumerate(_array(s["frames"], p + ".frames")):
        fpath = f"{p}.frames[{i}]"
        f = _object(item, fpath, "frame_id t camera_transform intrinsics tracking_state lens_offset_m depth_ref depth_confidence_ref mask_ref exposure_offset used_for_visibility")
        _string(f["frame_id"], fpath + ".frame_id")
        _require(f["frame_id"] not in ids, fpath, "duplicate frame_id")
        ids.add(f["frame_id"])
        _vector(f["camera_transform"], 16, fpath + ".camera_transform")
        _vector(f["intrinsics"], 9, fpath + ".intrinsics")
        _number(f["t"], fpath + ".t", low=0, high=end - start)
        _number(f["lens_offset_m"], fpath + ".lens_offset_m", low=0, nullable=True)
        _number(f["exposure_offset"], fpath + ".exposure_offset", nullable=True)
        _bool(f["used_for_visibility"], fpath + ".used_for_visibility")
        state = f["tracking_state"]
        _string(state, fpath + ".tracking_state")
        _require(state in ("normal", "not_available") or (state.startswith("limited:") and bool(state[8:].strip())), fpath, "invalid tracking state")
    lock = _object(s["viewpoint_lock"], p + ".viewpoint_lock", "anchor_world tolerance_m max_drift_m frames_within frames_beyond handling")
    _vector(lock["anchor_world"], 3, p + ".viewpoint_lock.anchor_world")
    for key in ("tolerance_m", "max_drift_m"):
        _number(lock[key], p + ".viewpoint_lock." + key, low=0, nullable=True)
    for key in ("frames_within", "frames_beyond"):
        _number(lock[key], p + ".viewpoint_lock." + key, low=0, integer=True)
    _enum(lock["handling"], ("depth_recentered", "tolerated", "rejected"), p + ".viewpoint_lock.handling")
    g = _object(s["guidance"], p + ".guidance", "question corridor_ref")
    _enum(g["question"], ("winter_breakfast", "full_year", "west_afternoon", "custom"), p + ".guidance.question")


def _north(value):
    n = _object(value, "$.north", "candidates resolved")
    for i, item in enumerate(_array(n["candidates"], "$.north.candidates")):
        p = f"$.north.candidates[{i}]"
        c = _object(item, p, "source group yaw_deg sigma_deg valid")
        _string(c["source"], p + ".source")
        _enum(c["group"], ("magnetic", "map", "solar", "vps"), p + ".group")
        _bool(c["valid"], p + ".valid")
        _number(c["yaw_deg"], p + ".yaw_deg", low=0, high=360, nullable=not c["valid"])
        _require(c["yaw_deg"] is None or c["yaw_deg"] < 360, p, "yaw must be less than 360")
        _number(c["sigma_deg"], p + ".sigma_deg", low=0, nullable=not c["valid"])
    if n["resolved"] is not None:
        p = "$.north.resolved"
        r = _object(n["resolved"], p, "yaw_deg sigma_deg method groups_used groups_rejected conflict conflict_detail resolved_at")
        _number(r["yaw_deg"], p + ".yaw_deg", low=0, high=360)
        _require(r["yaw_deg"] < 360, p, "yaw must be less than 360")
        _number(r["sigma_deg"], p + ".sigma_deg", low=0)
        _string(r["method"], p + ".method")
        _bool(r["conflict"], p + ".conflict")
        _string(r["conflict_detail"], p + ".conflict_detail", nullable=True)
        _timestamp(r["resolved_at"], p + ".resolved_at")
        for key in ("groups_used", "groups_rejected"):
            _strings(r[key], p + "." + key)
            _require(len(r[key]) == len(set(r[key])), p + "." + key, "duplicate group")
            for group in r[key]:
                _enum(group, ("magnetic", "map", "solar", "vps"), p + "." + key)
        _require(not set(r["groups_used"]) & set(r["groups_rejected"]), p, "used/rejected groups overlap")


def _visibility(value):
    p = "$.visibility"
    v = _object(value, p, "grid states_ref confidence_ref votes coverage segmentation near_field")
    grid = _object(v["grid"], p + ".grid", "az_step_deg alt_step_deg az_frame alt_range")
    for key in ("az_step_deg", "alt_step_deg"):
        _number(grid[key], p + ".grid." + key, low=0, high=360)
        _require(grid[key] > 0, p + ".grid." + key, "step must be positive")
    _enum(grid["az_frame"], ("ar_world",), p + ".grid.az_frame")
    _vector(grid["alt_range"], 2, p + ".grid.alt_range")
    _require(-90 <= grid["alt_range"][0] < grid["alt_range"][1] <= 90, p, "invalid altitude range")
    if v["votes"] is not None:
        votes = _object(v["votes"], p + ".votes")
        for key, count in votes.items():
            _number(count, p + ".votes." + key, low=0, integer=True)
    c = _object(v["coverage"], p + ".coverage", "corridor_cells unknown_cells glass_cells covered_cells coverage_pct")
    for key in ("corridor_cells", "unknown_cells", "glass_cells", "covered_cells"):
        _number(c[key], p + ".coverage." + key, low=0, integer=True)
    _require(c["covered_cells"] == c["corridor_cells"] - c["unknown_cells"], p, "inconsistent covered_cells")
    _require(c["glass_cells"] <= c["covered_cells"], p, "glass exceeds covered cells")
    _number(c["coverage_pct"], p + ".coverage.coverage_pct", low=0, high=1, nullable=c["corridor_cells"] == 0)
    if c["corridor_cells"]:
        _require(abs(c["coverage_pct"] - c["covered_cells"] / c["corridor_cells"]) <= 1e-9, p, "inconsistent coverage fraction")
    else:
        _require(c["coverage_pct"] is None, p, "empty corridor must have null coverage fraction")
    if v["segmentation"] is not None:
        s = _object(v["segmentation"], p + ".segmentation", "model glass_detected reflection_flags manual_edits")
        _string(s["model"], p + ".segmentation.model", nullable=True)
        if s["glass_detected"] is not None:
            _bool(s["glass_detected"], p + ".segmentation.glass_detected")
        _strings(s["reflection_flags"], p + ".segmentation.reflection_flags")
    if v["near_field"] is not None:
        n = _object(v["near_field"], p + ".near_field", "d_near_m recentered_cells source")
        _number(n["d_near_m"], p + ".near_field.d_near_m", low=0, nullable=True)
        _number(n["recentered_cells"], p + ".near_field.recentered_cells", low=0, integer=True)
        _enum(n["source"], ("lidar",), p + ".near_field.source")


def _geometry(value):
    g = _object(value, "$.geometry", "windows planes level")
    _enum(g["level"], ("R1_only", "R2_available"), "$.geometry.level")
    for w in _array(g["windows"], "$.geometry.windows"):
        _object(w, "$.geometry.windows[]", "id corners_world source")
        _string(w["id"], "$.geometry.windows[].id")
        _enum(w["source"], ("roomplan", "manual"), "$.geometry.windows[].source")
        _array(w["corners_world"], "$.geometry.windows[].corners_world")
        _require(len(w["corners_world"]) == 4, "$.geometry.windows[]", "expected four corners")
        for corner in w["corners_world"]:
            _vector(corner, 3, "$.geometry.windows[].corners_world[]")
    for p in _array(g["planes"], "$.geometry.planes"):
        _object(p, "$.geometry.planes[]", "id normal point extent source")
        _string(p["id"], "$.geometry.planes[].id")
        _string(p["source"], "$.geometry.planes[].source")
        for key in ("normal", "point"):
            _vector(p[key], 3, "$.geometry.planes[]." + key)
        _array(p["extent"], "$.geometry.planes[].extent")
        _require(len(p["extent"]) in (2, 3), "$.geometry.planes[].extent", "expected two or three dimensions")
        for dimension in p["extent"]:
            _number(dimension, "$.geometry.planes[].extent", low=0)


def _analysis(value):
    for a in value:
        _object(a, "$.analysis[]", "query bands heatmap_ref attribution uncertainty versions computed_at")
        q = _object(a["query"], "$.analysis[].query", "date_from date_to time_window scenario")
        _enum(q["scenario"], ("current",), "$.analysis[].query.scenario")
        for key in ("date_from", "date_to"):
            _date(q[key], "$.analysis[].query." + key)
        _require(q["date_from"] <= q["date_to"], "$.analysis[].query", "reversed date range")
        for band in _array(a["bands"], "$.analysis[].bands"):
            _object(band, "$.analysis[].bands[]", "date segments")
            _date(band["date"], "$.analysis[].bands[].date")
            for segment in _array(band["segments"], "$.analysis[].bands[].segments"):
                _object(segment, "$.analysis[].bands[].segments[]", "from to state")
                for key in ("from", "to"):
                    _require(isinstance(segment[key], str) and re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", segment[key]) is not None, "$.analysis[].bands[].segments[]." + key, "invalid local time")
                _require(segment["from"] < segment["to"], "$.analysis[].bands[].segments[]", "reversed segment")
                _enum(segment["state"], ("direct", "blocked", "unknown", "sensitive"), "$.analysis[].bands[].segments[].state")
        for item in _array(a["attribution"], "$.analysis[].attribution"):
            _object(item, "$.analysis[].attribution[]", "from to cause az_range alt_range")
            for key in ("from", "to", "cause"):
                _string(item[key], "$.analysis[].attribution[]." + key)
            for key in ("az_range", "alt_range"):
                _vector(item[key], 2, "$.analysis[].attribution[]." + key)
        u = _object(a["uncertainty"], "$.analysis[].uncertainty", "yaw_sigma_deg samples boundary_jitter_deg")
        _number(u["samples"], "$.analysis[].uncertainty.samples", low=1, integer=True)
        _object(a["versions"], "$.analysis[].versions", "inputs_hash")
        _string(a["versions"]["inputs_hash"], "$.analysis[].versions.inputs_hash")
        _timestamp(a["computed_at"], "$.analysis[].computed_at")


def _date(value, path):
    _require(isinstance(value, str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value) is not None, path, "invalid date")
    try:
        date.fromisoformat(value)
    except ValueError as error:
        raise ValidationError(f"{path}: invalid calendar date") from error


def _evidence(r):
    for key in ("location", "target", "capture_session", "visibility"):
        _require(r[key] is not None, "$.'" + key + "'", "analysis-ready record requires input evidence")
    _require(r["location"]["lat"] is not None and r["location"]["lon"] is not None, "$.location", "coordinates required")
    t = r["target"]
    _require(t["height_m"] is not None and t["confirmed_by"] == "user", "$.target", "user-confirmed target height required")
    s = r["capture_session"]
    _require(s["viewpoint_lock"]["handling"] != "rejected", "$.capture_session.viewpoint_lock", "rejected viewpoint")
    _require(any(f["used_for_visibility"] and f["tracking_state"] == "normal" and f["mask_ref"] is not None and f["lens_offset_m"] is not None for f in s["frames"]), "$.capture_session.frames", "no usable visibility frame evidence")
    n = r["north"]["resolved"]
    _require(n is not None and n["conflict"] is False and bool(n["groups_used"]), "$.north.resolved", "unresolved or conflicting north")
    groups = {c["group"] for c in r["north"]["candidates"] if c["valid"]}
    _require(set(n["groups_used"]) <= groups, "$.north", "resolved north has no matching valid candidate evidence")
    v = r["visibility"]
    _require(v["states_ref"] is not None and v["confidence_ref"] is not None, "$.visibility", "visibility assets required")
    _require(v["coverage"]["corridor_cells"] > 0 and v["coverage"]["covered_cells"] > 0, "$.visibility.coverage", "empty visibility evidence")
    _require(v["segmentation"] is not None and v["segmentation"]["model"] is not None, "$.visibility.segmentation", "segmentation provenance required")


def validate(record):
    """Validate in place without modifying or dropping any source fields."""
    _walk(record)
    r = _object(record, "$", _ROOT)
    _enum(r["schema_version"], ("0.1.0",), "$.schema_version")
    _string(r["scene_id"], "$.scene_id")
    _timestamp(r["created_at"], "$.created_at")
    _string(r["timezone"], "$.timezone")
    _require(r["timezone"] == "UTC" or "/" in r["timezone"], "$.timezone", "expected IANA timezone identifier")
    try:
        ZoneInfo(r["timezone"])
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise ValidationError("$.timezone: unknown IANA timezone") from error
    app = _object(r["app"], "$.app", "version build algorithms")
    for key in ("version", "build"):
        _string(app[key], "$.app." + key)
    algorithms = _object(app["algorithms"], "$.app.algorithms", "sun segmentation north visibility")
    for key, value in algorithms.items():
        _string(value, "$.app.algorithms." + key, nullable=True)
    d = _object(r["device"], "$.device", "model os lidar scene_depth geo_tracking")
    for key in ("model", "os", "geo_tracking"):
        _string(d[key], "$.device." + key)
    for key in ("lidar", "scene_depth"):
        _bool(d[key], "$.device." + key)
    if r["location"] is not None:
        loc = _object(r["location"], "$.location", "lat lon alt_m h_acc_m v_acc_m source captured_at")
        _number(loc["lat"], "$.location.lat", low=-90, high=90, nullable=True)
        _number(loc["lon"], "$.location.lon", low=-180, high=180, nullable=True)
        _number(loc["alt_m"], "$.location.alt_m", nullable=True)
        _string(loc["source"], "$.location.source")
        _timestamp(loc["captured_at"], "$.location.captured_at")
    if r["target"] is not None:
        t = _object(r["target"], "$.target", "target_id label height_m anchor_world confirmed_by notes")
        for key in ("target_id", "label"):
            _string(t[key], "$.target." + key)
        _number(t["height_m"], "$.target.height_m", low=0, nullable=True)
        _vector(t["anchor_world"], 3, "$.target.anchor_world")
        _string(t["confirmed_by"], "$.target.confirmed_by", nullable=True)
        _string(t["notes"], "$.target.notes", nullable=True)
    if r["capture_session"] is not None:
        _capture(r["capture_session"])
    _north(r["north"])
    if r["visibility"] is not None:
        _visibility(r["visibility"])
    if r["geometry"] is not None:
        _geometry(r["geometry"])
    a = _array(r["analysis"], "$.analysis")
    q = _object(r["quality"], "$.quality", "level gates flags false_valid_guard blocked_reason")
    _enum(q["level"], ("R0", "R1", "R2", "R3"), "$.quality.level")
    _enum(q["false_valid_guard"], ("blocked", "passed"), "$.quality.false_valid_guard")
    gates = _object(q["gates"], "$.quality.gates", "level coverage north segmentation lens")
    for key, gate in gates.items():
        _enum(gate, ("pass", "warn", "blocked"), "$.quality.gates." + key)
    _strings(q["flags"], "$.quality.flags")
    _string(q["blocked_reason"], "$.quality.blocked_reason", nullable=True)
    if q["level"] == "R0" or q["false_valid_guard"] == "blocked":
        _require(not a, "$.analysis", "R0 or blocked records must have empty analysis")
    if q["level"] != "R0" or q["false_valid_guard"] == "passed":
        _require(q["level"] != "R0" and q["false_valid_guard"] == "passed", "$.quality", "inconsistent level/guard")
        _require("blocked" not in gates.values(), "$.quality.gates", "blocked gate forbids analysis-ready status")
        _require(q["blocked_reason"] is None, "$.quality.blocked_reason", "passed guard cannot retain a blocked reason")
        _evidence(r)
    _analysis(a)
    sh = _object(r["sharing"], "$.sharing", "include_hero precise_address revoked revoked_at")
    for key in ("include_hero", "precise_address", "revoked"):
        _bool(sh[key], "$.sharing." + key)
    _require(not sh["revoked"] or sh["revoked_at"] is not None, "$.sharing.revoked_at", "revocation requires timestamp")
    _object(r["context"], "$.context", "address_estimate")


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, "$", f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def loads(data):
    """Decode strict JSON and validate, retaining unknown fields and nulls."""
    def reject_constant(value):
        raise ValidationError(f"$: non-JSON numeric constant {value}")
    try:
        record = json.loads(data, object_pairs_hook=_pairs, parse_constant=reject_constant)
        validate(record)
        return record
    except (UnicodeError, RecursionError) as error:
        raise ValidationError("$: invalid JSON encoding or nesting") from error


def dumps(record, pretty_printed=True):
    """Validate and encode normalized JSON; numeric spelling is not preserved."""
    validate(record)
    return json.dumps(record, ensure_ascii=True, allow_nan=False, sort_keys=True,
                      indent=2 if pretty_printed else None,
                      separators=None if pretty_printed else (",", ":"))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Validate capture-first SceneRecord 0.1.0 and emit normalized JSON. No asset or field validation.")
    parser.add_argument("input", help="JSON filepath (use - for UTF-8 stdin)")
    parser.add_argument("-o", "--output", help="write JSON to this filepath instead of stdout")
    parser.add_argument("--compact", action="store_true", help="omit pretty-print whitespace")
    args = parser.parse_args(argv)
    import sys
    try:
        data = sys.stdin.buffer.read() if args.input == "-" else Path(args.input).read_bytes()
        output = dumps(loads(data), pretty_printed=not args.compact) + "\n"
        if args.output:
            Path(args.output).write_text(output, encoding="utf-8")
        else:
            sys.stdout.write(output)
        return 0
    except (ValueError, OSError) as error:
        print(f"scene-record-check: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
