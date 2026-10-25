# One bounded ref-5 face-shape trial

Status: opt-in candidate only; approved production/default strength stays 1.0.
The goal is stronger cell-correlated strip fragmentation without changing
roughness, bevel normals, fine grain, lights, exposure or camera.

- Candidate strength: 1.8, only `ref_tile_pearl`.
- Centre tilt limit: 0.629982 degrees per axis; crown: 90 micrometres.
- Sampled face-height range: -0.159232 to +0.275887 mm.
- Conservative continuous absolute-height bound: 0.279604 mm, below the
  unchanged 0.280 mm relief.
- Bound method: 512x512 midpoint samples for every periodic cell, plus an
  analytic gradient/Lipschitz remainder of 0.003716 mm. The exact zero height
  and gradient at cell boundaries are retained.
- Strength 2.0 reaches +0.306542 mm even before the bound remainder. It exceeds
  the relief criterion and is not the candidate.

The paired runtime shaders retain their separate baseline face-strength input;
bevel amplitude is untouched. Following the negative visual review,
`strong_face` was removed from the runtime factory, and its rejection is
tested. Only the offline QA helper/data remain for reproducibility. Dry/satin
and other palette roles retain their original roughness/pitch and defaults.

For Blender, `generate_shape_candidate.py` emits an exact 16-bit normal and
hash/bounds sidecar only inside the ignored `output/` QA folder. It adds no
production image. `apply_strong_face_candidate` swaps only pearl's normal
image; node-contract checks verify other maps, roughness and roles are intact
and the original default can be restored.

## Reviewed result: not promoted

The matched 320x320 crops from the same 640-pixel/FOV40 diagnostic frame have
now been reviewed. Both used 256 samples, seed 5074 and identical lighting,
roughness, bevel and exposure. [Baseline](material_evidence/strong_face_trial/stair_facet_baseline_1_crop.png)
and [1.8 trial](material_evidence/strong_face_trial/stair_facet_trial_18_crop.png)
show only modest additional kinks; the reflected strip remains one coherent
band across several cells. The benefit is insufficient to promote strength
1.8. Default remains 1.0; the user's per-cell reflection criterion is not met.

The full-cell smooth window forces zero face slope on both sides of each cell
boundary. This favors continuous reflected-source alignment there. Raising
amplitude preserves that structure. A different nearly planar interior with a
narrow perimeter transition is a separately scoped QA design, not a gain retry.
See `PLANAR_FACE_TRIAL.md`. No native NVIDIA conclusion follows from these
CPU crops. Source/GLB hashes remained unchanged in the crop metadata.
