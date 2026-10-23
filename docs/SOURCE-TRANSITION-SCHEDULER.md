# Exact source-water transition scheduling

This work changes when immutable work is collected, prepared and published. It does not reduce the original 25-room residency, collision geometry, 48 m water radius (96 m domain), water resolutions, optical triangle set, caustic mask dimensions, reflection-face resolution or quality effects.

## Problems found

- A full live scene extraction performed mesh-face readback, collider traversal, transforms and large-array construction on the main thread. The measured baseline native snapshot took 174.8 ms; its following worker preparation took 11.95 s in the software-rendered cloud environment.
- Repeated room completion invalidated the aggregate snapshot. Unchanged rooms were traversed again. Imported `ArrayMesh.get_faces()` can involve rendering-server work; a nominal 2 ms traversal budget cannot interrupt one indivisible call.
- Exact incoming masks were a large CPU cost. The separately validated native implementation now preserves the original GDScript and pinned-source JavaScript outputs, including float32 boundaries. The runtime still has the exact GDScript fallback.
- The six-entry terrain cache could retain two obsolete revisions at one origin, evicting a different room just before returning to it. The first measured revisit then rebuilt for 22.72 s.
- A demanded origin could wait behind an unrelated speculative worker. Cache completion time also gave speculative entries priority over rooms the player had actually visited.
- Early travel to a formal destination could publish its completion before preceding queued rooms. Because dictionary order is also optical BVH input order, the cache correctly rejected that different identity. A catalog-only validation did not catch this actual startup path.
- Identical quality calls could reconfigure caustics, planar reflections and bindings. Runtime quality changes now return early when their value is unchanged, preserving unrelated explicit overrides.

## Runtime pipeline

1. `PoolWorld` retains collision-first shell construction and one atomic original-room interior per frame, nearest first. Original seeded streaming remains a 5 x 5 set. No normal-path `complete_pending_streaming()` shortcut was added.
2. `SourceRoomSnapshot` performs bounded main-thread capture of immutable values. Worker finalization receives plain arrays, transforms and collider data, not live scene nodes or mesh resources. Four pending finalizers are bounded; canceled work is retired and reaped without joining on a transition frame.
3. Unchanged per-room values survive coordinate-specific invalidation. Only entering/changed rooms are collected. Aggregation preserves the existing room/DFS order exactly and uses a fixed initial geometry origin.
4. `SourceTerrainIdentity` computes separate conservative depth, BVH and mask keys. It excludes a room only when its values cannot enter that component. False dependencies may rebuild unnecessarily; missing dependencies must never produce an incorrect hit.
5. `SourceTerrainPrepare` runs the existing preparation kernels on immutable input. Exact matching BVH/mask components may be reused independently while depth changes. Shifted origins and effective lamps participate in identity.
6. Completed payloads pass a shared typed-component validation gate before any rebase or depth publication. The previously valid 96 m field stays live across adjacent room requests. Far requests are not falsely marked ready. Cache replacement commits before pruning, coalesces superseded same-origin revisions and retains the still-applied entry.
7. There are at most two terrain workers: latest urgent work plus one older immutable job. An unrelated speculative job can retire into that second slot without being forcibly terminated or joined on a frame. When both slots are occupied, rapid movement updates one latest-demand coordinate, never an unbounded job queue. A demand already being prepared by the retired worker is not duplicated. Both owners drain on suspension/disposal. Force/size changes and current semantic keys are checked again before caching/publication; an older completion cannot replace a newer cached revision.
8. Background prewarming remains bounded to six terrain entries. Actual visited origins take priority over speculative completions. Prefetch selects only the nearest unvisited origins that fit beside protected visits, so it does not cycle endlessly between mutually evicted candidates. A newly visited demand may evict the least recent old visit. Cold work and queued work remain measurable costs; this is not a claim that every first transition is instantaneous.

`get_preparation_status()` exposes stage, readiness, pending status, requested coordinate, rooms collected/total, current collection vertices/slices, worker stage/elapsed time, worker coordinate/count, background-worker count, queued demand, probe diagnostics and errors. Progress follows the demanded job, not an unrelated prewarm. Readiness means usable initialized water for the current request, not merely that a worker has started. Adjacent valid old terrain can be ready while fresher terrain is pending.

### Immutable batch arrays

`SourceArchitectureBatch` attaches its exact pre-upload position/index arrays as `source_static_arrays`, and reuses a single surface-array read during one atomic batch instead of requesting the same rendering-server data two or three times. Snapshot workers expand those arrays without changing ordering.

