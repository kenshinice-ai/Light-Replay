#!/usr/bin/env python3
"""Draft sky labels for experiment 1: a person's polygons, and inside them a colour rule for edges no polygon can follow.

    python3 tools/segeval/label.py view KEY...      # the picture with a grid, beside what the colour rule alone would say
    python3 tools/segeval/label.py build [KEY...]   # labels/KEY.json → truth/KEY.png and check/KEY.jpg

A label file (upright pixel coordinates, origin top-left):

    {"zones": [{"poly": [[x, y], ...], "mode": "fill" | "otsu" | "sky" | "bright" | "blue", "threshold": 180, "glass": true}],
     "ignore": [[[x, y], ...]], "not_sky": [[[x, y], ...]], "note": "..."}

`fill` makes the whole polygon sky. The other modes keep, inside the polygon, the pixels a colour rule calls sky:
`bright` by luminance (white sky behind leaves), `otsu` the same with the split found from the polygon's own
pixels, `blue` by blue excess, `sky` by either. The polygon is the person's
judgement of where sky can be; the rule only traces leaves and wires inside it. A one-pixel band along every traced
edge is marked "ignore", and so is anything in `ignore` (translucent roofing, glare a person cannot call).

A zone may carry `"kind": "translucent"` (roofing that lets light through: neither sky nor a wall) or
`"kind": "reflection"` (sky mirrored in glass or a screen: not sky, and the case a segmenter is most likely to get
wrong); both are scored apart from the rest. `"kind": "glass_unsure"` is glazing where a person cannot say whether
the brightness behind it is sky, a sunlit wall or the room mirrored in the pane: the right answer there is
"glass, uncertain", and a method that calls it sky is counted, though not as a miss against the truth.

Truth values: 0 not sky, 1 sky, 2 sky seen through glass, 3 translucent roofing, 4 a reflection (not sky),
5 glass a person cannot call, 255 ignore. No zones means no sky in the frame.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

LABELS, TRUTH, CHECK, VIEW = (os.path.join(common.WORK, d) for d in ("labels", "truth", "check", "view"))
DEFAULTS = {"bright": 190.0, "blue": 12.0}


def luminance(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def blue_excess(rgb):
    return rgb[..., 2].astype(np.float32) - (rgb[..., 0].astype(np.float32) + rgb[..., 1]) / 2


def rule(rgb, mode, threshold=None):
    rgb = rgb.astype(np.float32)
    if mode == "bright":
        return luminance(rgb) >= (threshold if threshold is not None else DEFAULTS["bright"])
    if mode == "blue":
        return blue_excess(rgb) >= (threshold if threshold is not None else DEFAULTS["blue"])
    if mode == "sky":
        bright = threshold if threshold is not None else DEFAULTS["bright"]
        spread = rgb.max(axis=-1) - rgb.min(axis=-1)
        return (blue_excess(rgb) >= DEFAULTS["blue"]) | ((luminance(rgb) >= bright) & (spread <= 40))
    raise ValueError(mode)


def otsu(values):
    counts, edges = np.histogram(values, bins=256, range=(0, 256))
    total, levels = counts.sum(), np.arange(256)
    weight = np.cumsum(counts)
    mean = np.cumsum(counts * levels)
    between = np.zeros(256)
    ok = (weight > 0) & (weight < total)
    between[ok] = (mean[-1] * weight[ok] / total - mean[ok]) ** 2 / (weight[ok] * (total - weight[ok]))
    return float(np.argmax(between)) + 1


def polygon_mask(shape, poly):
    image = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(image).polygon([tuple(p) for p in poly], fill=1)
    return np.asarray(image).astype(bool)


def edge(mask):
    """Pixels of `mask` or of its complement that touch the other side (4-neighbours)."""
    out = np.zeros_like(mask)
    out[1:, :] |= mask[1:, :] != mask[:-1, :]
    out[:-1, :] |= mask[1:, :] != mask[:-1, :]
    out[:, 1:] |= mask[:, 1:] != mask[:, :-1]
    out[:, :-1] |= mask[:, 1:] != mask[:, :-1]
    return out


def truth_from(label, rgb):
    shape = rgb.shape[:2]
    truth = np.zeros(shape, dtype=np.uint8)
    band = np.zeros(shape, dtype=bool)
    for zone in label.get("zones", []):
        inside = polygon_mask(shape, zone["poly"])
        mode = zone.get("mode", "fill")
        if mode == "fill":
            sky = inside
        elif mode == "otsu":   # dark leaves against a lit sky: the split that best separates the two inside the polygon
            sky = inside & (luminance(rgb.astype(np.float32)) >= otsu(luminance(rgb.astype(np.float32))[inside]))
        else:
            sky = inside & rule(rgb, mode, zone.get("threshold"))
        kind = zone.get("kind", "sky")
        truth[sky] = {"sky": 2 if zone.get("glass") else 1, "translucent": 3, "reflection": 4, "glass_unsure": 5}[kind]
        if mode != "fill" and kind == "sky":
            band |= edge(sky) & inside
    truth[band] = 255
    for poly in label.get("ignore", []):
        truth[polygon_mask(shape, poly)] = 255
    for poly in label.get("not_sky", []):   # carve-outs: a lamp, a reflection, a pale wall inside a traced zone
        truth[polygon_mask(shape, poly)] = 0
    return truth


def gridded(rgb, alt=None):
    image = Image.fromarray(rgb).convert("RGB")
    draw = ImageDraw.Draw(image)
    h, w = rgb.shape[:2]
    for x in range(100, w, 100):
        draw.line([(x, 0), (x, h)], fill=(255, 255, 0), width=1)
        draw.text((x + 2, 2), str(x), fill=(255, 255, 0))
    for y in range(100, h, 100):
        draw.line([(0, y), (w, y)], fill=(255, 255, 0), width=1)
        draw.text((2, y + 2), str(y), fill=(255, 255, 0))
    if alt is not None:   # the horizon, where the camera's own gravity puts it
        horizon = edge(alt > 0)
        ys, xs = np.nonzero(horizon)
        for x, y in list(zip(xs, ys))[::3]:
            draw.point((x, y), fill=(255, 0, 0))
    return image


def tinted(rgb, truth, label=None):
    out = rgb.astype(np.float32)
    for value, colour in ((1, (255, 0, 160)), (2, (0, 200, 255)), (3, (255, 120, 0)), (4, (0, 220, 60)), (5, (120, 90, 255)), (255, (255, 230, 0))):
        m = truth == value
        out[m] = out[m] * 0.45 + np.array(colour) * 0.55
    image = Image.fromarray(out.astype(np.uint8))
    if label:
        draw = ImageDraw.Draw(image)
        for zone in label.get("zones", []):
            draw.polygon([tuple(p) for p in zone["poly"]], outline=(0, 255, 0))
    return image


def side_by_side(*images):
    sheet = Image.new("RGB", (sum(i.width for i in images) + 8 * (len(images) - 1), max(i.height for i in images)), "white")
    x = 0
    for i in images:
        sheet.paste(i, (x, 0))
        x += i.width + 8
    return sheet


def view(keys):
    os.makedirs(VIEW, exist_ok=True)
    for key in keys:
        f = common.frame(key)
        guess = np.where(rule(f.rgb, "sky") & (f.alt > 0), 1, 0).astype(np.uint8)
        side_by_side(gridded(f.rgb, f.alt), tinted(f.rgb, guess)).save(os.path.join(VIEW, key + ".jpg"), quality=88)
        print(key, f.rgb.shape[1], "x", f.rgb.shape[0])


def build(keys):
    os.makedirs(TRUTH, exist_ok=True)
    os.makedirs(CHECK, exist_ok=True)
    keys = keys or sorted(n[:-5] for n in os.listdir(LABELS) if n.endswith(".json"))
    for key in keys:
        label = json.load(open(os.path.join(LABELS, key + ".json")))
        f = common.frame(key)
        truth = truth_from(label, f.rgb)
        Image.fromarray(truth).save(os.path.join(TRUTH, key + ".png"))
        side_by_side(gridded(f.rgb), tinted(f.rgb, truth, label)).save(os.path.join(CHECK, key + ".jpg"), quality=88)
        share = lambda v: 100 * float((truth == v).mean())  # noqa: E731
        print(f"{key} sky {share(1):.1f}% through glass {share(2):.1f}% ignore {share(255):.1f}%")


def sheet(keys, name="sheet", width=640):
    """The tinted halves of several checks on one picture."""
    tiles = []
    for key in keys:
        label = json.load(open(os.path.join(LABELS, key + ".json")))
        f = common.frame(key)
        tile = tinted(f.rgb, np.asarray(Image.open(os.path.join(TRUTH, key + ".png"))), label)
        tile.thumbnail((width, width))
        ImageDraw.Draw(tile).text((4, 4), key[3:], fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
        tiles.append(tile)
    rows = [tiles[i:i + 3] for i in range(0, len(tiles), 3)]
    out = Image.new("RGB", (3 * (width + 6), sum(max(t.height for t in r) + 6 for r in rows)), "white")
    y = 0
    for r in rows:
        for i, t in enumerate(r):
            out.paste(t, (i * (width + 6), y))
        y += max(t.height for t in r) + 6
    out.save(os.path.join(common.WORK, name + ".jpg"), quality=88)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("view", "build"):
        sys.exit(__doc__)
    (view if sys.argv[1] == "view" else build)(sys.argv[2:])
