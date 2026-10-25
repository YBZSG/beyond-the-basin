# Reference 5: dry descending stair gallery

This is an original, complete Blender-authored scene based on the supplied `reference-5/1000074570.jpg`, not a pool-room conversion or an asset-pack placeholder.

## Architecture

- One 3.00 m clear route between the left continuous tiled parapet and the right full-height wall.
- Upper landing at Y 4.68 m, lower landing at Y 0.52 m: 26 risers at 0.16 m and treads at 0.32 m.
- One closed stepped structural mesh includes the upper landing. The stair underside is solid and rests on a real foundation slab.
- A continuous, 0.28 m thick sloping parapet stands on the foundation. The recessed left planter contains supported structural fill, a 60 mm soil layer, and 249 individually rooted original plants, with layered solid leaf meshes rather than faceted hedge crowns.
- The main ceiling is Y 11.32 m; the lower landing to ceiling is 10.80 m. Two parallel rows of eight slim ceiling fixtures are physically mounted to that roof slab.
- A 1.10 m wide, 2.10 m high arched doorway sits at the lower landing. Its jambs bear on the threshold; its continuous arch reveal has exact segmented convex collision wedges. No AABB obstructs the opening.
- A concealed dry passage physically shifts from arch centre X 1.4 to the common north module interface at X 0, Z -16: a 3.00 m wide / 2.80 m high opening, threshold Y 0.52. Every other reachable room boundary is closed.
- No water region, pool, circular lounge, unsupported roof card, or floating stair is present.

## Files and regeneration

Complete rebuild and all CPU checks: `bash tools/blender/reference_wing/stair_gallery/rebuild_stair_gallery.sh`. Append `--render` only when a Cycles render is wanted. The shell wrapper uses `--python-exit-code 1`, so Blender Python failures cannot masquerade as successful process exits.


- Editable source: `source/stair_gallery.blend`, intentionally under `.gdignore`.
- Runtime asset: `assets/models/reference_wing/stair_gallery.glb`.
- Explicit runtime/verification contract: `assets/models/reference_wing/stair_gallery.geometry.json`.
- Regenerate: `blender -b -t 4 --python-exit-code 1 --python tools/blender/reference_wing/stair_gallery/build_stair_gallery.py`.
- Add `-- --render` for the labeled CPU Cycles composition preview.
- Verify exported binary attributes: `python tools/blender/reference_wing/stair_gallery/inspect_stair_export.py`.
- Actual mesh sections: `blender -b -t 2 --python-exit-code 1 --python tools/blender/reference_wing/stair_gallery/draw_stair_sections.py`.

The editable `.blend` retains named components, the shared reference-glaze candidate, camera, lights and exact collision proxies. Runtime export batches visible geometry into seven material meshes without changing the silhouette. UV0 is metric: 1 UV unit per metre, with no additional mesh scale. Standard glTF Y-up export is used, including its normal UV V convention. Ceramic roles use a 0.10 m tile pitch supplied by the runtime material family. The stair, lower landing, threshold and connector use the separate `ref_tile_dry` face roughness 0.26; the original pearl role is unchanged and the approved vertical-wall profile uses the dedicated `ref_tile_pearl_ref5_crown` role. Ceramic exposed structural edges use 4 mm two-segment bevels; concealed contacts and small details are not indiscriminately beveled.

## Collision and verification contract

The sidecar provides `collision_proxies` with explicit `BOX` or `CONVEX` types, actual bounds or Godot-space vertices, and identity transforms. Convex subtypes distinguish arch voussoirs and sloped structural wedges. It also supplies `steps`, `portal_contracts`, `support_contacts`, measured bearing gaps, fixture `lights`, zero `water_regions`, expected support/tread rays, and arch clearance rays.

The generator performs actual Blender BVH raycasts and manifold, signed-volume, degenerate-face, exact metric-UV and convexity checks. Separate auditors independently measure both surfaces of all 56 supports and verify 246 body/shoulder/head envelope rays against the actual collision proxies, including the small arch and centred north opening. QA outputs are written to `output/reference_wing/stair/`. The section SVG intersects actual source mesh polygons, rather than drawing nominal bounding boxes.

