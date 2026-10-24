# Integrated Poolrooms wing authoring

Three complete original PoolCore room compositions incorporate a small selected subset of Cenji's free Poolrooms geometry. They are not copies of the paid showcase and are not a redistributed standalone asset kit. The raw acquisition folder is external to the project. No source water meshes are imported. The separately evaluated No Diving pack is not used.

## Deliverables

- `assets/models/poolrooms_wing/crescent_court.glb`: asymmetric pool, three Cenji wide arches, a curved half-circle rest alcove, benches and wall fixtures.
- `assets/models/poolrooms_wing/vaulted_lanes.glb`: two long basins, a 4 m nominal central dry walk, four Cenji arch ribs connected by an original shallow barrel vault, real narrow skylights.
- `assets/models/poolrooms_wing/circular_bath.glb`: west basin, a large Cenji circular gateway, east dry rest niche, restrained rounded divider, benches and wall fixtures.
- `source/*.blend`: editable assembled scenes with named components, source attribution properties, existing project PBR texture links and preview-only lights. The `.gdignore` excludes authoring files from game import.
- `source_provenance/poolrooms_wing/geometry.json`: exact runtime water, stairs, collider, fixture, room, source-file hash and exported GLB hash contracts.

## Rebuild

Use Blender 4.3.2, CPU/background mode:

    blender -b -t 2 --python tools/blender/poolrooms_wing/build_poolrooms_wing.py -- --source-dir /absolute/path/to/Cenji_BackroomsLevel37_Poolrooms_FREE/GLB

To rebuild one room, add `--only circular_bath` (or the other room basename). The default source path expects the private acquisition beside the project folder. Do not publish or package that original asset folder as a kit.

    python tools/blender/poolrooms_wing/verify_poolrooms_geometry.py

The audit validates exact axis-aligned BOX proxies, UV/tangent presence, one UV unit per metre on every nondegenerate exported visible triangle, no embedded images, and safe stair dimensions. All source materials are replaced by the existing `art_pass_*` roles; ceramic maps repeat 0.8 m across eight 10 cm tiles. Runtime uses existing project PBR maps, not the source pack's 25 cm tiles.

## Spatial contract

Godot Y-up, 32 m cell, local origin, deck 0.52 m, water 0.32 m. Common portal entry water rectangles and seven 0.155 m-rise / 0.5 m-tread entry steps match Expanded exactly. Four outer portal openings are 8 m wide; inner portals are 4.4 m wide. The common foundation top is -0.72 m. Basin-floor solids raise only the basins to -0.22 m, giving 0.54 m water depth, and are included in `water_steps` along with all steps. Basin access uses four 0.5 m treads, 2 m width, and five equal 0.148 m rises including the floor landing.

Interior ceiling heights are 5.2 / 4.7 / 5.2 m. Common vestibule roof underside is 5.4 m, roof top 5.6 m. Skylights are actual roof apertures with reveals and thin mullions, not emissive cards. No water, dynamic props or room-runtime scripts are authored here.

Each room has documented dry perimeter waypoints. The court and circular bath do **not** have a dry straight crossing through their basins. The lane room has a central dry spine. The circular gateway lies in plane x=2.1 m, with circle centre y=2.15 m,z=0 and radius 2.16 m; it retains approximately 2.8346 m clear width at deck level.

Every `COLLISION_*` mesh is a separate exact axis-aligned box. Imported arch piers and high lintels have boxes; their curved intrados start at y=3.30/3.35 m, above the normal player jump/head envelope, and deliberately omit complex collision. The circular gateway's reachable sides use horizontal box bands outside the true opening; the curved alcove uses small axis-aligned boxes around its plan curve. No full-room trimesh or concave physics is required.

## Architecture previews

`preview_poolrooms_wing.py` renders CPU-only architecture checks from the editable blends. The PNGs are noisy low-sample authoring previews, not game screenshots and not evidence of runtime water/lighting. `probe_gateway.py` additionally ray-tests the actual circular gateway visual mesh to ensure the hole remains open after floor clipping.

The final game must be verified through its production controller, source-water renderer and room builder by the integration task. Source geometry is combined into integrated room exports, not offered separately.

## Final acceptance notes

The four lane benches were moved outward to x = ±10.8 m after a production-controller test caught the original bench seats obstructing the x = ±9 m dry perimeter route. The repaired production movement suite passed all 56 cases, including every basin stair direction, the circular gateway, the dry routes and shared thresholds. A final visual-only roof correction then raised the free side edges of the continuous lane vault from 3.35 m to 3.50 m while keeping its crown at 4.45 m. This changed no movement collider, water step, bench or route. The lane CPU preview predates this minor final roof-edge change; final native game captures are authoritative.

`relocation_dependency_audit.json` records an actual independent-project copy test: only the three assembled blends and existing project PBR textures were copied, with no downloaded source asset folder present. Every room's 14 image links is relative and resolves inside the relocated project; there are no orphan raw source meshes. The generator still correctly requires the separately downloaded free kit if regeneration is requested.

The same audit checks the production jump constants. Conservatively jumping from coping yields a maximum head height of 3.45821 m, below the continuous vault's 3.50 m free edge. At the imported arch ribs, solid pier boxes constrain the capsule's upper hemisphere, yielding minimum reachable clearances of 0.16179 m in the court and 0.21179 m in the lanes. Thus omitted curved overhead collision remains outside actual capsule reach without a full-room trimesh.

### Imported normal repair

Native SDFGI review revealed incorrect face winding on disconnected imported GLB faces, despite valid UVs/tangents. The generator now welds imported components at 0.00001 m before consistent normal recalculation, preserving flat shading. The audit found and corrected 1,445 / 2,137 / 607 flipped faces in court / lanes / bath; all 30 imported components now have zero boundary edges, positive signed volumes and no faces needing reorientation. Position clouds, bounds, face counts, collisions, water, fixture records, spawns and routes remained unchanged. No extra lights were included in this repair.

Evidence: `imported_normals_before.json`, `imported_normals_after.json`, `normals_repair_comparison.json`, and `exported_pier_normals_after.json`. Independent source relocation was rechecked after the repair and still passes. Authoring PNGs predate this normals repair; use the latest native game captures for final visual evidence.

### Four-light local relocation candidate

After a normals-only native GI comparison, the existing four Lanes wall fixtures were relocated to the inward faces of the two middle arch piers, not duplicated. Their housings are 0.35 m wide, mounted at x = ±1.945 m, y = 2.7 m, z = ±2.5 m. Matching light points are x = ±1.765 m, y = 2.7 m, z = ±2.5 m, with authored power 14 and `range = 6.5` metadata. This preserves the four-light shadow budget. Court and bath models are unchanged from the normals repair.

The actual blend and exported GLB pass lens-normal tests; point lights sit 0.13 m in front of the lenses. Housings retain 3.79 m corridor width and 0.415 m clearance above a normally walking capsule. Centre deck and vault probes have clear visibility from the relocated fixtures. All collision, water, spawn and route contracts remain unchanged. See `actual_inner_fixture_audit.json`, `exported_inner_fixture_normals.json` and `light_relocation_comparison.json`. This geometry candidate is frozen for native image review; it makes no global environment, renderer or shadow-budget changes.
