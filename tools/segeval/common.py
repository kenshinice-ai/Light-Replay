"""Spool frames as arrays, upright, with the geometry experiment 1 needs (docs/07 §5a).

A frame is read from the pulled app data: `<pull>/LightSpool/<session>/` plus the scene record that names the session.
Everything is returned upright (the way the buyer held the phone), because that is how a person labels a picture and
how the segmenter should see it. Nothing here writes into the repository: the data root is outside it.
"""
import hashlib
import json
import math
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image

DATA = os.path.expanduser(os.environ.get("PR_FIELD", "~/Library/Application Support/propertyreplay-field"))
PULL = os.path.join(DATA, "2026-10-09-iphone")
RECORDS = [os.path.join(DATA, "2026-10-05-iphone-records"), os.path.join(DATA, "2026-10-09-iphone-records")]
WORK = os.path.join(DATA, "exp1")


def records():
    """scene_id → record, for every pulled Light scan."""
    out = {}
    for folder in RECORDS:
        for name in sorted(os.listdir(folder)):
            if name.endswith(".json"):
                record = json.load(open(os.path.join(folder, name)))
                out[record["scene_id"]] = record
    return out


def spool(record):
    session = record["capture_session"]["session_id"]
    folder = os.path.join(PULL, "LightSpool", session)
    return folder, json.load(open(os.path.join(folder, "manifest.json")))


def planes(record):
    """The surfaces ARKit labelled during the scan (docs/04 §12), or None for a spool from before they were kept."""
    return spool(record)[1].get("planes")


def quarter_turns(record):
    """How many clockwise quarter turns make the native (landscape) picture upright."""
    hero = (record["capture_session"].get("hero_frame") or {}).get("image") or {}
    return int(hero.get("rotation_deg", 0)) // 90 % 4


def upright(array, turns):
    return np.rot90(array, k=-turns) if turns else array


def _depth(path, width, height):
    out = tempfile.mktemp()
    subprocess.run(["compression_tool", "-decode", "-a", "lzfse", "-i", path, "-o", out], check=True)
    raw = open(out, "rb").read()
    os.remove(out)
    n = width * height
    assert len(raw) == n * 3, "depth file has the wrong length"
    metres = np.frombuffer(raw[: n * 2], dtype=np.float16).astype(np.float32).reshape(height, width)
    confidence = np.frombuffer(raw[n * 2:], dtype=np.uint8).reshape(height, width)
    return metres, confidence


class Frame:
    """One spooled frame, upright. `rgb` is H×W×3 uint8; `alt` and `az` are degrees per pixel in the AR frame;
    `depth` (metres) and `conf` (0 low, 1 medium, 2 high) are the LiDAR map resampled to the picture, nearest."""

    def __init__(self, record, entry, folder=None):
        self.scene = record["scene_id"]
        self.id = entry["frameID"]
        self.key = f"{self.scene}_{self.id}"
        self.entry = entry
        self.turns = quarter_turns(record)
        folder = folder or spool(record)[0]
        image = entry["image"]
        native = np.asarray(Image.open(os.path.join(folder, image["file"])).convert("RGB"))
        h, w = native.shape[:2]
        scale = image.get("scale", 1.0)
        k, m = entry["intrinsics"], entry["cameraTransform"]
        fx, fy, cx, cy = k[0] * scale, k[4] * scale, k[6] * scale, k[7] * scale
        u, v = np.meshgrid(np.arange(w) + 0.5, np.arange(h) + 0.5)
        x, y, z = (u - cx) / fx, -(v - cy) / fy, -np.ones_like(u)
        rx, ry, rz = np.array(m[0:3]), np.array(m[4:7]), np.array(m[8:11])
        world = x[..., None] * rx + y[..., None] * ry + z[..., None] * rz
        world /= np.linalg.norm(world, axis=-1, keepdims=True)
        alt = np.degrees(np.arcsin(np.clip(world[..., 1], -1, 1)))
        az = np.degrees(np.arctan2(world[..., 0], -world[..., 2])) % 360
        depth = conf = None
        if entry.get("depth"):
            d = entry["depth"]
            metres, confidence = _depth(os.path.join(folder, d["file"]), d["width"], d["height"])
            rows = np.minimum((np.arange(h) * d["height"] / h).astype(int), d["height"] - 1)
            cols = np.minimum((np.arange(w) * d["width"] / w).astype(int), d["width"] - 1)
            depth, conf = metres[np.ix_(rows, cols)], confidence[np.ix_(rows, cols)]
        self.rgb = upright(native, self.turns)
        self.alt, self.az = upright(alt, self.turns), upright(az, self.turns)
        self.depth = None if depth is None else upright(depth, self.turns)
        self.conf = None if conf is None else upright(conf, self.turns)
        forward = -rz
        self.camera_alt = math.degrees(math.asin(max(-1, min(1, forward[1]))))
        self.offset_m = entry.get("lensOffsetM") or 0.0

    @property
    def shape(self):
        return self.rgb.shape[:2]


def frame(key, _cache={}):
    """`PR-20261005-03_f00252` → Frame."""
    scene, frame_id = key.rsplit("_", 1)
    if "records" not in _cache:
        _cache["records"] = records()
    record = _cache["records"][scene]
    folder, manifest = spool(record)
    entry = next(e for e in manifest["frames"] if e["frameID"] == frame_id)
    return Frame(record, entry, folder)


def stable_number(text):
    """A number from a name, the same on every run and machine (for reproducible picks)."""
    return int(hashlib.sha256(text.encode()).hexdigest()[:12], 16)
