# Streamed RT material refresh

This narrowly scoped change removes the full resident-scene material sweep from
each streamed geometry batch. It does not disable hardware RT, alter the shader
pairs, replace material resources, reduce scene detail, defer collisions, change
water simulation, or change reflection/capture settings.

## Integration contract

`scripts/rendering/rt_material_refresh.gd` is a `RefCounted` helper. The existing
desktop-quality owner is responsible for scheduling it:

1. `configure(main)` stores a weak host reference.
2. `refresh_all(active)` handles the initial RT state, actual toggles and world
   replacement. This path still visits every geometry instance and the material
   library's `_receiver_materials()`, including receivers not yet instantiated.
   It clears old pending work.
3. Call `queue_node(node)` for **every** entering `GeometryInstance3D` while RT is
   active, not only the first node that causes a deferred callback to be scheduled.
4. Schedule one deferred `refresh_pending(current_active)` for the batch. This
   reads materials after construction, processes only queued nodes, and honors
   the latest state if RT changed before the callback.
5. `get_stats()` returns cumulative counts, pending/cached resource counts, and
   the last batch's collection, application and total CPU times.

Each batch deduplicates material instance IDs and skips shaders already at the
requested path. Only the existing four raster/RT shader pairs are eligible.
Converted shader resources are cached lazily, at most eight per helper. Queued
nodes are weak references; freed, pending-deletion, detached and outside-host
nodes are ignored. Reconfiguration clears the pending queue. The helper does not
own or disconnect the desktop panel's SceneTree signal.

Counters describe submitted work, not proof of shader compilation or GPU stalls.
The helper does not retain a historical set of material IDs: a material can be
converted again after a later legitimate toggle or material replacement.

## Reproduce the CPU-headless contract

Use the already imported checkout. Do not run concurrently with asset import.
This fixture does not import the project, run the game, or launch a graphical
renderer. It loads the eight production Shader resources and builds controlled
MeshInstance3D/MultiMeshInstance3D scene nodes under Godot's headless renderer.

```sh
mkdir -p /tmp/poolcore-takeover-home/{data,config,cache} /tmp/poolcore-transition-rt
HOME=/tmp/poolcore-takeover-home \
XDG_DATA_HOME=/tmp/poolcore-takeover-home/data \
XDG_CONFIG_HOME=/tmp/poolcore-takeover-home/config \
XDG_CACHE_HOME=/tmp/poolcore-takeover-home/cache \
/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64 \
  --headless --path . \
  --script res://tests/room_transition/rt_material_refresh_contract.gd \
  -- --report=/tmp/poolcore-transition-rt/contract.json
```

Functional assertions cover all four shader pairs; full toggles and library-only
receivers; shared materials and independent clones; material parameters;
MeshInstance surface/override/overlay and MultiMesh surface/override/overlay routes;
unrelated shaders and StandardMaterial3D; duplicate queue requests; late material
assignment; freed/detached/queued-for-deletion/outside-host nodes; rapid toggles;
stale deferred callbacks; world replacement, reconfiguration and freed hosts.

The controlled benchmark uses 5,000 existing geometry nodes, 32 shared resident
materials and 12 batches of 40 entering nodes sharing eight new materials. The
baseline repeats the actual 4876a68 `_set_rt_materials()` operations, with timing
and counters only. Both paths see the same scene. Their order alternates, and
the same eight entrant shaders are reset before each measured call. Scene
creation, reset and destruction are outside the timed calls. Candidate queue
time is recorded separately and included in its end-to-end comparison.

The report records each sample, structural work counts, stage times, engine,
renderer/device, source hashes and every assertion. This is **CPU-headless
traversal/material-dispatch evidence, not Windows GPU frame time, hardware RT,
FG artifact acceptance, or full-game performance**. There is intentionally no
machine-dependent speed threshold in the test. Target-PC continuous room
crossings still require measurement with the same scene, quality and RT/FG state.

## Production-world CPU-headless stream contract

Use the same environment variables and Godot executable above, with:

```sh
timeout 115s "$GODOT" --headless --path . \
  --script res://tests/room_transition/rt_production_stream_contract.gd \
  -- --report=/tmp/poolcore-transition-rt/production-stream.json
```

