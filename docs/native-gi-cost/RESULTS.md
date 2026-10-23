# Actual-bath SDFGI diagnostic: partial bounded result

## Decision

**Do not change production GI settings from this test.** The actual bath shows a substantial nonzero response when SDFGI is enabled, unlike the earlier unrelated small control. However, the required closing-OFF capture did not finish inside the 480 s guard, and the red emissive positive control did not establish a separately identifiable red bounce. This is not an accepted speedup, complete performance comparison, visual improvement claim, or target-GPU benchmark.

The one native run was intentionally killed by its wall-time watchdog at **480.12 s**, during closing-OFF warm-up. Runner exit 124, native process return -9. This was **not** an observed out-of-memory event. No retry was performed. The serial native slot was released after process completion.

## Useful measured evidence

Godot **4.6.3**, native Forward+ Vulkan, cloud **llvmpipe LLVM 19.1.7, 256 bits**, `LP_NUM_THREADS=4`. One actual authored circular bath, no water or other rooms. These are wall intervals between actual rendered frame-post-draw events, not GPU timestamps, target hardware FPS, or a complete-game quality preset.

| Captured state | Warm frames before timing | Timed frames | Mean wall ms | Median wall ms | p95 wall ms | Rendering allocation MiB | RSS at capture MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| Opening OFF | 16 | 24 | 1,868.35 | 1,822.02 | 2,172.08 | 783.00 | 1,561.47 |
| SDFGI, 4 cascades | 48 | 24 | 1,742.23 | 1,728.53 | 1,842.70 | 1,112.29 | 1,995.48 |
| SDFGI, 6 cascades | 48 | 24 | 1,904.92 | 1,922.40 | 2,075.98 | 1,232.60 | 2,396.32 |
| Closing OFF | Incomplete | Not captured | — | — | — | — | — |

- Six versus four cascades had **162.68 ms greater observed mean wall time** and **120.31 MiB greater reported rendering allocation**. This is one ordered sequence, not an isolated causal effect or a reliable optimization gain.
- The four-cascade sample happened to be shorter than opening OFF. Do **not** call that an SDFGI speedup: it lacks a closing-OFF drift check and independent repeats.
- First-half/second-half median drift was 9.13%, 6.64%, and 5.34% respectively, within the predeclared 15% within-window timing check. This does not prove lighting convergence or remove between-state drift.
- Initial/transition work is excluded from the table: opening OFF warm-up **110.71 s**, four-cascade transition/warm-up **94.66 s**, six-cascade transition/warm-up **105.17 s**. Opening OFF included individual intervals of 50.55 s and 34.09 s. This does not attribute those intervals exclusively to shader compilation.
- Peak sampled native RSS was **2.344 GiB**, below the 3.0 GiB sampled guard. Rendering allocation is the engine's counter, not measured physical GPU VRAM. Cgroup memory-event files were unavailable in the graphical process namespace; no cgroup/OOM conclusion is supported.

## Image and contribution evidence

All three saved native scene-HDR captures are **640 × 360**, finite, zero negative RGB components, maximum RGB **5.0**. They were copied read-only from the resolved native pre-tone-map color texture into an owned RGBA32F buffer. The borrowed engine texture was never freed. Tone-mapped PNGs are saved separately at the same dimensions. Captures/readbacks were outside timed samples.

- SDFGI-4 mean absolute RGB delta from opening OFF: **0.08959** linear HDR. Six cascades: **0.09183**. Mean tone-mapped absolute RGB differences are **20.83** and **21.28** display levels out of 255. The visible bath becomes brighter and bluer. This is genuine nonzero image response, not a zero-delta test.
- A clean actual plaster-wall crop has mean luminance increase **0.11431**; the ceiling crop **0.11625**. The four and six-cascade values are identical in those crops. The originally predeclared broad wall crop included the control-panel edge; it is preserved and flagged, with a separate clean-right-wall diagnostic crop added after OFF-image geometry review.
- Three small direct-light-excluded receiver samples increase by **0.05798–0.05921** linear luminance, but their red-excess changes are **negative**, about **−0.0324 to −0.0328**. Both GI modes give the same values there. There is no demonstrated separate red-panel bounce. Blue indirect/sky response can mask red contribution, so this also does not prove that emission contributes exactly zero.
- Four versus six-cascade full-frame HDR mean absolute RGB difference is **0.002242**; maximum difference **0.06079**. 36,435 of 230,400 pixels differ by more than 0.00001 in any RGB channel. Those differences do not establish better image quality.
- No closing OFF exists. All deltas above are versus the opening OFF only, with no temporal-drift bound. Image response with `sdfgi_read_sky_light=true` must not be equated with verified emission-driven voxel bounce.

Visual review confirms the real circular room, opening, basin, railings and control meshes. The 4/6 frames look broadly similar and brighter than OFF. No visual improvement is accepted. See [the labelled partial contact sheet](run01/partial-off-4-6-off-contact-sheet.png) and [receiver regions](run01/receiver-regions.png). The blank closing-OFF cell is intentional, not a missing-file substitution.