Godot's `Mesh.get_faces()` builds a `TriangleMesh`; `TriangleMesh::create()` snaps each local face vertex to 0.0001 before welding. A first raw-array prototype differed by one float ULP. The final path applies the same `Vector3.snappedf(0.0001)` before the same scalar transform, preserving the original face bytes. References: [Godot 4.6 TriangleMesh implementation](https://raw.githubusercontent.com/godotengine/godot/4.6-stable/core/math/triangle_mesh.cpp), [Mesh implementation](https://raw.githubusercontent.com/godotengine/godot/4.6-stable/scene/resources/mesh.cpp).

## Authored immutable assets

Only the complete formal catalog is eligible. Original seeded rooms never use these bundles.

The current 16 bundled containers are one shared five-room snapshot plus five
authored coordinates at three distinct depth sizes. The coordinates are
`(-1,-1)`, `(0,-1)`, `(-1,0)`, `(0,-2)` and `(-1,-2)`; they do not include the
original spawn at `(0,0)`. That world's `authored_snapshot_hits = 0` and
`disk_cache_hits = 0` are therefore expected, not proof of a failed cache lookup.
Its geometry is prepared dynamically and its warm publications use the bounded
in-memory terrain cache. A complete formal catalog and `formal = true` on every
layout are required before the runtime even invokes either disk loader.

- Raw snapshots are keyed by loaded reconstruction/runtime/algorithm source, all static layout values except the independently proven seed-only field, room order, geometry origin and the imported scene bytes.
- Prepared terrain additionally validates exact component identities, quality size, coordinate, domain and origin.
- Signature construction hashes the loaded script source, not a possibly edited source file on disk. Unavailable script source fails closed. Release script mode 0 is therefore required for the current scheme.
- A bundled miss, signature mismatch, missing imported resource hash, corrupt container or invalid payload takes the genuine extraction/preparation fallback. Diagnostics identify the expected key/path, algorithm, layout digest, order and reason. There is no force-hit switch.
- Container schema 2 uses built-in lossless Zstandard, stored and expanded SHA-256 checksums, bounded header and payload lengths, exact file-length validation and typed shape checks. Decoding does not permit Objects. Atomic pending-file rename prevents partially written caches from becoming valid entries.
- Immutable formal completion can skip the obsolete three-frame quiet period once the complete catalog is present. Dynamic original streaming keeps that guard.
- Explicit early formal travel finishes only unfinished catalog predecessors before the requested room. All authored meshes/colliders already exist. This makes completion/BVH input ordering deterministic without changing ordinary initial one-room completion, original streaming, optical algorithms or geometry.

### Build and validate

Run these serially with any editor import/export operation:

```sh
godot --headless --path . --fixed-fps 120 \
  --script tools/cache/bake_formal_terrain.gd -- --all-quality
godot --headless --path . \
  --script tools/cache/validate_formal_terrain.gd -- --all-quality \
  --early-room=0,-2 --report=/absolute/validation.json
```

The bake covers five coordinates at sizes 384, 768 and 1152. Low and Medium share size 384. BVH and mask bytes do not depend on this depth size, so the bake reuses them only when component identities match. Every written payload is reloaded and compared in full.

For all early-travel paths, repeat validation for `-1,-1`, `0,-1`, `-1,0`, `0,-2` and `-1,-2`. Repeat seeds 1337 and 250821 when validating seed independence. The validator uses actual World initialization, explicit early travel and normal queued completion, never a synthetic dictionary reorder.

An exported package must include `assets/cache/source_terrain/*.terrain` and raw `.gd` source. A source-tree pass alone does not establish package validity. Use the external validator against the actual PCK:

```sh
godot --headless --path /package/root --main-pack /package/root/game.pck \
  --script /absolute/frozen-source/tools/cache/validate_formal_terrain.gd \
  -- --all-quality --require-pck --early-room=0,-2 \
  --report=/absolute/pck-validation.json
```

The report includes the actual main-pack argument, standalone feature, loaded source signatures, complete publication order and per-payload hashes. Changes to geometry, imports, layout/material/lighting construction or any hashed algorithm require rebaking. Do not distribute stale files simply because their names exist.

### Diagnostic timing provenance

`SOURCE_TERRAIN_COMMIT.cached` is the current **memory-cache entry count**, not a
hit flag. `prepare_worker_ms` is timing attached to that payload. It describes
fresh work only when the payload was actually prepared in the current process;
a later in-memory publication repeats its stored timing. For a disk hit,
`SourceTerrainDiskCache` preserves old preparation times as `baked_timing_ms`
and replaces `timing_ms` with the current disk read/decode duration and zero
preparation-stage durations. Commit and rebase timings are measured for each
publication separately. Use the explicit memory/disk/raw-snapshot hit counters
and job counts to distinguish these cases; do not sum repeated payload timings
as if every publication rebuilt the BVH or masks.

## Verification and limits

Evidence is under `docs/verification/eight-hour/transition/`.

