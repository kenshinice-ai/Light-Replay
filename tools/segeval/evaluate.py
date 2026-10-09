#!/usr/bin/env python3
"""Scores the segmentation paths of experiment 1 against the labelled frames.

    python3 tools/segeval/evaluate.py [development|held_back|all]

Per frame and method it counts, over the pixels a person could call (truth 0–4): hits, misses and false sky; the
same inside the all-year sun corridor (the record's compass Δ places it); and how much of the translucent roofing,
of the reflections and of the glass nobody could call was given as sky. Results go to <data>/exp1/results-<split>.json.
"""
import datetime
import json
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "engine"))
import common
import label
import methods
from lightreplay import bands

METHODS = ("appearance", "depth", "heuristic", "vision")


def corridor_pixels(frame, record, _cache={}):
    """True where the pixel's direction lies in the all-year sun corridor, in the capture's own AR frame."""
    scene = record["scene_id"]
    if scene not in _cache:
        candidate = next(c for c in record["north"]["candidates"] if c.get("valid"))
        year = datetime.datetime.fromisoformat(record["capture_session"]["started_at"]).year
        lat, lon = record["location"]["lat"], record["location"]["lon"]
        _cache[scene] = np.array(bands.SunCorridor(bands.corridor_days("allYear", year, lat), lat, lon, record["timezone"],
                                                   candidate["yaw_deg"]).cells).reshape(bands.ALT_CELLS, bands.AZ_CELLS)
    cells = _cache[scene]
    alt = np.floor(frame.alt - bands.MIN_ALT_DEG).astype(int)
    az = np.floor(frame.az).astype(int) % bands.AZ_CELLS
    ok = (alt >= 0) & (alt < bands.ALT_CELLS)
    out = np.zeros(frame.shape, dtype=bool)
    out[ok] = cells[alt[ok], az[ok]]
    return out


def score(mask, truth, corridor):
    sky = (truth == 1) | (truth == 2)
    callable_ = truth <= 4
    not_sky = callable_ & ~sky
    count = lambda m: int(m.sum())  # noqa: E731
    return {
        "hit": count(mask & sky), "miss": count(~mask & sky), "false": count(mask & not_sky), "not_sky": count(not_sky),
        "c_hit": count(mask & sky & corridor), "c_miss": count(~mask & sky & corridor),
        "c_false": count(mask & not_sky & corridor), "c_not_sky": count(not_sky & corridor),
        "glass_hit": count(mask & (truth == 2)), "glass": count(truth == 2),
        "open_hit": count(mask & (truth == 1)), "open": count(truth == 1),
        "translucent_as_sky": count(mask & (truth == 3)), "translucent": count(truth == 3),
        "reflection_as_sky": count(mask & (truth == 4)), "reflection": count(truth == 4),
        "unsure_as_sky": count(mask & (truth == 5)), "unsure": count(truth == 5),
        "pixels": int(truth.size),
    }


def main(split):
    plan = json.load(open(os.path.join(common.WORK, "frames.json")))["frames"]
    frames = [f for f in plan if split == "all" or f["split"] == split]
    records = common.records()
    workdir = os.path.join(common.WORK, "vision-" + split)
    os.makedirs(workdir, exist_ok=True)
    rows = []
    for item in frames:
        frame = common.frame(item["key"])
        truth = np.asarray(Image.open(os.path.join(label.TRUTH, item["key"] + ".png")))
        corridor = corridor_pixels(frame, records[item["scene"]])
        row = dict(item, methods={})
        for name in METHODS:
            started = time.time()
            if name == "vision":
                mask, seconds, note = methods.vision_above_horizon(frame, workdir=workdir)
            else:
                mask, note = getattr(methods, name)(frame), ""
                seconds = time.time() - started
            row["methods"][name] = dict(score(mask, truth, corridor), seconds=round(seconds, 3), note=note)
            Image.fromarray((mask * 255).astype(np.uint8)).save(os.path.join(workdir, f"{item['key']}.{name}.png"))
        rows.append(row)
        print(item["key"], {n: row["methods"][n]["hit"] + row["methods"][n]["false"] for n in METHODS}, row["methods"]["vision"]["note"])
    json.dump(rows, open(os.path.join(common.WORK, f"results-{split}.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "development")
