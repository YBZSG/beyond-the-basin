# Exact water execution improvements, 2026-10-21

This iteration keeps the water from the pinned original repository at
`66a4543602d9e774db07c2da12ce1d40d522532c`. It changes execution overhead, not
appearance or simulation quality. There is no replacement ripple shader,
particle-count reduction, simulation downsampling, skipped APIC stage, shorter
caustic path, or new timing policy.

## Results established so far

| Change | Observed result | Evidence boundary |
| --- | --- | --- |
| Fused native SWE callback | 36.268 → 0.978 ms median, 97.3% less CPU callback time | Complete production-sized callback, shared Linux CPU, no GPU wait/FPS claim |
| Engine-owned surface descriptor cache | 8.453 → 1.656 microseconds per request, 80.4% lower host API cost | Bounded global-RD microbenchmark; all HDR pixels and lifetime checks pass |
| Exact MPM grid transfer clear | Byte-identical APIC particle state in all measured cases | GPU timing benefit varies between runs; see both runs below |
| Splash spawn loop invariant reuse | 22.7–36.9% lower CPU initialization cost across five measured cases | Original particle hashes, params, RNG and depth-callback sequence remain exact |
| Capture environment synchronization | Current source/formal illumination, without applying main tonemapping twice | 120 CPU lighting checks; actual scene capture remains a separate acceptance step |
| Exact native incoming masks | 8,930.159 → 115.480 ms median, 98.7069% lower CPU preparation time | Same 2 × 256² masks; independent source/reference fixtures and actual original/formal room bytes |

The standard 384² physics field, three 18,000-particle domain caps, 80³ MPM grid,
1/720-second APIC timestep, 36-step submission cap, source interactions,
anisotropic reconstruction, separate 4x-MSAA whitewater, IOR/absorption,
caustic optics and shaders are unchanged. Existing exact caustic lattice caching
is retained; this document makes no new caustic GPU speedup claim.

## 1. Native readback without a native simulation dependency

`source_wave_solver.gd` delegates only an already-returned RGBA16F byte payload
to a small, stateless CPU helper. The helper validates every texel, decodes the
three fields directly into owned packed arrays, and performs the original
sequential binary64 energy and peak reduction. It does not touch the GPU,
request cadence, timeout clock, request serials, terrain generations, or any
public field. The existing callback publishes all three fields and reductions
atomically, then emits the same signal.

There is no fast math, FMA contraction, reassociation, parallel reduction, or
approximate half conversion. Signed zero, subnormal halves and the entire
finite binary16 domain are covered. Invalid alpha, Inf/NaN, dimensions or
payload length reject the complete result without partial publication.

The unchanged GDScript path remains available if the class is absent, or with:

```text
--no-native-water-readback
```

`readback_parser_backend` records `native_exact` or `gdscript`.
`readback_native_ms` records the fused native stage. Existing convert/reduce
metrics apply to the fallback only; we do not manufacture separate timings for
work fused into one native call.

### Independent numerical authority

- `tests/fixtures/source_wave_solver_pre_native.gd.fixture` preserves the full
  pre-change callback, SHA-256
  `00dcd737937c18c8a2927e6ff33b65c298f2b3672c28967bddf3a470264d8551`.
- `source_readback_original_reference.mjs` executes the literal `parseReadback`
  method body from the pinned original TypeScript and literal Three 0.185.1
  half-decoder/table bodies. It does **not** reuse the port or native parser.
- Five independent source fixtures include all finite half values, signed
  zeros/subnormals, weak production waves and two seeded random 384² payloads.
  Field hashes and raw binary64 reduction bits are recorded in
  `tests/fixtures/source_readback_original.json`.
- `source_readback_original_parity.gd`: 79 checks, both complete production
  callback backends agree with that original-source authority.
- Both backends pass the unchanged 30-assertion readback lifecycle contract:
  63,488 finite encodings, 6,144 physical-channel nonfinite cases, all 65,535
  invalid alpha patterns, atomic signals, generation/reset/disposal guards,
  request retirement and transport-error ownership.
