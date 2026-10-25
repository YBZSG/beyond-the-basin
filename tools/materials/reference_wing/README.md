# Reference-wing ceramic family

New roles only: `ref_tile_pearl`, `ref_tile_teal`, `ref_tile_pink`,
`ref_tile_dark_teal`, `ref_tile_dry`, `ref_tile_teal_dry`, `ref_tile_pink_dry`,
`ref_tile_dark_teal_dry`, `ref_tile_teal_satin`, `ref_tile_teal_satin_dry`,
`ref_tile_pink_satin`, `ref_tile_pink_satin_dry`, `ref_tile_pearl_ref5_crown`,
`ref_tile_cyan_satin`, `ref_tile_cyan_satin_dry`, `ref_grout`.
The runtime `ReferenceMaterials` adapter ignores all other names and never
mutates old material resources. Parent integration owns the new RT shader pair.
Original water and the accepted six ceramic shaders remain unchanged.

## Coordinate and physical contract

- One runtime UV1 unit is one metre. Ref-5/colonnade and original new-wing
  glaze roles remain 0.10 m. Scoped cyan/pink satin roles are 0.15/0.20 m.
- Maps repeat eight cells in 0.80 m. Export real tangents and name Blender's
  active UV map `UVMap`. Do not rescale mesh UVs by 1/0.8.
- Nonmetal, F0 0.04, no clearcoat dependency. Candidate face roughness is
  0.075 +/- 0.004; porous grout is 0.82.
- Dry walkways/stairs/thresholds explicitly use `ref_tile_dry`: same pearl
  maps and shape with face roughness 0.26 +/- 0.004. This is a visual material
  distinction, not a real-world slip-resistance certification.
  `ref_tile_teal_dry` and `ref_tile_pink_dry` retain their matching palettes.
