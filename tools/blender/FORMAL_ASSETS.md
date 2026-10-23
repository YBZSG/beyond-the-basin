# Formal PoolCore assets

The formal main hall was reconstructed in Blender 4.3.2 from the recovered concept and runtime reference. The terrace and curved bath are newly authored connected spaces. This is not a bit-identical restoration of the lost source, and a concept image is not evidence of runtime quality.

## Rebuild and editable sources

For a safe independent verification, run `python3 -B tools/blender/verify_formal_delivery.py --work-root /tmp/formal-delivery-check`. The directory must be empty and outside this project. The helper snapshots production hashes, copies the generator, runs a two-thread factory-startup Blender rebuild, reopens/exports the delivered editable scenes without saving them, and compares both outputs with production. It retains logs and generated artifacts in scratch space. Set `--blender` if Blender is not on PATH. Recheck an existing completed run without starting Blender by adding `--compare-existing`.

Only when intentionally editing/promoting assets, run `blender -b --python tools/blender/build_formal.py` in this project to replace all six runtime models and source scenes. Append `-- --only formal_mainhall` (or another asset name) to replace just that GLB and editable `.blend`; other geometry remains unchanged. A new runtime import, collision/optics verification and affected cache/lightmap rebuild are required after promotion.

Runtime assets are `assets/models/formal/formal_{arch,mainhall,arcade,sidepool,terrace,bath}.glb`. Editable scenes are `tools/blender/source/formal_*.blend`. The source directory has `.gdignore`, so Godot imports GLB and does not invoke Blender automatically. `formal_manifest.json` records room dimensions, coordinates, aperture sizes and connections.

The fitted delivery has an independent two-thread Blender 4.3.2 reproducibility proof: a fresh generator run in a separate root reproduces all six GLBs byte-for-byte, and reopening/exporting each delivered `.blend` without running the generator also reproduces all six exact GLBs. The manifest is semantically identical but differs in JSON key order/final newline. `formal_source_roundtrip.py` and `tests/formal_clean_rebuild_compare.py` make these checks repeatable without overwriting production. Current evidence is `docs/verification/formal-fitted-clean-rebuild.json`; the earlier `formal-clean-rebuild.json` remains a historical enclosure checkpoint.

The generator needs no external mesh, image, add-on or paid asset input. Its imports are Blender's bundled `bpy`, `bmesh`, `mathutils`, plus Python's standard library. The comparison and floor-plan scripts also use `tests/formal_architectural_junctions.py`, which is delivered with them. Blender 4.3.2 is the exact verified export baseline. Other Blender versions may change glTF serialization; the comparison reports byte identity separately from strict geometry/material/UV/proxy identity rather than claiming either without checking it.

Units are metres, exported glTF Y-up. Visible geometry has identity transforms and room-local coordinates. Most proxies also have identity transforms; curved bath sectors intentionally preserve local rotations, which the source depth extractor needs for oriented bounding boxes. Do not apply those transforms into world-aligned proxy meshes.

## Connected architectural graph

The sidepool/bath depth revision is a reversible geometry candidate, not yet accepted. Water remains +0.32 m; the source 1.04 m depth cap, optics/solver and 1.25/1.10 m swim latch are unchanged. Regenerate only these rooms with `blender -b -t 2 --python tools/blender/build_formal.py -- --only formal_sidepool formal_bath`; this also refreshes only their manifest sections. Mainhall, terrace and arcade GLB/.blend files are not rewritten. The verification reports below predate this candidate unless explicitly marked otherwise.

- Main hall `(-1,-1)`: 22 × 20 m, roof underside 4.8 m, 16 × 12 m basin. Dry deck +0.52 m, floor −0.12 m, water +0.32 m. Four stair tops: +0.38, +0.24, +0.10, −0.04 m.
- Arcade `(0,-1)`: 24.8 × 6 m, roof underside 4.1 m. Four transverse frames leave its 6 m-wide north branch unobstructed.
- Side pool `(-1,0)`: retained 14 × 14 m room, 3.9 m roof underside and 8 × 8 m basin. The geometry-only depth candidate lowers the basin floor to −0.52 m for 0.84 m of water. Six 0.65 m treads, 4.8 m wide, and the basin landing form seven equal 0.148571 m risers from the unchanged +0.52 m deck. The north ramp and its enclosure are unchanged.
- Daylight terrace `(0,-2)`: 20 × 18 m, roof underside 4.2 m, real 12 × 9 m open-sky aperture. Basin 12 × 8 m, floor +0.10 m and 0.22 m water depth, with two actual entry treads.
- Curved bath `(-1,-2)`: 8.8 m inner room radius, 9.16 m outer masonry radius, vaulted underside rising from 4.6 m to approximately 5.58 m, and a 3.6 m-diameter oculus with glazing at 6.025 m. Circular 4.8 m-radius basin with the retained 3.6 m-wide south stair alcove and continuous annular dry deck. The geometry-only depth candidate lowers the basin floor to −0.62 m for 0.94 m of water. Six 0.65 m treads and the basin landing form seven equal 0.162857 m risers. The stairs extend from z=6.0 to z=2.10; lower rail sockets land on the basin floor at z=1.72.

