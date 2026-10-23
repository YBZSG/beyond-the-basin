# Source caustic performance and cadence

Source baseline: `source_provenance/beyond-the-basin-66a4543/app/pool-vct` at commit `66a4543602d9e774db07c2da12ce1d40d522532c`.

## Two different causes of perceived lag

1. The original `causticsRefresh=2` deliberately skips two water frames after each update. This produces 20 updates/s at 60 rendered frames/s, 10 at 30, and about 6.7 at 20. This is visible temporal stepping, not evidence of a synchronous GPU readback. Value `0` is the original supported per-frame setting. The source constants and cadence fixture remain unchanged; the PC quality layer can select `0` separately.
2. A refresh itself is substantial GPU work. High traces two 256-segment floor grids and sixteen 96-segment wall grids into separate 1024-square RGBA16F atlases. It then applies the original four separable filter draws and twenty mip draws. A slow refresh can lower whole-frame rate independently of the refresh interval.

The previous capture's eleven caustic updates over a displayed twelve-frame sample did not demonstrate a cadence bug: its count included warmup, and the water clock covered thirty-three simulation frames. Use counter deltas over the measured window, not lifetime counters.

## Audit findings

- `source_caustics.gd` does not call `texture_get_data`, `buffer_get_data`, `submit`, or `sync` in production. Photon transport, the Jacobian, blur and mip generation remain on the global RenderingDevice. There is no CPU caustic pixel generation.
- The steady-state submission path creates small parameter snapshots, push constants and a uniform buffer update. Texture targets, mesh index buffers, shader pipelines, geometry buffers and descriptor sets are retained. Geometry changes are separate from steady-state refreshes.
- Incoming occlusion is a source 256-square mask. The production prepared-terrain path publishes two complete masks and a triangle BVH together and disables incremental render-side mask preparation. The legacy `set_geometry` path still supports budgeted CPU mask preparation and intentionally invalidates caustics while preparing.
- The neighboring wave solver has asynchronous 384-square physics readback and an explicit synchronous fallback if async requests fail. Those are separate from caustic transport. Its `sync_reads`, `async_lands`, pending age and host conversion should be inspected before attributing an entire frame stall to caustics.
- Source photons are forward-projected indexed triangles, not a fullscreen raymarch or a scrolling pattern. Floor rays refract with a second bathymetric intersection; wall rays retain reflected and transmitted branches. Outgoing BVH visibility does not introduce an invented bounce budget.

## Same-workload optimization

`caustic_wave_cache.glslinc` evaluates the unchanged shared `poolSurfaceHeight` and `poolNormal` equations once for each original lattice vertex, in FP32, on the same refresh. Floor and wall lattices have separate storage and preserve the original opposite row orientation. The photon vertex shader reads those exact samples for its repeated lamp and wall passes.

At High, the logical repeated evaluations decrease from `2 × 257² + 16 × 97² = 282,642` to `257² + 97² = 75,458`, a 73.3% reduction in repeated height/normal evaluations. This is a count reduction, not a claim of equal overall frame-time savings. The cache takes 2,414,656 bytes and two compute dispatches per High refresh. It never persists old wave samples across refreshes.

Wall rays with `t <= 0` or `t >= 64` have exactly zero source throughput. The optimized path avoids their outgoing BVH traversal while preserving their zero power and projected position. Valid rays retain the same triangle tests, ray offsets and receiver tolerance.

Unchanged:

- Source wave, normal, Snell, Schlick and Beer equations.
- Original photon grids, ray branches, full atlas resolutions, additive HDR accumulation and fragment derivative Jacobian.
- Source incoming masks and genuine opaque triangle BVH.
- Original strip-safe blur coefficients, already-half-resolution intermediate filter and mip chain.
- Wave physics, interaction simulation and default source cadence contract.

`reuse_wave_samples=false` and `skip_zero_power_visibility=false` retain the direct evaluation path for diagnostic A/B comparison. This is not a lower-quality fallback. Optional `profile_enabled` captures completed GPU timestamp queries; it is off in normal play. Diagnostics include cadence reasons, parameter invalidations, last render-thread queue latency and CPU submission time. The production readback byte count is explicitly zero.

## Verification

CPU-only:

```sh
XDG_DATA_HOME=/tmp/source-caustic-tests godot --headless --path . --script res://tests/source_caustic_contract.gd
XDG_DATA_HOME=/tmp/source-caustic-tests godot --headless --path . --script res://tests/source_caustic_perf_contract.gd
python3 tests/source_caustic_equations.py
```

