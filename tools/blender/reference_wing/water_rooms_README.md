# Three separate reference water rooms

These are original, editable metric scenes for references 1, 2 and 3, not a hybrid
room or disconnected prop kit. No paid/external model assets are incorporated.
Geometry is validated independently; final Godot/NVIDIA appearance remains for
the user's local test. The accepted local lighting and palette choices below are
not a claim of photographic equality or native visual acceptance.

## Final compositions and finishes

- **Colonnade:** 10.4 × 25.6m chamber, seven paired square 1.15m piers, narrow
  center water aisle and dark side aisles. Dark-teal ceramic remains on walls,
  ceiling and basin; only the 14 paired piers use midtone `ref_tile_teal`.
  Actual dry surfaces use `ref_tile_dark_teal_dry`. Tile pitch is 0.10m.
  All piers extend to the -0.22m basin floor.
- **Cyan corridor:** 3.6 × 24m flooded corridor, four sealed black recessed
  windows with luminous jambs, six supported upper-left vertical wall strips,
  and a red no-entry sign on a floor-anchored pole/flange. The east exit is a
  closed dogleg near the dark far end. Final `ref_tile_cyan_satin` face is
  #63B0A6 with #4D8279 grout, 0.15m pitch and 0.34 face roughness; matching
  `_dry` surfaces use 0.40. This scoped palette does not alter colonnade teal.
- **Octagonal bath:** 13m across flats, 9m basin, continuous 2m dry rim and
  three real concentric treads. Eight complete concentric roof tiers and a
  center cap form the ceiling. Two rear 1.3 × 2.3m portals lead through closed
  passages to the west/south interfaces. Walls, ceiling, basin and integrated
  portal reveals use `ref_tile_pink_satin`, 0.20m pitch and 0.40 face roughness;
  dry surfaces use the matching `_dry` role. There are no black metal door
  frames, exterior wall washers or projecting washer hoods in the final scene.

## Final authored lighting

All direct sources have a modeled housing, supported mount or aperture.
The sidecar `lights` list is the editable native lighting document. Source RGB
is explicitly `color_space: "linear"`, matching Blender Light.color; the native
adapter converts it to Godot's expected color convention. Do not decode twice.

- **Colonnade: 9 enabled sources.** Seven axial rectangular fixtures have native
  energies 0.75, 0.75, 0.75, 0.75, 0.75, 0.58, 0.58. The entrance fixture is
  0.42 and the east connector fixture is 0.30.
- **Cyan: 7 enabled sources.** Six vertical strips sit on the left wall at
  Godot z=9.8, 7.7, 2.9, -2.6, -7.4, -10.7m. Their point centers are
  x=-1.72m, y=2.925m, aimed inward along +X, with linear RGB [0.72, 1, 1]
  and energies 0.90, 0.80, 0.65, 0.45, 0.18, 0.06. Housings contact the
  wall at x=-1.80m; source centers clear the diffuser by 12mm. The remaining
  connector source is 0.28. The former six generic ceiling batons are removed.
- **Bath: 4 enabled sources.** The existing concealed left connector practical
  is at [-1.45, 3.16, -7.15]m, aimed toward [-1.45, 0.52, -4.5]m. Its native
  energy is 1.20 and linear RGB is [1, 0.58, 0.28]. The roof-seated housing
  remains inside the portal cavity, with 36mm source clearance. The supported
  entry-side practical, outside the fixed camera view, is at [0, 3.05, 6.385]m,
  aimed along [0, 0.1, -1], with energy 8.0 and linear RGB [0.82, 0.90, 1].
  Its housing contacts the front wall and the source clears its diffuser by
  23mm. West/south connector fixtures remain 0.35 each and `shadow: false`.
  The eight concealed cove meshes remain, with local mesh emission reduced
  to 0.15, but all eight cove direct-light rows have `runtime_enabled: false`.
  There is no active continuous cove-light ring or floating central fill.

Native sources use finite POINT/SPOT approximations, not rectangular area
lights. The usual Spot half-angle is 85 degrees, attenuation 0.15 and sampling
radius 0.005m; the bath cavity lamp uses 75 degrees and attenuation 0.35.
The read-only native proxy uses a fixed diagnostic conversion of 100 Blender
Watts per native energy unit. It is not a physical-unit or pixel-equivalence
claim. Production Blender sources retain their authored practical light types.

The original water photon solver is unchanged and does not consume Spot cones.
Its first two active bath sources are the cavity practical and west connector,
not the entry practical. Cyan's first two are wall strips 01 and 02. Disabled
coves are skipped without reordering the original source list. These sources
and the native raster shadow budget must not be confused with angular water
transport or path-traced visibility parity.

## Editable sources, runtime assets and reproduction

Editable sources are `water_sources/{colonnade,cyan_corridor,octagonal_bath}.blend`.
The directory has `.gdignore`. Named components, material roles, cameras and
collision proxies remain editable. Preview water, author lights and cameras
are in `PREVIEW_ONLY_NOT_EXPORTED`. No replacement water is exported.
Runtime files are `assets/models/reference_wing/{room}.glb` and `.geometry.json`.

From the project root, with Blender 4.3.2:

```sh
blender -b -t 4 --python tools/blender/reference_wing/water_rooms_build.py
# Optional: append -- --only cyan_corridor (or another room name).
python tools/blender/reference_wing/water_rooms_verify.py
```

The complete production build requires these author files:

