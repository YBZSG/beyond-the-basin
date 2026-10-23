# Optional return-valve activity candidate

This is an isolated opt-in candidate, not a promoted gameplay change. No host,
original seeded room, formal catalog, water solver, shader, rig, player or existing
asset was edited. Mobile is outside this work. Integration is deliberately owned
by the existing main/player code so the candidate cannot silently compete for E.

## What is delivered

- `scripts/world/facility_devices_candidate.gd`: persistent owner, two fixed
  authored placements, actual camera/physics visibility, E interaction seam,
  mechanical 90-degree handle travel and carefully limited source-wave input.
- `assets/models/facility_devices/pool_return_valve.glb`: original 182 × 261.5 ×
  99.3 mm wall control, restrained blue enamel, satin stainless housing, real
  fasteners and a small geometric RETURN label. 3,988 triangles, 211,472 bytes.
- `assets/models/facility_devices/pool_return_fitting.glb`: original 104 mm
  diameter, 32 mm projection stainless return, with a real approximately 22 mm
  recessed outlet rather than a painted black circle. 2,824 triangles, 112,032 bytes.
- Matching editable `.blend` files under `tools/blender/facility_devices/source/`,
  protected by `.gdignore`, plus the standalone deterministic authoring generator.
- Source reopening/exporting, raw-GLB geometry and CPU-native interaction tests.

The device is a quarter-turn control, not a falsely animated multi-turn gate
valve. The handle closes horizontally and opens vertically. There is no emitted
light, cosmetic water sheet, scrolling jet mesh, caustic overlay, foam decal,
invented fluid system or arbitrary mechanical noise. Existing audio contains
source-project water/toy/footstep sounds but no verified fitting mechanical
sample, so this candidate intentionally has no sound.

The original existing project license remains in force. All new fitting geometry
was authored for this project; no third-party model, image, add-on, texture, audio
or paid asset was downloaded. Label geometry uses Blender's bundled Bfont.

## Sparse placements and physical ownership

Room-local coordinates in metres, Godot Y-up. The room grid remains 32 m.

| Room | Control centre | Return mount | Source input centre | Inward direction |
|---|---|---|---|---|
| Sidepool `(-1,0)` | `(6.8245,1.70,1.8)` | `(3.9195,-0.05,1.8)` | `(3.18,0.32,1.8)` | `(-1,0)` |
| Curved bath `(-1,-2)` | `(0,1.70,-8.7995)` | `(0,-0.05,-4.7995)` | `(0,0.32,-3.95)` | `(0,1)` |

The sidepool station is on the east wall, away from the north stairs and west
bench. The bath station is on its north wall, away from south stairs and east/south
doorways. The sidepool's existing fixed return at `z=0.9` remains untouched.
Independent rays against the real delivered formal GLBs verify all four mount
planes meet the existing walls within 0.5 mm. Fifty further downward rays cover
the full source-support grids, verifying the real floor at 0.84 m depth in the
sidepool and 0.94 m in the bath, not a stair, wall or void. These tests are not a new whole-room
capsule-walking or rendered-image acceptance.

Each device uses a frozen RigidBody3D with a small real collision envelope, no
`pool_interactable` group and no force/grab behavior. This intentionally follows
the existing source snapshot rule that skips all RigidBody3D subtrees. Thus the
existing immutable formal terrain/optical cache is not silently invalidated or
modified by these optional prop bodies. They render and cast ordinary engine
shadows, but the source triangle optics does not include these tiny fittings,
just as that path excludes ordinary dynamic props. Their reflectance is the
actual imported PBR finish; this is not a claim of source ray-traced fixture
visibility or a new physical plumbing network. Pipework is assumed embedded in
the existing walls/deck, not represented by invented surface pipes.

## Exact integration proposal, not an applied patch

`owner_integration.patch` contains the exact proposed changes to `main.gd` and
`pool_player.gd`. It has **not** been applied. A standard `patch --dry-run -p1`
check succeeds against the SHA-256 baselines in `owner_patch_provenance.json`.
`tests/facility_devices/build_integration_patch.py` regenerates only this proposal
and refuses changed host context. It never edits host files. The runtime option
in that proposal is `--formal-return-valves`; it still requires formal mode.

