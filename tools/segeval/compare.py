#!/usr/bin/env python3
"""Pictures of where each path is right and wrong.

    python3 tools/segeval/compare.py SPLIT KEY...      # → <data>/exp1/compare/KEY.jpg

Left to right: the draft truth, the depth map (near dark, far light, low-confidence cells hatched out in red), then
one panel a method: green = sky found, red = called sky and is not, blue = sky missed; untinted = agreed not sky.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
import label
from evaluate import METHODS


def panel(frame, truth, mask):
    sky = (truth == 1) | (truth == 2)
    callable_ = truth <= 4
    out = frame.rgb.astype(np.float32) * 0.55 + 60
    for m, colour in ((mask & sky, (0, 220, 60)), (mask & callable_ & ~sky, (255, 30, 30)), (~mask & sky, (40, 90, 255)),
                      (mask & (truth == 5), (255, 150, 0))):
        out[m] = out[m] * 0.3 + np.array(colour) * 0.7
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def depth_panel(frame):
    d = np.clip(frame.depth, 0, 25) / 25
    out = np.stack([d * 255] * 3, axis=-1)
    low = frame.conf == 0
    out[low] = out[low] * 0.6 + np.array((120, 0, 0)) * 0.4
    return Image.fromarray(out.astype(np.uint8))


def main(split, keys):
    out_dir = os.path.join(common.WORK, "compare")
    os.makedirs(out_dir, exist_ok=True)
    for key in keys:
        key = key if key.startswith("PR-") else "PR-202610" + key
        frame = common.frame(key)
        truth = np.asarray(Image.open(os.path.join(label.TRUTH, key + ".png")))
        panels = [label.tinted(frame.rgb, truth), depth_panel(frame)]
        for name in METHODS:
            mask = np.asarray(Image.open(os.path.join(common.WORK, "vision-" + split, f"{key}.{name}.png"))) > 127
            p = panel(frame, truth, mask)
            ImageDraw.Draw(p).text((6, 6), name, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
            panels.append(p)
        panels = [p.resize((p.width // 2, p.height // 2)) for p in panels]
        label.side_by_side(*panels).save(os.path.join(out_dir, key + ".jpg"), quality=86)
        print(key)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
