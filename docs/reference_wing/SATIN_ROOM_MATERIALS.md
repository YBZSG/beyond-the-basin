# Reference 2/3 satin correction

## Final scoped palette direction

The accepted cyan-only roles are `ref_tile_cyan_satin` and
`ref_tile_cyan_satin_dry`, nominal face#63B0A6 and grout#4D8279. They reuse the
existing teal atlas with explicit linear per-region gains, mixed by the same
ORM coverage in runtime and Blender. No new cyan texture, global tint or
change to colonnade teal/dark teal/pink is introduced. Pitch remains0.15 m,
roughness0.34 and dry0.40; crown profile remains0.

The single CPU palette frame reads richer cyan/teal instead of gray-green,
with the near-wall grid retained and no return to mirror-like glaze. The
room remains darker than reference2 and its distant/ceiling grid is weaker.
The approved strip-color change also contributes, so this is not a strict
material-only A/B. This is an accepted bounded direction, not native visual
acceptance or a claim of final scene fidelity. No additional material tuning
or renders followed. The helper's two-role binding preserves every unrelated
existing material graph by node identity and graph fingerprint.

## Evidence and scope

The actual reference-2 and reference-3 photographs were inspected separately
from the reference-5 stair image. Cyan surfaces show restrained, broad highlights
and readable joints. Pink walls and ceiling terraces read satin/matte, not like
the mirrored fixture blobs in the initial CPU room previews. Applying the
ref-5 0.075 glaze to both rooms was the wrong finish choice. The successful
ref-5 strip experiment did not validate that finish for other references.

Independent GLB audits found one UV unit per metre with no sampled UV-density
failures: 6,936 cyan and 11,560 bath triangles at the inspected baseline.
The grid loss is not evidence of absent UVs. Existing narrow joints are also
subpixel over substantial parts of these views; specular glare and Monte Carlo
noise further obscure them.

Read-only pixel measurements and known-camera projections are saved in
[`material_evidence/satin/pixel-spacing.json`](material_evidence/satin/pixel-spacing.json).
Ref-2 right-wall horizontal joints recur every 13–14 pixels; the authored
camera's 0.10 m tiles project to about 9.05 pixels at the same image width.
Ref-3 rear-wall joints recur near 3 pixels; that camera projects 0.10 m tiles
near 1.61 pixels. This supports scoped 1.5x and 2x candidates. It is **not** a
calibrated recovery of real-world dimensions: the reference lens, geometry,
framing and aspect ratio are not known exactly.

## Named presets

| Role | Nominal face roughness | Physical pitch | Physical joint |
| --- | ---: | ---: | ---: |
| `ref_tile_teal_satin` | 0.34 | 0.15 m | 2.7 mm |
| `ref_tile_teal_satin_dry` | 0.40 | 0.15 m | 2.7 mm |
| `ref_tile_pink_satin` | 0.40 | 0.20 m | 3.6 mm |
| `ref_tile_pink_satin_dry` | 0.40 | 0.20 m | 3.6 mm |

Existing palette maps and their finite per-cell roughness variation are reused.
There are no new image pixels, global tints, post-sharpening or global grout
strength changes. The reference-5/colonnade roles stay at their previous finish
and 0.10 m pitch. Dry/satin roughness cannot be reset to 0.075 by the ref-5
diagnostic variants.

## Exact coordinate and physical contract

Mesh UVs stay at one unit/metre. `material_metres = UV / tile_scale` feeds all
albedo/ORM/bevel sampling and the analytic face function in the common raster/RT
include. Uniform material scale also scales relief height, so
`H_actual(U,V) = s * H_base(U/s,V/s)` and the tangent slope remains unchanged.
The cyan bevel/recess/crown become 0.9/0.42/0.075 mm; pink becomes
1.2/0.56/0.10 mm. Runtime stats and the Blender helper report these actual units.

Blender's image repeat becomes 1.20/1.60 m. Its sampling phase remains
`(u/repeat, v/repeat + 1 - 1/repeat)`, accounting for standard glTF V inversion
and image row direction exactly once. The tangent normal's green component is
still inverted once. This matters especially at a 1.20 m repeat, where the
glTF constant 1 is not an integer repeat.

## Validation boundary

CPU tests cover scale, physical dimensions, the derivative chain rule and V
phase. Official Godot headless tests cover bindings, reported dimensions,
shader-front-end parameters and satin isolation. Blender's no-render contract
checks the actual node graphs/maps and compares role parameters with runtime.

One bounded CPU frame per room is the next visual check. Larger cells do not
guarantee distant grid readability: the predicted joint footprint at the
reference-sized far bath wall is still about 0.058 pixels. Preserve coverage
through ordinary texture mip filtering and judge the real frame; do not fake
detail with post-sharpening or quietly thicken every room's grout.

The bath builder also identified oversized disk area emitters behind the
semicircular highlights and is correcting them to fixture-matched rectangles.
Consequently the new room frame is a combined material/fixture correction, not
a pure roughness ablation. No final reference-faithfulness or native NVIDIA
rendering claim is made here.

## First visual follow-up

The corrected cyan CPU frame shows readable near/mid-wall joints and broader,
restrained wall highlights instead of the previous mirrored patches. Its
geometry, camera, light power, water and exposure were held fixed in the
architecture parity report. The frame remains noisy and is not a native or
final-faithfulness pass.

The first corrected bath frame is not a valid material judgment: narrowing the
oversized disk emitters exposed occlusion by the cove's concealment lip. The
scene builder is resolving that fixture geometry separately. The pink satin
parameters have not been changed in response to that lighting failure.
