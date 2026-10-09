"""Writes tests/fixtures/scene-v2-cases.json: schema 0.2.0 records, one change each, and the verdict each must get.

Shared by the Python and Swift tests so both hold the same line (ADR-0022, docs/03 §11, docs/04 §6, docs/05 §2a,
reviews R01–R08 and V2-01…V2-06). What each case expects is written here by hand from the documents; the script
refuses to write a fixture the reference implementation disagrees with. All synthetic.
Run from engine/: python3 scripts/make_v2_fixture.py
"""

import base64
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

ENGINE = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ENGINE), str(ENGINE / "tests"), str(ENGINE / "scripts")]
from lightreplay import quality, scenerecord  # noqa: E402
from make_quality_fixture import apply, candidate, resolved_for  # noqa: E402
from test_scenerecord import fixture, ready_record  # noqa: E402

WIDTH, HEIGHT = 360, 100


def deflated(raw):
    packer = zlib.compressobj(9, zlib.DEFLATED, -15)   # raw DEFLATE, RFC 1951: what Apple's Compression calls ZLIB
    return packer.compress(raw) + packer.flush()


def payload(raw, width, height, encoding="deflate+base64"):
    body = deflated(raw) if encoding == "deflate+base64" else raw
    return {"encoding": encoding, "width": width, "height": height, "byte_count": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(), "data": base64.b64encode(body).decode("ascii")}


def grid(state_at):
    """Row-major from the lowest altitude (-10 degrees), azimuth 0 first."""
    return bytes(state_at(az, row - 10) for row in range(HEIGHT) for az in range(WIDTH))


def synthetic_states(az, alt):
    if 150 <= az < 210:
        return 0                      # behind the buyer: never scanned
    if alt < 12:
        return 2                      # a skyline of roofs
    if 20 <= az < 40 and alt < 35:
        return 3                      # a neighbour's glass front
    return 1


