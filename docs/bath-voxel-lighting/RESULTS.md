# Actual-bath VoxelGI: valid, but visually rejected

Completed 2026-10-22, native Godot 4.6.3 Forward+ using cloud llvmpipe. **Do not integrate this candidate.** One subdivision-64 volume produces a measurable but extremely small shading response on the actual non-emissive plaster/tile receivers, without a useful improvement in depth at normal viewing size. No subdivision-128 run was justified or launched.

## Useful outcome

- Runtime assertions passed; exit 0; tested source hashes unchanged. Shutdown logged seven leaked Texture RIDs, so this is successful execution, not warning-free teardown. No production edits, light-rig changes, water-solver changes, or scene-default changes.
- One shared volume is technically feasible in this isolated room, but it is not free per view: the observed renderer allocation increase was **41.90 MiB** for the main view with VoxelGI and **31.59 MiB more** for one shared 512×288 view.
- Named plaster/tile/ceiling receiver rectangles have **zero pixels more than one 8-bit luminance level above both off-state images**. They remain visibly flat.
- The secondary view's mean native linear-HDR luminance increased by only **0.447%**. No nonfinite, negative, or over-100 radiance pixels occurred; maximum channel was 2.1796875 in both states.
- Peak observed process RSS: **1.627 GiB**. Total supervised native execution: **443.40 s**, including startup/compilation/captures. This is neither target-GPU FPS nor full-game memory/performance evidence.

## Evidence

- [Off/on/off contact sheet](run64-02/off-on-off-contact-sheet.png), three native cameras, unchanged exposure and lights.
- [Native report](run64-02/report.json), [pixel/receiver analysis](run64-02/analysis.json), [exit receipt](run64-02/receipt.json), [source stability](run64-02/source-stability.json), [RSS samples](run64-02/memory.json), [engine log](run64-02/godot.log).
- Full-resolution 960×540 PNGs and 512×288 linear-HDR EXRs are preserved in `run64-02/`.
- External candidate resource: `assets/lighting/bath_voxel_candidate/run64-02.res`, **1,046,425 bytes** (0.998 MiB), not referenced by production scenes.

## Why this was a valid bounded test

The production builder loaded the requested continuous-wall GLB, with 70 visible meshes, 46,776 visible triangles, all 687 original collision shapes, and three original glazing meshes. The production material library and actual light-rig definitions were used. The local test contains no water, avatar, other rooms, or stand-in water.

The documented ShaderMaterial bake limitation was not ignored. All 67 opaque shader surfaces temporarily used explicit StandardMaterial3D proxies derived from their real pigment and average ceramic atlas albedo. Their exact original material instances were restored before the first GI-on capture. Actual glazing remained GI-disabled/shadow-disabled and retained its transparent material. Proxy emission was zero. Dynamic caustic gain was explicitly zero because no live caustic atlas exists in the isolated test; no caustics or substitute emission were baked.

The average tile/grout and triangle-centroid wet-darkening proxies are approximations, not exact world-projected texture baking. Full directional BRDF is not represented in VoxelGI's albedo/emission field; narrow metals are diffuse-color approximations. These limitations are recorded per surface in the native report and in [PLAN.md](PLAN.md).

The 20×8×20 m volume used a 64×32×64 field, about 0.3125 m cells, unit energy, propagation 0.5, two bounces, interior enabled, dynamic range 2, bias 1.5 and normal bias 0. Geometry bake took **430.443 ms**. The data contained 21,543 cells, including 17,042 leaves, all nonblack; no leaf was emissive. The saved binary reloaded with byte-identical octree and data fields. These facts establish populated material/geometry data, **not** live bounce quality by themselves.

## Actual receiver response versus off-state drift

Luminance below is display-referred, in 0–255 levels. Signal = on minus the mean of the two off states. Drift = mean absolute difference between the off states. Rectangles use `[x0,y0,x1,y1]` at 960×540. They were chosen post-hoc by inspecting only the off-before images, not by selecting bright delta-map pixels. They avoid glazing and the bright aperture.

