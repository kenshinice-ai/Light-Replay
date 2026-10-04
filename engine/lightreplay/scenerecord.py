"""SceneRecord validation, schema 0.1.0 and 0.2.0; synthetic software checks, not field validation.

0.2.0 (ADR-0022) carries its evidence inside the record: the visibility grid and a few keyframe masks as inline
payloads with a length and a SHA-256, the hero image's scale chain, the evidence behind all five lights, and a
result revision. 0.1.0 records stay valid as they are.

Unknown fields and explicit nulls survive loads/dumps. Asset paths are lexical
references only: no asset is opened, no orientation is resolved, and no result is
certified. Matrices are flat column-major arrays and are never transposed.
"""

import argparse
import base64
import binascii
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zlib
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


class ValidationError(ValueError):
    """A malformed or unsupported SceneRecord."""


_ROOT = "schema_version scene_id created_at timezone app device location target capture_session north visibility geometry analysis quality sharing context".split()
_TIMESTAMP = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})\Z")
_TIME_KEYS = set("created_at captured_at started_at ended_at sampled_at resolved_at computed_at revoked_at timestamp".split())
_ACCURACY_KEYS = set("h_acc_m v_acc_m heading_accuracy sigma_deg yaw_sigma_deg boundary_jitter_deg".split())
#: Inline payload limits (ADR-0022). A grid is one byte a cell; a record keeps at most this many keyframe masks.
MAX_GRID_BYTES = 360 * 181
MAX_MASK_BYTES = 400_000
MAX_KEYFRAMES = 5
#: A keyframe mask is a small greyscale PNG; its side is bounded before anything is inflated (review A03).
MAX_MASK_SIDE = 2048
#: Sun-disk candidate validity, sundisk-0.1 (docs/05 §2a). Candidates until experiment 2 (docs/07 §5).
SUN_DISK_RULES = "sundisk-0.1"
SUN_ALTITUDE_RESIDUAL_DEG = 1.5
SUN_MIN_ALTITUDE_DEG = 5.0
SUN_MIN_SKY_RING = 0.6


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