The CPU Cycles image uses the shared glaze candidate and is a composition/material preview, explicitly labeled on the image. It is not a Godot render, NVIDIA/Windows validation, performance claim or player-controller walking test. This environment's Blender build has no OpenImageDenoise, so CPU denoising is deliberately disabled rather than silently failing. Runtime integration and target-machine visual testing are separate.

## Controlled material evidence

`render_stair_wall_crops.py` performs four small CPU-only crops without saving material changes: default 0.075 roughness with face shape at 64/256 samples, the requested 0.115 roughness / face-shape-off control at 256 samples, and 0.115 roughness / face-shape-on at 256 samples. This separates sampling, roughness, and the face tilt/crown while retaining bevel normals and dry-floor roughness. The production source retains default wall glaze and the separate 0.26 dry walking surface. Old full frames named `v1_before_dry_leaf_revision` are superseded composition evidence, not evidence of the current revision.

## Separate near-wall diagnostic

The editable source also includes `DIAGNOSTIC_RightWall_10cm_Grid`, but the original reference camera remains active and the runtime spawn is unchanged. This diagnostic eye is (2.3,7,4), aimed at the actual mirrored fixture centre on the right wall near (2.9,7.8760419,3.59375). It uses 40° vertical FOV and a 640×640 image. The 10 cm tile at the target projects to about 74.4 px along the corridor and 49.0 px vertically. The diagnostic view is stored separately in `diagnostic_views` and is not a playable spawn.

Run `blender -b -t 4 --python-exit-code 1 --python tools/blender/reference_wing/stair_gallery/render_stair_diagnostic.py` only when the bounded 256-sample CPU shot is wanted. It does not add lights, change exposure/materials, enable optional filters, save source changes or modify the runtime GLB.

The saved `.blend` uses project-relative paths for all referenced images (seven loaded maps after the scoped crown rebuild, including the dedicated crown normal; all are verified in an isolated copy). `verify_stair_portability.py` opens both the real source and an isolated source-plus-maps copy, forces all referenced images to decode, and verifies unchanged source and runtime hashes. A separate camera-only source-change report records the diagnostic-camera addition; it is not a portability repair.

## Bounded stronger-face trial: not promoted

The additional `render_stair_facet_trial.py` comparison rendered identical 320×320 native borders of the same 640×640 diagnostic view at 256 samples, with fixed roughness, grid, bevel, light, exposure and seed. Its only candidate uses the QA-only normal generated by `tools/materials/reference_wing/generate_shape_candidate.py`; no production source, GLB or default was saved. The 1.8-strength field is physically bounded below the 0.28 mm relief.

The matched result is negative for the requested isolated-glint outcome: it creates modest bends, but the long source remains a coherent strip. Independent material review recommends retaining strength 1.0. The current C1 zero-slope face boundary contributes to that continuity; raising gain alone is not a complete solution. The candidate and all controls are preserved for inspection, not activated in the game.

## Explicit native-light metadata

All 17 fixture contracts declare scene-linear RGB, native spot type, 80° spot angle, and 5 mm spherical emitter radius. The main light origins are 15 mm below the visible lens underside, so this small native sampling radius remains outside that opaque geometry. Ceiling energies remain 4.0 and continuation energy 2.0. These native point/spot approximations do not replace the authored elongated emission mesh, and the unchanged Blender area-light wattages are preview data, not claimed equivalent native power.

The metadata-only migration is reproducible with `update_stair_light_metadata.py`; its QA report records the prior source-byte backup and verifies identical geometry, UVs, material nodes, preview lights, camera lenses/transforms, image paths and runtime GLB before/after saving and reopening. No render or production material change is part of that migration.

## Single structural face-model trial

`render_stair_planar_trial.py` rendered one additional QA-only 320×320 native-border crop, reusing the unchanged exact baseline image. The candidate uses a nearly planar 92 mm tile interior with small independently tilted faces and a bounded 2.5 mm transition to the existing bevel. Roughness, camera, illumination, exposure, sample count, seed and all other roles remain fixed. It does not save the source or runtime assets.

