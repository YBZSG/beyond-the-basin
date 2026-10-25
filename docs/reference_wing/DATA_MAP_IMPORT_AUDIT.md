# New data-map import integrity

Only the new `bevel_slope_rg_2k.png` and `glaze_orm_2k.png` are in scope.
Original world maps/shaders, albedo compression and image pixels are unchanged.

## Measured before changing settings

An official Godot4.6.3 headless process read the **existing central** `.ctex`
files directly with `CompressedTexture2D.load()`, then `get_image()` and
CPU `decompress()`. No editor, import or GPU was run for this audit.
Both BPTC_RGBA/BC7 (Image format22) and ASTC_4x4 (format35) decoded successfully,
with all 11 mip levels after the base retained. File hashes and exact settings
are preserved in `material_evidence/data-map-codec-audit.json` and
`material_evidence/data_map_codec_before/`.

Base-level differences against the actual PNG8 source:

- Neutral face interiors retain RG=(128,128) exactly in both codecs.
  Interior roughness and coverage are also exact. Blue-channel changes in
  BC7 do not affect this shader, which does not use slope B or ORM metallic B.
- At joint/bevel pixels, BC7 slope R/G errors reach 8/4 byte levels.
  The additional normal-angle error reaches 3.626621 degrees, with joint
  99th percentile 0.817123 degrees. BC7 ORM roughness error reaches 3/255
  and coverage error 4/255.
- ASTC slope R/G errors reach one byte level each; additional normal-angle
  error reaches 0.637993 degrees. ASTC ORM roughness error reaches 2/255;
  coverage is exact at base level in this measurement.

These are **additional codec errors**, not the existing PNG8 quantization.
The original slope PNG's maximum normal-angle error against the analytic
bevel is separately measured at 0.170131 degrees. Analytic face normals do
not pass through that PNG8 slope quantization.

The interior mask starts at texel centres 1.758 mm from each tile boundary,
beyond the 1.5 mm grout/bevel transition. The four-texel boundary band is
reported separately. All RGBA errors are stored, but changed-pixel fractions
count only channels the runtime shader actually uses.

Lower mip levels were also compared with Godot Image-generated source mips.
Those differences may include the importer's mip construction as well as
codec loss; they are not attributed solely to compression. The base-level
comparison cleanly isolates the additional codec loss.

## Narrow correction and validation gate

The approved correction sets `compress/mode=0` for these **two new data maps
only**. Linear treatment, normal conversion disabled, explicit RGBA channel
mapping, face-coverage alpha, mip generation and disabled roughness filtering
remain intact. The generator now emits that policy; albedo keeps mode2.
No PNG is regenerated or resampled.

The lead's coordinated central import completed successfully. A subsequent
read-only headless check opened the actual new `.ctex` files: bevel slope is
RGB8 (format4), ORM is RGBA8 (format5), both mode0. Every decoded base byte
matches the source PNG, and every channel of all 11 generated mip levels
matches the independently Image-generated reference mips exactly. Maximum
error is zero throughout. Fresh central material/RT-pair binding tests also
pass. The readback ran no editor, import, GPU or Blender render.

The measured after-state is retained separately in
`material_evidence/data-map-lossless-readback.json`, so the compressed
before-state is not overwritten. This validates actual decoded data, not
merely the updated configuration value. Lossless formats increase potential
texture memory compared with BC7; no native VRAM or performance measurement
is claimed.

This correction cannot explain the observed CPU crop artefacts: those Cycles
renders use source PNGs, not Godot's `.ctex` files. Nor did this measurement
find a neutral base-level interior-normal bias. It removes a demonstrated
joint-data error and a needless future source of mismatch, without making a
native visual or performance claim.

## Reproduction

`tests/reference_wing/dump_imported_data_maps.gd` accepts the absolute source
project path, a QA output directory and codec name. It reads existing imports
only and may run from an isolated temporary project to avoid editor activity.
Then run:

    python tools/materials/reference_wing/audit_imported_data_maps.py --directory output/reference_wing/data_map_audit --output docs/reference_wing/material_evidence/data-map-codec-audit.json

Keep the before/after directories separate so the original compressed
measurements remain reproducible and their reports are not overwritten.