1. Keep an instance of `FacilityDevicesCandidate` as a child of main, above the
   streamed rooms. Instantiate only for an explicit desktop opt-in such as
   `--formal-return-valves`, with `_spawn_mode == "formal"`. Do not enable by
   default, for the original world, for the expansion catalog, or on mobile.
2. At each `_create_world`, call `configure_world(session_key, world_seed, opt_in)`.
   Include a monotonically increasing world-generation identity in `session_key`
   so re-creating the same seed deliberately resets station state. This clears
   old attachments and the old source binding. Bind the newly created water with
   `bind_source_water(water)` after it exists. Failure must leave only mechanical
   interaction, not fall back to legacy water. A non-source water implementation
   is intentionally rejected.
3. In `_on_room_loaded`, after ordinary water/prop setup, call
   `attach_formal_room(room, coord, layout)`. Do not pass `geometry_only=true`
   outside the tests. Existing rooms can be iterated once if enabling the option
   after startup. The manager rejects unsupported/rotated/moved geometry and dry,
   original or expanded layouts. Imported model failure returns false, rather
   than leaving an invisible interactive control.
4. Pass the owner reference to the player. In `interact_action()`, preserve the
   existing held-object release and aimed-prop grab checks. Only after both fail,
   offer E to the valve before the ordinary ladder fallback. Treat climbing as
   busy so E continues to release the ladder. Do not add a second input listener.
5. In the same player-status branch that currently falls back to the ladder/hint,
   ask `interaction_hint(camera, prop_has_priority, player_busy, exclude)`.
   Use a nonempty returned hint only when the player is enabled, not holding or
   aiming at a prop, and not climbing. Its text is `E 开启回水阀` / `E 关闭回水阀`.
6. Call `advance(delta, world.current_room, not menu_open and player.enabled)`
   once per physics frame. It returns the number of admitted pulses, always 0 or
   1. Do not also call it from `_process`. No source sampler, capture, quality,
   lightmap or water-tuning configuration is changed by the owner.
7. Call `clear()` on permanent removal. Normal room exit is observed through a
   weak reference and identity-checked signal, retaining only two small
   room/station-keyed state records. The owner itself must survive room unload.

Suggested player branch, after its existing held-object branch:

```gdscript
var picked: RigidBody3D = pick_prop()
if picked != null:
    grab_prop(picked)
    return
var exclude: Array[RID] = [get_rid()]
if is_instance_valid(facility_devices) and facility_devices.try_interact(
        camera, false, not enabled or is_instance_valid(climbing), exclude):
    return
toggle_ladder()
```

The explicit `prop_has_priority` and `player_busy` arguments are also tested
defensively. Echo rejection remains the player's existing responsibility; the
candidate independently consumes a repeated E inside its 300 ms debounce.
The pure ray seam requires a visibility callback and fails closed if omitted.
Never use an unconditional `true` visibility callback in actual gameplay.

## Honest source-wave behavior and limits

The only write is the existing
`OriginalSourceWater.push_wake(world_position, impulse, sigma)`, which forwards
to `SourceWaveSolver.push` / `queue_push`. It queues SWE momentum only, with zero
height splat. It does not directly call splash, impact, crest, MPM, whitewater,
detail-wave or caustic functions. Original solver behavior and user water tuning
remain untouched. There is no free-surface or jet-pipe solver here.

- One inward momentum pulse of magnitude `0.0015`, sigma `0.16 m`, at most every
  `0.50 s`, active room only. Maximum admitted magnitude is `0.003` per second
  and `0.18` per 60 seconds. This is a discreet low-energy return approximation,
  not a volumetric jet/nozzle claim or a deliberately spectacular effect.
- The source shader's actual support is a square of half-width `4 * sigma`, or
  `0.64 m`. The entire support fits the conservative wet contour. It is not
  mistaken for a radius of one sigma or the bath's coarse bounding rectangle.