- `tools/blender/reference_wing/water_rooms_build.py`
- `tools/blender/reference_wing/water_rooms_joint_helpers.py`
- `tools/blender/reference_wing/water_rooms_joint_manifest.json`
- `tools/blender/reference_wing/water_rooms_lighting_helpers.py`
- `tools/materials/reference_wing/blender_materials.py`
- `assets/materials/reference_wing/material_manifest.json`
- Under `assets/materials/reference_wing/`: `full_normal_gl_16.png`,
  `glaze_orm_2k.png`, `ref5_crown_normal_gl_16.png`,
  `ref_tile_dark_teal_albedo_2k.png`, `ref_tile_pearl_albedo_2k.png`,
  `ref_tile_pink_albedo_2k.png`, and `ref_tile_teal_albedo_2k.png`.

The shared material factory currently initializes all roles, which is why its
crown-normal and unused palette inputs are listed. No external Python packages,
QA folder, candidate .blend or output JSON is an input to the production build.
Other `water_rooms_*` scripts are optional audits, preview tools or historical
candidate/promotion tooling, not additional production-generator dependencies.

GLBs contain zero embedded images. Temporary texture-free PBR placeholders
preserve exact tile/grout role names during export, then authored shared
material graphs are restored for source save. The runtime binds these names to
shared materials. Source texture paths are relative and verified after moving
the final files into `water_sources/`.

## Geometry and camera contracts

Sidecars use Godot XYZ, metres, Y up. All rooms fit a centered 32 × 32m module.
Dry interfaces are y=0.52m, water y=0.32m, basin floor y=-0.22m. External portals
are 3m wide with 2.8m measured dry headroom. Colonnade opens south/north/east,
cyan south/east, and bath west/south; all other module boundaries are closed.
Passageways have real floor, wall and roof thickness. Stairs are solid steps,
not hidden ramp colliders. Bath tread tops are 0.335, 0.150 and -0.035m, then
floor -0.220m. The first tread is 15mm above water; the others are submerged.

`collision_proxies` distinguish exact BOX and CONVEX shapes with explicit
transforms/bases. Octagonal ring pieces are individual trapezoidal prisms,
never one filled hull spanning the basin. `COLLISION_` objects must not render.
Water polygons, clipped bounding rectangles, exclusions, exact stair footprints
and actual submerged support-top profiles are derived from generated geometry.
The cyan flange top is -0.17m, giving 0.49m water depth outside its pole; it is
not a surface exclusion. `water_rooms_depth_contract.py` evaluates real polygon
footprints and actual GLB triangles, not ring-piece AABBs.

UV0 is 1 UV per metre, phase-aligned across coplanar surfaces. Material pitch
is supplied by the shader/helper without mesh UV scaling. Tangent bases and
normals are verified. The near-black `ref_recess_black` role must not become
bright grout.

Camera position/target and exact vertical FOV are stored in `camera_views`:

- Colonnade: lens 23mm, 700 × 700, vertical FOV 76.094090 degrees.
- Cyan: lens 22mm, horizontal sensor fit, 700 × 688, vertical FOV 77.609411
  degrees, corresponding closely to the 400 × 393 reference aspect.
- Bath: lens 18mm, horizontal sensor fit, 700 × 875, vertical FOV 102.680383
  degrees, matching the 400 × 500 reference aspect.

FOV is calculated from the actual Blender projection/view frame, not an assumed
16:9 conversion. Earlier square bath/cyan frames are retained only as A/B history.
Route waypoints include inset connector turns and are geometric witnesses, not
proof that every controller approach or target GPU has been validated.

## Contact repairs and verification

The production joint helper/manifest includes seven bath portal-cap terminations
and all 37 independently witnessed reachable duplicate-surface repairs: nine
colonnade joins, eighteen cyan joins/reveal laps and ten bath route corners.
Exact BOX interval trims replace coplanar overlaps, with removed slabs proved
contained in the unchanged collision union. Floors, stairs, water profiles and
portal clearances are preserved. Buried end edges are not beveled; exposed
edges retain metric bevels. Actual-mesh ray sections separately check visible
closure, because collision containment alone does not establish bevel closure.

Independent seam review removed all 37 target pairs with zero exposed remaining
same-facing overlaps in its sampled camera/route views. Some internal touching
faces remain; this is not a claim of eliminating every internal surface.
Geometry checks cover closed visual meshes, actual GLB normals/tangents, UV area
density, exact proxies, support gaps and headroom. Final main-generator output
matches the accepted cyan/bath scene geometry, UVs, material slots, author
lights and protected contracts exactly. Source relocation preserves a full
semantic fingerprint. No render or runtime visual claim follows from these
CPU proofs.

## Final preview evidence and known differences

`output/reference_wing/water_rooms/FINAL_ARTIFACT_MANIFEST.json` records frozen
production hashes and dependencies. `FINAL_PREVIEWS.json` identifies the selected
frames; older `*_blender_cpu.png` files can be superseded diagnostics, not final
acceptance frames. The selected cyan and bath frames are native-Spot-model CPU
previews of scenes verified equivalent to the final source recipes. They remain
48-sample diagnostics, not Godot/NVIDIA output.

Cyan is more saturated turquoise with a readable near-wall grid, red sign and
dark end, but remains darker than reference 2 with localized ceiling highlights
and weak distant grid visibility. Bath now lights the left cavity itself rather
than projecting an exterior white washer patch; its warm spill is still weaker
than reference 3. The ceiling/room framing is not photographically identical.
Low-sample noise and a single-interface Blender-only water approximation limit
both previews. Bath preview water is neutral and transmissive, not the earlier
strongly tinted stand-in. The water-off structural diagnostic shows all three
real treads; final runtime water clarity, reflections, caustics and energy
calibration require the user's local test. Global exposure/world settings and
original runtime water are not changed by these local revisions.
