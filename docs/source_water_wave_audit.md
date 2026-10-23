# Original shallow water and detail port audit

Source: poolcore commit `66a4543602d9e774db07c2da12ce1d40d522532c`, not the later V2 working copy.

- `app/pool-vct/shallow-water.ts` SHA256: `ead64d322bf067d7f4eadee72f593d8671ada8bbd07af8a22bc764fdf2d51c52`.
- `app/pool-vct/ripple-detail.ts` SHA256: `39e8579528ae1253c900baf51cc2593cb1e566122efe9a26a9fa7bad5a2b8748`.

## Source mapping

| Original | Godot implementation |
|---|---|
| `ShallowWater` | `scripts/water/source_port/source_wave_solver.gd` |
| `PREAMBLE`, `VELOCITY` | `shaders/source_water/swe_velocity.glsl` |
| `PREAMBLE`, `HEIGHT` | `shaders/source_water/swe_height.glsl` |
| Instanced additive Gaussian-Laplacian packet sources | `swe_source.glsl`, `_rd_inject` |
| `COPY`, `DOWNSAMPLE`, `inherit` | `swe_copy.glsl`, `swe_downsample.glsl`, `swe_resample.glsl` |
| `RippleDetail` integration, source, rebase | `detail_step.glsl`, `detail_source.glsl`, `detail_copy.glsl` |
| `buildTerrain`, `impact`, `push`, `wakeDipole`, CPU samples | Corresponding GDScript methods, with snake_case names |

These are actual time-integrated GPU fields, not analytic rings or a reduced CPU replacement. All shallow velocity and height/foam expressions are ported from original shader bodies. Source shaping, wet-neighbor behavior, harmonic face depth, upwind advection, friction/wall bands, clamp thresholds, and full foam production/advection/diffusion/decay are retained.

## Storage and coordinates

- Shallow RGBA16F: center height η, west-face u, south-face v, aeration.
- Detail RGBA16F: height, height velocity, zero, zero. It never contributes to buoyancy.
- Sources and physics readback are RGBA16F; terrain remains R32F.
- Texture x/y correspond to world-local x/z. Shallow domain 96 m, detail domain 48 m; no image Y inversion.
- Default shallow grid 768² and readback 384². Separate detail resolution permits original low384/192, medium384/384, high768/768, ultra1152/1152 tiers. Small grids are supported for tests only.
- Default level .32 m, floor -.72 m, rest depth 1.04 m, dry threshold .04 m.
- Runtime uses only the global RenderingDevice, scheduled with `RenderingServer.call_on_render_thread`. Stable Texture2DRD objects expose the current RIDs to Godot materials and caustics without a CPU texture upload.

## Equations and scheduling retained

- Shallow timestep min(1/120, original conservative CFL bound); max8 steps and the original dropped-time cap. Thus default768 uses1/120; sufficiently fine grids/high gravity may use the original smaller CFL timestep.
- Detail fixed1/120, speed .85 m/s, damping1.3 plus5 boundary band; ±.012 m / ±.15 m/s caps; quiet-clear after8 s.
- Original impact .13 cap, .3 scaling and .42–.52 m radii; momentum ±2 m/s and .16–2 m radii; bow/stern pressure dipole retained.
- Exact packet numerator/denominator and sinc limit, with the original Nyquist clamp. Source quads retain square support (±4σ shallow / ±3σ detail), not circular truncation.
- No-through-masonry source segment tests: shallow up to95 probes, detail12 probes. No-flow dry faces and no-sink foam boundaries are retained.
- Downsampling centers staggered velocities before area averaging. Alpha1 sentinel rejects incomplete/nonfinite readbacks. Sampling, hydrostatic slope push and Stokes drift retain original caps.
- Terrain column intersections include tilted boxes, upright circular pillars, submerged treads and overhead bridge clearance.
- Rebase shifts state with source JS rounding, shifts CPU readbacks and pending sources, and bilinearly shifts detail for fractional offsets.
- `inherit(previous)` bilinearly resamples live shallow state and copies readbacks/queued sources when changing quality. Call after new.configure(), before previous.dispose(). Detail resets as in the source.

## Intentional backend adaptations

1. Fragment passes become compute dispatches with the same grid-centered math. Instanced additive source blending is serialized per texel, with128-source batches and half quantization after each addition.
2. Explicit IEEE binary16 nearest-even rounding is applied before storage/source additions. OpenGL ES and Vulkan do not mandate identical target-conversion rounding. Mesa llvmpipe raw `imageStore` and GLSL `packHalf2x16` were experimentally shown to truncate .101 to .1009521484375; nearest-even is .10101318359375. Without normalization, repeatedly truncating foam accumulated a .0122 discrepancy after24 steps. Normalization preserves the equations and float16 precision while avoiding driver-dependent biased decay. This is a portability choice, not a claim that every WebGL driver originally selected nearest-even.
3. `set_terrain` is synchronous here; incremental terrain budgeting belongs to the world/integration layer. `set_depth_image` also accepts the integration's authored water-footprint mask. No physics resolution reduction is substituted.
4. Raw GLSL is compiled when present in the development project; exported builds can load imported RDShaderFile SPIR-V when raw source is omitted.
5. Async readbacks use Godot's frame-queued callback. The original1 s timeout /30 Hz synchronous fallback, stale-generation rejection, and quiet settling are preserved.