- The colonnade's `ref_tile_dark_teal`/`ref_tile_dark_teal_dry` use dedicated
  dark teal pigment (#3F6863) and darker grout (#294842), not global tint or
  exposure. They share all geometric maps and the same glaze/dry
  finish distinction; neither dark role adds a water film.
- Ref-2 cyan walls/ceiling use `ref_tile_teal_satin`: roughness 0.34,
  `tile_scale=1.5`, 0.15 m pitch, 1.20 m atlas repeat and 2.7 mm grout.
  Ref-3 pink walls/coffers use `ref_tile_pink_satin`: roughness 0.40,
  `tile_scale=2.0`, 0.20 m pitch, 1.60 m repeat and 3.6 mm grout.
  Their `*_satin_dry` aliases are roughness 0.40 at the matching room pitch.
  These presets stay fixed under the ref-5 roughness diagnostic variants.
  They are reference-guided candidates, not dimensions measured from a photo.
- `tile_scale` uniformly scales the full relief: cyan bevel/recess/crown are
  0.9/0.42/0.075 mm; pink values are 1.2/0.56/0.10 mm. Tangent slopes stay
  unchanged because `H_actual(U,V)=s*H_base(U/s,V/s)`. No UV-density changes,
  post-sharpening or global grout-strength boosts are used. The same scaled
  coordinates sample albedo, ORM, bevel and analytic face shape.
- Real normal-field edge dimensions: 1.8 mm grout, 0.6 mm easing and 0.28 mm
  recess. Surface silhouette/collision is still the authored architecture.
- Analytic smooth face height gives cell-centre slopes up to +/-0.35 degrees
  per axis and a 50 micrometre crown with mild per-cell variation. It is not
  random pixel noise. Height and derivative vanish at the cell boundary. The
  middle gradient is the tilt parameter; the whole bowed face is not a rigid
  tilted plane. Face derivatives are never sent through the old 0.08 gate.
- No artificial wet film or replacement water simulation is enabled.

The dedicated `ref_tile_pearl_ref5_crown` is the CPU-reviewed ref5 wall/parapet
direction: one C2 0.30 mm crown of radius40 mm per 10 cm cell, +/-15% stable
height variation, and the existing +/-0.35-degree tilt. It is not assigned to
ceilings, dry floors or other rooms. Generic pearl stays unchanged. Runtime
profile1 is analytic; Blender binds the separate `ref5_crown_normal_gl_16.png`.
The generic height texture does not represent this profile. See
`docs/reference_wing/CROWN_REFLECTION_DIAGNOSIS.md` for bounds and visual limits.

The explicit cyan palette roles reuse the teal atlas, not a new texture or
global tint. Their nominal face/grout swatches are #63B0A6/#4D8279, applied as
linear gains mixed by the existing ORM face coverage. Runtime and Blender
use identical math; old teal/dark-teal/pink roles receive identity gains.
Pitch remains0.15 m, face roughness0.34 and dry0.40. The grout swatch is a
documented candidate, not a calibrated photo measurement.

`surface_math.py` is canonical for physical constants, integer hash and height
polynomial. `generate.py` emits both maps and the shared shader include:

    python tools/materials/reference_wing/generate.py

The manifest records hashes, height range, palette values and color spaces.
`bevel_slope_rg_2k.png` is **custom linear slope data**, not a standard normal:
decode `(byte - 128)/127`; do not use Godot normal-map import conversion.
`full_normal_gl_16.png` is a conventional high-precision tangent normal for the
Blender comparison, combining decoded bevel data and the exact analytic field.
Albedo is sRGB. ORM, normals, height and slope data are linear/Non-Color. ORM
alpha is face coverage, never transparency. AO is not baked into albedo.
Only the two linear data imports use lossless mode0 after measured BC7/ASTC
joint-data errors. Albedo compression remains unchanged. Source PNG pixels
and dimensions are not resampled; mip generation and channel mappings stay
explicit. See `docs/reference_wing/DATA_MAP_IMPORT_AUDIT.md`.

## Blender source/preview helper

Inside Blender's Python process:

    import sys
    sys.path.insert(0, str(PROJECT / 'tools/materials/reference_wing'))
    from blender_materials import attach_named_materials
    attach_named_materials()

Or call `build_materials()` before assigning named slots. The helper retains
the explicit role names, replaces only their nodes and does not edit geometry,
UVs, emitters, water or cameras. Standard glTF exports metre UV `(u,v)` as
`(u,1-v)`. The helper accounts for that V phase, PNG row direction, and tangent
normal Y reversal once. It uses Principled IOR 1.5, no coat, the same albedo,
roughness and full normal field. Do not add an extra green inversion or UV
normalization. The map is a precise offline reference of the shader field at
base level, not a live Godot shader inside Blender. Quantization/interpolation,
BRDF implementation, RT grazing clamping and denoising still differ by engine.
For a controlled CPU preview roughness A/B, call
`attach_named_materials(face_roughness=0.115)` versus default `0.075`, leaving
shape, camera, lighting, sample count and denoiser fixed. Restore the default
before saving/exporting production sources. The dry role stays 0.26.
For the exact runtime `control` equivalent, also pass `face_shape_strength=0.0`.
This chooses the high-precision bevel-only reference normal, retaining grout
and edge relief rather than flattening every normal. The offline helper accepts
binary shape ablations 0/1 only. Default strength 1 is the combined candidate.
For a scoped palette trial without rebuilding any other existing node graph,
use `build_materials(roles=[...])` or `attach_role_materials([...])`. This isolation
is checked by node identity, not just equivalent parameter values.

The nonstandard preview-node network may not export as a complete standard
glTF material. That is intentional: runtime replaces the named slots with the
actual project shaders. Save the `.blend` source for the true preview material.

## Runtime binding and diagnostics

    var materials = preload("res://scripts/reference_wing/reference_materials.gd").new()
    materials.apply_to_imported(imported_room, existing_pool_material_library)

The optional existing library is used only to register ordinary caustic
receivers. Without it the receiver gain is explicitly zero. The adapter exposes
`resolve`, `set_raytracing_enabled`, `set_diagnostic_variant` and `get_stats`.
Diagnostic variants are `control`, `shape_only`, `roughness_only`, `combined`.
They isolate 0/1 shape strength and 0.115/0.075 roughness. None mutates legacy
materials. Dry walkways remain 0.26 in every roughness variant. The exact
legacy comparison in the lab uses the actual old
`art_pass_tile_pearl`, not a renamed reconstruction of it.

## Rejected ref-5 shape trial, QA reproduction only

The single 1.8 face-shape trial was not visually accepted. `strong_face` has
been removed from the runtime factory and cannot be selected through
`--reference-material`. Default remains `combined` at 1.0. Its offline QA
helper and evidence are retained below, not as an active asset or feature.

The trial gives 0.62998 degrees centre tilt per axis and a 90 micrometre crown.
A per-cell sampled height bound plus an analytic Lipschitz remainder gives
absolute face excursion <0.279604 mm, below 0.280 mm joint relief. Strength
2.0 exceeds that bound and was not selected. Bevel amplitude is unchanged.

For the one controlled CPU crop, generate a QA-only normal:

    python tools/materials/reference_wing/generate_shape_candidate.py --output output/reference_wing/stair/qa_face_shape_1_8_normal.png

In the transient Blender session, call `attach_named_materials()` followed by
`apply_strong_face_candidate(PROJECT / 'output/reference_wing/stair/qa_face_shape_1_8_normal.png')`.
This swaps only pearl's normal texture, not roughness, other roles, lights,
geometry, UVs or exposure. The PNG and its bounds/hash sidecar stay under the
ignored QA output folder. Do not save/export that transient scene as production.
The matched crop retained a coherent strip, so this trial is not promoted.

See `tests/reference_wing/README-materials.md` for CPU/headless checks and the
NR-off visual lab. Source checks are not native NVIDIA/GPU visual acceptance.

## Lossless source-map encoding

The three 16-bit PNGs use adaptive None/Sub/Up/Paeth byte-row filters, with
RGB16 stride six bytes and grayscale stride two. This changes only compressed
bytes, not resolution, bit depth, samples or color-space metadata. Independent
FFmpeg and Python decoders confirmed uint16 identity before promotion. The
nine PNG assets total 5,824,564 bytes after this encoding-only change. Original
byte hashes and decoder evidence are in
`docs/reference_wing/material_evidence/png16-lossless-encoding.json`.

    python tests/reference_wing/test_png16_encoding.py

The encoder test includes full-range RGB/grayscale values, correct byte
strides, deterministic output and optional independent FFmpeg decoding.