Native windowed, with no other GPU test running:

```sh
./tests/source_caustic_perf_run.sh
```

The runner uses Vulkan/Mobile only as an isolated test viewport. High transport still uses the complete 1024-square targets, 768-square input fields, source photon grids and all eighteen photon passes. It runs direct/cached/cached/direct (ABBA), reports GPU stages separately from render-thread CPU submission and wall-frame intervals, and performs output readback only after the timed sections to compare two deterministic wave times. GPU pixel comparisons report byte equality or explicit error metrics, never label nonidentical bytes exact.

Expected report: `output/source-caustic-perf-high.json`. The fixture checks a non-flat wave field, detail waves, a depth discontinuity and 108 genuine triangles. It is a controlled kernel test, not a whole-game benchmark. Cloud llvmpipe results must never be represented as FPS on the user's PC or phone.

Native performance/parity results are recorded below after the controlled run completes.

### Controlled High kernel result (2026-10-21)

Godot 4.6.3, Vulkan Mobile, cloud `llvmpipe (LLVM 19.1.7, 256 bits)`; 16 timed refreshes per phase, direct/cached/cached/direct:

| Phase | GPU refresh median | CPU render submission median | Queue latency median |
| --- | ---: | ---: | ---: |
| Direct A | 238.062 ms | 0.194 ms | 0.034 ms |
| Cached B | 183.739 ms | 0.206 ms | 0.033 ms |
| Cached B | 176.932 ms | 0.197 ms | 0.033 ms |
| Direct A | 234.496 ms | 0.198 ms | 0.033 ms |

The mean of the two direct medians is 236.279 ms; cached is 180.336 ms, 23.6767% lower. This is a same-workload isolated GPU refresh result on a software renderer, not a game FPS or target-hardware speedup claim. Its full-frame wall intervals tracked GPU work rather than the roughly 0.2 ms of host encoding. The original production caustic readback remains zero bytes.

At `poolTime=0` and `17.25`, both complete base-level floor and wall images were byte-identical between direct and cached paths: zero maximum absolute error and zero relative L1 error. See `output/source-caustic-perf-high.json` and `docs/verification/source-caustic-perf-native.log`.

The first native run correctly failed because the compute descriptor set omitted declared-but-unused incoming-mask samplers (bindings 4 and 5). Godot retains those shared declarations in the SPIR-V layout. Both are now bound; a failed cache set also stops the draw instead of drawing uninitialized/stale wave data. The failed report/log are retained as `output/source-caustic-perf-high-invalid-binding.json` and `docs/verification/source-caustic-perf-invalid-binding.log`; no performance claim uses that run. The passing run had unrelated no-audio-device startup errors and a Mobile TAA warning. The next runner explicitly selects Dummy audio; this is not represented as an error-free whole application test.

### Full-scene fixture

`tests/source_caustic_perf_scene_run.sh` uses native Forward+, 800×450, the actual default original room, High 768-square water fields, full 1024-square caustic atlases and 1024-square planar reflection. Player and props remain frozen. It waits for streaming, terrain and HDR probe publication, stops new background prewarm requests only after readiness, then verifies no geometry/probe/camera changes in each measured interval. Exogenous drips and crest spray are fixture-only disabled so no MPM domain appears. A final small ripple uses the real source detail-impact entry point.

It records twelve frames per phase: direct refresh 2; direct refresh 0; cached refresh 0 twice; direct refresh 0 again; caustics disabled; cached controlled ripple. GPU caustic time, whole-frame wall intervals, actual cadence deltas, and wave readback/host-parse telemetry are separate. A fixed 60 Hz simulation clock does not pretend the cloud renderer is realtime. Failure to reach a steady scene is an explicit failed/inconclusive benchmark, not a valid performance comparison.

The first full-scene attempt did **not** reach a valid measurement window. After 182.3 seconds on llvmpipe it still had 20 streaming units pending, no terrain publication and zero caustic refreshes; therefore no full-game timing/speedup conclusion is drawn from it. Its final frame reported 1,739 render draw calls. Shutdown also reported seven Texture RIDs leaked during the incomplete-startup teardown; this is retained, not labeled a clean full-scene pass. Evidence: `output/source-caustic-perf-scene-unsteady-startup.json` and the corresponding native log.