The crop shows flatter highlight interiors and clearer narrow joint interruptions, but the long reflected source remains connected and bright edge fringes increase. This does not demonstrate isolated small tile glints; it is not a production promotion. See `stair_planar_interior_trial_checks.json` for controls and source/GLB hashes.

## Square reference-frame correction

The actual supplied reference is 750×750. The earlier 900×1000 composition and all A/B evidence remain retained. `measure_stair_square_camera.py` verifies a proposal to change only the original reference camera's image aspect to square: the same 22 mm AUTO-fit camera preserves its 78.578814° vertical field and all vertical landmark positions, while widening the horizontal field from 72.733159° to 78.578814°. The proposal was then approved and adopted in the saved source, sidecar and generator using `update_stair_square_framing.py`. No square render was performed. Future wide renders use `stair_cycles_square_preview.png` and `stair_final_square_metadata.json`, preserving the prior portrait and all A/B evidence. The correction report records source backup, before/after hashes, unchanged geometry/material/light/camera-lens signatures, and every retained PNG hash.

## Bounded localized-crown mechanism trial

After angular-width analysis, one further explicitly approved QA crop used a C2 localized crown with nominal 0.30 mm height and 40 mm radius, retaining the existing ±0.35° tilt, 0.075 roughness, bevel, camera, lighting and sampling. `render_stair_crown_trial.py` renders only the same 320 px border and reuses the unchanged exact baseline. The candidate introduces separate cell-linked short glints and scalloped/gapped portions of the reflection. A broad connected backbone and some paired/stretched lobes remain, so this is mechanism evidence rather than final visual acceptance. No source, GLB, production map or runtime default was changed. All controls, bounds and hashes are in `stair_localized_crown_trial_checks.json`.

The crown candidate was subsequently checked at a second actual viewing angle in `stair_crown_square_candidate.png`, a separate 750×750, 96-sample CPU reference-camera frame. The room-scale wall still reads planar, with straight grid lines and no obvious egg-carton or liquid-wall pattern; upper-right reflections break into cell-scale patches/fringes. The undenoised CPU frame remains noisy, and broad physical source envelopes persist. This supports the direction without proving final/native appearance. Both this frame and the close diagnostic remain QA-only, with source and runtime asset hashes unchanged.


## Current scoped crown integration

After review of the close diagnostic and the square reference frame, the crown direction was approved for scoped integration, not native visual completion. The current source/generator/GLB binds `ref_tile_pearl_ref5_crown` to exactly 134 vertical polygons on 33 main/far-wall, parapet and arch-spandrel objects. Ceiling, horizontal parapet caps, sloping structural bevels, dry walking surfaces, teal arch, foundations and hidden connector retain their original roles. The current runtime still has seven visible mesh nodes, 23,908 triangles and 98 exact collision proxies, with zero embedded preview textures.

`stair_crown_integration_checks.json` proves exact source mesh/topology/UV, camera/light, canonical GLB POSITION/NORMAL/UV triangle and collision-proxy parity. All seven old used material node graphs and 23 structural sidecar fields also match their preserved pre-integration versions. Seven image dependencies pass the isolated-copy portability check. The independent buried threshold/far-wall foundation overlap remains recorded, not repaired or concealed by this material-only update.

Archived experimental scripts temporarily restore base-pearl assignments in memory before applying their historical QA controls, never saving those assignments. Thus later scoped integration cannot silently contaminate a rerun of the old baseline. Current source previews do not perform that restoration. No new render was required or performed for the material-role integration.

## Portable core rebuild order

For editing on Windows, invoke the installed Blender executable with the project as the working directory, then run the Python export inspector, then the Blender contact measurement. The exact three commands and prerequisite notes are in `docs/reference_wing/ASSET_PORTABILITY.md`. The inspector and contact measurement update production geometry JSON fields; they are not read-only checks. Run rebuilds in a personal project copy. The optional Bash/Pillow diagrams require the documented Linux font setup; they are not needed for the runtime scene or core Blender regeneration.
