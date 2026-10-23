# Authored wing geometry, October 2026 refinement

## First main-hall milestone

The hall remains 22 × 20 metres, with a true 4.8 m ceiling underside, dry deck at 0.52 m, basin floor at −0.12 m and runtime-owned water at 0.32 m. The four stair tops remain 0.38, 0.24, 0.10 and −0.04 m. Twenty-one established ground, basin, coping, stair and east/south connector collision meshes retain exact names, transforms, vertex positions and triangle indices.

The redundant longitudinal arch lattice is removed. Nine continuous, thick transverse spans remain, including the clear east-portal return. Each arch uses twelve individually convex local sectors. No whole-room or whole-arch hull closes a doorway.

The new paired handrails are closed 76 mm stainless tubes with controlled 160 mm circular elbows rather than auto-Bezier bends. The dry-deck and basin ends have 210 mm base plates, 106 mm socket collars and flush fixings. The basin mounts sit beyond the last tread, on the actual basin floor. Individual short collision segments leave the centre of the stair clear. The existing coping joints, flush nosings and ceramic termination caps remain.

Clerestories now have actual masonry jambs and soffit reveals. Original roof/window apertures have not moved in this milestone. Formal plaster has its own `formal_plaster` material mapping, leaving original-room plaster unchanged. Two natural floats remain in the main basin's distant corners; eggs remain an original-room interaction kind, not a formal arrival-view prop.

## Authoring and import contract

- Edit `tools/blender/build_formal.py`; generate with Blender in background mode.
- `--only formal_mainhall` updates only the specified GLB and `.blend` source.
- Source `.blend` files live under `tools/blender/source/.gdignore`; runtime imports GLB only.
- Geometry uses metres. UV0 is metric; ceramic material pitch is 0.1 m. UV2 is packed independently and remains unbaked.
- Material source roles remain `Formal_Ceramic`, `Formal_Plaster`, `Formal_Coping`, `Formal_Metal`, `Formal_Drain`, `Formal_Glazing`, and hidden `Formal_Collision`.
- Hidden `COLLISION_` meshes are separate exact proxies. Runtime uses `create_convex_shape(true, false)`, without simplification.
- Runtime owns the water surfaces and coupling; assets must not contain a duplicate water plane.

## Evidence and limits

`tests/formal_authored_architecture.py` validates direct GLB data: preserved ground collisions, exact heights, local arch sectors, safe UV2 ranges, unit normals, manifold capped rails and floor-mounted socket geometry. The historical junction test remains an entry point for this current contract; `--historical-check` retains its older immutable-snapshot audit explicitly as history.

Godot headless import and continuous player-walk tests are separate from native rendered-pixel review. A passing geometry or headless test is not a claim that lighting or real-time performance has been visually verified.

## Integrated five-room authored wing

The approved cells are `(0, -2)`, a daylight shallow terrace, and `(-1, -2)`, a quiet curved bath. Their GLB assets and editable Blender sources are registered in the live formal catalog. After the first identical-camera native hall capture, the main hall and arcade gained actual north portals and enclosed, top-lit connecting ramps. The existing side pool remains at `(-1, 0)`.

The connected physical loop is main hall north → curved bath south → curved bath east → terrace west → terrace south → arcade north → arcade west → main hall east. All room origins are on the existing 32 m grid, without teleport transitions. Each new connector has a clear 6 m width. Its floor starts at the dry deck, 0.52 m, and meets the adjacent cell at −0.72 m. The existing main-hall east/south routes are unchanged.

### Daylight terrace

