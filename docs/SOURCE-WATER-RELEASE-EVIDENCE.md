# Accepted source-water changes and release evidence

Updated 2026-10-22 01:36 UTC. This is a subsystem evidence summary, **not a final
package/device or whole-game performance certification**. The later release
manifest must bind the actual exported tree. Detailed older experiments remain
archived; their earlier "pending" statuses do not supersede the completed gates
listed here.

## Unchanged source boundaries

Source authority: pinned Beyond the Basin commit
`66a4543602d9e774db07c2da12ce1d40d522532c`, under `source_provenance`.

The accepted execution optimizations retain the source SWE/APIC-MPM equations,
1/720 s APIC timestep, 36-step submission cap, three 18,000-particle domain caps,
80³ MPM grid, source interactions and particle ordering. They do not lower
simulation/atlas/lattice resolution, reduce photon draws, alter refresh cadence,
shorten ray paths, replace effects, or change optical coefficients. The source
257×257 floor and 97×97 wall lattice samples, source receiver math, ray tests,
blur/mipmap operations and the surviving host particle body remain intact.
Quality choices already in the project are not new optimization evidence.

"Exact" is scoped to the stated numerical fixture and preserved source port,
not a claim that Godot and the original browser renderer are wholly identical.
Native rigid-body integration/contact scheduling is still Godot/Jolt. Original
Three cubemap reflections use GGX PMREM; the existing port uses ordinary linear
cubemap mipmaps. Formal AgX lighting/exposure is separately authored presentation,
not the original ACES output. Those existing differences were not hidden or
"fixed" by altering source optics during this iteration.

## Accepted changes and measured boundaries

| Accepted change | Established result | What the measurement does not mean |
|---|---|---|
| Native exact SWE callback decode/reduction | Complete 384² callback median 36.268→0.978 ms; fields/reductions exact against literal original TypeScript/Three fixtures | CPU callback only, not GPU transfer latency or game FPS |
| Native exact incoming masks | Original-room paired preparation 8,930.159→115.480 ms including packing; 55 fixtures, 7,208,960 mask bytes exact | Cold CPU preparation, not rendering/device FPS |
| Indexed BVH host storage | 46 cases, 74,188,416 encoded bytes exact; same Godot sort/ties/node order; lifecycle and wrapper controls pass | 3,049.326→1,112.199 ms pair was contended by software rendering, not an isolated headline speedup |
| Exact floor-photon result reuse | Balanced production-shaped GPU medians 153.130→132.055 ms, 13.76% lower; 116 complete raw/filtered/mip RGBA comparisons exact | Isolated High/108-triangle llvmpipe workload, not a whole original-room frame or hardware GPU forecast |
| Exact caustic wave-lattice reuse | Earlier isolated refresh comparison about 24% lower, source outputs preserved | Not additive/multiplicative with the later floor result; no combined whole-game claim |
| MPM transfer-buffer zeroing | Complete particle buffers exact against original stage sequence; direct-kernel fallback preserved | GPU improvement is case/run-dependent: the production paired medians were impact 132.231→133.374, collider 134.660→134.376, crest 139.925→124.678 ms |
| Global-RD descriptor reuse | 8.453→1.656 μs host request cost; 14 pixel/lifetime checks pass | Host descriptor API cost, not the liquid draw's GPU duration |
| Spawn invariants and exact typed frame sampling | Original particle/parameter/RNG/callback and host-row checks retained | Earlier initialization/packing fixtures are not a measured whole-game speedup |
| Whole-inert-domain particle gate | Actual replay frame 39: 8.501→4.983 ms; frame 59: 6.845→0.379 ms; rows/state/events exact | Both frames have zero visible rows. Three visible snapshots show no meaningful active-state speedup |