- Original 25-room accelerated CPU route: 71 checks, seven complete reference checkpoints, six adjacent crossings. Only five entering rooms are re-extracted per crossing. Full depth, packed BVH and both masks equal uncached preparation; actual floor collision rays remain valid.
- Warm-route first revisit: 22.720 s before origin coalescing/native masks, 0.597 s afterward. These are fixture phase times including traversal/streaming, not game FPS. The startup number 20.846 s is **six-origin prewarming**, not first-playable latency.
- A separately paced cold route passes 70 checks without startup prewarming. It currently settles at checkpoint boundaries, so it is not yet evidence of uninterrupted walking. It ran concurrently with software rendering; its long tails must not be presented as an isolated CPU or target-device benchmark.
- `tests/source_uninterrupted_walk_cpu.gd` now passes **76 checks for each runtime**, with 16 full publication-boundary reference rebuilds in each process. It holds actual production forward/sprint Input actions and moves the CharacterBody through 300 m / 12 room crossings, including beyond the initial 48 m half-domain. There are no inter-leg teleports, settling waits or reference builds. Both runs have zero floor misses, incomplete destinations, residency shortfalls and field-overrun observations; workers remain bounded to one archived / two current and six cache entries. The 57.54-second route is wall-paced by normal 60 Hz physics, not accelerated fixed-fps. These corrected functional runs overlapped native rendering and are not isolated performance measurements. See [the evidence qualification](SOURCE-UNINTERRUPTED-WALK.md).
- Immutable batch snapshot: 148 checks. Existing 60-room render-geometry parity: 2,569,272 corners, zero position/UV error.
- Five actual early formal destinations: 136 checks against independently baked normal-startup assets. Full collider, solid and triangle bytes, High depth, BVH nodes/triangles and both masks are unchanged.
- Additional contracts cover immutable component reuse, dynamic streaming identities, cache integrity/corruption, origin-coalescing eviction, formal seed independence, lifecycle join and startup readiness gates.
- Demand scheduling: 97 controlled-barrier checks prove two-worker ownership, latest-demand priority, exact complete payload parity, stale-result rejection, drain/disposal, visited-first eviction, stable prewarm selection and malformed-payload atomicity. The barriers test correctness, not performance. The existing 58-check lifecycle, 15-check streaming, 8-check origin-cache and 26-check disk-cache contracts also pass.
- A prior actual native three-room formal run hit the raw/prepared cache: worker read 50.334 ms and main commit 3.446 ms, with zero BVH/mask rebuild. That result does not establish the later five-room package; its exact native/package validation is tracked separately.

This environment uses Godot 4.6.3 and llvmpipe. Long rendered-frame and asynchronous readback wall times are not target PC/phone measurements or necessarily a blocking CPU call. High still captures six 1024-square HDR cubemap faces and complete mips. No blanket resolution/effect reduction is part of this scheduler work.

The indexed BVH helper is included in the complete algorithm signature; the water pipeline's independent byte-parity tests cover its exact output. Remaining investigations include a repeated isolated timing comparison with the corrected walk observer, indivisible mesh-face readbacks, imported scene startup work and conservative cubemap invalidation on streamed geometry changes. The historical seven-TextureRID shutdown warning has now been reproduced in an isolated engine-only native probe control; it has not been fixed or used to claim that all full-game resources are clean. CPU lifecycle tests cannot establish GPU resource release.

The current fitted-geometry, calibrated five-room cache set contains **16 files /
31,416,862 bytes**, bound by
`verification/eight-hour/transition/mainhall-exposure-cache-manifest.json`.
All five actual early-spawn orders hit the raw snapshot and all 15 quality/origin
payloads in source CPU validation. The latest 106-check comparison verifies the
prepared core bytes; its manifest retains exact source identities and report
paths. The approved main-hall-only display exposure changed the conservative
raw source identity, while its entire serialized raw snapshot payload remained
byte-identical. Derived identities and all numerical terrain components are
also unchanged; refreshed timing metadata accounts for changed container bytes.
Old payloads are not admitted under new keys. This supersedes the earlier
31,416,904-byte watchdog set and 30,449,274-byte calibration-only set.
Final actual-PCK validation remains a
separate release gate and must prove the same five early-target paths, all three
sizes, exact loaded sources and all container hashes without building fallback.

The completed smallest native lifecycle pair was
`lifecycle-isolated-probe-01`, with three cycles each in `baseline` and
`native-probe` isolated modes. Both exited zero with no survivors; the baseline
had zero shutdown Texture RID warnings and the engine-native probe alone had
seven, with flat post-cleanup memory across its three same-World3D cycles.
See `SOURCE-RESOURCE-LIFECYCLE-AUDIT.md` for its bounded command and exact scope.
The broader source-runtime lifecycle fixture remains separate and unexecuted;
neither result is continuous per-room leak testing.