def _payload(value, path, encoding, max_bytes):
    """An inline asset: stated length and SHA-256 must be those of the decoded bytes. Returns the bytes."""
    a = _object(value, path, "encoding width height byte_count sha256 data")
    _enum(a["encoding"], (encoding,), path + ".encoding")
    for key in ("width", "height", "byte_count"):
        _number(a[key], path + "." + key, low=1, integer=True)
    _require(a["byte_count"] <= max_bytes, path + ".byte_count", "payload larger than the limit")
    _string(a["sha256"], path + ".sha256")
    _string(a["data"], path + ".data")
    _require(len(a["data"]) <= 4 * (max_bytes // 3 + 4), path + ".data", "payload larger than the limit")
    try:
        raw = base64.b64decode(a["data"], validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValidationError(f"{path}.data: not base64") from error
    if encoding == "deflate+base64":   # raw DEFLATE (RFC 1951), bounded so a small payload cannot inflate without limit
        try:
            raw = zlib.decompressobj(wbits=-15).decompress(raw, max_bytes + 1)
        except zlib.error as error:
            raise ValidationError(f"{path}.data: not DEFLATE") from error
        _require(0 < len(raw) <= max_bytes, path + ".data", "payload does not inflate, or inflates past the limit")
    _require(len(raw) == a["byte_count"], path + ".byte_count", "stated length is not the payload's")
    _require(hashlib.sha256(raw).hexdigest() == a["sha256"], path + ".sha256", "stated hash is not the payload's")
    return raw


def _capture(value, v2=False):
    p = "$.capture_session"
    s = _object(value, p, "session_id started_at ended_at world_alignment hero_frame frames viewpoint_lock guidance"
                + (" keyframes" if v2 else ""))
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
        if v2:
            _require("image" in h, p + ".hero_frame", "missing image")
            if h["image"] is not None:
                _hero_image(h["image"], p + ".hero_frame.image")
    ids = set()
    roles = {}
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
        if v2:
            _require("role" in f, fpath, "missing role")
            _enum(f["role"], ("visibility", "calibration"), fpath + ".role")
            # A frame taken while confirming the direction is not evidence about the target point's sky (review V2-02).
            _require(f["role"] == "visibility" or f["used_for_visibility"] is False, fpath, "a calibration frame cannot be used for visibility")
            roles[f["frame_id"]] = f
    if v2:
        keyframes = _array(s["keyframes"], p + ".keyframes")
        _require(len(keyframes) <= MAX_KEYFRAMES, p + ".keyframes", "too many keyframes")
        for i, item in enumerate(keyframes):
            kpath = f"{p}.keyframes[{i}]"
            k = _object(item, kpath, "frame_id mask")
            _string(k["frame_id"], kpath + ".frame_id")
            _require(k["frame_id"] in roles, kpath + ".frame_id", "keyframe is not one of the frames")
            _require(roles[k["frame_id"]]["used_for_visibility"] is True, kpath + ".frame_id", "keyframe was not used for visibility")
            png = _payload(k["mask"], kpath + ".mask", "png+base64", MAX_MASK_BYTES)
            _require((k["mask"]["width"], k["mask"]["height"]) == _mask_png(png, kpath + ".mask"), kpath + ".mask", "stated size is not the image's")
    lock = _object(s["viewpoint_lock"], p + ".viewpoint_lock", "anchor_world tolerance_m max_drift_m frames_within frames_beyond handling")
    _vector(lock["anchor_world"], 3, p + ".viewpoint_lock.anchor_world")
    for key in ("tolerance_m", "max_drift_m"):
        _number(lock[key], p + ".viewpoint_lock." + key, low=0, nullable=True)
    for key in ("frames_within", "frames_beyond"):
        _number(lock[key], p + ".viewpoint_lock." + key, low=0, integer=True)
    _enum(lock["handling"], ("depth_recentered", "tolerated", "rejected"), p + ".viewpoint_lock.handling")
    g = _object(s["guidance"], p + ".guidance", "question corridor_ref")
    _enum(g["question"], ("winter_breakfast", "full_year", "west_afternoon", "custom"), p + ".guidance.question")


def _mask_png(png, path):
    """A keyframe mask must be a whole PNG that can be decoded within bounds: every chunk present and intact, greyscale,
    not interlaced, sides within the limit, and pixel data that inflates to exactly its rows. Returns (width, height).
    The size is read and bounded before anything is inflated; a header that claims 100000 x 100000 costs nothing."""
    p = path + ".data"
    _require(png[:8] == b"\x89PNG\r\n\x1a\n", p, "not a PNG")
    at, chunks = 8, []
    while at < len(png):
        _require(at + 12 <= len(png), p, "truncated PNG")
        length, kind = struct.unpack(">I4s", png[at:at + 8])
        _require(at + 12 + length <= len(png), p, "truncated PNG")
        body = png[at + 8:at + 8 + length]
        _require(struct.unpack(">I", png[at + 8 + length:at + 12 + length])[0] == zlib.crc32(kind + body), p, "damaged PNG chunk")
        chunks.append((kind, body))
        at += 12 + length
    _require(len(chunks) >= 3 and chunks[0][0] == b"IHDR" and len(chunks[0][1]) == 13 and chunks[-1] == (b"IEND", b""), p, "not a whole PNG")
    width, height, depth, colour, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    _require(1 <= width <= MAX_MASK_SIDE and 1 <= height <= MAX_MASK_SIDE, path, "mask larger than the limit")
    _require(colour == 0 and depth in (1, 8) and (compression, filtering, interlace) == (0, 0, 0), p, "mask must be a plain greyscale PNG")
    data = b"".join(body for kind, body in chunks if kind == b"IDAT")
    _require(bool(data), p, "not a whole PNG")
    rows = height * (1 + (width * depth + 7) // 8)
    try:
        pixels = zlib.decompressobj().decompress(data, rows + 1)
    except zlib.error as error:
        raise ValidationError(f"{p}: PNG pixel data does not inflate") from error
    _require(len(pixels) == rows, p, "PNG pixel data is not the size of the image")
    return width, height


def _hero_image(value, path):
    """Where the hero's pixels are and how they relate to the sensor image the intrinsics describe (review R01)."""
    i = _object(value, path, "storage native_size encoded_size scale crop rotation_deg byte_count sha256")
    _enum(i["storage"], ("row.photo",), path + ".storage")
    for key in ("native_size", "encoded_size"):
        _vector(i[key], 2, path + "." + key)
        _require(all(n >= 1 and n == math.floor(n) for n in i[key]), path + "." + key, "expected whole pixels")
    _vector(i["crop"], 4, path + ".crop")
    x, y, w, h = i["crop"]
    _require(x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= i["native_size"][0] and y + h <= i["native_size"][1], path + ".crop", "crop outside the native image")
    _number(i["scale"], path + ".scale", low=0)
    _require(i["scale"] > 0, path + ".scale", "scale must be positive")
    _require(type(i["rotation_deg"]) in (int, float) and i["rotation_deg"] in (0, 90, 180, 270), path + ".rotation_deg", "unsupported value")
    expected = (w * i["scale"], h * i["scale"])
    if i["rotation_deg"] in (90, 270):
        expected = expected[::-1]
    _require(all(abs(e - n) <= 1 for e, n in zip(expected, i["encoded_size"])), path + ".encoded_size", "encoded size does not follow from crop, scale and rotation")
    _number(i["byte_count"], path + ".byte_count", low=1, integer=True)
    _string(i["sha256"], path + ".sha256")


def _sun_disk(c, p, frames):
    """A sun-disk candidate stated valid must carry evidence that passes sundisk-0.1 (docs/05 §2a).

    Passing does not prove the bright spot was the sun (a vertical mirror keeps the altitude, review V2-01); it
    refuses the candidates that certainly were not."""
    e = _object(c.get("evidence"), p + ".evidence", "rules frame_id time altitude_measured_deg altitude_expected_deg "
                "azimuth_expected_deg depth_m sky_ring_fraction user_confirmed tracking_continuous")
    _enum(e["rules"], (SUN_DISK_RULES,), p + ".evidence.rules")
    _string(e["frame_id"], p + ".evidence.frame_id")
    _require(e["frame_id"] in frames, p + ".evidence.frame_id", "evidence frame is not one of the frames")
    _timestamp(e["time"], p + ".evidence.time")
    for key in ("altitude_measured_deg", "altitude_expected_deg"):
        _number(e[key], p + ".evidence." + key, low=-90, high=90)
    _number(e["azimuth_expected_deg"], p + ".evidence.azimuth_expected_deg", low=0, high=360)
    _number(e["depth_m"], p + ".evidence.depth_m", low=0, nullable=True)
    _number(e["sky_ring_fraction"], p + ".evidence.sky_ring_fraction", low=0, high=1, nullable=True)
    for key in ("user_confirmed", "tracking_continuous"):
        _bool(e[key], p + ".evidence." + key)
    if c["valid"]:
        failed = sun_disk_failures(e)
        _require(not failed, p, "stated valid, but " + failed[0] if failed else "")


def sun_disk_failures(evidence):
    """Why this sun-disk evidence cannot stand, in the order checked; empty when nothing rules it out."""
    failed = []
    if abs(evidence["altitude_measured_deg"] - evidence["altitude_expected_deg"]) > SUN_ALTITUDE_RESIDUAL_DEG + 1e-9:
        failed.append(f"the bright spot is not at the sun's altitude (limit {SUN_ALTITUDE_RESIDUAL_DEG:g} degrees)")
    if evidence["altitude_expected_deg"] < SUN_MIN_ALTITUDE_DEG:
        failed.append(f"the sun is below {SUN_MIN_ALTITUDE_DEG:g} degrees")
    if evidence["depth_m"] is not None:
        failed.append("there is a surface at the bright spot: a lamp or a reflection, not the sky")
    if evidence["sky_ring_fraction"] is None or evidence["sky_ring_fraction"] < SUN_MIN_SKY_RING:
        failed.append("the bright spot is not surrounded by sky")
    if not evidence["user_confirmed"]:
        failed.append("nobody confirmed it was the sun")
    if not evidence["tracking_continuous"]:
        failed.append("tracking was interrupted between the scan and the confirmation")
    return failed


def _north(value, frames=None):
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
        if frames is not None and c["source"] == "sun_disk" and (c["valid"] or c.get("evidence") is not None):
            _sun_disk(c, p, frames)
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


def _visibility(value, v2=False, used_frames=0):
    p = "$.visibility"
    v = _object(value, p, "grid votes coverage segmentation near_field " + ("states confidence" if v2 else "states_ref confidence_ref"))
    grid = _object(v["grid"], p + ".grid", "az_step_deg alt_step_deg az_frame alt_range")
    for key in ("az_step_deg", "alt_step_deg"):
        _number(grid[key], p + ".grid." + key, low=0, high=360)
        _require(grid[key] > 0, p + ".grid." + key, "step must be positive")
    _enum(grid["az_frame"], ("ar_world",), p + ".grid.az_frame")
    _vector(grid["alt_range"], 2, p + ".grid.alt_range")
    _require(-90 <= grid["alt_range"][0] < grid["alt_range"][1] <= 90, p, "invalid altitude range")
    if v2:
        _grid_payloads(v, grid, p, used_frames)
    elif v["votes"] is not None:
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


def _grid_payloads(v, grid, p, used_frames):
    """0.2: the grid travels inside the record. One byte a cell, row-major from the lowest altitude, azimuth 0 first:
    0 unknown, 1 sky, 2 blocked, 3 glass-uncertain. `votes.cells` must be the grid's own histogram, and
    `votes.frames_used` the number of frames the record marks as used for visibility: a grid that knows anything
    rests on at least `min_distinct_frames` of them (review A04). This counts frames; whether each cell had enough
    distinct support is the accumulator's business and is tested there."""
    width = 360 / grid["az_step_deg"]
    height = (grid["alt_range"][1] - grid["alt_range"][0]) / grid["alt_step_deg"]
    _require(width == math.floor(width) and height == math.floor(height), p + ".grid", "steps do not divide the ranges")
    payloads = {}
    for key in ("states", "confidence"):
        if v[key] is None:
            continue
        payloads[key] = _payload(v[key], f"{p}.{key}", "deflate+base64", MAX_GRID_BYTES)
        _require((v[key]["width"], v[key]["height"]) == (width, height) and v[key]["byte_count"] == width * height,
                 f"{p}.{key}", "payload is not the size of the grid")
    _require((v["states"] is None) == (v["confidence"] is None), p, "states and confidence travel together")
    if v["votes"] is not None:
        votes = _object(v["votes"], p + ".votes", "frames_used min_distinct_frames cells")
        _number(votes["frames_used"], p + ".votes.frames_used", low=0, integer=True)
        _number(votes["min_distinct_frames"], p + ".votes.min_distinct_frames", low=1, integer=True)
        cells = _object(votes["cells"], p + ".votes.cells", "unknown sky blocked glass")
        for key in ("unknown", "sky", "blocked", "glass"):
            _number(cells[key], p + ".votes.cells." + key, low=0, integer=True)
    if "states" in payloads:
        states = payloads["states"]
        _require(max(states) <= 3, p + ".states", "unknown cell state")
        votes = _object(v["votes"], p + ".votes", "cells")
        histogram = [states.count(bytes([state])) for state in range(4)]
        _require([votes["cells"][key] for key in ("unknown", "sky", "blocked", "glass")] == histogram, p + ".votes.cells", "cell counts are not the grid's")
        _require(votes["frames_used"] == used_frames, p + ".votes.frames_used", "not the number of frames used for visibility")
        _require(sum(histogram[1:]) == 0 or votes["frames_used"] >= votes["min_distinct_frames"], p + ".votes.frames_used",
                 "a grid that knows anything needs at least min_distinct_frames frames")


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


def _minutes(clock):
    return int(clock[:2]) * 60 + int(clock[3:])


def _analysis(value, result=None):
    for a in value:
        _object(a, "$.analysis[]", "query bands heatmap_ref attribution uncertainty versions computed_at"
                + (" revision totals" if result is not None else ""))
        q = _object(a["query"], "$.analysis[].query", "date_from date_to time_window scenario"
                    + (" representative" if result is not None else ""))
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
        if result is not None:
            _bool(q["representative"], "$.analysis[].query.representative")
            # A day's segments are one timeline inside the query's window: in order, touching, never overlapping. A stretch
            # nothing is known about is a segment of its own, state unknown (review A02).
            window = _array(q["time_window"], "$.analysis[].query.time_window")
            _require(len(window) == 2 and all(isinstance(t, str) and re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", t) for t in window)
                     and window[0] < window[1], "$.analysis[].query.time_window", "expected two local times in order")
            dates = [band["date"] for band in a["bands"]]
            _require(len(dates) == len(set(dates)), "$.analysis[].bands[].date", "a date appears twice")
            for band in a["bands"]:
                _require(q["date_from"] <= band["date"] <= q["date_to"], "$.analysis[].bands[].date", "date outside the query")
                previous = None
                for segment in band["segments"]:
                    _require(window[0] <= segment["from"] and segment["to"] <= window[1], "$.analysis[].bands[].segments[]", "segment outside the query's window")
                    _require(previous is None or segment["from"] == previous, "$.analysis[].bands[].segments[]", "segments overlap or leave a gap")
                    previous = segment["to"]
                # A one-day question is answered for its whole window; what is not known is said, not left out.
                if q["date_from"] == q["date_to"]:
                    _require(bool(band["segments"]) and band["segments"][0]["from"] == window[0] and previous == window[1],
                             "$.analysis[].bands[].segments[]", "segments do not cover the query's window")
            _require(a["revision"] == result["revision"], "$.analysis[].revision", "not the record's result revision")
            _require(a["versions"]["inputs_hash"] == result["inputs_hash"], "$.analysis[].versions.inputs_hash", "not the record's inputs hash")
            # Minutes a state is shown for are the segments' own: an unknown stretch can never be counted as sun.
            totals = _object(a["totals"], "$.analysis[].totals", "direct_min sensitive_min blocked_min unknown_min")
            summed = dict.fromkeys(("direct", "sensitive", "blocked", "unknown"), 0)
            for band in a["bands"]:
                for segment in band["segments"]:
                    summed[segment["state"]] += _minutes(segment["to"]) - _minutes(segment["from"])
            for state, minutes in summed.items():
                _number(totals[state + "_min"], f"$.analysis[].totals.{state}_min", low=0, integer=True)
                _require(totals[state + "_min"] == minutes, f"$.analysis[].totals.{state}_min", "not the sum of the segments")


def _date(value, path):
    _require(isinstance(value, str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value) is not None, path, "invalid date")
    try:
        date.fromisoformat(value)
    except ValueError as error:
        raise ValidationError(f"{path}: invalid calendar date") from error


def _result(r):
    """0.2: which analysis this record carries. Revision 0 is the record as saved, before any analysis."""
    p = "$.result"
    result = _object(r["result"], p, "revision capture_digest north_digest inputs_hash computed_at")
    _number(result["revision"], p + ".revision", low=0, integer=True)
    for key in ("capture_digest", "north_digest"):
        _string(result[key], p + "." + key)
    _string(result["inputs_hash"], p + ".inputs_hash", nullable=True)
    if result["revision"] == 0:
        _require(result["inputs_hash"] is None and result["computed_at"] is None, p, "a record that was never analysed has no inputs hash")
        _require(r["visibility"] is None and not r["analysis"], p, "a record that was never analysed carries no grid and no analysis")
    else:
        _require(result["inputs_hash"] is not None and result["computed_at"] is not None, p, "an analysed record states its inputs hash and when")
    return result


def _quality_evidence(value, steady=frozenset(), hero=None):
    """0.2: what the detectors reported, so that every light can be worked out again (rules in quality.py).

    A check that ran says which frame of *this* capture it looked at (review A01): the horizon check one of the scan's
    normally tracked frames or the hero, the lens check the hero. `not_found` is a check that ran."""
    p = "$.quality.evidence"
    e = _object(value, p, "rules horizon lens reflection")
    _enum(e["rules"], ("quality-0.2",), p + ".rules")
    h = _object(e["horizon"], p + ".horizon", "status residual_deg confidence frame_id detector")
    _enum(h["status"], ("measured", "not_found", "not_run"), p + ".horizon.status")
    measured = h["status"] == "measured"
    _number(h["residual_deg"], p + ".horizon.residual_deg", low=0, high=180, nullable=not measured)
    _number(h["confidence"], p + ".horizon.confidence", low=0, high=1, nullable=not measured)
    lens = _object(e["lens"], p + ".lens", "status smudge_confidence frame_id detector")
    _enum(lens["status"], ("measured", "unusable_input", "not_run"), p + ".lens.status")
    _number(lens["smudge_confidence"], p + ".lens.smudge_confidence", low=0, high=1, nullable=lens["status"] != "measured")
    for name, part in (("horizon", h), ("lens", lens)):
        ran = part["status"] != "not_run"
        _string(part["detector"], f"{p}.{name}.detector", nullable=not ran)
        _string(part["frame_id"], f"{p}.{name}.frame_id", nullable=not ran or part["status"] == "unusable_input")
    if h["status"] != "not_run":
        _require(h["frame_id"] in steady or h["frame_id"] == hero, p + ".horizon.frame_id", "not a normally tracked frame of this scan")
    if lens["frame_id"] is not None:
        _require(lens["frame_id"] == hero, p + ".lens.frame_id", "the lens is checked on this scan's hero frame")
    reflection = _object(e["reflection"], p + ".reflection", "status frames_checked hits detector")
    _enum(reflection["status"], ("none_found", "suspected", "undetermined", "not_run"), p + ".reflection.status")
    for key in ("frames_checked", "hits"):
        _number(reflection[key], p + ".reflection." + key, low=0, integer=True)
    ran = reflection["status"] != "not_run"
    _string(reflection["detector"], p + ".reflection.detector", nullable=not ran)
    _require(ran == (reflection["frames_checked"] > 0), p + ".reflection", "a check that ran looked at frames; one that did not, did not")
    _require((reflection["status"] == "suspected") == (reflection["hits"] > 0), p + ".reflection", "hits and status disagree")


def _evidence(r, v2=False):
    for key in ("location", "target", "capture_session", "visibility"):
        _require(r[key] is not None, "$.'" + key + "'", "analysis-ready record requires input evidence")
    _require(r["location"]["lat"] is not None and r["location"]["lon"] is not None, "$.location", "coordinates required")
    t = r["target"]
    _require(t["height_m"] is not None and t["confirmed_by"] == "user", "$.target", "user-confirmed target height required")
    s = r["capture_session"]
    _require(s["viewpoint_lock"]["handling"] != "rejected", "$.capture_session.viewpoint_lock", "rejected viewpoint")
    usable = {f["frame_id"] for f in s["frames"] if f["used_for_visibility"] and f["tracking_state"] == "normal" and f["lens_offset_m"] is not None
              and (v2 or f["mask_ref"] is not None)}
    _require(bool(usable), "$.capture_session.frames", "no usable visibility frame evidence")
    if v2:
        _require(any(k["frame_id"] in usable for k in s["keyframes"]), "$.capture_session.keyframes", "no keyframe mask to check the grid against")
    n = r["north"]["resolved"]
    _require(n is not None and n["conflict"] is False and bool(n["groups_used"]), "$.north.resolved", "unresolved or conflicting north")
    groups = {c["group"] for c in r["north"]["candidates"] if c["valid"]}
    _require(set(n["groups_used"]) <= groups, "$.north", "resolved north has no matching valid candidate evidence")
    v = r["visibility"]
    _require(all(v[key] is not None for key in (("states", "confidence") if v2 else ("states_ref", "confidence_ref"))), "$.visibility", "visibility assets required")
    _require(v["coverage"]["corridor_cells"] > 0 and v["coverage"]["covered_cells"] > 0, "$.visibility.coverage", "empty visibility evidence")
    _require(v["segmentation"] is not None and v["segmentation"]["model"] is not None, "$.visibility.segmentation", "segmentation provenance required")


def validate(record):
    """Validate in place without modifying or dropping any source fields."""
    _walk(record)
    r = _object(record, "$", _ROOT)
    _enum(r["schema_version"], ("0.1.0", "0.2.0"), "$.schema_version")
    v2 = r["schema_version"] == "0.2.0"
    if v2:
        _object(record, "$", "result")
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
        _capture(r["capture_session"], v2)
    session = r["capture_session"]
    frames = {f["frame_id"] for f in session["frames"]} if session is not None else set()
    _north(r["north"], frames if v2 else None)
    if r["visibility"] is not None:
        _visibility(r["visibility"], v2, sum(1 for f in session["frames"] if f["used_for_visibility"]) if session is not None else 0)
    if r["geometry"] is not None:
        _geometry(r["geometry"])
    a = _array(r["analysis"], "$.analysis")
    q = _object(r["quality"], "$.quality", "level gates flags false_valid_guard blocked_reason" + (" evidence" if v2 else ""))
    result = _result(r) if v2 else None
    if v2:
        steady = {f["frame_id"] for f in session["frames"] if f["tracking_state"] == "normal" and f["role"] == "visibility"} if session is not None else set()
        hero = session["hero_frame"]["frame_id"] if session is not None and session["hero_frame"] is not None else None
        _quality_evidence(q["evidence"], steady, hero)
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
        _evidence(r, v2)
    _analysis(a, result)
    sh = _object(r["sharing"], "$.sharing", "include_hero precise_address revoked revoked_at")
    for key in ("include_hero", "precise_address", "revoked"):
        _bool(sh[key], "$.sharing." + key)
    _require(not sh["revoked"] or sh["revoked_at"] is not None, "$.sharing.revoked_at", "revocation requires timestamp")
    _object(r["context"], "$.context", "address_estimate")
    # Last, once the shape is known to be sound: the stated lights must be the ones the evidence gives (R08).
    from . import quality   # imported here because quality builds on this module's error type
    quality.check(r)


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
    parser = argparse.ArgumentParser(description="Validate a SceneRecord (0.1.0 or 0.2.0) and emit normalized JSON. No asset or field validation.")
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