- Native standalone contract: 72,823 assertions, plus 1,000 typed ABI calls,
  concurrent shared-helper calls, and ASan/UBSan. LeakSanitizer was unsupported
  by the sandbox and is not claimed as passed.

`source_readback_runtime_perf.gd` alternates complete old/new callbacks for 31
measured iterations after three warmups. Every pair checks all field bytes and
exact reductions: 170 checks. The 36.268/0.978 ms result includes normal callback
instrumentation and atomic publication, but not downstream signal subscribers.
Raw report: `verification/eight-hour/water/source_readback_runtime_perf.json`.
The isolated helper benchmark independently measured 35.775/1.056 ms.

### Real target artifacts, explicit platform limits

The standard GDExtension descriptor ships actual compiled Linux x86-64, Windows
x86-64 and Android ARM64 binaries, not placeholders. They have one exported
initialization symbol, no external runtime imports, and no OS/network/file/GPU
access. Android uses 16 KiB-compatible ELF alignment. Local compiler archives
and object intermediates are outside the exported resource set; the build
folder has `.gdignore` so Windows `.obj` is not imported as a mesh.

Linux execution and ABI are verified. Windows and Android cross-build and
static binary audit are verified; this subsystem has **not** executed either
artifact on its target device. Package inclusion/loading and device behavior
must not be inferred from a successful cross-build. The packaging verification
owner separately checks Windows dependency adjacency and Android native-lib
placement. No macOS, iOS, Web, 32-bit, Windows ARM64 or Linux ARM64 binary is
provided. Unsupported target exports must omit this descriptor and use the
GDScript fallback. See `native/source_water/README.md` for build commands,
licenses, provenance, checksums and exact unsupported-editor behavior.