- Bounds: 20 × 18 m, x ±10 and z ±9. Pavilion roof underside: 4.20 m.
- Genuine open-sky aperture: x [−6, 6], z [−4.5, 4.5]. There is no glazing or luminous imitation panel across it.
- Basin: 12 × 8 m; actual floor +0.10 m, runtime water +0.32 m, depth 0.22 m.
- South entry: two 4 m-wide treads at z 3.78 and 3.36 m, tops 0.38 and 0.24 m. Paired mounted 76 mm rails.
- West connector: x −10 to −16; south connector: z 9 to 16. Each has a 0.8 m-wide longitudinal glazed top-light at y 3.40 m, with ceiling underside 3.15 m.
- Low courtyard perimeter: 2.45 m masonry plus 0.07 m coping. The east bench seat is 0.99 m above the reference plane. Repeated native-controller sprint-jumps from that bench remain inside the wall.
- Including the later restrained fittings: 118 visible meshes, 128 individual proxies, 34,424 triangles including proxies.

### Quiet curved bath

- Inner room radius: 8.8 m; outer masonry radius: 9.16 m. Wall openings face east and south, 6 m clear.
- Vault underside rises from 4.60 m at its perimeter to approximately 5.58 m at the real 3.6 m-diameter central oculus. Oculus glass is at y 6.025 m, with a built curb and metal mullions.
- Basin: 4.8 m radius, extended by a south stair alcove 3.6 m wide to z 6 m. Actual floor −0.12 m, water +0.32 m, depth 0.44 m.
- South entry: four 3.6 m-wide treads at z 5.78 − i × 0.42 m, tops 0.38, 0.24, 0.10 and −0.04 m. Paired mounted 76 mm rails.
- Continuous annular deck at 0.52 m, ceramic basin cladding, coping and a curved slot drain. Dry deck is not a rectangular water overlay.
- East/south connectors: 9.3 to 16 m, matching the terrace's physical shared edge.
- 69 visible meshes, 685 individual proxies, 57,420 triangles including proxies. Of these proxies, 596 preserve nonidentity local rotations through GLB and the production builder.

The source depth extractor represents convex shapes as local bounding boxes plus their object transforms. Curved sectors therefore retain their local radial/tangential orientation. Baking them into world-aligned boxes would incorrectly remove water near the curved shore. A production importer/kernel test verifies the actual 0.44 m circular wet region, the dry annulus and all four stair depths. No source-water algorithm was modified for these rooms.

### Expansion verification

`tests/formal_expansion_assets.py` checks direct GLB normals, explicit material roles, metre-scale floor UV0, packed UV2 bounds, noncollapsed UV triangles and positive-area triangle overlap within every visible mesh. It also checks closed capped rails, exact basin/stair heights, real apertures and rotated local proxies. Results: `docs/verification/formal-expansion-assets.json`.

`tests/formal_expansion_geometry.gd` instantiates both GLBs through the production builder. It uses the native player controller and unchanged source depth kernel, without rendering or starting a GPU water simulation. Its 12,945 assertions include 26 walking routes, 396 full-width ramp samples, 4,134 circular-basin wet samples, 569 dry-shore samples, another 7,750 exact circular/stair-alcove boundary samples with only a 30 mm geometric margin, both directions of the shared bath/terrace threshold at three lateral positions, and repeated wall-containment jumps. A read-only adapter of the actual source depth grid also confirms that both basins use wading, not swimming, and the original player controller emits depth-weighted coupling calls. Results: `docs/verification/formal-expansion-geometry.json`.

`tests/formal_connected_loop.gd` validates all five live rooms through the production world and player controller. Its 322 checks cover 52 walking legs, including every graph edge in both directions, the full 6 m width of the new portals, and two complete four-room circuits without warping between legs. Across 30,476 movement frames the player never lost floor contact. All five spawns, all stair/water descriptors and the five sparse floats match actual geometry. Results: `docs/verification/formal-connected-loop.json`.

The integrated main hall, including retained-ramp enclosures and fixed maintenance fittings, has 223 visible meshes, 254 local proxies and 79,660 triangles including proxies. All 21 pre-refinement ground collision meshes remain bit-identical. Its new 6 m north opening has masonry reveals and a matching dry approach, rather than an exit into the basin. The arcade has four structural arch frames, leaving the new central north branch genuinely unobstructed.

