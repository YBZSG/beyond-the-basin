# Bounded glossy-ceramic candidate

This candidate preserves the accepted joint/bevel normal-amplitude separation,
UVs, tile pitch, pigments, nonmetal dielectric response and water implementation.
It is a material adjustment, not new geometry or a mirror shader.

- Art-pass tiles already store **linear face coverage in ORM alpha**. Blue,
  pearl and wet variants share the exact same mask. It contains values 0, 199
  and 255; the 2048 atlas repeats eight tiles over 0.8 m (100 mm pitch).
  Average joint coverage is 3.437%. Reading alpha replaces the invalid
  threshold of filtered roughness. Alpha is not connected to shader ALPHA.
- RGB coping maps have no tile grid: implicit sampled alpha 1 preserves the
  separately modelled coping joints without inventing a 100 mm overlay.
- Dry face roughness is about 0.105 blue / 0.115 pearl / 0.12 coping. Wet
  finishes are about 0.085–0.09. Existing small roughness variation remains;
  dry/wet joint roughness is 0.82/0.68. Clearcoat strength is unchanged and its
  roughness is 0.12 rather than 0.08.
- Formal/source ceramic glazes use the same conservative finite glossy range.
  Existing geometric-normal construction and strong-edge/quiet-face separation
  remain untouched. The optional local wet finish is now an exact identity
  outside both masks.

## CPU contracts

Run `python tests/tile_finish/test_tile_finish.py` (NumPy and Pillow).
This checks source alpha/UV pitch, linear coverage over all ideal mip levels,
finite face/joint ranges, raster/RT material formula parity, derivative-free RT
variants and zero-mask identity. It does not validate GPU compression or RT.

After import, `godot --headless --path . --script tests/tile_finish/imported_alpha_contract.gd`
additionally decodes the actual imported compressed textures and checks joint,
bevel, face and last-mip alpha plus production material bindings. This is native
resource/decoder evidence, **not** GPU sampling or visual acceptance.

## Isolated raster laboratory

Only run after assets are imported and the shared GPU slot is available:

`godot --path . --rendering-method forward_plus --rendering-driver vulkan --script tests/tile_finish/raster_lab.gd -- --tile-out=/absolute/output/path`

Use a real display/virtual display, not `--headless`. The fixture uses only
production material resources, two metric planes, an orange reflection subject,
known lights, a reflection probe and SSR. It never starts the game, changes user
settings, runs the water simulation, or accesses custom RT/NR/DLSS APIs.
It captures close, grazing and distant views of art pearl, art blue, formal deck and
source blue. It first samples each imported tile ORM alpha through an actual
GPU shader at a joint, bevel and face to catch dropped alpha/compression issues.

For matching handoff A/B, provide `--tile-baseline-dir=/absolute/path` containing
the unmodified handoff versions of art_pass_pbr.gdshader,
ceramic_world.gdshader and pc_source_ceramic.gdshader. This loads shader source
only; geometry, lighting, cameras, textures and material parameters stay fixed.
The old shaders ignore the newly introduced finish uniforms.

The JSON report and PNGs are **official-engine raster lab evidence only**.
Inspect the image pixels and shader/engine logs. Success does not certify the
full world, imported architectural tangents, hardware RT reflections, denoising,
native NR, gameplay, performance, or a release export. Those require the matching
custom engine and separately authorized native validation.