The fixture now completes the same resident room construction synchronously before warmup (setup only), rather than rendering each expensive intermediate streaming state. It accepts `--warmup-seconds=N` for a longer explicit initialization budget, while retaining its steady-state gates. This does not change production streaming or reduce scene quality.

### Why this startup attempt differed from earlier captures

Code inspection of the failed run found no disabled batching or substituted geometry. `PoolRoomBuilder.batch_architecture_enabled` defaulted to true, but batching occurred only at the end of `build_interior`. `PoolWorld` installs all 25 collision shells first, then completes one interior per rendered frame. Unfinished shells are therefore still individual meshes during the slow software-rendered startup. The diagnostic's value `streaming_pending=20` summed queue and builder entries, representing ten unfinished rooms, not twenty distinct rooms.

The terrain preparer waits three process frames after the latest room-change invalidation; while another room completes every frame, no stable terrain payload is published. That explains zero water time and zero caustic refreshes in the failed startup: no caustic kernel was running yet. Existing `--qa` captures call `complete_pending_streaming()` before their readiness loop, unlike the first version of this fixture. Their startup states and measured windows are therefore not comparable. The fixture launcher also defaults to its own `/tmp` cache rather than the older QA launcher's persistent shared shader cache; cold compilation is a possible additional contributor but was not independently measured.

The same seven-Texture-RID shutdown warning is present in the preserved earlier `docs/verification/original-scene-capture.log`. The caustic wave-cache change adds a storage buffer, not a new texture. Current evidence does not establish that warning as a new caustic-cache regression. Whole-scene performance testing was stopped after the explicit inconclusive result; the setup correction is prepared but has not been natively rerun.


### Bounded production startup correction

`PoolRoomBuilder.build_shell()` now batches its immutable architecture immediately, before the next rendered startup frame. When the interior arrives, `PoolSourceArchitectureBatch.batch()` combines the existing shell batches with new primitives by the same live material, shadow, layer, GI, index and optical-exclusion groups. It does not append duplicate shell faces or leave separate shell/interior draw groups. Repeated calls without new primitives return the existing report. Original primitive provenance stays in construction order; singleton primitives are recorded only once. No detached node or raw-mesh cache is retained.

This changes submission organization, not generated geometry, RNG, native collision, room streaming order, optical exclusions, materials or source simulation. No `pool_world.gd` or `main.gd` change was needed. The previous batching switch remains available for validation.

Headless tests on all 60 original room fixtures passed:

- Before the interiors exist, 904 original shell meshes become 162 draw meshes, an 82.08% draw-mesh-count reduction across the fixtures, not an FPS claim.
- Finished rooms still have exactly the old one-pass result: 5,854 original primitives become 257 draw meshes.
- 2,569,272 triangle-corner checks cover unbatched versus one-pass, unbatched versus batched shell, and unbatched versus completed two-stage construction. Maximum position error is zero; maximum UV error is zero. The minimum normal dot against primitive normals is 0.99999988079071, within native ArrayMesh normal packing.
- The completed two-stage and old one-pass outputs additionally compare **exactly equal** for every triangle-corner position, packed normal and UV in every live material group. Collision counts, original triangle counts, ordered provenance and repeat-call idempotence remain unchanged.
- Unchanged `original_geometry_parity.gd` passes for 60 rooms, 5,854 primitives, 125 signs, 96 ladders and 2,722 solids. `world_room_parity.gd` passes all 60 fixtures. `world_streaming.gd` passes its actual startup set with 2,601 source meshes and the unchanged 117 final draw meshes.

Evidence: `docs/verification/source-caustic-startup-batch-cpu.log` and `docs/verification/source-caustic-startup-batch-exact-cpu.log`. This bounded correction has not been GPU-benchmarked. The full-scene performance result remains explicitly inconclusive; no new native run was launched for it.

## Exact floor-result reuse, integrated 2026-10-21 22:29 UTC

The next measured hotspot was repeated floor transport, not CPU readback. The
optional floor-result pass evaluates the unchanged two-lamp floor projection,
attenuation and BVH visibility once per original lattice vertex on each refresh.
It writes two FP32 records per vertex, then the existing indexed floor draws
read those records. Fragment derivatives/Jacobian, additive accumulation, all
18 photon draws, wall transport, blur and complete mip chains are unchanged.
No previous refresh's results may be reused. The independent original photon
shader/pipeline/descriptors remain present for walls and every fallback.