## Verification (Godot4.6.3)

- Headless GDScript compile checks passed for solver and GPU/global test scripts.
- `tests/source_wave_contract.gd`:27 assertions passed (API shaping, depth columns, pillars/bridges, rebase, samples, crest criteria, half readback validation).
- `tests/source_wave_reference.py`:13 independent CPU reference tests passed.
- `tests/source_wave_fixtures.json`:9 original-derived numerical cases. It is a CPU transcription fixture, not a captured original browser GPU output.
- `tests/source_wave_gpu_test.gd`: actual Vulkan llvmpipe,35 comparisons,0 failures. All shallow source/velocity/height/downsample and multi-step cases were byte-exact to nearest-even reference; one detail first-step component differed by1.1920929e-7, with later checkpoint exact. Dry separation walls, wet-only foam sampling, variable depth/still level and detail depth mapping were covered.
- `tests/source_wave_global_test.gd`: actual global Vulkan device passed,0 failures. Separate16²/8² fields, live Texture2DRD wrappers,36 simulation steps,16 asynchronous readbacks,0 rejected transactions, terrain mask/rebase, detail disable and GPU resource teardown all passed. This is a lightweight lifecycle/interoperability test, not a768² performance claim.
- Godot4.6 Texture2DRD clears its render-server texture and size on null assignment but retains the numeric backing-RID getter value; teardown checks width0 and released RD ownership rather than generic RID.is_valid().

The headless renderer provides no RenderingDevice, including local devices in this Godot build. Numerical GPU tests therefore use a tiny real Vulkan window through the coordinated cloud test session. The local RD is confined to tests; the game uses global RD.

Official API/spec references:
- https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html
- https://docs.godotengine.org/en/4.6/classes/class_texture2drd.html
- https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html
- https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-fp16
- https://docs.vulkan.org/spec/latest/appendices/spirvenv.html
- https://registry.khronos.org/OpenGL/specs/es/3.0/es_spec_3.0.pdf (floating-point color conversion)

## Original crest and environmental event bridge

`source_wave_events.gd` ports `InteractiveWater.crestSpray` and the environmental injection inside `InteractiveWater.render`, from the same original `water-system.ts` (SHA256 `bfada37aadd94abf413f80fcab2b9f7112e576fa3ea501172458c58e4c3cdc43`). The source has no separate method named environmentalDrips.

- Crest gating is original quality!=Low, simulation enabled, foam enabled with positive foamStrength or positive spray, unsettled SWE and peak>=.008.
- Original30 Hz accumulator, max.05 elapsed addition, elapsed<=.1, camera-centered64x64 readback scan (16m square),1597/4096 phase rotation,12-emission cap, convex-maximum thresholds, wet-position rejection, ridge refinement and tangent random scatter are retained.
- Rate is max(foam,power)*12 and probability is1-exp(-rate*elapsed). Original foamStrength only enables the foam criterion here; it does not scale it. There is no invented per-cell cooldown or view-frustum rejection.
- `crest_power` uses scalar double arithmetic, avoiding standard Godot Vector2.length's float32 rounding in the original JS Math.hypot path. Physics input arrays remain float32, as in the source.
- Environmental time gate is strictly time-last>2.7. Position is(sin(time*1.71)*12,sin(time*2.39)*12), detail amplitude .0003*environmentalStrength, radius .12. The timestamp advances even when the selected position is dry. It does not feed shallow impacts, momentum, foam or MPM splashes, and does not multiply body-impact scale. Default environmentalStrength=.08.

Integration API:

- `configure(solver, settings_dictionary, optional_rng_callable)`; settings use original keys `quality`, `simulation`, `foam`, `foamStrength`, `spray`, `environmentalStrength`.
- `set_solver(new_solver)` after a quality change preserves event timing and scan counters.
- `apply_settings(partial_dictionary)` applies the original relevant sanitizer ranges/types.
- `crest_spray(min(delta,.05)*whitewater_rate, callback, camera_local_xz)`; callback takes(x,z,power,foam). Original engine passes power and local flow to `liquid.crest` and ignores the fourth foam argument. Existing downstream MPM thresholds remain unchanged.
- Original order is crest scan, liquid update, particle update, environmental injection, water solver/detail frame. Use `environmental_drips(absolute_render_time)` immediately before `solver.step`.
- Coordinates passed to these methods and callbacks are relative to the96m solver origin, not absolute world coordinates.

Validation: `source_wave_events_reference.mjs` executes literal original JS method bodies with only TypeScript number annotations removed. It defaults to hash-verified vendored source and can alternatively read the pinned git commit. `source_wave_events_test.gd` passes538 assertions across25 crest and4 environmental cases, with0 failures and maximum numerical discrepancy8.5e-13. Random and dt/time input values include exact IEEE64 bytes to avoid decimal JSON transport changing an exact30Hz/Poisson boundary. Coverage includes source gates, scan order/12 cap, both ridge orientations, exact probability equality, dry refined positions, strict environmental timing, and actual detail-only source injection.

Adjacent integration audit: the original liquid/particle `surfaceAt` uses the weighted9-point macro filter and waveHeight, and `slopeAt` applies wavePush. These belong to `source_water_runtime.gd`; the parent integration task was notified rather than these files being changed by the event-port worker.