The first native terrace image (`output/eight-hour/formal-terrace-02.png`) shows the intended low pavilion, open roof, dry deck and mounted rails. Its water still reads too much like an opaque pale plane, and the nearly uniform sky makes the aperture harder to read. Architecture is held fixed for controlled optical diagnosis. The bath still needs native rendered review; CPU contracts do not certify final lighting or visual quality.

The [measured plan](formal-wing-floorplan.svg) was refreshed from the frozen fitted-wing GLB floor faces and a 1.5 m wall section by `tools/blender/export_formal_floorplan.py`. It includes the actual sloping connector floors, the service cabinet intersecting that section and the verified dry loop, rather than schematic rooms. Low furniture is not part of this floor/wall drawing, and it is not a runtime screenshot. `verification/formal-floorplan-provenance.json` pins the plan and five input GLBs. The historical `verification/formal-clean-rebuild.json` remains the pre-fitting enclosure proof; the current `verification/formal-fitted-clean-rebuild.json` proves all six fitted GLBs byte-identical both from a fresh generator run and direct export of the delivered editable scenes.

### Retained-ramp enclosure regression

The measured plan exposed an inherited defect: the original main/arcade and main/sidepool ramp halves had no side enclosure. With water correctly absent outside basin bounds, a native-controller probe could walk off all four halves and fall 9–15 m into unmodeled space. This is now fixed with an enclosure-only batch, not by an invisible universal floor or changes to the player/water model.

All four historical ramp meshes and their exact proxies remain unchanged. Main-south and sidepool-north retain 8 m width; main-east tapers from its 8 m portal to the arcade's existing 6 m shared edge. Each half has 240 mm masonry sidewalls, actual slope-following ceramic returns, a 200 mm roof at 3.15 m underside and an 800 mm clear rooflight on 120 mm curbs. No existing pool aperture is obstructed. The terrace and bath were left byte-identical for optical comparison.

At the enclosure checkpoint, `tests/formal_connector_enclosures.py` passed 40,531 checks, preserving all 377 previous proxies and all 290 previous visible shapes/normals/UV0 across the three changed assets. The current strict audit passes 40,595 checks: all 377 proxies and 284 non-grate historical visuals remain exact, while six explicitly named stainless-grate variants and 30 fixed-fitting nodes are pinned by exact witnesses. It still checks 7,568 enclosure UV2 triangles for degeneracy/overlap and 544 true-metre ceramic edges, including the tapered wall plane. UV2 was repacked, so earlier main-hall lightmaps must not be attached to the current asset.

### Fixed maintenance fittings, single promoted batch

The [fitting batch report](formal-fitted-details.md) records the narrow-slot grates, correctly mounted basin service faces, closed tiled access covers, sidepool bench and arcade cabinet. No structural opening, room connection, original receiver surface or old collision proxy changed. All 145 previous main-hall bake receivers are exact through independent native import; two new receiver meshes bring the new total to 147. Original-room defaults, the optional formal spawn and all five sparse formal floats are unchanged. Geometry is frozen pending actual native image review and the coordinated cache/lightmap rebuild.

The later native terrace-05 image visibly includes the small skimmer/return faces and narrow grates without introducing obvious contact gaps or doorway obstruction. That one camera does not certify the sidepool bench, arcade cabinet, curved bath or final baked hall. The 84-check lightweight source contract confirms exact promoted hashes, the historical fitting patch, unchanged structural authoring and the shipped manifest without rebuilding or rewriting active assets. The subsequent isolated two-thread Blender check independently reproduces all six exact GLBs from the generator and all six exact GLBs from the delivered `.blend` scenes; all 16 active source/model/runtime files remain unchanged.

`tests/formal_connector_containment.gd` passes 620 checks with the native controller: 80 lateral sprint/repeated-jump attempts at five stations on each half, plus 12 uninterrupted full-width crossings. No floor footprint is lost. Jump input events are checked to cause real airborne motion and more than 0.5 m clearance, rather than merely setting an unused input state. The fixture uses a dry water adapter only on routes verified outside every basin rectangle, so fallback buoyancy cannot mask a fall. The unchanged 52-leg whole-wing loop and legacy wading regression also pass.
