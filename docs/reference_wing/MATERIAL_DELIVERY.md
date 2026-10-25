# Material delivery and freeze

All scoped material work is frozen. Native NVIDIA visual validation remains
pending; the lead owns the final imported-world RT-refresh parity check.

## Runtime scope

- `scripts/reference_wing/reference_materials.gd` and its UID: explicit roles,
  fixed dry/satin presets, ref5-only crown profile, cyan-only linear gains.
- `shaders/reference_wing/reference_glaze{,_rt}.gdshader`, shared
  `reference_glaze_surface.gdshaderinc`, generated
  `reference_glaze_math.gdshaderinc`, and their UIDs.
- `assets/materials/reference_wing/`: ten original PNGs plus import descriptors
  and `material_manifest.json`. Six 2k textures are runtime inputs. Four RGB16/
  height preview/reference maps are not sampled by the runtime glaze.

Only `ref_tile_pearl_ref5_crown` uses the reviewed compact crown. Only the two
`ref_tile_cyan_satin*` roles use the refined cyan gains. Generic pearl, dry
floors, teal/dark teal and pink remain separate. The rejected `strong_face`
variant is absent from the runtime API. Legacy six shaders and original
water/custom-engine code remain untouched by this material work.

The separate crown normal is 2,600,417 bytes; all ten PNGs total 8,424,981
bytes. Previous lossless PNG re-encoding saved 9,338,978 bytes while independent
decoders verified identical samples. No production map was resampled.

## External dependencies, not owned edits

- `scripts/reference_wing/reference_room_builder.gd`: explicit role binding.
- `scripts/rendering/rt_material_refresh.gd`: new raster/RT pair registration.
- `scripts/rendering/pool_materials.gd`: existing optional local-receiver API.
- `shaders/source_water/caustic_receiver.gdshaderinc`: existing receiver include.
- Stair/cyan GLB material-slot names and editable Blender sources are owned by
  their architecture workers. Metre UV0 and exported tangents are required.

No new SDK, GPU runtime, network service or third-party texture is required.
Authoring helpers use installed Python/NumPy/Pillow and Blender4.3.2. Headless
resource tests use official Godot4.6.3 and do not establish native GPU parity.

## Verification and evidence

- Ten production CPU tests, five crown tests, four rejected-planar regression
  tests and two PNG encoder tests pass. The NR-off lab includes the actual
  legacy material, four baseline ablations and the explicit scoped crown role;
  its final source was parse-checked, not rendered on a GPU.
- Fresh central headless binding/RT-pair switching passes for 15 tile roles
  plus grout. All runtime/Blender physical, profile and linear palette
  parameters match, with unrelated-node preservation verified.
- Actual post-import lossless data textures match source base pixels and all
  11 reference mip levels byte-for-byte, every RGBA channel. The previous
  BC7/ASTC joint errors are separately retained; neutral interiors were already
  exact. These Godot import errors did not cause the source-PNG CPU crop artefacts.
- Close and whole-wall crown evidence supports improved cell-linked glints
  without obvious liquid-wall/egg-carton appearance. Broad source envelopes,
  some paired lobes and render noise remain. No final crispness/native claim.

Key reports are `material_evidence/report.json`,
`material_evidence/scoped-profiles-source-contract.json`,
`material_evidence/data-map-codec-audit.json`,
`material_evidence/data-map-lossless-readback.json`, and
`material_evidence/png16-lossless-encoding.json`.
The source audit is `CERAMIC_REFLECTION_AUDIT.md`; physical reflection diagnosis
and frozen visual comparisons are in `CROWN_REFLECTION_DIAGNOSIS.md`.

The exact owned file list, per-file SHA256 values and dependency identities
are in `material_evidence/material-delivery-inventory.json`. It intentionally
excludes derived `.godot`, Python caches and ignored `output/` QA normals.
Rejected trial generators/data are offline tests/evidence, not active assets.
