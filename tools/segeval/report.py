#!/usr/bin/env python3
"""Tables from evaluate.py's results.

    python3 tools/segeval/report.py development|held_back [--frames]

IoU is sky ∩ / sky ∪ over the pixels a person could call. A frame "has sky" when at least 0.5% of it is sky; frames
with less are counted with the no-sky frames for the "sky evidence where there is none" line, and their slivers are
still in the pooled numbers. Pooled = all frames' pixels together; the median is over frames that have sky.
"""
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from evaluate import METHODS

HAS_SKY = 0.005
SPECK = 0.001      # sky called on less than this share of a frame is a speck; reported apart from "any at all"


def iou(m):
    union = m["hit"] + m["miss"] + m["false"]
    return m["hit"] / union if union else None


def pct(a, b):
    return f"{100 * a / b:5.1f}%" if b else "    —"


def main(split, per_frame):
    rows = json.load(open(os.path.join(common.WORK, f"results-{split}.json")))
    print(f"{split}: {len(rows)} frames from {len({r['scene'] for r in rows})} clips")
    first = rows[0]["methods"][METHODS[0]]
    has_sky = [r for r in rows if (r["methods"][METHODS[0]]["hit"] + r["methods"][METHODS[0]]["miss"]) >= HAS_SKY * r["methods"][METHODS[0]]["pixels"]]
    without = [r for r in rows if r not in has_sky]
    print(f"frames with sky: {len(has_sky)}; without (or under {HAS_SKY:.1%}): {len(without)}")
    header = f"{'':28s}" + "".join(f"{n:>12s}" for n in METHODS)
    print(header)

    def line(title, cell):
        print(f"{title:28s}" + "".join(f"{cell(n):>12s}" for n in METHODS))

    total = {n: {k: sum(r["methods"][n][k] for r in rows) for k in first if isinstance(first[k], int)} for n in METHODS}
    line("IoU, pooled", lambda n: f"{iou(total[n]):.3f}")
    line("IoU, median of sky frames", lambda n: f"{statistics.median(iou(r['methods'][n]) or 0 for r in has_sky):.3f}")
    line("IoU, worst sky frame", lambda n: f"{min(iou(r['methods'][n]) or 0 for r in has_sky):.3f}")
    line("sky frames at IoU ≥ 0.90", lambda n: f"{sum(1 for r in has_sky if (iou(r['methods'][n]) or 0) >= 0.9)}/{len(has_sky)}")
    line("sky found (recall)", lambda n: pct(total[n]["hit"], total[n]["hit"] + total[n]["miss"]))
    line("  open sky", lambda n: pct(total[n]["open_hit"], total[n]["open"]))
    line("  sky through glass", lambda n: pct(total[n]["glass_hit"], total[n]["glass"]))
    line("not-sky called sky", lambda n: pct(total[n]["false"], total[n]["not_sky"]))
    line("  inside the corridor", lambda n: pct(total[n]["c_false"], total[n]["c_not_sky"]))
    line("  worst frame, in corridor", lambda n: pct(*max(((r["methods"][n]["c_false"], r["methods"][n]["c_not_sky"]) for r in rows if r["methods"][n]["c_not_sky"]),
                                                          key=lambda t: t[0] / t[1])))
    line("no-sky frames with any sky", lambda n: f"{sum(1 for r in without if r['methods'][n]['hit'] + r['methods'][n]['false'] > 0)}/{len(without)}")
    line(f"  with more than {SPECK:.1%}", lambda n: f"{sum(1 for r in without if r['methods'][n]['hit'] + r['methods'][n]['false'] > SPECK * r['methods'][n]['pixels'])}/{len(without)}")
    line("translucent roof as sky", lambda n: pct(total[n]["translucent_as_sky"], total[n]["translucent"]))
    line("reflection as sky", lambda n: pct(total[n]["reflection_as_sky"], total[n]["reflection"]))
    line("uncallable glass as sky", lambda n: pct(total[n]["unsure_as_sky"], total[n]["unsure"]))
    line("seconds a frame, median (Mac)", lambda n: f"{statistics.median(r['methods'][n]['seconds'] for r in rows):.3f}")
    notes = {}
    for r in rows:
        note = r["methods"]["vision"]["note"]
        key = note if note == "no_seed" or not note[:1].isdigit() else "ran"
        notes[key] = notes.get(key, 0) + 1
    print("vision:", notes)
    if per_frame:
        print("\nframe                     sky%   " + "".join(f"{n:>22s}" for n in METHODS) + "   (IoU, false-in-corridor)")
        for r in rows:
            m0 = r["methods"][METHODS[0]]
            sky = 100 * (m0["hit"] + m0["miss"]) / m0["pixels"]
            cells = []
            for n in METHODS:
                m = r["methods"][n]
                value = iou(m)
                cells.append(f"{'   — ' if value is None else f'{value:5.3f}'} {pct(m['c_false'], m['c_not_sky'])}")
            print(f"{r['key'][3:]:25s} {sky:5.1f}  " + "".join(f"{c:>22s}" for c in cells))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "development", "--frames" in sys.argv)
