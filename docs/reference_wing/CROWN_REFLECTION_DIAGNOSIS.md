# Reflected-strip geometry and one localized ceramic-crown trial

The experiments below were QA-only with frozen controls. After the close and
whole-wall reviews, the direction was integrated into one explicit ref5 role,
as described at the end. Generic material defaults, old shaders, water and
custom-engine code remain unchanged. Native acceptance is still pending.

## Why the earlier trials retained a strip

The diagnostic eye is at (2.3, 7.0, 4.0) m and looks at the ideal reflection
of the actual lens centre on the right wall, approximately
(2.9, 7.876042, 3.593750) m. Eye-to-wall distance is 1.136877 m,
wall-to-lens distance 4.320130 m and view angle 58.145644 degrees from the
wall normal. These are measured scene dimensions, not inferred from the photo.

Both sources were enabled in every CPU crop:

- The physical emissive lens is 98 mm by 1530 mm. Its short-axis angular
  extent at the wall is 1.103983 degrees. Its ideal mirrored image is
  13.026920 pixels wide, perpendicular to the strip, at the 640-pixel
  diagnostic camera. Required surface-normal width is 0.547444 degrees.
- The preview Area is 120 mm by 1530 mm, 25 mm below the lens, at 24 W.
  It is 22.45% wider than the lens. Its corresponding extents are
  1.355514 degrees at the wall, 15.977504 image pixels and 0.671593 degrees
  in required surface-normal space. Its ideal image length is 231.508 pixels.

These are central short-axis widths, not bounding-box widths of the tilted
image. Angular image widths at the eye are 0.873985 and 1.072504 degrees.
The source input is documented in the stair builder's fixture construction
and retained crop contract; the architecture worker independently confirmed
the saved source bindings. Native finite-point lights are not equivalent to
this CPU Area-light composition, so this diagnosis is not native validation.

For a fixed eye and surface point, the normal required to see a source point
is normalize(view direction + source direction). This half-vector mapping
is used directly rather than universally assuming reflection moves by twice
the normal angle, which would be inaccurate across directions at this view.

Across the exact 64-cell hash, transverse centre-normal standard deviations
are 0.0821 degrees for the rejected planar trial's +/-0.15-degree tilt,
0.1915 degrees for production's +/-0.35 degrees, and 0.3447 degrees for the
rejected 1.8-gain centre tilt. Production is not planar throughout its faces:
its full-cell smooth height window further changes orientation with position.

At roughness 0.075, assuming isotropic GGX with alpha = roughness squared,
the normal-distribution half-width at half peak is 0.207427 degrees. The
finite source therefore illuminates a substantially wider normal interval
than the planar trial's orientations. Small normal changes naturally keep
sampling the same bright source. This is a geometric/material explanation,
not evidence that NR, denoising or a texture blur caused the CPU result.

## Crown comparison and diagnostic limits

Increasing only the original full-cell crown to 0.12, 0.15 or 0.18 mm while
keeping +/-0.35-degree tilt produces transverse normal standard deviations
of 0.1431, 0.1633 and 0.1850 degrees. These heights are bounded, but do not
create a wide enough useful orientation distribution by themselves.

The final reproducible diagnostic expands each actual, curved source
half-vector boundary by the GGX NDF half-width, including the lens/Area
offset. Fractions of sampled interior normals outside both expanded source
envelopes are: production 0%; rejected gain1.8 1.14%; full-cell crown0.18 mm
0.31%; localized crown candidate 8.64%. This refines the preliminary
symmetric single-source estimates of 1.1%, 0.045% and 9.3% respectively.

This envelope is **not** a BRDF convolution, a predicted dark-pixel fraction
or a success metric. GGX has tails; Fresnel, masking, visibility, other
fixtures, multiple bounces and renderer sampling affect the image. The
calculation samples every cell at 256x256 points and excludes a 4 mm edge
band to avoid using bevel highlights as evidence for face fragmentation.
The NDF calculation uses nominal 0.075 roughness; the retained per-cell
roughness variation and texture quantization are not separately integrated.

Reproduce the geometry and field statistics without rendering:

    python tools/materials/reference_wing/measure_reflection_cone.py

Full inputs and results are in
`material_evidence/reflection-cone-diagnosis.json`.

## One approved bounded candidate

Retain the exact production hashed +/-0.35-degree tilt component, including
its existing smooth boundary window. Replace only the 50-micrometre crown
with one low-frequency ceramic crown per cell:

    H_crown = A * max(1 - (x*x + y*y)/(R*R), 0)^3
    R = 0.040 m
    A = 0.00030 m * (0.85 + 0.30 * existing_cell_hash)

