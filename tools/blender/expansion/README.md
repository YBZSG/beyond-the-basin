# PoolCore expanded facility modules

Original Blender-authored geometry, made for this project. No downloaded meshes,
textures, fonts, purchases, or external licences are involved in this asset pack.
The AI architectural reference is a design aid, **not a runtime screenshot**:
`assets/models/expansion/reference/poolcore_ai_architecture_reference.png`.
The reference and editable Blender sources are excluded from Godot runtime imports.

## Deliverables

Four 32 m modules, each with a 23.2 m inner room and four 4.4 m clear interior portals:

- `shower_changing`: dry changing deck, eight real shower fittings, privacy fins,
  linear grates and four paired changing islands with eight tiled benches and low
  locker-like dividers. Two connected shallow ceiling ribs organize existing lamps.
  Ceiling slab center is 4.5 m, underside 4.3 m; deck-to-ceiling headroom 3.78 m.
- `low_arched_bath`: four repeated low elliptical arches, four shallow basins,
  six-riser basin entries and steel handrails. Inner ceiling 5.8 m.
- `skylight_gallery`: four side basins, large genuine roof openings with structural
  mullions and beams, and peripheral benches. Inner ceiling 6.5 m.
- `service_transition`: recessed service doors, vents, handles, tiled seating,
  structural pilasters and a real 4 x 8 m roof light. Inner ceiling 4.3 m.

Seven separately reusable models: bench, shower, linear drain, handrail, portal,
wayfinding plaque and service door. Each has its own editable `.blend` and `.glb`.
`ExpandedFacilityModel.instantiate(name, materials)` creates a Godot-ready standalone
instance, hiding authoring proxies and adding simple box collision where needed.
Drains and plaques are intentionally non-colliding surface detail.

The `.blend` files retain individually named editable objects before batching.
Exported GLBs are batched by material, not tessellated by every 10 cm tile. The
ceramic grid comes from the existing runtime material at a 100 mm real-world pitch.
UV0 uses one UV unit per metre. Explicit small bevels are physical geometry.
All collision proxies are simple boxes; no full-room triangle collider is generated.
The rail has separate post and top-bar proxies, not a solid invisible wall.

## Regeneration

From project root:

```sh
blender -b --python tools/blender/expansion/build_expansion.py
# One model only, preserving other outputs:
blender -b --python tools/blender/expansion/build_expansion.py -- --only shower_changing
```

Sources: `tools/blender/expansion/source/*.blend`
Runtime: `assets/models/expansion/*.glb`
Reconciled counts: `assets/models/expansion/manifest.json`

## Seeded integration and invariants

`PoolRoomCatalog.room_layout(coord, seed, expanded=false)` keeps the original
8-variant selection and original RNG draw order as its default. Expanded mode uses
an independent hash/RNG and selects 56% facility modules / 44% unchanged old rooms.
Four discoverable new anchors are at origin, east, north and west. Formal mode is
independent and unchanged.

- New module: `layout.expanded == true`; mixed-world tag: `layout.expanded_mode`.
- Original cell size 32 m, ground -0.78 m and physical source floor top -0.72 m.
- Shared outer portal remains 8 m wide with top at 5.4 m; only N/W boundaries
  are owned. E/S receive only an upper closure when taller than their neighbor.
- Dry deck top +0.52 m. Four entrances use seven 15.5 cm treads down to the
  shared -0.72 m floor. Portal connections are never sealed by authored doors.
- Original water level +0.32 m. Basin depth is deliberately 1.04 m, not a decorative
  thin water sheet. Explicit entry rectangles keep water off the dry deck.
- `water_rects` contains four wet threshold strips; bath/gallery add four 7 x 7 m
  basins. `water_steps` describes exact physical step boxes. `water_exclusions`
  comes only from imported solids crossing the real waterline.
- No floats are generated in dry rooms; bath/gallery receive two seeded ducks
  strictly within actual basins, not on the central walking route.
- `ExpandedPoolRoomCatalog.spawn(coord)` returns a dry supported +0.60 m spawn.
- `ExpandedPoolRoomCatalog.route_points(coord, entry, exit)` returns center-line
  route points for all cardinal entry/exit pairs. Runtime movement still uses the
  production player and actual collisions; this is not teleport-based navigation.

## Materials and fixtures

GLB material names directly match existing material-library keys:
`formal_dry_deck`, `formal_basin`, `formal_wainscot`, `formal_plaster`,
`formal_coping`, `brushed stainless`, `black`, `service`, `dark sign board`.
No common material implementation is modified by this pack. The shower alone
clones its dry-deck material and sets coat_strength from 0.06 to 0.0. Its roughness,
shader, textures and all other parameters remain identical; wet and shared
original/formal materials are not changed.

No baked lamp geometry remains. Runtime fixtures are defined in
`expanded_room_catalog.gd::fixtures(index)`, with source-compatible dictionaries:
`alive, position, color, power, power_scale, flicker, flicker_seed, flicker_amp`.
Expanded fixtures are maintained and do not flicker. Cable mounts use
`layout.interior_ceiling`, not the higher outer boundary ceiling.
Gallery tubes hang below central roof beams, not inside open roof lights.

## Verification

- `tests/expanded_topology_test.gd`: 128 seeds / 56,448 coordinates,
  deterministic mixed selection, all reciprocal portals, spawns and wet bounds.
- `tests/expanded_import_clearance.gd`: actual imported geometry/physics,
  dense 25 cm scans of all cardinal corridors at center and +/-1.8 m lanes,
  exact floor levels, entry and basin stair descriptors, capsule headroom.
- `tests/expanded_continuous_routes.gd`: production Player/Jolt, 304 m continuous
  walking through all four modules clockwise and counter-clockwise, then across
  an original/source room boundary in both directions. No inter-leg teleport.
- `tests/expanded_asset_contract.py`: actual GLB structure, UVs, known material
  names, editable sources, small collision proxies and triangle budgets.
- Existing `world_parity`, `world_room_parity`, `original_geometry_parity` and
  `original_batch_parity` tests all remain applicable to the untouched default.

Native GPU visual/lighting acceptance is performed separately by the integration
coordinator; the AI reference and CPU geometry tests are not substitutes for it.

## Shower revision, 2026-10-22

Four symmetric paired bench/storage islands preserve the 8.3 m central cross.
The closest privacy fins now stop outside that cross. Both side aisles remain
2.15 m clear. Ceiling ribs overlap the slab underside and existing fixture cables;
there are no additional baked lamp models.

Final shower: 12,168 visible triangles, 9 material batches, 135 simple proxies.
Its explicit triangle cap is 12,500 to account for the extra benches, storage and
ribs; all other assets retain the original 10,000 cap. All 11 assets total 32,629
triangles. This is a measured asset cost, not a native performance claim.

The revised geometry passed 23,756 checks, including 7,878 cross-route capsule
samples, 1,818 side-aisle samples and 304 m continuous production Player/Jolt routes.
The promoted live import separately passed 4,308 checks, and its isolated dry
material 34 checks. Reports are in output/expansion-candidate-01/. The source bundle
is an editable asset/integration add-on, not the complete runnable game package.
