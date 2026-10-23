# Rendering-resource ownership audit, 2026-10-22

## Result and disposition

**No independently evidenced game-owned texture leak or stale binding was found in this bounded review. No production disposal patch is recommended.** Main's current regeneration source path preserves the root World3D/scenario; it does not construct a new native reflection atlas per mode change. This last statement is source-path verification, not a new native before/after identity measurement.

The existing **seven-Texture-RID shutdown defect is independently reproduced by a historical engine-only native ReflectionProbe control**. That does not make the game leak-free, explain fourteen by arithmetic, establish a runtime memory-growth cause, or reproduce/fix the reported black/neon-green transition. No causal conclusion is drawn about the interrupted full transition test or its SIGKILL.

This audit launched **no Godot process**, made **no runtime/engine/shader/physics edits**, introduced no global GPU synchronization, freed no borrowed handles, purged no caches and disabled no probes. Its 74 source/evidence contracts pass. These contracts are text/evidence checks, not a native GPU liveness test.

## Self-contained historical native evidence

Raw original logs are preserved byte-for-byte under `historical/`. `provenance.json` records their original absolute paths, SHA-256 values, original filesystem mtimes and the preservation time. Original execution wall-clock timestamps are **not recorded in the logs**; filesystem mtimes are not substituted for execution receipts. Both original files came from the earlier `poolcore-godot-visual-work/docs/verification/eight-hour/lifecycle/` tree, and their hashes match the already-saved ownership audit.

| Historical Godot 4.6.3 Forward+/llvmpipe control | Native cycles | Exit | Texture warning | Post-disposal texture bytes |
| --- | ---: | ---: | ---: | --- |
| `historical/lifecycle-isolated-probe-01-baseline.log` | 3 | 0 | 0 | 20635648, 20635648, 20635648 |
| `historical/lifecycle-isolated-probe-01-native-probe.log` | 3 | 0 | 7 | 527425536, 527425536, 527425536 |

Each mode records the same World3D identity across all three of its own cycles, no surviving process and no runtime errors. The probe fixture has one native `UPDATE_ONCE` probe per cycle and no game preload, source water, custom RenderingDevice allocation or native helper. The native probe is removed between cycles; the root World3D remains. The retained atlas explains why memory need not return to the initial baseline; a plateau is supporting evidence against cycle-by-cycle growth here, **not proof that each handle was released**. The difference between the two memory levels is not the size of seven leaked handles.

For inspectability, `historical/fixture-project.godot.txt` and `historical/fixture-reproduce.gd.txt` preserve the current fixture source. Their bytes match the earlier audit's source fingerprints. The original native logs did not seal fixture source hashes, so these are explicitly **audit-time snapshots**, not retroactive run-time source verification.

### Known engine cleanup omission, not a game-owned handle

The earlier source audit identified a missing `color_buffer` retirement in Godot 4.6.3's `LightStorage::_reflection_atlas_clear`: the atlas allocates one color cubemap plus six dependent shared face views, while cleanup omits the parent. See [official 4.6.3 cleanup and destruction](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L1229-L1279), [allocation](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L1420-L1444), and [dependent-RID release](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/rendering_device.cpp#L154-L179). The exact local source-analysis record is `../verification/pc-refine/texture-ownership-audit.md`.

This audit revalidated the raw native logs, not a new upstream checkout or moving master branch. The previous two-line engine-only patch remains a proposal in `../verification/pc-refine/texture-ownership-engine-fix-proposal.patch`; it was not applied, built or tested here. Game code must not guess and free the atlas's internal handles.

The observed defect is exposed at shutdown in the matched native controls. An engine atlas-clear/resize during execution could also encounter that cleanup code, so this is not an assertion that the engine defect is intrinsically shutdown-only. The **current game path reviewed here contains no explicit atlas resizing, scenario replacement or native-probe UPDATE_ALWAYS change**. Its source path and the historical flat same-world control do not support claiming a new atlas leak on every regeneration.

## Current world regeneration and shutdown

