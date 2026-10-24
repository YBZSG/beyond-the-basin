#!/usr/bin/env python3
"""CPU/source contracts. Does not import Godot assets or claim GPU/RT acceptance."""
from pathlib import Path
import json
import re
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TEXTURES = ROOT / "assets/materials/art_pass/textures"
TILES = ["tile_blue", "tile_pearl", "tile_blue_wet", "tile_pearl_wet"]


def downsample(a):
    return a.reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2).mean(axis=(1, 3))


class TileFinishContract(unittest.TestCase):
    def test_authored_coverage_and_metric_pitch(self):
        reference = None
        for name in TILES:
            image = Image.open(TEXTURES / (name + "_orm_2k.png"))
            self.assertEqual(image.mode, "RGBA")
            data = np.array(image)
            self.assertEqual(data.shape, (2048, 2048, 4))
            alpha = data[..., 3]
            self.assertEqual(set(np.unique(alpha)), {0, 199, 255})
            if reference is None:
                reference = alpha
            else:
                np.testing.assert_array_equal(alpha, reference)
            # Eight 100 mm tiles in the existing 0.8 m atlas repeat.
            np.testing.assert_array_equal(alpha[128, :256], alpha[128, 256:512])
            self.assertEqual(alpha[128, 0], 0)
            self.assertEqual(alpha[128, 2], 199)
            self.assertEqual(alpha[128, 128], 255)
            self.assertEqual(np.count_nonzero(alpha[128] == 0), 32)
            # Linear mask means total joint coverage survives every mip.
            coverage = 1.0 - alpha.astype(float) / 255.0
            expected = coverage.mean()
            self.assertAlmostEqual(expected, 0.0343702129289216)
            while coverage.shape[0] > 1:
                coverage = downsample(coverage)
                self.assertAlmostEqual(coverage.mean(), expected, places=12)
            settings = (TEXTURES / (name + "_orm_2k.png.import")).read_text()
            self.assertIn("process/channel_remap/alpha=3", settings)
            self.assertIn("compress/channel_pack=0", settings)
            self.assertIn("mipmaps/generate=true", settings)

    def test_shader_coverage_and_rt_parity(self):
        for family in ["art_pass_pbr", "ceramic_world", "pc_source_ceramic"]:
            raster = (ROOT / "shaders" / (family + ".gdshader")).read_text()
            rt = (ROOT / "shaders" / (family + "_rt.gdshader")).read_text()
            self.assertNotRegex(rt, r"\b(?:dFdx|dFdy|fwidth)\s*\(")
            for token in ["float glaze", "ROUGHNESS", "METALLIC", "SPECULAR", "CLEARCOAT"]:
                extract = lambda s: [line.strip() for line in s.splitlines()
                                     if line.strip().startswith(token)]
                self.assertEqual(extract(raster), extract(rt), family + ": " + token)
            self.assertIn("smoothstep(0.025", raster)
            self.assertIn("mix(0.08,", raster)
        for suffix in ["", "_rt"]:
            shader = (ROOT / "shaders" / ("art_pass_pbr" + suffix + ".gdshader")).read_text()
            self.assertIn("float grout = 1.0 - channels.a;", shader)
            self.assertNotIn("smoothstep(0.55", shader)
            self.assertNotRegex(shader, r"\bALPHA\s*=")
            self.assertIn("vec4 channels", shader)

    def test_finite_glossy_face_and_rough_joints(self):
        library = (ROOT / "scripts/art_pass/art_pass_materials.gd").read_text()
        roles = re.findall(r'"(art_pass_(?:tile|coping)[^"]*)": Vector3\(([^)]*)\)', library)
        self.assertEqual(len(roles), 6)
        stats = {}
        for role, numbers in roles:
            base, reference, grout = map(float, numbers.split(","))
            name = role.removeprefix("art_pass_")
            filename = name + "_orm_2k.png" if "tile" in name else ("coping_wet_orm_1k.png" if "wet" in name else "coping_orm_1k.png")
            image = np.asarray(Image.open(TEXTURES / filename), dtype=float) / 255.0
            face = image[..., 3] if image.shape[2] == 4 else np.ones(image.shape[:2])
            glaze = np.clip(base + np.clip(image[..., 1] - reference, -.08, .08) * .06, .06, .25)
            rough = glaze * face + grout * (1.0 - face)
            pure_face = rough[face == 1.0]
            self.assertGreaterEqual(pure_face.min(), .075)
            self.assertLessEqual(pure_face.max(), .13)
            self.assertLess(pure_face.max() - pure_face.min(), .01)
            self.assertGreaterEqual(grout, .65)
            if "wet" in name:
                self.assertLess(base, .10)
            stats[role] = {"face_min": float(pure_face.min()), "face_max": float(pure_face.max()), "grout": grout}
        print("TILE_FINISH_CPU_RANGES " + json.dumps(stats, sort_keys=True))

    def test_local_wet_masks_have_identity_at_zero(self):
        # Match the two-stage shader expression, including extreme face/mortar values.
        for grout in np.linspace(0, 1, 17):
            for rough in np.linspace(.075, .82, 17):
                damp = .015 * (1 - grout) + .075 * grout
                lower = .075 * (1 - grout) + .65 * grout
                after_damp = rough * (1 - 0.0) + max(rough - damp, lower) * 0.0
                film = .08 * (1 - grout) + .68 * grout
                result = after_damp * (1 - 0.0) + film * 0.0
                self.assertEqual(result, rough)
        for suffix in ["", "_rt"]:
            code = (ROOT / "shaders" / ("ceramic_world" + suffix + ".gdshader")).read_text()
            self.assertIn("rough = mix(rough, max(rough - damp_roughness, mix(0.075, 0.65, grout)), local_wet.y);", code)
            self.assertIn("rough = mix(rough, film_roughness, local_wet.x);", code)


if __name__ == "__main__":
    unittest.main(verbosity=2)