A fresh headless editor import exposed the known Godot extension-documentation
shutdown race [#111048](https://github.com/godotengine/godot/issues/111048).
Independent no-extension and startup-prelisted controls exit 0, while late
first discovery aborts before helper deinit. The packaging runner must bootstrap
the standard extension list before first import; a failed process is never
counted as a successful build. The shipped native parser did not change for
this editor-lifecycle issue. Details and retained failure evidence are in the
native README.

## 2. Exact zero initialization instead of a redundant MPM kernel

Original stage 0 writes four integer zeros to all 512,000 cells. The production
encoder can replace precisely those 8,192,000 bytes with `RD.buffer_clear`.
Godot tracks the transfer/compute dependency. Because buffer operations cannot
occur inside an active compute list, the unchanged stages 1–4 are encoded in a
per-substep list. Deletions happen before the first step; source resetHeads,
link and exportState stages 5–7 remain after the final step. Their barriers and
source shaders are unchanged. No extra host staging or synchronous readback is
introduced.

A failed transfer clear falls back to original stage 0 for that substep and
increments `gridClearFallbacks`. The original whole compute-list path can be
selected with `--no-transfer-mpm-clear`. `transferGridClear` reports selection.

The independent reference is the original stage-dispatch sequence, not a
second invocation of the optimized helper. The optimized side invokes the
actual production `_rd_encode_steps`. Original impact/collider/crest initial
particle fixtures remain byte exact; each has 13,494–13,806 particles and runs
all 36 substeps. Five measured repetitions per path follow one warmup,
alternating order. Every resulting full APIC particle buffer is byte-identical.
Exported anisotropic covariance differs by at most 2.384e-7 between runs due to
the unchanged atomic linked-list traversal ordering; this is separately
reported, not mislabeled byte exact.

Median isolated GPU milliseconds on llvmpipe, all timer completions present:

| Fixture | Initial validated experiment: compute → transfer | Production-encoder rerun: compute → transfer |
| --- | ---: | ---: |
| Impact | 150.831 → 120.295 | 132.231 → 133.374 |
| Collider | 165.068 → 161.060 | 134.660 → 134.376 |
| Crest | 135.500 → 131.014 | 139.925 → 124.678 |

These are variable shared software-renderer results. They do **not** establish
an across-the-board 20% splash improvement, real-device GPU benefit or game FPS.
The mechanism is exact and the production run demonstrates a useful crest
case, but actual hardware may benefit differently. CPU encode time and GPU
timestamps are measured separately, with allocation/readback outside the GPU
interval. Raw reports are `output/source-mpm-clear-perf-pre-integration.json`
and `output/source-mpm-clear-perf.json`.

The first attempt missed three timer query completions; its particle comparisons
passed but its overall result was a failure. That report/log are retained as
`source-mpm-clear-perf-incomplete-timers.json` and
`verification/source-mpm-clear-incomplete-timers.log`. Continuous frame-post-draw
timer collection fixed the harness; missing timers are still test failures.

## 3. Device-owned surface descriptors

`source_liquid_surface.gd` now requests descriptor sets through the global
`UniformSetCacheRD`, on the same render thread/device used by its renderer.
Binding order, RID identity, shader, sampler, uniforms, target format and draw
order are unchanged. Godot owns cached sets and invalidates them when a bound
texture, buffer or shader is freed. The renderer never manually frees a cached
RID. The old allocate/draw/free path remains selectable with
`--no-water-descriptor-cache`.

The fixture checks full HDR byte equality at 17×23, 32×32 and 64×35, reuse of live
RIDs, unrelated resize behavior, source texture invalidation, shader/buffer
invalidation, and complete drain of renderer-owned resources: all 14 checks
pass. The benchmark allocates at most 128 transient sets per render callback,
then allows four retirement frames; 15 measured alternating batches follow a
warmup. Median cost is 1.082 ms transient vs 0.212 ms cached per 128 requests.
This removes small repeated host allocations; it does not explain the entire
splash cost or establish whole-frame performance.

The first unbounded microbenchmark attempted 10,000 transient allocations per
callback, with many more before frame retirement. Godot crashed in the **old
transient creation branch**, not the cache call. Resource-retirement pressure is
an explanation consistent with the bounded pass, not a proven driver root
cause. The failed log is retained as
`verification/source-surface-descriptor-unbounded-crash.log`. No crash result is
counted as a pass. Production stayed disabled until the bounded lifecycle/HDR
fixture passed.

Godot API authority:
[UniformSetCacheRD](https://docs.godotengine.org/en/4.6/classes/class_uniformsetcacherd.html).

## 4. Reuse exact splash initialization constants

The original source places multiple vertical particles at each XZ column. Its
column distance, envelope and upward/outward impulse are identical for every
particle in that column. `build_source` now computes those scalar binary64
values once per column, and caches the immutable queued source's flow/impulse
values instead of repeatedly accessing/converting dictionary fields. Individual
random jitter still executes in the same order for every particle; no particle,
column, depth query, parameter, seed or arithmetic expression is approximated.

`source_spawn_exact_perf.gd` compares with the immutable pre-change host over
small click, impact, collider, crest and partial-land cases. All complete raw
particle bytes, parameter bytes, counts, cell size, final RNG state and the
ordered depth-query coordinates are identical. Every measured iteration also
checks particle and parameter bytes. The separate original-source binary hash
test still passes all four canonical source fixtures.

Twenty-one alternating measured iterations follow three warmups. Median CPU
initialization savings are 31.0%, 30.7%, 26.7%, 36.9% and 22.7% respectively on
the shared host. Absolute durations vary with competing cloud CPU work, so this
is not an in-game frame or device claim. Raw samples:
`verification/eight-hour/water/source_spawn_exact_perf.json`. The extension ABI
and target binaries did not change for this improvement.

## 5. Reflections follow actual lighting, without double grading

A deeply copied Environment retained stale sky and ambient values after a room
palette change. Planar capture now keeps one separate Environment with the
actual source Sky resource, shared read-only by the capture. Changed light,
ambient, fog, SSAO and SDFGI settings are synchronized; bounded live mood values
follow their tweens. No environment duplication occurs per frame. The capture
always retains linear tonemapping, exposure 1, no glow and no color adjustment.
The main viewport still performs its own postprocessing once.

120 CPU checks cover source→formal→source changes, unchanged-resource identity,
no-op refreshes, 20 tween samples and main-only postprocess isolation. Camera
projection, clipping, water exclusion and source optics were not changed. The
room-probe worker separately owns frozen six-face capture coherence and
invalidation. Neither CPU property checks nor a copied sky alone prove final
visual quality; the native authored-room checkpoint is separate.

## Reproduction and remaining checks

CPU-only, without starting a graphics process:

```sh
node tests/source_readback_original_reference.mjs
godot --headless --path . --script res://tests/source_readback_original_parity.gd
godot --headless --path . --script res://tests/source_readback_callback_native.gd
godot --headless --path . --script res://tests/source_readback_callback_native.gd -- --no-native-water-readback
godot --headless --path . --script res://tests/source_readback_runtime_perf.gd
godot --headless --path . --script res://tests/source_capture_lighting_contract.gd
godot --headless --path . --script res://tests/source_spawn_exact_perf.gd
```

Native serial runners, launched only by the assigned GPU slot owner:

```sh
tests/source_mpm_clear_perf_run.sh
tests/source_surface_descriptor_cache_run.sh
tests/source_water_optimized_regression_run.sh
```

The last runner passed on native Mobile Vulkan, with both production SWE
callback backends selected and accepted. Both descriptor modes pass all liquid,
droplet, occlusion, translation, refraction-gradient and direct-shadow checks;
all four retained PNGs are byte-identical across modes. The live three-domain
case has 41,418 simulated particles, 90 asynchronous callbacks, 2,124 unchanged
MPM steps, 885 returns and 40 return ripples. It reports zero grid-clear
fallbacks and empty solver/surface errors. Report:
`verification/eight-hour/water/source_water_optimized_regression.json`.

Two failed setup attempts are retained. Standalone fixtures bypassed Main's
Mobile scene-MSAA guard and the Android quality layer's HDR2D setup. Applying
those exact production settings first restored hidden-particle deltas to zero,
then restored the visible-droplet signal from half-scale UNORM to linear HDR.
No background color, acceptance threshold, shader, optics or separate internal
4x whitewater target was changed. Godot's pinned implementation explains the
[Mobile color-unit difference](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp#L716-L720).
Neither an Android device nor the user's PC has been accessed for this work.


## Optional delayed GPU timestamps (native validated)

`--source-gpu-timings` enables staged caustic queries (wave cache, floor photon
raster, floor filter, wall photon raster, wall filter, mip chains) and complete
MPM batch queries. No flag means no collector object, signal hook, timestamp
query or readback. Queries occur only between closed command lists. MPM timing
includes parameter uploads, all original substeps and export, but not the async
sample readback. Existing host submission and queue timings remain separately
labelled; neither is called GPU time.

A render-thread collector harvests the engine's already-completed timestamp
window after frame draws. It does not call `sync`, `submit`, texture readback or
buffer readback. Per-instance prefixes prevent cross-room/solver collisions;
128 pending samples and64 retained samples bound memory. Missing, invalid or
all-zero queries are reported rather than interpreted as zero-cost work. Its
main-thread report is deferred, avoiding concurrent mutation of diagnostic
Dictionaries. CPU-only synthetic query ingestion passes22 checks, but is not
GPU evidence. The serial native runner `tests/source_gpu_timestamps_run.sh`
now passes: 35 caustic samples and 12 MPM samples, with zero missing, invalid or
dropped query groups. Its caustic fixture deliberately alternates direct and
cached phases, so the overall 216.98 ms mean is **not optimized-only cost**.
Cached-phase medians are 192.19/190.68 ms versus 236.37/249.66 ms direct; cached
floor photons take about 93 ms and wall photons 78–83 ms. All four floor/wall
HDR comparisons remain byte-identical. The one-domain MPM fixture averages
81.22 ms per mixed 12/24-step batch. These are cloud software-Vulkan query
durations, not target-device FPS. The report retains raw GPU nanoseconds and
separate CPU encoding microseconds:
`verification/eight-hour/water/source_gpu_timestamps_native.json`.

Unit note: Godot4.6 documentation labels GPU timestamp results microseconds,
but the pinned4.6.3 Vulkan implementation multiplies raw ticks by Vulkan's
nanosecond timestampPeriod and returns nanoseconds. This collector and earlier
MPM experiments divide GPU deltas by1,000,000 for milliseconds; CPU timestamp
microseconds are separately divided by1,000. See the exact
[Vulkan implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/drivers/vulkan/rendering_device_driver_vulkan.cpp#L5352-L5381)
and [RenderingDevice implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/rendering_device.cpp).

## Calm surface normal audit

`tests/source_normal_field_contract.py` passes243 source-literal/analytic checks.
All ten shared wave functions in both shader ports match pinned `water-optics.ts`
after only `texture2D` API and zero-constructor adaptations. Fragment normal
assembly, XZ axes, floating-origin continuity and runtime time/quality bindings
are unchanged. This is a CPU source audit, not a GPU screenshot assertion.

At source defaults, the sampled unfiltered micro slope RMS is0.00115 and maximum
tilt about0.094degrees. The original reflection offset formula gives a
conservative micro-only displacement bound of0.029pixels at1m and0.0044pixels
at8m for a1180-pixel-wide image, before footprint band limiting. Micro normals
fade exactly to zero at18m. They are present at simulation time zero; waiting
changes phase, not amplitude. Twelve fixed60Hz frames advance the dominant
phase only0.0216radians. A nearly flat calm reflection therefore does not prove
missing normals. Real visible ripples should be assessed using the source SWE
and detail interaction paths, not by changing the original field coefficients.
Source default parameters and shader optics have not been changed for this audit.

The native compiled-field fixture also passes all 4,096 cases: source/port
micro and normal fields have zero byte mismatches, 3,104 micro samples are
nonzero, and the independent CPU analytic reference differs by at most
2.521e-8. This proves the compiled normal field, not perceptual screenshot
quality. See `output/source-normal-field-gpu.json`.


## Exact native incoming masks

The next cold-transition bottleneck is now removed from GDScript without
changing geometry or ray tests. The paired original origin-room benchmark
(109 solids, nine measured alternating calls after two warmups) measures
8,930.159ms →115.480ms including native input packing,98.7069% lower CPU time.
All55 synthetic/original/authored fixtures agree on7,208,960 mask bytes with
independent references. The production wrapper additionally reproduces all25
original-room fixture masks,3,276,800 bytes, in1,765ms combined on this host.
This is not an FPS, GPU or target-device performance claim.

The exact `.31` plane, two256² masks, AABB order, float32 Vector3 boundaries,
binary64 slab arithmetic and segment tolerances remain. Missing, older,
disabled or rejected helper results retain unchanged GDScript, including
custom double-precision-engine fallback. Linux/Windows/Android artifacts are
all rebuilt and statically audited; only Linux is runtime-executed here.
Build outputs are now staged and atomically renamed after successful builds.
See [full mask evidence and reproduction](SOURCE-NATIVE-INCOMING-MASKS.md).

## Exact indexed BVH host storage

The old median-split builder spent most CPU time repeatedly looking up
per-triangle Dictionary keys inside Godot's sorting comparator. A typed-object
candidate was rejected because it was no faster. The accepted implementation
sorts original triangle indices, with the same `Array.sort_custom` and the same
already-computed center values. It does not replace Godot's unstable sort,
change tie ordering, choose a different split, reorder nodes, or simplify any
geometry. Packed Float64 center components retain the Vector3 result without
adding a new rounding boundary. Output remains the same 48-byte node/triangle
layout, including zero padding and empty geometry behavior.

Each call owns a fresh `source_triangle_bvh.gd` builder; immutable caller inputs
are not changed. `SourceCaustics.build_triangle_bvh` retains its existing API,
with optional `prefer_indexed=false`, and `--no-indexed-water-bvh` selects the
unchanged Dictionary implementation. The helper is included in the terrain
cache's loaded-algorithm fingerprint, so stale payloads fail closed.

Validation completed before enabling the production wrapper:
- 46 independent frozen-old-builder cases, all 25 original room origins,
  equal-center unstable-sort ties across leaf boundaries, empty/trailing,
  degenerate/nonfinite, tiny/huge/signed-zero and seeded random geometry.
- 74,188,416 encoded node/triangle bytes compared exactly, with immutable input
  checks. The clean production helper body matches the validated candidate.
- 26 lifecycle checks, including four concurrent independent builders and
  retained prior outputs across reuse.
- 38 production wrapper checks in both normal and command-line-disabled modes.

Nine alternating measured calls per implementation, after two warmups each,
observed 3,049.326 → 1,112.199 ms median elapsed for the same 61,458-triangle
origin, a 63.53% reduction. A separate software-rendered screenshot was active,
so this is explicitly a contended CPU comparison; an isolated paired rerun is
pending before making a headline timing claim. No native binary was changed.
Evidence: `verification/eight-hour/water/source_bvh_index_contract.json`,
`source_bvh_index_lifecycle.json`, `source_bvh_production_contract*.json`, and
`source_bvh_index_perf-contended.json` in the same directory.

## Disabled receiver evaluation

The shared receiver now returns zero immediately only when `causticGain == 0`.
Every nonzero-gain expression, sampler and evaluation order remains unchanged.
This is a disabled-effect correctness guard, not an active-light clamp or an
attempt to conceal nonfinite caustic data.

The native UV2-material probe covers source architecture and source ceramic on
both floor and wall geometry. Four preserved legacy controls produce NaNs with
poisoned textures even at zero gain; the guarded cases produce finite zero.
All four finite positive-gain cases remain byte-identical to the frozen
pre-guard include. Positive gain with poisoned input still exposes NaNs, as
expected. A separate ceramic probe establishes that assigning `EMISSION = 0`
alone is insufficient: disabled receiver evaluation must actually be skipped.
This evidence does not identify a single internal sampler/arithmetic operation
as the cause. Camera-marker removal is identical in both bake-only variants.

Evidence: `verification/eight-hour/material-lighting/source-zero-gain-native.json`
and `ceramic-emission-cause-native.json`; frozen original include:
`tests/fixtures/source_caustic_receiver_pre_zero_guard.gdshaderinc.fixture`.

## 2026-10-22 00:55 UTC: current native gate and source prop rule

The post-promotion five-job native water regression passes against the frozen
production bundle. The actual splash exercised three domains, 41,418 particles,
90 callbacks, 180 native particle-gate calls and 28 visible-liquid frames, with
zero gate or transfer-clear fallback. All three target binary hashes and current
host/shader identities match the reviewed bundle. Fresh evidence and the honest
missing outer-exit observation are recorded in
`verification/eight-hour/water/promoted-water-native-review.json`; do not reuse
the older outer runner log. Isolated tests do not replace full-scene acceptance.

A separate audited source-parity omission is now restored: the original
`physics.ts` only integrates bodies within 24 m in three dimensions of the actual
eye, plus any held body. The former Godot path integrated all 640 original props.
The promoted small manager retains all visuals, exact existing force equations,
body state and native contacts for selected bodies, with authoritative menu pause
and a tested `--no-source-prop-active-set` fallback. It is not a replacement
rigid-body solver or a claim of full TypeScript trajectory equivalence.

Production-path validation passes 2,400 actual headless Jolt checks, 95 separate
legacy-disable checks and 65 source/hash checks. At the tested original seeded
positions and eye, a deterministic sloped analytic-water adapter observes 640 →
60 force calls and 2,368 → 454 water queries. These are synthetic-field workload
counts, not measured CPU time or actual-device FPS. See
`audit/prop_sampling/PROMOTED-SOURCE-ACTIVITY.md` for boundaries, native scheduling
differences, archived rollback baselines and the remaining actual-world
traversal/interaction release gate.