| Actual receiver | Rectangle | Mean signal | Mean off drift | Pixels above both off states by >1 level |
| --- | --- | ---: | ---: | ---: |
| wide: plaster_wall | [150, 205, 700, 255] | 0.078568 | 0.051813 | 0 |
| wide: basin_side | [425, 325, 550, 370] | 0.020454 | 0.017922 | 0 |
| wall_closeup: plaster_wall | [100, 215, 850, 295] | 0.105610 | 0.012331 | 0 |
| wall_closeup: left_tile_dado | [20, 360, 260, 410] | 0.062545 | 0.007867 | 0 |
| wall_closeup: tile_deck | [180, 430, 300, 500] | 0.023887 | 0.004552 | 0 |
| roof: ceiling_plaster | [200, 75, 750, 175] | 0.159754 | 0.000559 | 0 |
| roof: rear_plaster_wall | [200, 365, 690, 410] | 0.186165 | 0.006500 | 0 |

The closeup/roof signals exceed their temporal drift, so “exactly zero GI contribution” would be inaccurate. The amplitude remains negligible: at most about one display luminance level in these receiver regions, with no useful visible separation. Whole-image mean absolute RGB on/off differences were 0.109 (wide), 0.089 (closeup), and 0.186 (roof) levels. Off/off RGB drift was 0.0585, 0.0153, and 0.00304 levels respectively. A weak generic numeric threshold passes; that is **not visual acceptance**.

The secondary view's full native float scans report mean linear luminance 0.1719934684 off and 0.1727621766 on, a +0.0007687081 change. This is a difference of whole-image means, not a separately decoded per-pixel EXR comparison. The EXRs are preserved; the available ImageMagick build lacks an EXR decoder. No dependency installation or additional engine run was needed because the original native harness already scanned every HDR pixel.

## Memory and shared-view feasibility

| Checkpoint | Renderer-reported video allocation |
| --- | ---: |
| Baseline, no volume | 822.25 MiB |
| Volume on, one main view | 864.15 MiB |
| Volume hidden again | 864.15 MiB |
| Volume plus one shared 512×288 view | 895.75 MiB |
| Secondary view removed | 864.15 MiB |

Godot logged `WARNING: 7 RIDs of type "Texture" were leaked` at renderer finalization. Their ownership was not established by this bounded study; repeated teardown/streaming safety is unproven, and no further native run was made to chase the warning. The raw receipt's `engine_execution_clean` field checks exit code only.

Hiding the volume does not immediately release its allocations. The added view shared the same World3D and scenario, with exactly one VoxelGI node and one data resource. This verifies reuse, **not zero per-view GI cost**, full source-water reflections, six-face room-probe publication, or a target-GPU advantage. Renderer counters on llvmpipe are allocations, not measured hardware VRAM. The initial heavy texture baseline also remains; VoxelGI does not solve that cost.

## Decision and stopping condition

**Rejected for production.** The existing authored bath remains essentially unchanged visually. The small signal and extra allocations do not justify a resolution escalation, brightness boost, or another bake loop. No 128 approval file was created. The native slot was returned after this single valid geometry bake and full controlled capture sequence.

A prior `run64-01` launch in the non-graphical workspace namespace failed immediately with display initialization errors, before script execution or baking. Its failure receipts are retained. The successful `run64-02` was launched through the supported graphical cloud terminal with Python 3. No display substitution or namespace workaround was used.

## Primary sources

- [Official Godot 4.6 VoxelGI guide](https://docs.godotengine.org/en/4.6/tutorials/3d/global_illumination/using_voxel_gi.html): supported renderer, static ShaderMaterial limitation, interior/quality and binary resource guidance.
- [Godot 4.6.3 VoxelGI bake implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/voxel_gi.cpp) and [voxelizer material/cell implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/voxelizer.cpp).
- [Godot 4.6.3 GI renderer implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/environment/gi.cpp): instance resources and live light updates. Measurements here, rather than source assumptions, determine the outcome.