Set `GODOT=/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64` first, or substitute
that absolute executable path. The already imported assets are required.

This second fixture uses the actual `PoolWorld`, `RoomBuilder`, expanded imported
room assets and `PoolMaterials`, with the unchanged 5x5 resident radius and
ordinary one-interior-per-process-frame streaming. A controlled position advances
from x=0 to x=32 and back in 0.5m increments. Each position is submitted through
the production `update_player_position()` method. There is no distant teleport,
`ensure_room_ready()` shortcut or `complete_pending_streaming()` call in the
fixture. Physics floor rays inspect actual installed architecture after each step.

The fixture checks that each crossing eventually creates five entering shells, destination
rooms remain ready, all four actual shader families and room-local receivers
convert and restore, rapid toggles leave collision identities unchanged, and
world replacement cannot retain or process detached old-world geometry. It saves
actual geometry/material/collision counts, all queued material batches and their
CPU stages, crossing call times, position samples and source hashes.

These are controlled position inputs, **not an actual Player/controller walk**.
No water runtime, lights, probes, graphical rendering or hardware RT is started.
Turning on the fixture's routing flag selects the same production RT shader paths
only; it does not activate RT hardware. Headless crossing CPU costs and successful
collision rays do not establish full-game FPS, optical correctness, Windows
driver behavior or frame-generation artifact elimination.

## Staged outer-ring shells

**Experimental only, not the default delivered world.** Production
`scripts/world/pool_world.gd` remains byte-for-byte 4876a68, SHA-256
`a0ebc2d9a49b359b57e1f2887288d326f22c5c78da46cd44bec3a3e69e74cd5b`.

The saved staged candidate keeps the current room and adjacent 3x3 collision shells
immediately available, while missing outer-ring shells are created with their
interior in the existing nearest-first one-room-per-process-frame queue. The
settled desktop residency remains the same complete 5x5 room set. Initial
resident shell count is nine rather than 25; an ordinary crossing from an already
settled window normally needs no synchronous new shell. Incomplete startup,
rapid movement and far position changes can still synchronously create missing
nearby shells, and `ensure_room_ready()` remains synchronous for arbitrary calls.
The entire Formal branch's shell/publication ordering is unchanged.

Only if the experimental patch is explicitly applied, pass
`--legacy-synchronous-shells` as a Godot **user argument** to restore the old
all-shells-at-request policy. Default production has no staging flag because its
source is unchanged. The fixture loads the saved candidate as a separate script
and uses its `staged_outer_shells` field to compare both policies in one process.

The exact pre-edit source is saved as
`fixtures/pool_world_4876a68.gd.txt`, SHA-256
`a0ebc2d9a49b359b57e1f2887288d326f22c5c78da46cd44bec3a3e69e74cd5b`.
The candidate is saved as `fixtures/pool_world_staged_candidate.gd.txt`, SHA-256
`40bb9a7c97bbd5b870a0ea3bae178a6b68c4dc96223e71d95c833a3b80160110`,
with the exact unified diff in `staged_shells_opt_in.patch`. The fixture evaluates
both saved sources after removing only their global `class_name` registrations.
It asserts production still has the baseline hash and never writes production
files. No generated replacement serves as the baseline, and no patch is applied
automatically.

With the same environment/executable setup, run:

```sh
timeout 115s "$GODOT" --headless --path . \
  --script res://tests/room_transition/shell_staging_contract.gd \
  -- --report=/tmp/poolcore-transition-rt/shell-staging.json
```

The comparison covers Original seed 1337, Expanded and Poolrooms seed 250821,
ordinary crossing/return, partial-batch reversals, reversals during unfinished
startup, far movement, a genuinely nonresident direct `ensure_room_ready()`,
explicit deterministic completion, rollback and early Formal travel. It compares
actual layouts, render mesh arrays, collision/solid data and optical triangles
using production `SourceRoomSnapshot`, including `room_loaded` history, live room
insertion order and near-field triangle concatenation bytes. Every boundary also
checks real architecture floor collisions and immediate adjacent shells.