The main hall, bath, terrace and arcade form a physical four-room loop. The side pool remains a connected leaf. New connectors have 6 m clear width; floors slope from +0.52 m at each room to −0.72 m at the shared 32 m cell edge. There are no teleport-only links or openings directly into deep water. Runtime owns water, and no static water plane is included in a GLB.

The older main/arcade and main/sidepool links are also enclosed, fixing reachable falls off their former bare ramp edges. Their exact floor meshes and proxies are unchanged. The main/sidepool corridor stays 8 m wide; the main-east half tapers gently from 8 to 6 m to meet the arcade. Each half has 240 mm masonry sidewalls, slope-following ceramic returns, a 200 mm roof with 3.15 m underside and a genuine 800 mm central rooflight. The roof bears over the walls rather than floating beside them.

## Craft and material contract

Arches are continuous thick, beveled elliptical extrusions, not disconnected blocks. The main hall has three transverse structural frames, without the former redundant longitudinal lattice. Clerestories, portal reveals and skylight openings are real geometry. Coping has recessed physical joints and flush stair nosings. Grating bars are batched into meshes rather than hundreds of separate draw calls.

The final fixed-fitting pass adds small closed basin-return and skimmer faces, tool-fastened tiled maintenance covers, a 450 mm-high built-in sidepool bench and a shallow closed arcade service cabinet. These are architectural fittings, not usable doors, extra toys or water emitters. Narrow grates use 12 mm stainless ribs, 5 mm clear slots and 3 mm removable-panel joints. The existing stainless material role is unchanged. Exact dimensions, preserved receiver identities and the checkpoint are documented in [the fitting batch report](../../docs/formal-fitted-details.md).

New main/terrace/bath rails are closed 76 mm tubes with controlled 160 mm circular elbows, end caps, 210 mm mounted base plates and socket collars. Their lower posts land on the actual basin floor beyond the final tread. Short individual proxies follow the tubes without blocking the stair opening.

Material roles are `Formal_Ceramic`, `Formal_Plaster`, `Formal_Coping`, `Formal_Metal`, `Formal_Drain`, `Formal_Glazing`, and hidden `Formal_Collision`. The runtime maps formal plaster separately from the original source rooms. Ceramic UV0 coordinates are metres, with a runtime tile pitch of 0.1 m. UV2 has packed nonoverlapping islands and is unbaked; Godot may regenerate lightmap texel density. No lights, water simulation or gameplay are falsely represented as part of the Blender asset package.

## Exact collision contract

Every `COLLISION_` object is an individual proxy. Create shapes with `mesh.create_convex_shape(true, false)` and hide their mesh renderers. Disabling simplification prevents inflation of shallow stair heights. Arches use twelve local convex sectors, and curved rings use locally oriented sectors. Never make a whole-room, whole-arch, whole-stair-flight or whole-ring convex hull.

`scripts/world/formal_room_builder.gd` owns conversion of these proxies into Godot static collision and assigns runtime material roles. `formal_rooms.gd` owns the room graph, bounded water descriptors and exact `water_steps` boxes. The native source-water depth/mask path derives actual surfaces from transformed collision; the curved bath's coarse water rectangle must not replace its circular/alcove boundary. The Blender sources own architecture, not player collision code, simulated water, emitters or gameplay. The original source-world default and its mechanics remain separate from this selectable formal wing.

Twenty-one established main-hall ground, basin, coping, stair and east/south connector proxies retain their exact names, transforms, vertices and indices. The new north route adds geometry rather than changing those ground surfaces. Decorative grate bars, glass, screws and socket collars do not add unnecessary collision.

The enclosure checkpoint preserved all 377 pre-enclosure proxies and all 290 pre-enclosure visible shape/normal/UV0 witnesses across mainhall, arcade and sidepool. The subsequent fitting pass deliberately revises only six of those historical metal grates; all 284 other original visual witnesses and all 377 original proxies stay exact. Both historical witnesses and the six explicitly named approved variants remain checked. UV2 was repacked for added surfaces; any lightmap must use the current asset rather than an earlier bake. Tapered wall ceramics use exact metre coordinates along their actual wall plane.

