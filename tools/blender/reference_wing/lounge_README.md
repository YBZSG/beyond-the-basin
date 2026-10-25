# Reference 4: salmon ball-pit lounge

This is an original, editable Blender reconstruction guided by the supplied `reference-4/1000074569.jpg`. It is **not a water room**. No downloaded or paid assets are used.

## Delivered files

- `lounge_build.py`: deterministic Blender 4.3.2 authoring/export script, seed 4569.
- `lounge_sources/ball_lounge.blend`: complete editable source with individual architectural elements, cushions, metric UVs, preview lighting and reference camera. `.gdignore` prevents source re-import.
- `assets/models/reference_wing/ball_lounge.glb`: runtime mesh export, with two static ball batches rather than thousands of live physics objects.
- `assets/models/reference_wing/ball_lounge.geometry.json`: Godot XYZ/Y-up collision geometry, portal contract, lights, steps, support contacts, full sphere instance records, and an explicit empty `water_regions` list.
- `lounge_verify.py`: independent checks of the exported GLB attributes, actual support bounds and corridor/portal clearance.
- `output/reference_wing/lounge/`: numerical audit, build log, export verification and the Blender reference-camera preview.

## Reference landmarks preserved

The low salmon shell is 6.8 m wide × 16 m long. Its ceiling is at world Y 3.52 m, exactly 3 m above the common dry floor. The pale-blue/ivory ball fill occupies the left and center. A continuous gently bowed upholstered bench along the right wall has its top at Y 1.10 m, with a full supporting base extending down to the structural floor at Y 0.08 m. Coral cushions sit both on the bench and on measured local pile summits. Five circular cyan portholes are distributed across the right and rear walls.

The portholes are actual openings in 0.36 m-thick wall meshes. Their cylindrical recesses are 0.74 m deep, with thick glazing and a separate opaque, collision-backed outer closure. The front is a flush salmon opening, not a separate white ring. The preview daylight source sits 0.06 m inside the open cavity, ahead of the glazing at 0.70 m, so it does not shine through an opaque cap or bleach the deep sleeve. There are no open holes into the outside world and no paper disks substituted for wall depth. A closed 16-sector collision sleeve around every recess also prevents sideways escape beyond the wall, with less than 18 mm of conservative inward tolerance.

## Connections and collision behavior

- Module coordinates are centered on a 32 m square.
- North portal: `(0, 0.52, -16)`, 3 m wide × 2.8 m clear.
- West portal: `(-16, 0.52, 0)`, 3 m wide × 2.8 m clear.
- Both portals have physically closed, roofed connectors terminating at the actual west room entrance, on the dry apron at Z 4.8–8.0 m.
- Other module edges are sealed. No third implicit exit is assumed.
- A 1.45 m-wide shallow stair descends from Y 0.52 to the pit floor at Y 0.08 in three 0.1467 m rises, with 0.38 m treads. Its footprint and lower landing remain free of balls.
- The mandatory route stays on the dry connector floors and entry apron. Its conservative collision-bound proof measures 1.50 m minimum lateral half-clearance.
- The ball fill is **static decorative geometry**, not simulated physics. Each sphere has a recorded geometric contact with a floor, bench or preceding sphere; all placements are deterministic. No rigid bodies, collision layers or buoyancy are implied.
- In the pit, the player walks on the actual supporting structural floor at Y 0.08. The balls can visually surround the player's lower legs. There is no invisible floor falsely placed on the ball tops and no claim that the balls move when touched.
- The bench is approximated by 40 adjoining convex solids. Rendered soft edge rounding differs from the conservative collision profile by at most 0.10 m.

## Materials and UVs

The exported names are `ref_lounge_plaster`, `ref_lounge_fabric`, `ref_cushion_coral`, `ref_ball_blue`, `ref_ball_ivory`, `ref_glazing_cyan`, and `ref_fixture_metal`. Preview materials are deliberately matte/soft. They are not reflective ceramic. The integrating runtime may replace these named roles with the shared material library.

Architectural UV0 uses physical metre-scale projections. Ball UV0 uses physical spherical arc lengths. Small bevel strips are reprojected after bevel application so they do not inherit collapsed edge UVs. Closed caps are explicitly triangulated, and the exported normal/tangent streams are independently checked for unit lengths and finite values. The sidecar `material_roles` records each authored base color, roughness, metallic value and emission so integration can preserve the palette.

## Rebuild and verify

```sh
blender -b -t 4 --python tools/blender/reference_wing/lounge_build.py
python tools/blender/reference_wing/lounge_verify.py
```

After coordinating the shared CPU render slot:

```sh
blender -b -t 4 tools/blender/reference_wing/lounge_sources/ball_lounge.blend \
  --python tools/blender/reference_wing/lounge_render.py
```

The bounded 64-sample Blender preview is an authoring/composition check, not a Godot runtime screenshot. CPU denoising is disabled because this Blender build does not include OpenImageDenoise; any visible fine sampling grain is not part of the asset textures. Preview-only warm/camera bounce lights are excluded from final evidence; only the declared cavity/practical lights remain. The render report records source and GLB hashes, and verification reports whether the image matches the current export. No Godot editor/import process is launched by these scripts. The user owns the final local custom-Godot visual test and GPU/performance acceptance.

## Final export proof

The independent verifier measures a 32 m × 32 m exported footprint exactly (Y −0.38 to 3.84 m). The final export has 94 meshes, 528 explicit architectural collision proxies, 3,465 static spheres in two batches, and seven material roles. Both connector routes and both portals are clear. Twelve architectural/cushion support contacts are measured against exported geometry; sphere support error is below 0.000001 m. Every pit cushion is additionally checked against actual exported triangles for sphere penetration. The third stair tread is the existing pit floor, intentionally not a duplicate coplanar mesh.

## Final fixture seating correction

The five connector/practical assemblies are seated at Y3.46; their mount tops touch the actual Y3.52 ceiling underside. Their native light origins are Y3.41, 15mm below the opaque lens, outside the 5mm sampling sphere. Practical04 is at X−2.8 rather than buried in the west door header. Only these fixture meshes/transforms changed; all balls, routes, colliders and structural contacts are unchanged. The earlier composition preview predates this small mounting correction and is not a final-export lighting screenshot.
