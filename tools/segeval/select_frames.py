#!/usr/bin/env python3
"""Picks the evaluation frames of experiment 1 and splits the clips into a development half and a held-back half.

    python3 tools/segeval/select_frames.py            # writes <data>/exp1/frames.json and prints the table

Six frames a clip, in two draws of three: one from each third of the clip's frames ordered by how high the camera
looked, taken by a number derived from the clip's name, so the pick does not depend on anyone's eye. (One draw gave
too few frames with any sky in them: most of an indoor sweep is ceiling.) Clips, not frames, are split: frames of one
sweep look alike, and a rule tuned on one must not be scored on its neighbour.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

# Scans aimed at a blank wall on purpose; tracking failed or nothing above the horizon was looked at.
EXCLUDED = {"PR-20261005-08": "blank wall, on purpose", "PR-20261009-07": "blank wall; tracking lost, one frame kept"}


def main():
    records = common.records()
    clips = [s for s in sorted(records) if s.startswith(("PR-20261005", "PR-20261009")) and s not in EXCLUDED]
    frames = []
    for index, scene in enumerate(clips):
        record = records[scene]
        _, manifest = common.spool(record)
        entries = sorted(manifest["frames"], key=lambda e: -e["cameraTransform"][9])   # by camera altitude, low to high
        third = len(entries) // 3
        for draw, salt in (("a", ""), ("b", "/second")):
            for band, part in enumerate((entries[:third], entries[third: 2 * third], entries[2 * third:])):
                taken = {f["key"] for f in frames}
                start = common.stable_number(f"{scene}/{band}{salt}") % len(part)
                pick = next(part[(start + step) % len(part)] for step in range(len(part))
                            if f"{scene}_{part[(start + step) % len(part)]['frameID']}" not in taken)
                frames.append({"key": f"{scene}_{pick['frameID']}", "scene": scene, "band": ("low", "mid", "high")[band],
                               "draw": draw, "split": "development" if index % 2 == 0 else "held_back"})
    os.makedirs(common.WORK, exist_ok=True)
    json.dump({"excluded_clips": EXCLUDED, "frames": frames}, open(os.path.join(common.WORK, "frames.json"), "w"), indent=1)
    for f in frames:
        print(f["key"], f["band"], f["split"])
    print(len(frames), "frames from", len(clips), "clips")


if __name__ == "__main__":
    main()