Coordinates x/y are metric offsets from the cell centre. This is a single
80 mm-wide crown, not micrograin. Its height and first two derivatives reach
zero at its support. The added crown is identically absent at least 10 mm
before each cell boundary, so it introduces no random edge lippage or new
joint-normal discontinuity. Genuine bevel/grout slope remains separately
decoded and unchanged. Centre tilt, pitch, roughness and lighting stay fixed.

Over all 64 cells, sampled face-height excursion is -0.089362 to +0.359056 mm.
Where the existing bevel has reached its 0.28 mm top, sampled total height
above the joint floor is 0.190638 to 0.639056 mm. An analytic Lipschitz bound
plus nearest-midpoint remainder guarantees the interior remains between
0.186874 and 0.642821 mm. Existing grout/bevel behaviour is unchanged.
The sampled maximum face-normal deflection is 1.035886 degrees, with a
global gradient bound 0.027258, far below the genuine bevel's peak 0.7 slope.

The 0.28 mm value is joint relief, **not tile body thickness**. Individual
ceramic bodies are not modelled, and no invented body thickness is used to
justify this candidate. This bounded sub-millimetre ceramic crown differs
from independently tilting an entire 100 mm tile far enough to cause
1–2 mm random corner lippage.
These dimensions describe the analytic height field used to derive normals.
This trial does not displace mesh vertices or add relief self-shadowing.

## Reproduction and checks

    python tests/reference_wing/test_crown_candidate.py
    python tools/materials/reference_wing/generate_crown_candidate.py --output output/reference_wing/stair/qa_localized_crown_normal.png
    blender -b --factory-startup -t 2 --python-exit-code 1 --python tests/reference_wing/blender_material_contract.py -- --crown-normal output/reference_wing/stair/qa_localized_crown_normal.png

Four CPU tests verify exact derivatives, conservative height bounds, C2
compact support, cell-edge behaviour, retained centre tilt, negative UV and
periodicity. The generated RGB16 normal was independently decoded with
FFmpeg and checked against the analytic formula. Blender's no-render test
verifies pearl-only normal replacement, unchanged albedo/ORM/roughness and
all other roles, then successful restoration of the original default.

After `attach_named_materials()`, the transient Blender helper is
`apply_localized_crown_candidate(path)`. It verifies the sidecar's identity,
hash and bounds. It does not save a source, export, alter a runtime shader or
add the trial to a UI. The 2.60 MB QA normal stays in output/, not production.

## Actual matched-image review

The single authorized 320x320 CPU crop used the unchanged 640-pixel diagnostic
camera with a native render border, 256 samples, seed5074, denoising/adaptive
sampling off, roughness0.075, exposure-1 and identical geometry/light/bevel.
The baseline image was reused byte-for-byte. Source and GLB hashes remained
unchanged during the candidate render.

Independent inspection finds detached, cell-linked short glints above the
main band and visible dark notches/scalloping within it. This changes the
reflection mechanism more clearly than the gain or planar trials. However,
a continuous bright backbone, soft edges and some paired/stretched lobes
remain. **The user's crisp fragmented-reflection criterion is not established.**
Retain this as the strongest QA candidate, not a promoted production default.
No native Godot/NVIDIA test or photo-faithfulness claim follows from this crop.

The untouched baseline, candidate and detailed frozen controls are retained
in `material_evidence/localized_crown_trial/`.

The subsequently approved 750x750 whole-wall view used the reference camera,
96 samples and unchanged lighting/exposure/roughness, without a filter. Its
independent review found a straight near/mid-distance grid and an overall
flat wall, without obvious egg-carton or liquid-wall appearance. Upper-wall
reflections break into cell-scale fringes while retaining strip envelopes.
Noise and broad envelopes still limit a final crispness judgment. This is a
second-angle directional check, not native or final visual acceptance.

## Scoped integration after the two-angle gate

Only `ref_tile_pearl_ref5_crown` selects analytic profile1. The stair builder
binds it to intended glazed wall/parapet faces, not dry stairs/floors, ceilings,
other rooms, satin roles or generic `ref_tile_pearl`. Nominal roughness stays
0.075 with the existing finite tile variation, 0.10 m pitch and fixed profile
parameters. The generic nine PNGs remain byte-identical.

Runtime uses `surface_math.ref5_crown_face_field` emitted into the common
raster/RT include; no new runtime normal sampler is introduced. Blender uses
the separate 2,600,417-byte `ref5_crown_normal_gl_16.png`, byte-identical to the
reviewed candidate. Its height is defined analytically, not by the unchanged
generic `height_16.png`. Exact parity with the original reviewed formula,
profile isolation, all-role bindings and the normal-map hash are tested.
No UI control or global crown promotion is added. The rejected `strong_face`
runtime variant has been removed; offline evidence remains reproducible.
