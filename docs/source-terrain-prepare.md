# Static source-water preparation contract

The preparation path moves only static CPU work off the main thread. It does not alter water equations, photon optics, ray visibility, BVH splitting, simulation/texture resolutions, authored wet regions, or quality defaults.

## Ownership and scheduling

1. On the main thread, collect plain collision dictionaries, AABBs, genuine opaque triangle vertices, layout dictionaries, and two effective lamp dictionaries. Do not place Nodes, Resources, Callables into the snapshot.
2. Keep the snapshot and its nested arrays immutable until the worker joins. Geometry arrays may be reused across requests while immutable. Each concurrent worker owns its local output and any translated copies.
3. Start `SourceTerrainPrepare.build(snapshot)` on a worker Thread. The static helper uses only value/container data and `Time`; it does not instantiate a solver/renderer, traverse a SceneTree, or call RenderingServer.
4. After joining, discard outdated room/revision/grid results before changing live state. The scheduler owns cache limits, cancellation, domain rebasing, and complete terrain commit ordering.
5. On the main thread, create the RF depth image from `depth_data`, apply the solver depth and domain, set the same effective lamps used by the snapshot, and call `caustics.set_prepared_geometry(result)`. That method returns false for incomplete BVH/mask payloads without replacing the valid old caustic data.
6. Treat cached results as immutable. No partially built output is returned. Prepared caustics mark the legacy incremental job complete, so its existing render-side step immediately returns.

## Snapshot fields

- `coord: Vector2i`, `revision: int`: scheduler identity, copied to the result.
- `origin: Vector2`: target solver X/Z origin in world space.
- `geometry_origin: Vector2` (optional, defaults to origin): coordinate basis used by collider/solid/triangle inputs. Worker translates owned copies by `geometry_origin - origin`.
- `size: int`, `domain: float` (default 96.0): solver grid dimensions. Production authored wet-mask mapping remains the original 96m domain with the exact -48m offset.
- `colliders: Array[Dictionary]`: center, half, optional rotation/radius, in geometry_origin coordinates.
- `solids: Array`: AABBs or min/max dictionaries in geometry_origin coordinates.
- `triangles: PackedVector3Array`: genuine opaque faces in geometry_origin coordinates; no mesh simplification or AABB substitute.
- `layouts: Dictionary`: world room coordinates to immutable authored layouts.
- `lamps: Array`: exactly two effective lamp dictionaries with target-local `position: Vector3`. Powers do not affect incoming masks. Lamp positions are already in the target origin basis and are not translated by the helper.

## Complete result

`coord`, `revision`, `origin`, `size`, `domain`, `depth_data: PackedFloat32Array`, `packed_bvh: Dictionary`, `masks: Array[PackedByteArray]`, `filtered_solids: Array[AABB]`, and `timing_ms: Dictionary`.

`packed_bvh` retains the existing nodes, triangles, node_count, and triangle_count fields. `masks` always contains two complete 256×256 R8 images. Timings report translate, depth, wet_mask, bvh, masks, and total in milliseconds.

Prepared caustic upload is one render-thread callback that installs the packed geometry and both complete masks before another photon draw callback can run. Arrays are passed to that callback, rather than resolved from subsequently changed main-thread fields. Legacy set_geometry, begin_occlusion, step_occlusion, and render scheduling remain available and retain their previous semantics for original-source fixtures.

## CPU verification

The following describes historical fixture coverage, not a bundled test suite. The dedicated `tests/source_terrain_prepare_test.gd` fixture and its sandbox runners are not included in this focused source branch. Runtime implementation and authoring inputs are included; prior complete QA deliveries retain their evidence. Do not treat the counts below as a fresh graphical verification of this publication.

The 41 assertions cover a real worker thread, unchanged snapshots, translated geometry, literal former vertical intersection math, the former authored Image wet-mask loop, direct packed BVH byte equality, both full-resolution incoming masks, valid empty scenes, exact depth fixtures for axis-aligned/rotated/circular/submerged/overhead/below-bottom geometry, and rejection of partial lamp/row commits without changing the valid geometry revision. This fixture does not initialize the renderer or launch GPU work.

Existing source_wave_contract and source_caustic_contract also pass unchanged. GPU integration and runtime transition timing remain separate coordinated checks.