SWE evidence: [exact optimization record](SOURCE-WATER-EXACT-OPTIMIZATION.md),
`verification/eight-hour/water/source_readback_runtime_perf.json` and
`tests/fixtures/source_readback_original.json`. Mask evidence:
[SOURCE-NATIVE-INCOMING-MASKS.md](SOURCE-NATIVE-INCOMING-MASKS.md).
BVH evidence: `verification/eight-hour/water/source_bvh_index_contract.json`,
`source_bvh_index_lifecycle.json`, `source_bvh_production_contract*.json` and
`source_bvh_index_perf-contended.json` in the same directory.
Floor evidence: `output/source-caustic-floor-production-stage.json`, plus the
104-comparison independent floor-only audit and 40-comparison failure audit.
Particle-gate evidence: [SOURCE-NATIVE-PARTICLE-GATE.md](SOURCE-NATIVE-PARTICLE-GATE.md).
All table milliseconds are same-workload fixture measurements, not game FPS.
The exact MPM particle-state comparison is distinct from its exported
anisotropic covariance: unchanged atomic linked-list traversal produces
run-to-run covariance differences up to 2.384e-7. That export is not labeled
byte-exact, and no tolerance is used to relabel changed particle-state bytes.

## Actual promoted native regression

The five-job native regression launched at 00:45:54 UTC and completed with a
fresh aggregate `pass:true`. Its source and artifact hashes were independently
reviewed in `verification/eight-hour/water/promoted-water-native-review.json`:

- Real global-RD SWE callbacks pass with the native parser and disabled fallback.
- Production-supported Mobile viewport liquid tests pass on cached/reference
  paths, including translated origins, gradients and depth/occlusion controls.
  The earlier unsupported-MSAA fixture failure was retained, then the fixture
  was corrected to use production's supported viewport configuration.
- Three source splash domains reach 41,418 particles, 90 callbacks and 28 visible
  frames over the 60-frame run. The promoted helper makes 180 gate calls; no
  particle-gate or transfer-clear fallback occurs. Skipped-work counts describe
  coverage, not a speed measurement.
- Fresh individual logs have no script/shader/engine errors. The known Mobile
  TAA-unavailable setup warning is retained. This isolated splash fixture has
  no full room caustic/probe workload.

The parent observed final output, command completion and no remaining native
Godot. **No outer shell exit marker was captured for this particular launch.**
The old `optimized-native-runner.log` belongs to an earlier run and is not
relabeled. Individual fresh artifacts and the sequential runner's final report
are the evidence, not an invented outer exit code.

## Optical correctness and capture validation

- Scene and planar samplers now use original-source linear, non-mip capture
  sampling. Native Mobile and Forward+ tests pass 14 checks each. Actual
  terrace A-B-A images show the broad pale-floor appearance is not materially
  explained by this correction: A-B changes are smaller than A-A repeat drift.
  [Actual unedited-image analysis](audit/source_capture_sampling/TERRACE05-ACTUAL-ABA.md).
- Capture lighting synchronization keeps actual lighting/sky state current but
  retains linear HDR, exposure 1, no adjustment/glow and recursion exclusions.
- Independent compiled normal-field tests pass 4,096 cases with zero byte
  mismatches; 3,104 micro-normal samples are nonzero. No amplitude was raised to
  hide calm source defaults.
- Zero-gain receiver evaluation returns zero before touching disabled inputs.
  Poisoned zero-gain controls establish the NaN problem; all four finite
  positive-gain material comparisons remain byte-identical.
- End-to-end constant-radiance scene/planar/cubemap/AgX tests pass 50 Forward+
  and 50 Mobile checks. They do not show double gamma or double tonemapping on
  the tested paths. Lightmap exposure-normalization handling was separately
  audited. [Color-pipeline evidence](audit/source_capture_colors/SOURCE-CAPTURE-COLOR-PIPELINE.md).

Optional delayed GPU timestamps distinguish encoding, submission, transport and
actual GPU stage intervals. They never synchronize/read back to determine
quality or physics, and are disabled unless explicitly enabled. Earlier High
fixture timings identified photon transport, not the ~0.2 ms CPU submission,
as dominant GPU work. That diagnosis is not a later-room FPS measurement.

## Resource lifecycle and reversible paths