Time is redistributed, not removed: each ordinary crossing still builds the
same five shells/interiors. The report records synchronous request calls and all
subsequent jobs, including per-phase totals and maximum atomic-job cost. Two
rapidly cancelled five-room batches intentionally avoid eight shells that the
old scheduler builds then retires; the eight skipped shells never finish an
interior or enter the water snapshot. This is reported separately from ordinary
equal-work comparisons. Initial baseline assets may be cold and later candidate
assets cached, so initialization timing is not an isolated speed comparison.

The fixture manually invokes at most one production `_process()` room job per
controlled frame to keep comparison sequences identical. These are CPU method
costs, not rendered frame times. Hashing/snapshot/assertion overhead is recorded
separately and excluded from those method measurements. The earlier production
stream fixture additionally exercises ordinary automatic process callbacks and
the material router together.

### Unresolved integration boundaries

- The original water solver, terrain identity code and captures are unchanged.
  Exact static collector inputs/order at tested checkpoints are verified, but
  transient `SourceWaterRuntime` scheduling, GPU publication and visual capture
  timing are not executed by this fixture.
- `SourceTerrainDiskCache.CONTEXT_PATHS` includes `pool_world.gd`. Changing this
  source changes both the prepared-cache algorithm signature and the raw Formal
  snapshot fingerprint. Existing bundled caches may therefore miss and rebuild
  even though the Formal geometry/order comparison passes. Rebake and revalidate
  the appropriate engine/package caches before claiming preserved warm startup;
  do not bypass or weaken the identity check. The rollback flag does not restore
  old source hashes.
- A single shell/interior remains atomic. Heavy rooms can still exceed a frame
  budget, and RT acceleration structures, shader compilation, water work and
  reflection updates can add costs not measured here. Target-PC/FG acceptance
  remains outstanding.

## Actual production-world RT refresh comparison

```sh
timeout 115s "$GODOT" --headless --path . \
  --script res://tests/room_transition/rt_real_world_benchmark.gd \
  -- --report=/tmp/poolcore-transition-rt/rt-real-world-benchmark.json
```

This test retains the exact baseline `pool_world.gd`, creates the real Expanded
world with seed 250821, and compares the old full material scan with the
incremental queue on the **same live world and material instance IDs**. It uses
eight alternating repetitions for the actual five-shell crossing batch and each
of its five following interior jobs. Before each old/new variant, it restores
the exact shader Resource objects from that batch's real pre-refresh snapshot.
Creation, restoration, verification and retirement are outside the timed calls.
Candidate measurements include queueing plus the external flush-call duration.

Official Godot 4.6.3, headless, 173 checks passed:

- Five entering shells: 2,789 actual geometry nodes, 453 live entrants. Mean old
  scan 6.411 ms; incremental queue + flush 1.415 ms. Old scan performs 404 shader
  load/setter attempts; candidate considers 31 unique materials and makes 24
  actual shader changes.
- Following five interior batches: 2,580–2,815 resident geometry nodes versus
  4–11 live entrants. Mean old scans 5.084–7.064 ms; incremental means
  0.049–0.095 ms. These batches require no new eligible shader changes but still
  caused full scans in the previous implementation.
- Every repetition has identical resulting material IDs, shader paths and the
  checked texture/parameter state. All four shader families restore correctly.

The recorded input uses actual game nodes/materials, not the separate 5,000-node
synthetic population. Nodes created then freed inside atomic construction are
absent from the settled snapshot, so construction-time node-added callback cost
is not included. These are CPU-headless measurements, **not game FPS, GPU RT,
Windows performance, or evidence that FG jelly has been eliminated**.

Verified report SHA-256:
`013e3c918fb1d7e6c1a92f062a67671b92614bb8bc2b2d0af8af78934fa7db10`
for `/tmp/poolcore-transition-rt/rt-real-world-benchmark.json`.

The final standalone opt-in shell snapshot suite passed 2,181 checks with
production unchanged. Its report SHA-256 is
`bdf5322adb229c7654103f6797e8a16ea67e252d9e942072041eda7ca3f2c847`
for `/tmp/poolcore-transition-rt/shell-staging-opt-in.json`.
