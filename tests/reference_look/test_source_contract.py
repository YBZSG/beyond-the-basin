#!/usr/bin/env python3
"""Static guards, not a shader compiler, graphics test, or performance result."""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def code(path):
    value = (ROOT / path).read_text(encoding="utf-8")
    return re.sub(r"(?m)^\s*(?://|##?|;).*?$", "", value)


class ReferenceLookSourceContract(unittest.TestCase):
    def test_baseline_water_and_terrain_sources_are_byte_exact(self):
        manifest = json.loads((Path(__file__).parent / "protected_source_sha256.json").read_text())
        for relative, expected in manifest["sha256"].items():
            with self.subTest(path=relative):
                self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), expected)

    def test_wave_controller_has_no_solver_gpu_or_camera_dependency(self):
        source = code("scripts/reference_wing/reference_wave_controller.gd")
        for forbidden in ("RenderingDevice", "RenderingServer", "_camera", "world_anchor", "domain_origin", "get_image(", "texture_get_data(", "solver.", "caustics.", "set_tuning("):
            self.assertNotIn(forbidden, source)
        self.assertIn("func advance(delta: float)", source)
        self.assertIn('"coordinate_space": "fixed_world_xz"', source)
        self.assertIn('float(target.referenceWaveStrength) > 0.0', source)

    def test_optical_include_is_default_off_and_normal_only(self):
        source = code("shaders/reference_wing/reference_ripples.gdshaderinc")
        self.assertIn("uniform float referenceWavesActive = 0.0", source)
        self.assertIn("if (referenceWavesActive < 0.5) return vec2(0.0)", source)
        self.assertIn("for (int i = 0; i < 3; i++)", source)
        for forbidden in ("VERTEX", "DEPTH", "texture(", "imageStore", "buffer", "TIME"):
            self.assertNotIn(forbidden, source)

    def test_all_camera_samples_are_clamped(self):
        source = code("shaders/reference_wing/reference_camera_look.gdshader")
        reads = re.findall(r"texture\(screen_tex,", source)
        safe_reads = re.findall(r"texture\(screen_tex, safe_uv\(", source)
        self.assertEqual(len(reads), 5)
        self.assertEqual(len(reads), len(safe_reads))
        self.assertIn("repeat_disable", source)
        self.assertIn("vec2 border = pixel_size * 0.5", source)
        self.assertIn("direction * SCREEN_PIXEL_SIZE * clamp(reference_fringe_px, 0.0, 8.0)", source)

    def test_camera_has_no_blur_exposure_or_denoiser(self):
        source = code("shaders/reference_wing/reference_camera_look.gdshader")
        for forbidden in ("mipmap", "textureLod", "textureGrad", "exposure", "denois", "for (", "while (", "DEPTH"):
            self.assertNotIn(forbidden, source)
        self.assertIn("uniform bool reference_look_enabled = false", source)
        self.assertIn("COLOR = vec4(color, 1.0)", source)

    def test_filter_settings_do_not_own_storage_or_water(self):
        source = code("scripts/reference_wing/reference_look_settings.gd")
        for forbidden in ("FileAccess", "ConfigFile", "user://", "water.", "solver."):
            self.assertNotIn(forbidden, source)
        self.assertIn('"referenceWaves": false', source)
        self.assertIn('"referenceLook": false', source)
        self.assertIn("reference_has_effect", source)

    def test_derived_surface_has_only_the_optical_additions(self):
        original = (ROOT / "shaders/source_water_surface.gdshader").read_text()
        derived = (ROOT / "shaders/reference_wing/reference_water_surface.gdshader").read_text()
        expected = original.replace(
            '#include "res://shaders/source_water/wind_ripples.gdshaderinc"',
            '#include "res://shaders/source_water/wind_ripples.gdshaderinc"\n#include "res://shaders/reference_wing/reference_ripples.gdshaderinc"',
        ).replace(
            '  vec3 N=normalize(vec3(-sim-ripple-micro-wind,1).xzy);',
            '  vec2 reference=referenceOpticalSlope(worldPosition.xz,footprint,bed);\n  vec3 N=normalize(vec3(-sim-ripple-micro-wind-reference,1).xzy);',
        )
        self.assertEqual(derived, expected)

    def test_adapter_settings_cannot_dispatch_or_rebind_source(self):
        source = code("scripts/reference_wing/reference_water_runtime.gd")
        setter = source.split("func set_reference_wave_settings", 1)[1].split("\nfunc ", 1)[0]
        optical = source.split("func _apply_reference_surface", 1)[1].split("\nfunc ", 1)[0]
        for forbidden in ("super.", "_bind_all(", "_apply_surface(", "solver.", "caustics.", "get_image(", "set_tuning("):
            self.assertNotIn(forbidden, setter + optical)
        self.assertIn("material.shader != Surface and material.shader != ReferenceSurface", optical)
        self.assertIn("ReferenceSurface if _reference_requested() else Surface", optical)

    def test_adapter_has_one_clock_owner_and_unchanged_base_order(self):
        source = code("scripts/reference_wing/reference_water_runtime.gd")
        self.assertEqual(source.count("reference_waves.advance("), 1)
        self.assertEqual(source.count("super._process(delta)"), 1)
        self.assertIn("_time - _reference_source_time", source)
        self.assertIn("_reference_source_time = _time", source)
        for guard in ("not _configured", "not enabled", "_terrain_paused", "not _terrain_ready"):
            self.assertIn(guard, source)
        original = code("scripts/water/source_water_runtime.gd")
        loop = original.split("func _process(delta:float)->void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertLess(loop.index("_pump_terrain()"), loop.index("if not enabled or _terrain_paused or not _terrain_ready:return"))
        self.assertLess(loop.index("_time+="), loop.index("for material in _materials.values():_apply_surface(material)"))
        self.assertNotIn("reference_water_runtime", code("scripts/water/source_terrain_disk_cache.gd"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