The floor cache's optional buffer/shader/pipeline resources are tracked by the
same owner; both optional descriptor maps are retired. Allocation, shader,
pipeline and descriptor failures fall back to direct source photons. All ten
failure-injection cases, 40 full-byte comparisons and zero live owned textures
after disposal pass. The production-shaped resize/disposal audit also passes.
A detached Texture2DRD can retain a historical nonzero handle, so the corrected
fixture checks actual RD liveness and zero wrapper dimensions, not handle value
alone. The initial failing assertion is retained.

Explicit controls: `--no-native-water-readback`, `--no-native-water-masks`,
`--no-indexed-water-bvh`, `--no-transfer-mpm-clear`,
`--no-water-descriptor-cache`, `--no-caustic-floor-result-cache`, and
`--no-native-water-particle-gate`. Missing/older native helpers or rejected
native results retain the exact GDScript/original path. The wave-lattice direct
path remains selectable by its `reuse_wave_samples` diagnostic property.

A native engine-only lifecycle pair independently reproduces the fixed seven
TextureRID shutdown warning with one UPDATE_ONCE ReflectionProbe, versus zero
without it, after three same-world create/free cycles. Both processes exit 0
with flat post-cleanup texture memory. It contains no game/helper/custom RD
owners. This distinguishes the engine-atlas signature from evidence of source
water per-room growth; it does not certify every game owner's lifetime or fix
the engine. No engine-owned RID is manually freed.
[Resource audit](SOURCE-RESOURCE-LIFECYCLE-AUDIT.md).

## Native delivery limits

Actual Linux x86-64, Windows x86-64 and Android ARM64 binaries are built, with
one exported entry point, no external runtime imports and Android 16 KiB LOAD
alignment. Atomic-build evidence covers all three successful builds,
byte-identical repeat builds and a failing build publishing nothing. Sources,
licenses, toolchain provenance and checksum records are retained under
`native/source_water`; no unbuilt Windows/Android dependency was added.

Linux execution is verified. Windows/Android static audits are **not target
execution**. Final PCK/DLL adjacency, APK ARM64 inclusion and device behavior
remain the release/package owner's separate gate. Unsupported targets must
omit the descriptor and use fallback. Fresh editor discovery requires the
previously verified startup extension-list bootstrap; the failed discovery
process is not counted as a successful export.

## Separate source-rule restoration: nearby prop activity

Original `physics.ts` selects bodies at strict 3D eye distance <24 m, plus the
held body. The promoted manager restores that omitted rule without removing
visuals or changing force formulas. Inactive bodies preserve state/timers,
freeze and leave contact participation; held bodies remain active, and menu
pause is authoritative. Native ordering is explicitly documented, not called
bitwise TypeScript trajectory equivalence. `--no-source-prop-active-set` restores
the old callbacks. GI_MODE_DYNAMIC remains intact.

Promoted-path CPU/Jolt checks: 2,400 normal, 95 disabled, 1,252 multi-substep and
65 source/hash checks. The controlled original-position/sloped analytic-water
case records 640→60 force calls and 2,368→454 water queries: workload counts,
not a time/FPS measurement. The first actual original-world native walk is
**partial/failed on its wall-clock budget**, not a completed release gate. Its
80 physics ticks nevertheless record 64–67 nearby active bodies, 5,190 force
calls and zero inactive-contact violations, ownership errors or fallbacks.
Full traversal/interaction acceptance remains open.
[Promoted activity contract](audit/prop_sampling/PROMOTED-SOURCE-ACTIVITY.md).

## Explicitly rejected late candidate

The 01:21–01:24 quiet-window cursor study passes 1,170 host/reentrant checks and
125 real-snapshot/delta comparisons. It preserves arbitrary future-particle
callback mutations; a whole precomputed batch would not. It cuts one hidden
frame's work by ~94%, but realistic **visible** states have small, mixed gains
and regressions. The parent rejected promotion. Production host and all three
helpers are unchanged; there is no silent "stable callback" opt-in.
`tests/fixtures/particle_cursor_audit/DECISION.md` and `evidence.json` retain raw
measurements, source hashes, controls and the bounded stopping decision.
