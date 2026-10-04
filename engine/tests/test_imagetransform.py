"""The stored-image transform (docs/03 §11, review R01). Pure geometry; nothing is field-validated."""

import json
from pathlib import Path
import sys
import unittest

from lightreplay import imagetransform

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import make_transform_fixture  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "image-transform-cases.json"


class ImageTransformTests(unittest.TestCase):
    def test_fixture_is_current(self):
        self.assertEqual(json.loads(FIXTURE.read_text()), json.loads(json.dumps(make_transform_fixture.build())))

    def test_there_and_back(self):
        for case in json.loads(FIXTURE.read_text())["cases"]:
            for point in case["points"]:
                back = imagetransform.to_native(point["encoded"], case["crop"], case["scale"], case["rotation_deg"])
                self.assertAlmostEqual(back[0], point["native"][0], places=9)
                self.assertAlmostEqual(back[1], point["native"][1], places=9)

    def test_a_quarter_turn_clockwise_puts_the_top_left_corner_top_right(self):
        # Physical check, not a restatement: turn a picture clockwise and its top-left corner ends up top-right.
        crop = [0, 0, 400, 300]
        self.assertEqual(imagetransform.encoded_size(crop, 1, 90), (300, 400))
        self.assertEqual(imagetransform.to_encoded((0, 0), crop, 1, 90), (300, 0))
        self.assertEqual(imagetransform.to_encoded((400, 0), crop, 1, 90), (300, 400))   # top-right goes bottom-right
        self.assertEqual(imagetransform.to_encoded((0, 0), crop, 1, 180), (400, 300))
        self.assertEqual(imagetransform.to_encoded((0, 0), crop, 1, 270), (0, 400))      # top-left goes bottom-left

    def test_scaled_intrinsics_keep_the_same_ray(self):
        fx, fy, cx, cy = 1450.0, 1450.0, 960.0, 720.0
        crop, scale = [240, 180, 1440, 1080], 0.5
        sfx, sfy, scx, scy = imagetransform.scaled_intrinsics(fx, fy, cx, cy, crop, scale)
        native = (1300.0, 400.0)
        stored = imagetransform.to_encoded(native, crop, scale, 0)
        self.assertAlmostEqual((native[0] - cx) / fx, (stored[0] - scx) / sfx, places=12)
        self.assertAlmostEqual((native[1] - cy) / fy, (stored[1] - scy) / sfy, places=12)


if __name__ == "__main__":
    unittest.main()
