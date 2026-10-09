"""Reproduce the Stage A review with synthetic records; does not modify implementation or fixtures.

Run from the repository: python3 docs/reviews/2026-10-04-stage-a-probes.py --swift-check PATH
Current acceptance is a review finding, not the desired behavior. No PNG is decoded or allocated.
"""

import argparse
import copy
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "engine"), str(ROOT / "engine/scripts"), str(ROOT / "engine/tests")]
import make_v2_fixture as fixture
from lightreplay import quality, scenerecord


def probes():
    record = fixture.analysed()
    record["quality"]["evidence"]["horizon"]["frame_id"] = "nonexistent-frame"
    record["quality"]["evidence"]["lens"]["frame_id"] = "another-scan"
    yield "A01_foreign_detector_frames", record

    record = fixture.analysed()
    segments = record["analysis"][0]["bands"][0]["segments"]
    segments.insert(3, copy.deepcopy(segments[2]))
    record["analysis"][0]["totals"]["direct_min"] *= 2
    yield "A02_overlap_doubles_direct_minutes", record

    record = fixture.analysed()
    header = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 100000, 100000)
    record["capture_session"]["keyframes"][0]["mask"] = fixture.payload(header, 100000, 100000, "png+base64")
    yield "A03_header_only_png_unbounded_pixels", record

    record = fixture.analysed()
    record["visibility"]["votes"]["frames_used"] = 0
    yield "A04_grid_claims_zero_supporting_frames", record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-check", type=Path)
    options = parser.parse_args()
    for name, record in probes():
        try:
            scenerecord.validate(record)
            python = {"accepted": True, "gates": quality.evaluate(record)["gates"]}
        except scenerecord.ValidationError as error:
            python = {"accepted": False, "error": str(error)}
        result = {"probe": name, "python": python}
        if options.swift_check:
            with tempfile.TemporaryDirectory(prefix="propertyreplay-review-") as directory:
                path = Path(directory) / "synthetic.json"
                path.write_text(json.dumps(record))
                check = subprocess.run([str(options.swift_check.resolve()), str(path)], capture_output=True, text=True, check=False)
            result["swift"] = {"accepted": check.returncode == 0, "exit_code": check.returncode, "error": check.stderr.strip()}
        print(json.dumps(result))


if __name__ == "__main__":
    main()
