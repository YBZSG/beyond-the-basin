# Controlled ceramic wall crop review

2026-10-24. The scene builder rendered these cropped images in Blender CPU
Cycles. This review inspected the original images, script, metadata and
successful render log. **No image here was rendered in Godot or on the custom
NVIDIA engine. Final visual acceptance is still false.**

## Controlled conditions

Same authored stair scene, camera, crop, lighting, exposure (-1), seed 5074,
bevel map, grout and dry-floor finish. CPU device; denoising and adaptive
sampling disabled. Material experiments were transient, not saved over the
production source. Full metadata and image SHA-256s are in
[`cpu_crops/experiment.json`](cpu_crops/experiment.json).

- [A64](cpu_crops/stair_wall_A64.png): 64 samples, wall roughness 0.075, face shape on.
- [A256](cpu_crops/stair_wall_A256.png): 256 samples, wall roughness 0.075, face shape on.
- [B256 control](cpu_crops/stair_wall_B256_control.png): 256 samples, roughness 0.115, face shape off. Bevel remains.
- [C256 shape-only](cpu_crops/stair_wall_C256_shape_only.png): 256 samples, roughness 0.115, face shape on.

This control uses the **new family** at legacy-like roughness. It is not an
actual old-shader render. The separate Godot material lab selects the exact
legacy shader for that comparison, but that graphical lab was not executed.

## Observed differences

1. A64 to A256 reduces random speckle while keeping the same strip widths and
   cell-correlated bends/splits. Sampling alone does not remove that stable
   shape or its bright fringe.
2. B256 has the smoothest, broadest strip images. C256 retains the broader
   roughness halo but adds repeatable cell-linked fragmentation. This isolates
   the face-shape contribution without disabling genuine bevel normals.
3. A256 has the most identifiable strip cores and the sharpest fragmentation
   of the tested candidates. It does not read as one uniform wall mirror.
   Some bright fringes and Monte Carlo noise remain; these images do not prove
   a precise match to the supplied photograph.

## Decision and remaining boundary

Retain the approved 0.075 + analytic shape candidate for the final composition
check and native test. Keep palette-matched dry walking surfaces at 0.26.
Do not lower roughness toward a perfect mirror, add noisy normals, change NR,
or change the old six shaders in response to this crop.

The native engine's grazing-normal clamp, shader conversion, texture sampling,
RR and optional NR can alter this result. Actual native frames and diagnostic
logs remain required. The CPU crop result is a bounded material-ablation
finding, not gameplay, GPU, performance or NVIDIA validation.
