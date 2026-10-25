# One structural face-reflection candidate

QA only. The production shader, surface math and default remain unchanged.
This is not another gain change: it replaces the full-cell window in the
offline trial with an almost planar interior and a narrow perimeter blend.

## Dimensions and math

- Cell pitch: unchanged 100 mm.
- Independently hashed interior tilt: at most 0.15 degrees per axis.
- Small crown: 10 micrometres, with the existing modest cell variation.
- Almost-planar interior: 92x92 mm, 84.64% of the entire cell area.
- Additional shape is identically zero through the existing grout and bevel.
  It begins at the bevel's top, 1.5 mm from the cell boundary, and reaches the
  tilted interior at 4.0 mm. The transition is 2.5 mm wide.
- A quintic smootherstep has zero first and second derivatives at both ends.
  Its analytic product/chain-rule gradient is used directly, with the
  unchanged decoded bevel slope added separately.

The independent tilted-plane height plus crown is conservatively bounded by
0.273300 mm, below the unchanged 0.280 mm relief. Wherever the new field is
active, total height remains at least 0.006700 mm above the joint floor. The
field therefore does not cut through that floor, introduce an overhang or
make a discontinuity at the grout.

The transition spans 6.4 source texels. A conservative face-gradient length
bound is 0.2941, below the existing bevel's 0.7 peak slope. The actual sampled
maximum is 0.16134, about 9.2 degrees, within this finite smooth perimeter;
the main face is tilted only 0.15 degrees per axis. This is a smooth rolled
perimeter, not random grain or an unbounded normal spike.

Tradeoff: a nearly planar 100 mm tile with a shallow fixed joint cannot carry
a large independent rigid tilt without some corner heights exceeding the
relief. This candidate deliberately reduces the tilt while changing its
spatial structure. Subpixel filtering at distance is still a renderer question.

## Tests and reproduction

    python tests/reference_wing/test_planar_candidate.py
    python tools/materials/reference_wing/generate_planar_candidate.py --output output/reference_wing/stair/qa_planar_interior_normal.png

Four tests cover conservative bounds, finite-difference agreement with the
analytic derivative, exact zero shape through grout/bevel, smooth transition
boundaries, independent interior tilt and periodic/negative UVs. The 16-bit PNG
was independently decoded and sample-checked against the exact formula.

In a transient Blender session, call `attach_named_materials()` then
`apply_planar_face_candidate(PROJECT / 'output/reference_wing/stair/qa_planar_interior_normal.png')`.
Only pearl's normal image changes. Roughness remains 0.075; lights, exposure,
bevel, geometry, all other roles and production assets stay unchanged. A
no-render node test verifies role isolation and restoration of the default.

The normal and its hash/bounds sidecar are QA outputs, not production textures.
The production-isolation hash check is saved in
`material_evidence/planar-production-isolation.json`.

The single matched 256-sample CPU crop was independently reviewed. The main
source still forms one broad coherent stripe across multiple cells. The
flatter interior adds thin joint-adjacent interruptions, but also a stronger
bright perimeter network. This does not demonstrate the requested discrete
face reflections. The candidate is **not promoted**.

The unchanged baseline, trial and control hashes are retained under
`material_evidence/planar_trial/`. Roughness, lighting, camera, exposure, bevel,
source blend and GLB hashes remained fixed. No native Godot/NVIDIA validation
was performed. See `CROWN_REFLECTION_DIAGNOSIS.md` for the subsequent geometric
source-cone diagnosis, not a claim that the visual criterion has been met.
