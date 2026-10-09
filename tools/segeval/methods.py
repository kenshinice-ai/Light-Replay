"""The segmentation paths compared in experiment 1 (docs/07 §5a). Each takes a `common.Frame` and returns a boolean
"this pixel is sky" mask of the frame's upright shape.

  appearance   colour alone, above the horizon: blue, or bright and nearly grey. What a camera without depth can do.
  depth        the depth map alone, above the horizon: nothing within FAR metres.
  heuristic    both: far in the depth map, and not coloured like a leaf or a wall. No Vision.
  vision       Vision's iterative segmentation, seeded from the heuristic's largest regions, with LiDAR-near points
               as exclusions.

Every number here was chosen on the development clips only (select_frames.py); the held-back clips are scored once.
"""
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image

from label import blue_excess, luminance

FAR_M = 15.0          # ARKit's scene depth reads about 24 m where nothing answers; real surfaces in view are under 10
HORIZON_DEG = 0.0
BRIGHT, GREY_SPREAD, BLUE = 150.0, 60.0, 12.0
SEGSMOKE = os.path.expanduser("~/Library/Caches/propertyreplay/spm-segsmoke/release/segsmoke")


def sky_coloured(rgb, bright=BRIGHT):
    rgb = rgb.astype(np.float32)
    spread = rgb.max(axis=-1) - rgb.min(axis=-1)
    return (blue_excess(rgb) >= BLUE) | ((luminance(rgb) >= bright) & (spread <= GREY_SPREAD))


def appearance(frame):
    return (frame.alt > HORIZON_DEG) & sky_coloured(frame.rgb, bright=200.0)


def depth(frame):
    return (frame.alt > HORIZON_DEG) & (frame.depth >= FAR_M)


def heuristic(frame):
    return depth(frame) & sky_coloured(frame.rgb)


def regions(mask, cell=8):
    """Connected regions of `mask` on a coarse grid, largest first: (pixel count, centre x, centre y) in pixels.
    A cell counts when most of it is set; the centre is the set cell furthest from the region's edge, so a seed
    never lands on a branch crossing the sky."""
    h, w = mask.shape
    gh, gw = h // cell, w // cell
    grid = mask[: gh * cell, : gw * cell].reshape(gh, cell, gw, cell).mean(axis=(1, 3)) >= 0.8
    label = np.zeros((gh, gw), dtype=np.int32)
    found = []
    for y0 in range(gh):
        for x0 in range(gw):
            if not grid[y0, x0] or label[y0, x0]:
                continue
            index = len(found) + 1
            stack, cells = [(y0, x0)], []
            label[y0, x0] = index
            while stack:
                y, x = stack.pop()
                cells.append((y, x))
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < gh and 0 <= nx < gw and grid[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = index
                        stack.append((ny, nx))
            inside = set(cells)
            def room(c):   # how far the region reaches in the four directions before it ends
                y, x = c
                reach = 0
                while all(n in inside for n in ((y + reach + 1, x), (y - reach - 1, x), (y, x + reach + 1), (y, x - reach - 1))):
                    reach += 1
                return reach
            best = max(cells, key=room)
            found.append((len(cells) * cell * cell, (best[1] + 0.5) * cell, (best[0] + 0.5) * cell))
    return sorted(found, reverse=True)


def seeds(frame, most=3, smallest=0.004):
    """Points to include (centres of the heuristic's largest regions) and to exclude (near surfaces the LiDAR is
    sure of, above the horizon, beside the sky), as fractions of the picture from its top-left corner."""
    h, w = frame.shape
    include = [(x / w, y / h) for n, x, y in regions(heuristic(frame))[:most] if n >= smallest * h * w]
    near = (frame.depth < 4.0) & (frame.conf == 2) & (frame.alt > HORIZON_DEG)
    exclude = [(x / w, y / h) for n, x, y in regions(near)[:2] if n >= 0.02 * h * w] if include else []
    return include, exclude


def vision(frame, quality="accurate", workdir=None):
    """Returns (mask, seconds, note). No seed means no request and an empty mask: nothing in the frame looks like sky."""
    include, exclude = seeds(frame)
    h, w = frame.shape
    if not include:
        return np.zeros((h, w), dtype=bool), 0.0, "no_seed"
    workdir = workdir or tempfile.mkdtemp(prefix="segeval-")
    picture = os.path.join(workdir, frame.key + ".png")
    Image.fromarray(frame.rgb).save(picture)
    command = [SEGSMOKE, "--quality", quality, "--out", workdir]
    for x, y in include:
        command += ["--seed", f"{x:.4f},{y:.4f}"]
    for x, y in exclude:
        command += ["--exclude", f"{x:.4f},{y:.4f}"]
    out = subprocess.run(command + [picture], capture_output=True, text=True, timeout=120)
    row = out.stdout.strip().splitlines()[-1].split(",")
    outcome, seconds = row[5], float(row[7])
    path = os.path.join(workdir, frame.key + ".mask.png")
    if outcome != "mask" or not os.path.exists(path):
        return np.zeros((h, w), dtype=bool), seconds, outcome + ":" + ",".join(row[9:])[:120]
    mask = np.asarray(Image.open(path).convert("L").resize((w, h), Image.NEAREST)) > 127
    return mask, seconds, f"{len(include)}+{len(exclude)}"


def vision_above_horizon(frame, **kw):
    mask, seconds, note = vision(frame, **kw)
    return mask & (frame.alt > HORIZON_DEG), seconds, note