- `scripts/main.gd:141`: creates the persistent `WorldEnvironment` once in `_ready`.
- `scripts/main.gd:188`: `_create_world` creates water/props/player/game-world Node owners under the same Main. `scripts/world/pool_world.gd` extends `Node3D`, not `World3D`.
- `scripts/main.gd:278`: `_retire_world` stops work, disposes fog and water, removes/queues the four old owners, clears references, then yields before rebuilding. It does not destroy Main, the root Window, the persistent environment or the root World3D.
- `scripts/main.gd:529`: `regenerate` awaits retirement before `_create_world`.
- Only two production `world_3d` assignments exist: `source_planar.gd:32` and `source_room_probe.gd:226`. Both capture SubViewports explicitly share the source camera's World3D. Neither requests `own_world_3d`.
- All production scripts were checked for explicit `World3D.new`, own-world toggles, scenario construction, atlas-size mutation and scene replacement; none were found. Both native-probe constructors use `UPDATE_ONCE` (`pool_lighting.gd:405,541`).
- `scripts/main.gd:1451`: `_safe_quit` disposes active fog/water, awaits the existing rendering boundary, then frees scene owners, clears material/lighting and imported scene/shape caches, drains process/draw frames and quits. A render-thread queue barrier orders CPU work; it is not proof of GPU memory reclamation.

Thus current regeneration reuses the root scenario and its engine-managed atlas by construction. A direct current full-world same-scenario/native-RID-liveness capture remains absent. The successful process-restart fixture is a different scope and must not be relabeled as this measurement. No additional launch is requested merely to duplicate historical evidence.

## Ownership review

| Owner | Owned resources and correct release boundary | Borrowed/async distinction |
| --- | --- | --- |
| `SourceWaterRuntime.dispose` (`source_water_runtime.gd:902`) | Detaches the five water sampler parameters, clears both library caustic aliases and camera compositor bindings, then disposes child owners. `_exit_tree` uses the same idempotent path. | Material receivers do not own the native simulation allocations. They must stop referencing them before owner release. |
| `SourceWaveSolver` (`source_wave_solver.gd:510,893,907`) | All eight direct simulation/depth textures use `_rd_texture` and enter `_owned`; three wrappers detach before tracked frees. | Generation/serial guards reject stale async readbacks. A detached Texture2DRD can retain a historic numeric RD getter: test `texture_is_valid`, not just nonzero getter; do not call `get_rid` after detach and accidentally create a placeholder. |
| `SourceCaustics` (`source_caustics.gd:939,946`) | All masks, target textures and shared mip views use `_own`; two output wrappers detach; five uniform-set caches and tracked RIDs are released. | Output Resources and native originals have different ownership; no second manual free of engine bridge aliases. |
| `SourceLiquidSurface` (`source_liquid_surface.gd:178,586,591`) | Owns dummy cube, DFG, render targets, framebuffers/pipelines and persistent compute/draw resources. Detaches output and frees tracked targets/RIDs. | Scene color/depth are engine-owned; UniformSetCacheRD entries are engine-owned, unlike the separately freed transient sets. Input Texture/Environment references are cleared with the owner-thread deferred callback after render callbacks are disarmed. |
| `SourceLiquidMPM` / prewarm (`source_liquid_mpm.gd:1246`) | Owns buffers, groups, pipelines and shaders; cancels prewarm, frees patch resources, then pipeline/shader resources. | No direct texture creation. Cancellation drops the completion callback; epochs reject late results. No solver-math changes. |
| Source volumetric/distance fog (`source_volumetric_fog.gd:210`, `source_distance_fog.gd:157`) | Disarms callbacks, retires its owned UBO/shader/sampler/framebuffer/pipeline containers. | No direct texture allocation: color/depth and engine-cached sets are borrowed. Framebuffers invalidated by engine attachment retirement are validity-checked. |
| `SourcePlanar` (`source_planar.gd:90`) | Disables capture, disconnects draw completion, queues owned SubViewport and clears viewport/camera/output fields. | ViewportTexture lifetime is engine-managed. Shallow capture Environment shares source Sky read-only. The remaining source Environment reference is bounded by the planar Node's lifetime, not an orphan RD allocation. |
| `SourceRoomProbe` (`source_room_probe.gd:573`) | Cancels capture tickets, joins CPU mip workers, disconnects draw completion, queues viewport, clears bounded Cubemap cache/output/source Environment. | Deep capture Environment/Sky is owned through the camera. Async readback tickets isolate callback lifetime from the Node. Default path allocates high-level Cubemap Resources, not direct RD textures. |
| Opt-in GPU room cube | `source_gpu_room_cube_device.gd:284` transfers the allocation lease to the TextureCubemapRD. The final wrapper detaches its bridge before queuing lease release (`source_gpu_room_cube.gd:11`); lease reversely frees only tracked originals/views. | Worker disposal drops its wrapper reference, rather than invalidating a cubemap retained by a consumer material. Source viewport RID and RenderingServer bridge are borrowed and never added to the ownership ledger. |
| Whitewater | High-level mesh/material and child node ownership, released with the node. | No direct RD texture ownership. |

