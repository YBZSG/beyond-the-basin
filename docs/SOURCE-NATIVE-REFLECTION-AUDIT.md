# Native room reflection audit

Read-only production audit, 2026-10-21 23:25 UTC. No production shader, geometry,
lighting, reflection quality, or cache asset was changed for this investigation.
The later engine-only native lifecycle control is recorded below; native room-traversal capture timing remains separate.

## Measured object counts

`tests/source_native_reflection_audit.gd` uses the actual `PoolWorld`, room
builders, and `PoolLighting`, with ordinary one-interior-per-frame streaming.
It passed 81 CPU assertions. Coordinate requests are injected; this fixture is
not CharacterBody traversal and does not count completed native GPU captures.

Report: `verification/eight-hour/transition/native-reflection-node-audit.json`.
Log includes the actual child exit code, zero, and no failed checks.

| State | Rooms | Native probe nodes | New probes |
|---|---:|---:|---:|
| Original collision-first startup | 25 | 1 | 1 |
| Original interiors finished | 25 | 25 | 24 more |
| One cardinal crossing, before retirement | 30 | up to 30 | 5 |
| Crossing settled | 25 | 25 | none |
| Immediate return across that boundary | 30, then 25 | up to 30, then 25 | 5 |
| Authored startup | 5 | 1, then 5 | 5 total |

The resolved project defaults are **256-pixel faces and 64 atlas slots**.
All probes are visible, `UPDATE_ONCE`, and shadow-enabled. The original world's
16 far-ring rooms retain their probes, despite native point-light visibility
being limited separately. Crossing preserves the same 20 retained probe
instances; a retired outer row is reconstructed with five fresh probes on
return. There is no separate persistent native-probe LRU in application code.

The native walk observer records probe counts at crossings, room publication,
and leg ends. Actual attempt `native-walk-01` started with 25 nodes, including
16 far-ring nodes, observed a temporary peak of 28, then returned to 25. Its
atlas settings were still 256 pixels and 64 slots. These are node counts, not
rendered capture counts or a causal attribution of frame time. That route
failed its wall-clock/completion gate after three real crossings; see
`SOURCE-UNINTERRUPTED-WALK.md`. Its additional observer CPU cost is reported.

## Scheduling and staleness

The 4.6.3 renderer queues visible dirty/uninitialized probes. One `UPDATE_ONCE`
probe step runs per render-probe pass, but the first step renders **all six
faces together**. Subsequent steps prefilter roughness. Source/planar capture
viewports share the same world, so their views can also discover probes.
This is not evidence that all 25 probes render in one frame.
[Engine scheduling](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_scene_cull.cpp#L3325-L3440).

Application evidence:

- `pool_lighting.gd:add_room_lights` creates each probe immediately after that
  room's interior finishes, not after all its neighbors or lights are ready.
- `update_source_view` changes the active light and shadow selection as the
  camera moves. Fixture flicker changes light output independently.
- `update_active_room` signals at the start and end of its lighting tween.
  `main.gd:_capture_lighting_changed` forwards this to source water captures,
  not native room probes.
- The CPU audit observed all six initial/crossing/revisit palette signals while
  all retained native probe transforms and capture settings remained identical.

Thus native probe radiance can retain earlier geometry/lighting. Nearby geometry
changes alone do not automatically refresh `UPDATE_ONCE` probes.
[Godot update semantics](https://docs.godotengine.org/en/4.6/classes/class_reflectionprobe.html#enum-reflectionprobe-updatemode).

## Comparison with the pinned original

`source_provenance/beyond-the-basin-66a4543/app/pool-vct/engine.ts`:

- Lines 125–132 use the room environment's rough prefilter on ceramic; metallic
  objects additionally use the original reflection tracer.
- Lines 678–705 create **one** 1024 HDR cube, capture one face at a time, reuse
  already-rendered shadow maps, then produce a PMREM texture for
  `scene.environment`. The previous environment remains until replacement.
- Lines 995–999 separate face capture and final PMREM from CPU upload/commit
  frames. This is not a set of 25 independent native room probes.

The Godot paths are not redundant equivalents. `SourceRoomProbe.completed` feeds
the liquid compositor. Godot's architecture ceramic shaders use native spatial
specular/roughness, with the sky and local probes supplying environment lighting.
Simply deleting room probes would remove that architecture reflection input.
The existing raw cube/mip chain is also not the original ceramic PMREM result.

## Smallest safe experiment, not a production change

Prepare a test-only admission/refresh coordinator, preserving every probe,
256-pixel face size, shadows, bounds, masks, and final materials:

1. Defer only **new** probes until their required immutable geometry and light
   context is ready, then prioritize the occupied room before other candidates.
   Keep already valid, retained probes available while replacements prepare.
2. Coalesce real context changes through the final lighting-tween state instead
   of capturing incomplete startup context and leaving it stale. Do not use
   `UPDATE_ALWAYS`, nudge transforms every frame, or hash only the room coord.
3. Compare identical cold/out/back/revisit runs with per-frame draw counts,
   frame times, source capture progress, and fixed final screenshots. Report
   temporary availability and final image differences; never block movement.

This can avoid premature/stale captures, but **cannot divide the native six-face
burst through the current application API**. Hiding a cached probe is not a
safe pause mechanism because it removes its reflection contribution. Reusing a
retired probe also requires a full visible-context identity, not just a room key.
Therefore no performance win, exact image equivalence, or shipping change is
claimed. A shared-source-cube architecture environment would be a larger,
separately validated material integration, not a one-line probe removal.

## Engine-only seven-handle shutdown reproduction

The built-in atlas's seven color handles have a concrete unmatched cleanup path
in the current engine. The completed isolated `native-probe` lifecycle pair reproduces exactly seven Texture RID shutdown warnings without any source-water allocation. Baseline has zero; three same-World3D cycles have flat post-cleanup memory in both modes. See `SOURCE-RESOURCE-LIFECYCLE-AUDIT.md`.
No engine-owned RID should be freed by the game's resource owners.