At High the extra buffer is 4,227,152 bytes. Optional initialization failure,
missing descriptors, disabled wave caching, or `--no-caustic-floor-result-cache`
selects the original path. A disabled initialization creates none of the five
optional RIDs. Partial initialization failure immediately releases only the
optional group, preserving the independently initialized original pipeline.
Geometry replacement, quality changes and disposal clear both optional
uniform-set caches. Diagnostics are exposed as `floor_result_cache`, separately
from actual optional GPU timestamp diagnostics and CPU encoding time.

### Native evidence

The strict floor-only experiment passed 104 raw-base/full-mip RGBA comparisons
across every source quality and six High edge cases. Its phase-balanced High
median was 150.482 → 126.611 ms on cloud llvmpipe (15.9% lower). The more general
all-photon cache experiment was slower than floor-only and was not promoted.

The production-shaped version then passed **116** comparisons totaling
1,389,712,464 bytes, adding explicit runtime-disabled, unavailable-cache and
wave-cache-disabled fallback checks. Timed phases were
original/cached/disabled/disabled/cached/original, eight refreshes each, with
complete per-sequence GPU timestamps and stable execution-source hashes:

| Path | First phase median ms | Second phase median ms | Balanced median ms |
| --- | ---: | ---: | ---: |
| Unmodified original | 150.292 | 155.967 | 153.130 |
| Optional floor cache | 126.541 | 137.570 | 132.055 |
| Explicitly disabled cache | 153.904 | 154.994 | 154.449 |

That second run supports **13.8% lower total photon refresh time** relative to
its original control. These are sequential same-workload cloud software-Vulkan
measurements, not a claim of dedicated-hardware isolation, target-device FPS,
or a speedup for unchanged wall passes. Native equality is established on the
tested Godot 4.6.3/llvmpipe path, not untested Windows/Android GPU drivers.

A final test injected eight optional construction failures, one descriptor
failure and one positive cached control. All **40** further image comparisons
matched the original exactly. Every partially created optional RID reached
actual `RD.free_rid`; all ten disposed owners left zero actual live textures.
Shader failure released one partial RID, pipeline failure three, buffer failure
four and header-upload failure all five. The test models failures without
inducing driver OOM and does not add fault switches to production.

Lifecycle tests track `RD.texture_is_valid` and detached wrapper dimensions.
A nonzero historical `Texture2DRD.texture_rd_rid` alone is not a live allocation
in Godot 4.6.3. The initially incorrect wrapper assertion remains archived rather
than relabeled a pass. These component tests do not resolve the separate
full-scene seven-TextureRID shutdown warning.

Evidence:

- `output/source-caustic-floor-only-cache-audit.json`
- `output/source-caustic-floor-production-stage.json`
- `output/source-caustic-floor-failure-audit.json`
- `docs/verification/eight-hour/water/photon-floor-production-stage-native.log`
- `docs/verification/eight-hour/water/photon-floor-failure-native.log`
- `tests/source_floor_result_cache_contract.gd` (11 checks enabled and disabled)
- `docs/verification/eight-hour/water/exact-water-bundle-source-hashes.json`

The integrated source and shader bytes equal the tested production-shaped
fixtures, with the final rollback addition validated by the failure fixture.
The next full-scene/native splash and export package checks remain release gates.

### 2026-10-22 00:55 UTC validation follow-up

The promoted-water native regression has now passed its five serial jobs: actual
native and GDScript-fallback SWE callbacks, cached/reference liquid pixel tests,
and a live 41,418-particle, three-domain splash. The latter exercised 180 native
particle-gate calls, 28 frames with visible liquid, 90 completed callbacks and no
native gate or transfer-clear fallback. Current host/shader/binary identities are
bound by `verification/eight-hour/water/promoted-water-native-review.json`.

No outer terminal exit marker was recorded for this particular run. Its fresh
individual logs, final pass report and the launch owner's observed completion
are retained; the older `optimized-native-runner.log` is not reused as exit
evidence. This isolated splash is not a full-room caustic/probe capture and does
not establish device FPS. Actual-scene and final export acceptance remain
separate gates.

The fixed seven-TextureRID shutdown warning was independently reproduced by the
transition owner's isolated Godot-only ReflectionProbe control: baseline zero,
with one native probe exactly seven, after three same-World3D create/free cycles;
post-cleanup texture bytes stayed flat. No source water, helper, custom RD owner
or game preload was present. This establishes an engine-only reproduction of
the signature, not proof that every historical warning has the same owner or
that source-water growth can be ignored. See
`verification/eight-hour/lifecycle/lifecycle-isolated-probe-01-summary.json`.