def png(width, height, depth=1, colour=0, rows=None):
    """A valid greyscale PNG, all zero: the smallest honest stand-in for a keyframe mask. `rows` overrides the pixel
    data, for the cases that must be wrong."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    if rows is None:
        rows = b"".join(b"\x00" + bytes((width * depth + 7) // 8) for _ in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, colour, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


STATES = grid(synthetic_states)
CONFIDENCE = grid(lambda az, alt: 0 if synthetic_states(az, alt) == 0 else 200)
CELLS = {name: STATES.count(bytes([state])) for state, name in enumerate(("unknown", "sky", "blocked", "glass"))}
MASK = png(96, 72)
#: Review A03's probe: 24 bytes that start like a PNG and claim ten billion pixels.
HEADER_ONLY = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 100000, 100000)
NO_HORIZON = {"status": "not_found", "residual_deg": None, "confidence": None, "frame_id": "synthetic-frame-001", "detector": "synthetic-test-only"}
NOT_RUN = {"rules": "quality-0.2",
           "horizon": {"status": "not_run", "residual_deg": None, "confidence": None, "frame_id": None, "detector": None},
           "lens": {"status": "not_run", "smudge_confidence": None, "frame_id": None, "detector": None},
           "reflection": {"status": "not_run", "frames_checked": 0, "hits": 0, "detector": None}}
SUN_EVIDENCE = {"rules": "sundisk-0.1", "frame_id": "synthetic-frame-006", "time": "2026-09-21T10:42:10+10:00",
                "altitude_measured_deg": 41.2, "altitude_expected_deg": 41.6, "azimuth_expected_deg": 38.0,
                "depth_m": None, "sky_ring_fraction": 0.9, "user_confirmed": True, "tracking_continuous": True}


def frame(base, number, t, **overrides):
    f = copy.deepcopy(base)
    f.update(frame_id=f"synthetic-frame-{number:03d}", t=t, role="visibility", used_for_visibility=False, mask_ref=None)
    f.update(overrides)
    return f


def saved():
    """A 0.2.0 record as it is written at Save: nothing analysed, every check still to run."""
    r = fixture()
    r["schema_version"] = "0.2.0"
    r["result"] = {"revision": 0, "capture_digest": "synthetic-capture-digest", "north_digest": "synthetic-north-digest",
                   "inputs_hash": None, "computed_at": None}
    r["capture_session"]["hero_frame"].update(image_ref=None, image=None)
    r["capture_session"]["frames"][0]["role"] = "visibility"
    r["capture_session"]["keyframes"] = []
    r["quality"]["evidence"] = copy.deepcopy(NOT_RUN)
    r["quality"]["gates"] = {"coverage": "blocked", "north": "blocked", "segmentation": "blocked", "level": "blocked", "lens": "blocked"}
    return r


def analysed():
    """A 0.2.0 record after analysis: grid and masks inside it, a sun-disk confirmation beside the compass, R1."""
    r = ready_record()
    r["schema_version"] = "0.2.0"
    base = r["capture_session"]["frames"][0]
    r["capture_session"]["frames"] = [frame(base, n, 1.0 + 0.1 * (n - 1), used_for_visibility=n <= 4) for n in range(1, 6)] \
        + [frame(base, 6, 9.0, role="calibration")]
    r["capture_session"]["keyframes"] = [{"frame_id": "synthetic-frame-001", "mask": payload(MASK, 96, 72, "png+base64")}]
    r["capture_session"]["hero_frame"].update(image_ref=None, image={
        "storage": "row.photo", "native_size": [4032, 3024], "encoded_size": [2048, 1536], "scale": 2048 / 4032,
        "crop": [0, 0, 4032, 3024], "rotation_deg": 0, "byte_count": 1022817, "sha256": "synthetic-hero-hash"})
    candidates = [dict(candidate("magnetic", 2.0, 13.0), raw=r["north"]["candidates"][0]["raw"]),
                  dict(candidate("solar", 0.0, 2.0), source="sun_disk", evidence=copy.deepcopy(SUN_EVIDENCE))]
    r["north"] = {"candidates": candidates, "resolved": resolved_for(candidates)}
    r["visibility"] = {
        "grid": {"az_step_deg": 1, "alt_step_deg": 1, "az_frame": "ar_world", "alt_range": [-10, 90]},
        "states": payload(STATES, WIDTH, HEIGHT), "confidence": payload(CONFIDENCE, WIDTH, HEIGHT),
        "votes": {"frames_used": 4, "min_distinct_frames": 3, "cells": CELLS},
        "coverage": {"corridor_cells": 100, "unknown_cells": 4, "glass_cells": 6, "covered_cells": 96, "coverage_pct": 0.96},
        "segmentation": {"model": "synthetic-test-only", "glass_detected": True, "reflection_flags": [], "manual_edits": []},
        "near_field": None}
    r["result"] = {"revision": 1, "capture_digest": "synthetic-capture-digest", "north_digest": "synthetic-north-digest-2",
                   "inputs_hash": "synthetic-inputs-hash", "computed_at": "2026-09-21T10:42:40+10:00"}
    r["analysis"] = [{
        "query": {"date_from": "2027-06-21", "date_to": "2027-06-21", "time_window": ["07:30", "17:10"],
                  "scenario": "current", "representative": True},
        "bands": [{"date": "2027-06-21", "segments": [
            {"from": "07:30", "to": "10:30", "state": "blocked"}, {"from": "10:30", "to": "10:55", "state": "sensitive"},
            {"from": "10:55", "to": "13:50", "state": "direct"}, {"from": "13:50", "to": "14:15", "state": "sensitive"},
            {"from": "14:15", "to": "15:40", "state": "blocked"}, {"from": "15:40", "to": "17:10", "state": "unknown"}]}],
        "totals": {"direct_min": 175, "sensitive_min": 50, "blocked_min": 265, "unknown_min": 90},
        "heatmap_ref": None, "attribution": [], "revision": 1,
        "uncertainty": {"yaw_sigma_deg": 2, "samples": 64, "boundary_jitter_deg": 1},
        "versions": {"inputs_hash": "synthetic-inputs-hash", "sun": "synthetic-test-only"},
        "computed_at": "2026-09-21T10:42:40+10:00"}]
    r["quality"]["evidence"] = {
        "rules": "quality-0.2",
        "horizon": {"status": "measured", "residual_deg": 0.6, "confidence": 0.9, "frame_id": "synthetic-frame-001", "detector": "synthetic-test-only"},
        "lens": {"status": "measured", "smudge_confidence": 0.1, "frame_id": "synthetic-hero", "detector": "synthetic-test-only"},
        "reflection": {"status": "none_found", "frames_checked": 3, "hits": 0, "detector": "synthetic-test-only"}}
    r["quality"]["gates"] = dict(READY)
    return r


READY = {"coverage": "pass", "north": "warn", "segmentation": "pass", "level": "pass", "lens": "pass"}
SEGMENTS = analysed()["analysis"][0]["bands"][0]["segments"]
SAVED = {"coverage": "blocked", "north": "blocked", "segmentation": "blocked", "level": "blocked", "lens": "blocked"}
COMPASS_ONLY = [dict(candidate("magnetic", 2.0, 13.0))]
MIRRORED = [dict(candidate("magnetic", 0.0, 13.0)), dict(candidate("solar", 330.0, 2.0), source="sun_disk", evidence=SUN_EVIDENCE)]
LIMITED = [["capture_session.frames.2.tracking_state", "limited:excessive_motion"], ["capture_session.frames.2.used_for_visibility", False],
           ["visibility.votes.frames_used", 3]]
#: Analysis ran and the record is still R0: the direction never got past the compass. A normal ending, not a failure.
STILL_R0 = [["north.candidates", COMPASS_ONLY], ["north.resolved", None], ["analysis", []],
            ["quality.gates.north", "blocked"], ["quality.level", "R0"], ["quality.false_valid_guard", "blocked"],
            ["quality.blocked_reason", "direction rests on the compass alone"]]

# name, base, changes, accepted, path of the refusal, the lights the evidence gives
CASES = [
    ("saved_before_analysis", "saved", [], True, None, SAVED),
    ("analysed_r1", "analysed", [], True, None, READY),
    ("analysed_but_direction_is_compass_only", "analysed", STILL_R0, True, None, dict(READY, north="blocked")),

    # Inline payloads say how long they are and what they hash to; the validator checks both (ADR-0022).
    ("grid_hash_is_not_the_grids", "analysed", [["visibility.states.sha256", "0" * 64]], False, "$.visibility.states.sha256", READY),
    ("grid_length_is_not_the_grids", "analysed", [["visibility.states.byte_count", 35999]], False, "$.visibility.states.byte_count", READY),
    ("grid_is_not_the_size_of_the_grid", "analysed", [["visibility.states", payload(STATES[:3600], 360, 10)]], False, "$.visibility.states", READY),
    ("grid_with_an_unknown_state", "analysed", [["visibility.states", payload(STATES[:-1] + b"\x07", WIDTH, HEIGHT)]], False, "$.visibility.states", READY),
    ("cell_counts_are_not_the_grids", "analysed", [["visibility.votes.cells.sky", CELLS["sky"] + 1]], False, "$.visibility.votes.cells", READY),
    ("payload_that_inflates_past_its_stated_length", "analysed",
     [["visibility.confidence.data", base64.b64encode(deflated(bytes(2_000_000))).decode("ascii")]], False, "$.visibility.confidence.data", READY),
    ("payload_larger_than_the_limit", "analysed", [["visibility.states.byte_count", 70000]], False, "$.visibility.states.byte_count", READY),
    ("payload_that_is_not_base64", "analysed", [["visibility.states.data", "not base64!"]], False, "$.visibility.states.data", READY),
    ("states_without_confidence", "analysed", [["visibility.confidence", None]], False, "$.visibility", READY),
    # The grid rests on the frames the record says were used (review A04).
    ("grid_resting_on_no_frames", "analysed", [["visibility.votes.frames_used", 0]], False, "$.visibility.votes.frames_used", READY),
    ("more_frames_claimed_than_used", "analysed", [["visibility.votes.frames_used", 9]], False, "$.visibility.votes.frames_used", READY),
    ("fewer_frames_than_the_minimum", "analysed",
     [["capture_session.frames.3.used_for_visibility", False], ["capture_session.frames.2.used_for_visibility", False], ["visibility.votes.frames_used", 2]],
     False, "$.visibility.votes.frames_used", READY),

    # Keyframe masks: a few, each one of the frames that went into the grid.
    ("keyframe_that_is_not_a_frame", "analysed", [["capture_session.keyframes.0.frame_id", "synthetic-frame-099"]],
     False, "$.capture_session.keyframes[0].frame_id", READY),
    ("keyframe_that_was_not_used", "analysed", [["capture_session.keyframes.0.frame_id", "synthetic-frame-005"]],
     False, "$.capture_session.keyframes[0].frame_id", READY),
    ("mask_that_is_not_a_png", "analysed", [["capture_session.keyframes.0.mask", payload(b"GIF89a" + bytes(40), 96, 72, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask.data", READY),
    ("mask_of_another_size", "analysed", [["capture_session.keyframes.0.mask.width", 97]], False, "$.capture_session.keyframes[0].mask", READY),
    ("r1_without_a_keyframe_mask", "analysed", [["capture_session.keyframes", []]], False, "$.capture_session.keyframes", READY),
    # A mask has to be a whole PNG that decodes within bounds, not a header that says so (review A03).
    ("mask_that_is_only_a_header", "analysed", [["capture_session.keyframes.0.mask", payload(HEADER_ONLY, 100000, 100000, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask.data", READY),
    ("mask_claiming_ten_billion_pixels", "analysed", [["capture_session.keyframes.0.mask", payload(png(100000, 100000, rows=b""), 100000, 100000, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask", READY),
    ("mask_with_a_damaged_chunk", "analysed", [["capture_session.keyframes.0.mask", payload(MASK[:40] + bytes([MASK[40] ^ 1]) + MASK[41:], 96, 72, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask.data", READY),
    ("mask_cut_short", "analysed", [["capture_session.keyframes.0.mask", payload(MASK[:-12], 96, 72, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask.data", READY),
    ("mask_with_too_few_rows", "analysed", [["capture_session.keyframes.0.mask", payload(png(96, 72, rows=bytes(13 * 10)), 96, 72, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask.data", READY),
    ("mask_in_colour", "analysed", [["capture_session.keyframes.0.mask", payload(png(96, 72, colour=2, depth=8, rows=bytes((1 + 96 * 3) * 72)), 96, 72, "png+base64")]],
     False, "$.capture_session.keyframes[0].mask.data", READY),
    ("mask_eight_bits_deep", "analysed", [["capture_session.keyframes.0.mask", payload(png(96, 72, depth=8), 96, 72, "png+base64")]], True, None, READY),

    # The hero's pixels are a scaled copy of the sensor image; the chain has to add up (review R01).
    ("hero_scale_that_does_not_give_its_size", "analysed", [["capture_session.hero_frame.image.scale", 0.25]],
     False, "$.capture_session.hero_frame.image.encoded_size", READY),
    ("hero_rotated_a_quarter_turn", "analysed", [["capture_session.hero_frame.image.rotation_deg", 90],
                                                 ["capture_session.hero_frame.image.encoded_size", [1536, 2048]]], True, None, READY),
    ("hero_crop_outside_the_sensor", "analysed", [["capture_session.hero_frame.image.crop", [0, 0, 5000, 3024]]],
     False, "$.capture_session.hero_frame.image.crop", READY),

    # Frames taken while confirming the direction are not evidence about this point's sky (review V2-02).
    ("calibration_frame_used_for_visibility", "analysed", [["capture_session.frames.5.used_for_visibility", True]],
     False, "$.capture_session.frames[5]", READY),

    # Tracking, read from the frames (quality-0.2): 0.5 s passes, 2 s warns, relocalizing blocks.
    ("limited_for_a_tenth_of_a_second", "analysed", LIMITED, True, None, READY),
    ("limited_for_a_second_stated_pass", "analysed", LIMITED + [["capture_session.frames.3.t", 2.2], ["capture_session.frames.4.t", 2.3]],
     False, "$.quality.gates.level", dict(READY, level="warn")),
    ("limited_for_a_second_stated_warn", "analysed",
     LIMITED + [["capture_session.frames.3.t", 2.2], ["capture_session.frames.4.t", 2.3], ["quality.gates.level", "warn"]],
     True, None, dict(READY, level="warn")),
    ("limited_for_three_seconds", "analysed",
     LIMITED + [["capture_session.frames.3.t", 4.2], ["capture_session.frames.4.t", 4.3], ["quality.gates.level", "warn"]],
     False, "$.quality.gates.level", dict(READY, level="blocked")),
    ("relocalized_during_the_scan", "analysed",
     [["capture_session.frames.2.tracking_state", "limited:relocalizing"], ["capture_session.frames.2.used_for_visibility", False],
      ["visibility.votes.frames_used", 3]],
     False, "$.quality.gates.level", dict(READY, level="blocked")),
    ("limited_while_walking_to_the_sun_is_not_the_scan", "analysed",
     [["capture_session.frames.5.tracking_state", "limited:excessive_motion"]], True, None, READY),

    # Horizon against gravity: no horizon in view is not held against an indoor scan; not looking is.
    ("no_horizon_in_view", "analysed", [["quality.evidence.horizon", NO_HORIZON]], True, None, READY),
    ("no_horizon_without_saying_where_it_looked", "analysed", [["quality.evidence.horizon", dict(NOT_RUN["horizon"], status="not_found")]],
     False, "$.quality.evidence.horizon.detector", READY),
    # The evidence has to be about this capture (review A01).
    ("horizon_checked_on_a_frame_that_is_not_here", "analysed", [["quality.evidence.horizon.frame_id", "nonexistent-frame"]],
     False, "$.quality.evidence.horizon.frame_id", READY),
    ("horizon_checked_on_a_calibration_frame", "analysed", [["quality.evidence.horizon.frame_id", "synthetic-frame-006"]],
     False, "$.quality.evidence.horizon.frame_id", READY),
    ("horizon_checked_on_the_hero", "analysed", [["quality.evidence.horizon.frame_id", "synthetic-hero"]], True, None, READY),
    ("lens_checked_on_another_scan", "analysed", [["quality.evidence.lens.frame_id", "another-scan"]],
     False, "$.quality.evidence.lens.frame_id", READY),
    ("lens_checked_on_a_sweeping_frame", "analysed", [["quality.evidence.lens.frame_id", "synthetic-frame-002"]],
     False, "$.quality.evidence.lens.frame_id", READY),
    ("horizon_three_degrees_off", "analysed", [["quality.evidence.horizon.residual_deg", 3.0], ["quality.gates.level", "warn"]],
     True, None, dict(READY, level="warn")),
    ("horizon_six_degrees_off_stated_pass", "analysed", [["quality.evidence.horizon.residual_deg", 6.0]],
     False, "$.quality.gates.level", dict(READY, level="blocked")),
    ("horizon_not_checked", "analysed", [["quality.evidence.horizon", NOT_RUN["horizon"]]],
     False, "$.quality.gates.level", dict(READY, level="blocked")),

    # Lens: the detector's confidence, or nothing.
    ("lens_smudge_045_stated_warn", "analysed", [["quality.evidence.lens.smudge_confidence", 0.45], ["quality.gates.lens", "warn"]],
     True, None, dict(READY, lens="warn")),
    ("lens_smudge_07_stated_pass", "analysed", [["quality.evidence.lens.smudge_confidence", 0.7]],
     False, "$.quality.gates.lens", dict(READY, lens="blocked")),
    ("lens_not_checked_stated_pass", "analysed", [["quality.evidence.lens", NOT_RUN["lens"]]],
     False, "$.quality.gates.lens", dict(READY, lens="blocked")),
    ("lens_check_had_no_steady_frame", "analysed",
     [["quality.evidence.lens", dict(NOT_RUN["lens"], status="unusable_input", detector="synthetic-test-only")]],
     False, "$.quality.gates.lens", dict(READY, lens="blocked")),

    # Reflections: not looking blocks; looking and not being sure warns; finding none lets the glass share stand.
    ("reflections_not_checked", "analysed", [["quality.evidence.reflection", NOT_RUN["reflection"]]],
     False, "$.quality.gates.segmentation", dict(READY, segmentation="blocked")),
    ("reflections_could_not_be_ruled_out", "analysed",
     [["quality.evidence.reflection.status", "undetermined"], ["quality.gates.segmentation", "warn"]], True, None, dict(READY, segmentation="warn")),
    ("reflections_suspected_stated_pass", "analysed",
     [["quality.evidence.reflection.status", "suspected"], ["quality.evidence.reflection.hits", 2]],
     False, "$.quality.gates.segmentation", dict(READY, segmentation="warn")),
    ("hits_without_suspicion", "analysed", [["quality.evidence.reflection.hits", 2]], False, "$.quality.evidence.reflection", READY),

    # Sun disk (sundisk-0.1): the altitude has to match, and that alone is not enough (review V2-01).
    ("sun_two_degrees_off_its_altitude", "analysed", [["north.candidates.1.evidence.altitude_measured_deg", 43.7]],
     False, "$.north.candidates[1]", READY),
    ("a_surface_at_the_bright_spot", "analysed", [["north.candidates.1.evidence.depth_m", 2.4]], False, "$.north.candidates[1]", READY),
    ("bright_spot_not_surrounded_by_sky", "analysed", [["north.candidates.1.evidence.sky_ring_fraction", 0.2]],
     False, "$.north.candidates[1]", READY),
    ("nobody_confirmed_the_sun", "analysed", [["north.candidates.1.evidence.user_confirmed", False]], False, "$.north.candidates[1]", READY),
    ("tracking_broke_before_the_confirmation", "analysed", [["north.candidates.1.evidence.tracking_continuous", False]],
     False, "$.north.candidates[1]", READY),
    ("valid_sun_disk_without_evidence", "analysed", [["north.candidates.1.evidence", None]], False, "$.north.candidates[1].evidence", READY),
    ("sun_evidence_frame_is_not_a_frame", "analysed", [["north.candidates.1.evidence.frame_id", "synthetic-frame-099"]],
     False, "$.north.candidates[1].evidence.frame_id", READY),
    ("a_failed_confirmation_may_be_kept_as_invalid", "analysed",
     STILL_R0 + [["north.candidates", COMPASS_ONLY + [{"source": "sun_disk", "group": "solar", "yaw_deg": None, "sigma_deg": None,
                                                       "valid": False, "evidence": dict(SUN_EVIDENCE, depth_m=2.4)}]]],
     True, None, dict(READY, north="blocked")),
    # The reflection of review V2-01: same altitude, 30 degrees off, every stated check passed. The rules cannot see
    # it and the lights come out amber. Kept here so that nobody reads sundisk-0.1 as proof; experiment 2 measures it.
    ("a_mirror_at_the_suns_altitude_is_not_caught", "analysed", [["north.candidates", MIRRORED], ["north.resolved", resolved_for(MIRRORED)]],
     True, None, READY),

    # Which analysis a record carries.
    ("analysis_of_another_revision", "analysed", [["analysis.0.revision", 2]], False, "$.analysis[].revision", READY),
    ("analysis_of_other_inputs", "analysed", [["analysis.0.versions.inputs_hash", "another-hash"]], False, "$.analysis[].versions.inputs_hash", READY),
    ("unknown_minutes_counted_as_sun", "analysed", [["analysis.0.totals.direct_min", 265], ["analysis.0.totals.unknown_min", 0]],
     False, "$.analysis[].totals.direct_min", READY),
    # One timeline a day: no stretch counted twice, none left out, none outside the question (review A02).
    ("a_direct_stretch_counted_twice", "analysed",
     [["analysis.0.bands.0.segments", SEGMENTS[:3] + [SEGMENTS[2]] + SEGMENTS[3:]], ["analysis.0.totals.direct_min", 350]],
     False, "$.analysis[].bands[].segments[]", READY),
    ("direct_overlapping_unknown", "analysed", [["analysis.0.bands.0.segments.5.from", "15:00"], ["analysis.0.totals.unknown_min", 130]],
     False, "$.analysis[].bands[].segments[]", READY),
    ("a_missing_tail_instead_of_unknown", "analysed", [["analysis.0.bands.0.segments", SEGMENTS[:5]], ["analysis.0.totals.unknown_min", 0]],
     False, "$.analysis[].bands[].segments[]", READY),
    ("a_day_with_no_answer_at_all", "analysed",
     [["analysis.0.bands.0.segments", []], ["analysis.0.totals", {"direct_min": 0, "sensitive_min": 0, "blocked_min": 0, "unknown_min": 0}]],
     False, "$.analysis[].bands[].segments[]", READY),
    ("a_gap_in_the_middle", "analysed", [["analysis.0.bands.0.segments", SEGMENTS[:4] + SEGMENTS[5:]], ["analysis.0.totals.blocked_min", 180]],
     False, "$.analysis[].bands[].segments[]", READY),
    ("a_segment_after_the_window", "analysed", [["analysis.0.query.time_window", ["07:30", "17:00"]]],
     False, "$.analysis[].bands[].segments[]", READY),
    ("a_day_outside_the_query", "analysed", [["analysis.0.bands.0.date", "2027-06-22"]], False, "$.analysis[].bands[].date", READY),
    ("the_same_day_twice", "analysed",
     [["analysis.0.bands", [analysed()["analysis"][0]["bands"][0]] * 2], ["analysis.0.totals", {"direct_min": 350, "sensitive_min": 100, "blocked_min": 530, "unknown_min": 180}]],
     False, "$.analysis[].bands[].date", READY),
    ("analysed_without_an_inputs_hash", "analysed", [["result.inputs_hash", None]], False, "$.result", READY),
    ("never_analysed_but_carrying_a_grid", "analysed", STILL_R0 + [["result", saved()["result"]]], False, "$.result", dict(READY, north="blocked")),

    # 0.2.0 is not 0.1.0 with a new label.
    ("v2_without_evidence", "saved", [["quality", {k: v for k, v in saved()["quality"].items() if k != "evidence"}]], False, "$.quality", SAVED),
    ("v2_evidence_under_other_rules", "saved", [["quality.evidence.rules", "quality-0.1"]], False, "$.quality.evidence.rules", SAVED),
    ("v2_frame_without_a_role", "saved", [["capture_session.frames.0", {k: v for k, v in saved()["capture_session"]["frames"][0].items() if k != "role"}]],
     False, "$.capture_session.frames[0]", SAVED),
    ("saved_stating_a_light_nothing_checked", "saved", [["quality.gates.lens", "pass"]], False, "$.quality.gates.lens", SAVED),
]


def build():
    bases = {"saved": saved(), "analysed": analysed()}
    cases = []
    for name, base, changes, accepted, path, gates in CASES:
        record = apply(bases[base], changes)
        try:
            scenerecord.validate(record)
            outcome = None
        except scenerecord.ValidationError as error:
            outcome = str(error).split(": ", 1)[0]
        assert (outcome is None) == accepted and outcome == path, f"{name}: reference says {outcome!r}"
        try:
            given = quality.evaluate(record)["gates"]
        except (KeyError, TypeError):
            given = gates   # a record too malformed to evaluate is refused on shape; its lights are not the point
        assert given == gates, f"{name}: reference gives {given}"
        cases.append({"name": name, "base": base, "set": changes, "accepted": accepted, "error_path": path, "gates": gates})
    return {"note": "Synthetic 0.2.0 records and the verdict each must get (engine/scripts/make_v2_fixture.py). "
                    "Expectations are written by hand from ADR-0022, docs/03 §11, docs/04 §6 and docs/05 §2a.",
            "version": quality.VERSION_2, "bases": bases, "cases": cases}


def main():
    out = ENGINE / "tests" / "fixtures" / "scene-v2-cases.json"
    data = build()
    compact = {"separators": (",", ":")}
    bases = ",\n".join(f"  {json.dumps(name)}:{json.dumps(record, **compact)}" for name, record in data["bases"].items())
    cases = ",\n".join("  " + json.dumps(case, **compact) for case in data["cases"])   # one case a line
    head = ",\n".join(f"{json.dumps(key)}:{json.dumps(data[key])}" for key in ("note", "version"))
    out.write_text(f'{{{head},\n"bases":{{\n{bases}\n}},\n"cases":[\n{cases}\n]}}\n', encoding="utf-8")
    print(f"wrote {out} ({len(CASES)} cases, {out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