## Exact resource and setting scope

- Current `formal_bath.glb`, built through the current `FormalRoomBuilder`, `PoolMaterials`, and `PoolLighting`: **70 visible authored meshes / 46,776 triangles / 687 collision nodes**. Mesh census: 67 STATIC GI, 3 disabled glazing meshes. Geometry SHA-256: `f263ebbd828c03f5f5e0010856d671af667fbcc349f16f36a0ba60fcc8a59c01`.
- Five actual production lights: `FormalSourceFill0/1`, `BathOculusSky`, `BathBasinReturn`, `ApertureSun`. Their transformations, energy, indirect energy, bake mode, shadow settings and masks are recorded verbatim in `report.json`. Only their control-layer bit is excluded, identically in every phase.
- Two diagnostic STATIC StandardMaterial3D boxes, not substitute room geometry: neutral diffuse receiver at (−2.6, 0.85, 2.3), size (1.8, 0.25, 1.6); black-albedo emission panel at (−3.65, 1.65, 2.3), size (0.3, 1.6, 1.6), emission RGB (1, 0.02, 0.02), multiplier 5. No diagnostic Light3D is added. Both meshes are above the production planar clip plane.
- Water simulation, water surface, water-owned planar view, water probes, avatar and the other four rooms are **omitted, not altered or cheaply replaced**. The production material library is explicitly told there is no water caustics atlas, with zero caustic gain. This is not a water-performance test.
- Camera (0, 2.15, 7.4), looking at (0, 1.6, −2), vertical FOV 75°, near 0.08, far 60; cull mask 5. Mood transition completed and frozen. Native 640×360, 2×MSAA, TAA off, render scale 1, VSync off, uncapped frame rate. Project logical stretch coordinates are 1280×720, so receiver projections are mapped to actual capture coordinates at 2:1.
- **Not a Medium preset.** The desktop quality installer is not instantiated. The fixture explicitly requests directional atlas size **2048, 16-bit=true**, and positional atlas size **2048**. Applied directional allocation has no recorded getter; positional bit depth/quadrant allocation were not independently captured. Project directional and positional shadow filter-quality settings are both raw value 3. Per-light directional distance remains the production value 120 m. See `configuration-supplement.json` for source provenance, rather than inferring full-preset equivalence.
- Fixed diagnostic environment: SSIL, SSR, glow and volumetric fog disabled; production ambient and SSAO retained. Exposure 1.12 and tone-map mode raw enum 4 remain fixed. Every captured phase reports unchanged non-GI environment/camera/light state.
- GI min cell **0.2 m**, energy 1, bounce feedback 0.65, occlusion on, read sky on, normal/probe bias 1.1, Y-scale raw enum 1. Actual project GI raw enum values: probe ray count 1, frames to converge 5, light update 2, half-resolution false. Full runtime properties are retained rather than guessing enum labels.
- The runner checked hashes before and after: tracked production geometry/materials/lighting/settings, all original water scripts and water shaders, and the launched fixture were unchanged. No production file was edited by this task.

## Source concern, not a diagnosed cause

The architecture shader conditionally discards fragments below world Y 0.318 when camera layer marker 524288 is present. The inspected Godot 4.6.3 SDFGI material path invokes material fragment code. Its inspected SDF render-scene-data construction does not explicitly initialize `camera_visible_layers`; the field declaration also lacks an initializer. This is a concrete source-level confound worth recording, **not evidence of the runtime value, a proven voxelization failure, or the cause of this result**. The StandardMaterial control above that plane avoids this custom-shader condition.

Primary references: [Godot SDFGI usage](https://docs.godotengine.org/en/4.6/tutorials/3d/global_illumination/using_sdfgi.html), [4.6.3 SDFGI renderer source](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2729-L2802), [render scene-data field declaration](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/render_scene_data_rd.h#L39-L73), [shader material compilation path](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp#L710-L714).

## Evidence and reproducibility

- `run01/launch.json`, `memory.json`, `receipt.json`, `source-stability.json`, `godot.log`: exact invocation, watchdog, resources, terminal outcome and source integrity.
- `run01/report.json`: raw available phases, frame intervals, finite native readback checks, complete actual mesh/material/GI census and light/environment/camera values. It deliberately remains `completed=false`, `execution_pass=false`.
- `run01/partial-analysis.json`: explicit incomplete-comparison analysis; `performance_acceptance=false`, `visual_acceptance=false`.
- `run01/*.rgba32f` and corresponding PNGs: actual captured frames. `*-delta-x16.png` images are labelled diagnostic amplification, not beauty renders.
- `tests/native_gi_cost/analyze.py --allow-partial` reproduces the partial analysis without launching Godot. Full analysis refuses an incomplete run. `--self-test` passes. Parser check passed through the supported cloud terminal before launch. Native launch was also through that supported terminal, not a direct DISPLAY route.

The requested complete OFF→4→6→OFF experiment remains **incomplete**. This task stops after its single authorized bounded diagnostic; no bake loop, engine update, production switch, or additional native run is justified by this evidence alone.