The direct allocation sites and current source SHA-256 fingerprints are recorded in `static-report.json`. No concrete untracked allocation, known live consumer bound to a freed original, or callback accepting post-disposal results was established. Static guards are not a proof against all scheduling/interleaving defects.

### Static room/model/material caches

- `room_builder.gd:11-13`: imported PackedScenes, collision shapes and two notice fonts. `_safe_quit` clears the first two. They are high-level refcounted engine resources, intentionally reusable across streamed worlds, not code-owned RD texture handles. Per-instance material overrides keep current source-water wrappers out of the PackedScene originals.
- `expanded_room_builder.gd:5-6`: PackedScene and proxy BoxShape caches retain high-level geometry/shape resources. These are keyed by authored path/size; no per-regeneration World3D/viewport is cached.
- PoolMaterials owns per-library material/map dictionaries (including three ceramic maps), and tracks local caustic receivers with weak references. Runtime disposal clears live caustic aliases. It has no static direct-RD cache.
- Avatar finish retains script-level authored Texture resources plus per-instance material-change records; mesh tracking is weak and Main drops the helper on retirement. PoolLighting tracks streamed room/light nodes weakly; the persistent environment/material library is intentional.

Retained high-level caches can keep memory above startup levels. That is not evidence of orphan native handles or of monotonic per-mode growth. No indiscriminate purge is justified.

## Recent logs: comparable facts, distinct scopes

- `output/current-water-feel/water-feel-far-drop-640-01/godot.log` completes the native carry and reports seven leaked Texture RIDs at shutdown. Its `completed-receipt.json` records exit 0 and report pass; successful execution must not be called leak-free.
- `docs/bath-daylight/isolated01/godot.log` reports fourteen on successful exit. The fixture excludes source water, but creates native reflection fallback and changes it to `UPDATE_ALWAYS` for refresh before restoring `UPDATE_ONCE` (`tests/bath_daylight/native_test.gd:108-115`). It frees its host and quits immediately (`:158-166`), rather than following Main's full disposal path. **Fourteen alone identifies neither the owners nor how many atlases were allocated.** No matched native ownership trace attributes that larger warning here.
- `docs/world-retirement/native-contract-01.log` and `native-contract-01-result.json` pass 30 checks with no texture warning, including old-node destruction before replacement allocation. This substitutes FakeWater but constructs real PoolLighting, PoolMaterials, Environment and Sky (`tests/world_retirement/lifecycle_contract.gd:119`, `pool_lighting.gd:31,54`). It is not literally texture/resource-free despite its header wording. It creates no native ReflectionProbe and tests neither live source-water RD release nor full-room rendering.

## Recheck and remaining boundary

Run `python tests/resource_lifetime/audit_static.py`. It re-parses the preserved raw engine-only logs, checks exact warning observations, current construction/disposal text contracts, cache inventory and source fingerprints, then writes `static-report.json`. `static-run.stdout` records this audit's successful execution. This command never starts Godot.

No runtime diff proposal is attached because none is justified by an independently established game-owned defect. A future already-authorized native ownership run can use the existing `tests/source_runtime_lifecycle_gpu.gd` to test actual native RIDs while retaining wrappers and input owners; it must be coordinated and kept distinct from static checks and global memory plateaus. This audit stops here without requesting that launch, changing engine behavior, hiding the warning or claiming the user's transition symptom is fixed.