## Verification and evidence

After a normal headless import, run:

- `godot --headless --path . --script tools/blender/formal_import_check.gd`
- `python3 tests/formal_authored_architecture.py`
- `python3 tests/formal_expansion_assets.py`
- `godot --headless --path . --fixed-fps 120 --script tests/formal_expansion_geometry.gd`
- `godot --headless --path . --fixed-fps 120 --script tests/formal_connected_loop.gd`
- `python3 tests/formal_connector_enclosures.py`
- `godot --headless --path . --fixed-fps 120 --script tests/formal_connector_containment.gd`
- `godot --headless --path . --fixed-fps 120 --script tests/formal_fitted_circulation.gd`
- `python3 tests/formal_fitted_source_contract.py --baseline-dir /path/to/preserved/pre-fitting/checkpoint` (historical delta proof requiring the separately retained checkpoint, not the current-source rebuild)
- `python3 -B tests/formal_source_packaging_contract.py` (source-selection/dependency/exclusion preflight, not an archive or runtime test)

Use writable HOME and XDG data/config/cache/runtime directories in a sandbox. These commands are CPU/headless tests, not native image capture.

All six GLBs pass the import UV/material/proxy checks. The main hall has 223 visible meshes, 254 collision proxies and 79,660 triangles including invisible proxies. All 145 original diffuse bake receivers preserve their exact oriented positions, normals and UV0; two additional fitting receivers bring the total to 147. Direct geometry tests verify finite unit normals, true dimensions, safe noncollapsed/nonoverlapping UV2, metric deck UV0, closed rails and preserved ground collision. The expansion depth test verifies the actual curved basin/stair-alcove boundary with a 30 mm geometric margin.

The production-world loop test passes 322 checks over 52 walking legs and 30,476 controller frames, with zero airborne frames. It includes every connection both ways and both complete loop directions without warping between legs. The earlier stair/wading/arcade/sidepool regression also remains green with all five rooms present.

The connector regression passes 620 checks over 80 lateral sprint/repeated-jump attempts and 12 full-width crossings, with no lost floor footprints. Actual jump events are verified to lift the native controller by more than 0.5 m; a dry adapter prevents the player's unbounded fallback water from hiding missing floors. These routes are all outside the authored basin rectangles.

Current reports are in `docs/verification/formal-*.json`; detailed dimensions, aperture contracts and visual-review limitations are in `docs/formal-authored-architecture.md`. Historical main-hall counts/hashes remain explicitly named in the geometry fixture and `--historical-check` audit. The native terrace-05 image also shows the final small service faces and narrow grates, with coherent visible contacts. Water/soffit readability remains a separate optical question. The curved bath, sidepool bench and arcade cabinet still need native image review before final visual acceptance.

## Packaging and provenance

The editable delivery contains all six `.blend` scenes, all six matching runtime GLBs, the model manifest, the generator and its verification/floor-plan dependencies. The concise Chinese [route/editing guide](../../docs/FORMAL_WING_GUIDE.md) explains the verified five-room topology. `docs/verification/formal-source-packaging.json` audits 31 required authored paths and independently checks Blender exclusions in both release profiles. Numbered `.blendN` backups, interrupted `.blend@` saves, `blendcache_*`/`.bphys` caches, Python bytecode, temporary output and Godot import caches are not editable sources. Generated runtime GLBs and approved game terrain caches are intentional delivery inputs, not disposable Blender intermediates.

Source selection is not proof of an already shipped archive. The release pipeline must verify the final `PACKAGE-MANIFEST.json`, `SHA256SUMS.txt` and complete `EDITABLE-SOURCE-ARCHIVES.json` archive union after staging. If the editable package is split, extract every listed part into the same project folder; the source and Blender parts are complementary, not interchangeable. This preflight does not claim Windows/Android execution or final rendered acceptance.

These six formal assets are original project-authored geometry, not copied POOLS, stock or paid models. As recorded in [CREDITS.md](../../CREDITS.md), the owner's existing project license is preserved; this delivery does not apply a new MIT, CC0 or other unrelated license to the owner's geometry or code. The separately credited Poly Haven ceramic scans and original source-water dependencies retain their own existing notices. Blender/Godot tool licenses are not a new license grant for these authored model files. Keep `CREDITS.md`, the texture notice and source-water notices with the project; no broader redistribution permission for user-supplied audio or other third-party material is asserted here.
