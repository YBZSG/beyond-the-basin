# Independent new-wing water review

Reviewed 2026-10-24 with official Godot 4.6.3, headless dummy renderer. No graphics
API, display bypass, full GPU solver run, or custom-engine visual test was used.
The reviewer changed only water review tests/docs, not the three implementation
files under review.

## Outcome

The focused lifecycle/geometry review passes after the implementation owner fixed
the findings below. There is no remaining demonstrated scheduler/mesh-winding
blocker. This does not certify production GPU quality changes, performance, or
Windows 4.8/NVIDIA visual output.

- 70 geometry/depth assertions pass: actual PlaneMesh winding, all three authored
  water polygons at four grid densities, finite normals with encoding tolerance,
  no degenerate/outside triangles, bounded source spacing, correct octagon/tread/
  exclusion depths, immutable original payload and preserved BVH/masks.
- 30 scheduler assertions pass: actual new adapter plus real CPU correction threads
  against an explicitly isolated source scheduler double. Covers two-result queue
  bound, no duplicate launch, internal/user suspension, pending/status, malformed
  result rejection, old identity/force/size, revision/quality changes while a worker
  runs, immutable profile capture, quality rebuild, disposal and repeat disposal.
- 7 production cold-state assertions pass against the real inheritance chain.
  It compiles/instantiates, retains original source objects/settings/wind, preserves
  optional wave OFF identity, and does not configure or step the source solver.
- The existing 9 reference-look source contracts still pass, including 22 protected
  original source hashes. No base solver/runtime/cache/shader implementation changed.

## Findings addressed by the implementation owner

1. The original quality setter casts surfaces to PlaneMesh; new polygon surfaces
   are ArrayMesh. The new-only override now hides its surface dictionary during the
   synchronous original quality operation, then restores/rebuilds polygon meshes
   and visibility. Tests ensure the mocked original path never sees an ArrayMesh.
2. Capturing current profiles after an old source worker completed could associate
   new depth geometry with an old key. The adapter now rejects outdated force,
   size and exact profile-bearing key before capturing the correction inputs.
3. Original preparation_pending/status did not include the new correction worker.
   New overrides now cover its worker and queue, so regeneration can keep yielding
   while correction drains instead of going straight to a blocking disposal join.
4. Incomplete dictionaries previously reached the polygon worker. Preflight now
   validates them. Force/size rejection precedes validation, matching the original
   policy that old-quality results are stale rather than corrupt.

## Geometry details and remaining model boundary

Real PlaneMesh triangle cross-product Y is -4 in the fixture; all authored surface
triangles have the same sign. Negative cross Y is therefore correct for Godot's
clockwise front-face convention, not an inverted surface.

The octagon point (2,-2) now has 0.54 m depth rather than a false AABB step. The
outside corner (4,4) is dry. Depth remains a static authored profile sampled onto
the original solver grid, not a replacement fluid equation.

One small detail approximation remains in the reviewed geometry contract: the
cyan sign's 0.24×0.24 m submerged base plate has physical top y=-0.17, but is not in
water_steps. Outside the pole itself, the profile gives 0.54 m instead of 0.49 m
over that plate. This was reported to the owner; no speculative source change was
made. Do not describe the profiles as exact for every submerged decorative detail.

## Bounded incoming-caustic-mask audit

Commands below decode the current GLB position/index buffers directly, avoiding
cached imports and texture dependencies. The oracle uses actual authored triangles,
the current first two fixture positions, start y=0.31, the original AABB slab kernel,
and finite-segment bounds 0.005–0.995. It is CPU visibility evidence, not an image.

The targeted point (2,-2) plus its four neighboring 256² mask texel centers gives
10 rays. Every source mask ray is blocked, but every actual-triangle ray is also
blocked. The diagonal dry-rim/upper-step AABBs are spurious contributors, yet they
do not establish a net false occlusion: the first lamp is genuinely blocked by the
rear portal lintel (t≈0.881), and the second by cove ledge/lip/housing (t≈0.98–0.994).

A bounded 7×7 integer-coordinate grid inside the wet octagon, plus the four nearby
texel centers, totals 49 distinct positions ×2 lamps = 98 rays:

- Net false-blocked rays: 0.
- Blocked by both source AABBs and actual triangles: 65.
- Source-mask-visible but actual-triangle-blocked: 33.
- Visible by both: 0.

Thus the measured result does **not** justify brightening the mask or replacing the
source photon model. The opposite-direction mismatches expose the existing coarse
incoming-mask geometry limitation, including small fixture geometry absent from
the source solid set. The source photon path uses only its first two effective
lamps. Other visible room lights and indirect cove illumination are not equivalent
to an unobstructed direct photon path; do not fabricate direct caustics by ignoring
real lintels or cove lips. The audit stops here, with no broad mask rewrite.

Asset hashes for this mask result:

- GLB: 3b82a7c65590b57b9ec360b3c3e23b5416cb9102378d83a84b05bd006417bab1
- Geometry contract: 1a35dcd288d337774f20983961be98cb1a49874721c2141b5262f4a8c69e5b10

## Reproduction

    python3 tests/reference_wing/water_run_review.py
    python3 tests/reference_wing/water_run_mask_probe.py
    python3 tests/reference_wing/water_run_mask_probe.py --grid --summary
    python3 tests/reference_look/test_source_contract.py

The runners isolate user data/cache under /tmp. No tests alter user preferences,
production caches or protected source files. Measured CPU mesh-build durations are
diagnostics from this cloud machine, not target frame-rate claims.

Reviewed implementation SHA-256 values:

- reference_scene_water_runtime.gd: 952bfe2d9da627700d3f9b50d90d0e52788b86b5542a5d8567d2da246b162157
- reference_depth_field.gd: b2cb4d6bc69016a9ba5b56452b7008ff622a1a4d51a37f04dd17e8db58b2c1f5
- reference_surface_mesh.gd: f814058e67fed5c5a6dda1ff45a06d3725611251bb4f754f5a000dc8300263bc