- The candidate probes 25 support points against current source depth and wet
  APIs, and checks the analytic authored contour. The source shader further
  rejects dry destination cells and source-to-cell paths crossing dry geometry.
  The circular bath's south stair alcove and the sidepool stair footprint are
  excluded. No active-room/world-origin ambiguity is accepted.
- Source terrain must be ready, simulation enabled, source and game unpaused,
  current source requested room matching the owner, peak below `0.006 m` and local
  flow below `0.04`. Existing energetic waves therefore suspend return input
  rather than receiving additional momentum. Missing/unready water still permits
  mechanical handle interaction; it produces no substitute graphics.
- Closed, unloaded, disabled, paused and invalid states generate zero input.
  A hitch or resume never catches up missed pulses. Reload restores the open
  handle but starts a fresh half-second deadline.

No direct MPM emission is demonstrably present in this code/CPU queue test.
That does not prove that an arbitrarily configured source solver can never
produce an indirect crest in response to accumulated flow. The safety gates and
small rate budget are conservative, but native rendered/GPU quiet-water soak
and worst-tuning checks remain acceptance work. Do not increase the impulse to
force a visible result without doing those checks. A barely perceptible real
flow is preferable to a fabricated jet or splash storm.

## Tests and current acceptance

Run the light standard-library geometry/source audit:

```sh
python3 -B tests/facility_devices/asset_contract.py
```

With the shared native-engine CPU slot explicitly granted:

```sh
python3 -B tests/facility_devices/run_cpu_contract.py
```

This invokes the actual production candidate, native GLTF import and native
physics camera occlusion. The source object uses a fixture depth/flow sampler
but its original `push_wake` and original `queue_push` methods. It deliberately
never configures or steps a GPU solver, and makes no CPU fluid-surrogate claim.
The tests cover nearby/far/off-axis/back-of-wall selection; missing/blocked LOS;
prop/climbing priority; debounce; toggle/handle movement; pause/off/dry/not-ready
states; region confinement; 60-second event budget; long hitches; actual source
queue route; room identity races; unload/reload; seed/world reset; and cleanup.

The raw geometry audit also checks genuine outlet recess, actual wall contacts,
handle pivot/envelope and no embedded cameras, lights or water effects. Source
proof opens both delivered `.blend` files, never runs the authoring generator,
and reproduces both production GLBs byte for byte without changing either source.

Current reports are adjacent to this document. They state their own exact scope.
The final native CPU run **passed 9,489 assertions, exit 0**, in 0.756 s with
103,968 KiB peak RSS and no engine errors or warnings. The 60-second admission
test produced 118 pulses, below the 120-pulse cap. An initial duplicate room-exit
callback on same-room seed reset was fixed and explicitly covered by the clean
rerun. The raw geometry/source audit passes 23,284 checks. Both editable sources
re-export their delivered GLBs byte for byte; the Blender roundtrip took 1.562 s
and 219,736 KiB peak RSS, without rendering.

The owner integration patch has only passed a non-applying dry-run, not a full
host gameplay test. Native CPU tests cover the candidate and original source
queue route; they do not imply the still-unapplied owner patch is promoted.
No screenshot, native rendered quality, sustained GPU response, FPS improvement
or whole-room traversal result is claimed by this candidate. Before promotion:

1. Review actual close camera views and both open/closed handle poses in the real
   sidepool and bath, with the source renderer and existing lighting.
2. Walk past the real valves/returns, stair routes and doors with the capsule.
   Verify E still releases held props and ladders and grabs aimed props first.
3. Observe at least a minute of quiet-water operation in each room with props
   initially at rest; record source peak, admitted pulses, crest patches, MPM
   domains and GPU frame-time distribution, not just a still image.
4. Repeat pause/reload/world-switch, Low/High/Ultra and extreme supported damping/
   wave-speed combinations. Any substantial indirect splash or excessive cost
   means leave flow unpromoted or reduce/disable it, not alter source physics.

