# Architecture contact repair, 2026-10-24

This is a bounded repair to the three already assembled Blender rooms. The rooms were complete Blender-authored compositions before this repair; this is not a migration of room assembly from Godot into Blender. The previous delivered project and ZIP are untouched.

## Measured defects and changes

- Lanes: each of eight main pier feet was mapped to dry-deck height 0.52 m even though the broad foot area lies over a basin floor at -0.22 m. This left 0.74 m unsupported above the basin. A thin inner lip overlapped the coping, but that did not support the full pier section. Every pier now bears at -0.04 m on its own narrow submerged footing.
- The eight footings have bottom -0.32 m, embedded 0.10 m into the basin slab, and top -0.04 m, 0.18 m above the basin floor and 0.36 m below still water. Their footprints are 0.806667 m wide by 0.72 m deep, extending only 0.14 m beyond the shaft toward the wet lane and fore/aft. Their inner edges remain x = -2.0 / +2.0 m so the nominal 4 m dry central route is not narrowed. They do not reach the basin stair approach rectangles.
- Lanes rib tops were 4.67 m against a slab underside at 4.70 m. The existing imported upper spandrel is now mapped directly to 4.70 m. The arch crown 4.45 m and spring 3.35 m stay unchanged. No detached patch pieces were added.
- The existing continuous barrel was left ending at z = +/-9.6 m. It now ends at +/-11.8 m, engaging the existing portal headers by 0.20 m. It retains its 3.50 m spring edge, 4.45 m inner crown and 4.65 m outer crown.
- All three rooms had a 0.075 m horizontal separation between vestibule transition soffits and inner portal headers. Transition soffits are now 0.40 m deep at a local wall distance of 12.10 m, engaging the inner header by 0.10 m and retaining contact with the apron roof at 5.40 m.
- Court arcade feet, arcade-to-roof connections, Bath circular gateway, curved/rounded dividers, benches, basin treads and coping already meet their intended floor/roof elevations. They were not indiscriminately extended down to basin level.

## Runtime contract

All footings have exact BOX collision proxies. The same eight footing AABBs and eight full pier-shaft AABBs are included in source `water_steps`, so the footing changes water depth and each pier excludes water at the waterline. `water_obstacles` documents which named visual/collision components supply these entries; `architecture_bearings` and `architecture_connections` document receiving surfaces and load-path joints. These source contracts must be compiled by the runtime-integration task before game QA.

Current Lanes fixtures are unchanged: four housings on the existing middle pier inward faces, the same four light positions, range 6.5 m, power 14. No renderer, shader, global water, materials, controller, route, spawn, portal width, room scale or source-asset count was changed. UV0 remains one unit/metre with the project's eight-tile/0.8 m ceramic maps, giving 0.10 m tile scale. Imported mesh weld and normal correction remain enabled.

## Verification boundary

All three editable `.blend` files and all three integrated `.glb` files were regenerated with Blender 4.3.2 in background mode using two CPU threads. No GPU or Godot was launched by the architecture repair task. Independent contact rays/sections, exported geometry/UV checks and production-engine validation are separate acceptance checks. Historical preview images and audit reports in this directory predate this repair and are not current acceptance evidence.

Independent post-export source/contact QA subsequently confirmed all eight shafts meet their named footings within 0–1.891 mm (source bevel allowance), all eight footings are embedded 0.100 m in actual basin meshes, and rib-to-roof contacts are within 0–0.795 mm. All three exported triangle sets match the source scenes within 0.1 mm; all collision bounds/names match. Visible meshes are closed manifold, consistently oriented and positive-volume. Metric UV checks on edges at least 1 cm long give ratios 0.999979–1.000024; a submillimetre Bath edge outlier is float precision, not tile-scale distortion.

A final shared trim refinement seats every portal jamb on the first entry tread at y=0.365 m. The rear 75 mm lip now has direct tread contact; the rest of the unchanged jamb footprint embeds 155 mm into the dry deck. Jamb top y=3.72 m, inner opening width, landing geometry and routes remain unchanged. Source `portal_jamb_bearings` records all eight jambs per room.

Outer north/west shared walls extend 0.30 m into the neighboring cell's foundation region. A neighboring 32 m foundation translated north/west covers that outboard half at the same y=-0.72 m bearing elevation. This is a modular bearing contract, not permission to add overlapping foundations. Actual neighboring-cell presence remains a runtime acceptance condition; no foundation dimensions changed.

The final independent rerun after the jamb correction confirms all 24 jambs bear on the first stair treads, with 0.155 m dry-deck embed. Final source/export geometry, collision bounds and the declared frozen hashes match. See `output/contact-qa/ARCHITECTURE_CONTACT_QA.md` and `output/contact-qa/final_freeze_verification.json` for the independent final acceptance evidence. Translated neighboring foundation rays also show zero wall-base gap; actual neighbor presence is still reserved for native runtime QA.
