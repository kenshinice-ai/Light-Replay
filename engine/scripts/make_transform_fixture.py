"""Writes tests/fixtures/image-transform-cases.json: points carried between a sensor image and its stored copies.

The Swift SunEngine.ImageTransform must reproduce every case. Run from engine/: python3 scripts/make_transform_fixture.py
"""

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lightreplay import imagetransform  # noqa: E402

NATIVE = [1920, 1440]
POINTS = [[0, 0], [1920, 1440], [960, 720], [100.5, 20.25], [1900, 30], [12, 1400]]
STORED = [   # crop, scale, rotation: a spool frame, an upright hero, the other two ways of holding the phone, a crop
    ([0, 0, 1920, 1440], 0.5, 0),
    ([0, 0, 1920, 1440], 2048 / 1920, 90),
    ([0, 0, 1920, 1440], 2048 / 1920, 180),
    ([0, 0, 1920, 1440], 2048 / 1920, 270),
    ([240, 180, 1440, 1080], 0.75, 90),
]


def build():
    cases = []
    for crop, scale, rotation in STORED:
        cases.append({"native_size": NATIVE, "crop": crop, "scale": scale, "rotation_deg": rotation,
                      "encoded_size": list(imagetransform.encoded_size(crop, scale, rotation)),
                      "points": [{"native": p, "encoded": list(imagetransform.to_encoded(p, crop, scale, rotation))} for p in POINTS]})
    return {"note": "Native pixel positions and where they land in a stored image (engine/lightreplay/imagetransform.py).", "cases": cases}


def main():
    out = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "image-transform-cases.json"
    out.write_text(json.dumps(build(), indent=1) + "\n", encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
