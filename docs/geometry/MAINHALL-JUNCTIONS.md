# Mainhall architectural junction refinement

Authored in installed Blender 4.3.2 on 2026-10-21. This is a restrained detail pass, not a room remodel, water change or claim of photorealism.

## Delivered details

- Four 54 mm-wide pale ceramic stair nosings sit in 28 mm-deep visual seats. Their upper surfaces are exactly the existing tread tops: 0.38, 0.24, 0.10 and -0.04 m. They are not a raised overlay or a new collision obstacle. One combined `Main_CopingStairNosings` mesh uses `Formal_Coping`.
- Forty-four physical coping joints are cut into the existing five coping strips. The 5 mm groove has a 3 mm recessed centre and a maximum 4 mm depth, at approximately 1.05 m spacing. The original outside coping dimensions and 18 mm three-segment perimeter bevel remain. There is no decal or texture-noise overlay.
- One combined `Main_CopingArchitecturalCaps` mesh contains 17 slim 36 mm caps: six wall intervals and eleven existing ceramic-clad pier feet. Wall caps project 12 mm on each wall face; pier caps project 10 mm. They bridge the actual ceramic/plaster junction, with no trim across either 8 m portal opening.

Small new trim uses a one-segment 3 mm chamfer to avoid paying for tiny rounded detail. Existing arch geometry, arch bevels, roof, basin, decks, portals, ramps, drains and rails retain their exact exported vertex positions and normals.

## Rebuild and file scope

Run `blender -b --python tools/blender/build_formal.py -- --only formal_mainhall`.

The existing no-argument full build remains supported. `--only` saves only the chosen GLB and editable `.blend`; it does not rewrite the other assets or common manifest. The mainhall source remains `tools/blender/source/formal_mainhall.blend`, under the existing `.gdignore`, and runtime remains `assets/models/formal/formal_mainhall.glb`.

All three other `.blend`/GLB pairs and the manifest were compared to the preserved baseline and are byte-identical. No runtime materials, lighting, gameplay, water code or other worker's files were edited by this detail pass.

## Honest geometry budget

Counts below include the unchanged invisible collision meshes and refer to the actual exported GLB, not Blender's shared-vertex count.

| Metric | Before | After |
| --- | ---: | ---: |
| Exported vertices | 97,142 | 110,838 |
| Triangles | 66,444 | 73,384 |
| Visible mesh instances | 140 | 142 |
| Collision proxies | 219 | 219 |
| GLB bytes | 4,463,812 | 5,067,780 |

This is +14.099% vertices and +10.445% triangles, with only two added visible mesh batches. Joint strips were not split into dozens of separate draw objects. This is a geometry budget report, not a measured GPU performance improvement.

The two new batches and all five jointed coping strips have verified metre-space UV0 values; all 142 visible meshes retain UV0 and unbaked packed UV2. All original `Formal_*` material role names remain. UV2 is repacked after the edit; exported triangle diagonals on some unmodified curved meshes can differ, while their vertex positions, normals and triangle counts remain identical. Do not call the complete new mainhall GLB byte-identical to its predecessor.

## Collision and spatial contract

The canonical digest of all 219 collision object names, transforms, position arrays and index arrays is identical before and after:

`f8a5ec94250a288c0c23f21bbf1ca5ba9641d18b7c4b742e8144567552b59c43`

The room remains 22 × 20 m, with roof underside at 4.8 m; the basin bottom remains -0.12 m, the dry deck 0.52 m, and runtime-owned water 0.32 m. Neither collision proxy geometry nor portal/ramp access changed. There is no new static water mesh.

Final GLB SHA-256:

`2f597b61223b2265a8057a11d7d2275645977d120f30cbc9822cf45d862dbe39`

## Verification

1. `python tests/formal_architectural_junctions.py --baseline-root /path/to/original --report docs/geometry/mainhall-junction-validation.json` passes. It checks the actual joint recess vertices, all four flush nosing heights, 110,838 finite unit normals, 456 actual metre-space UV samples, 131 untouched visible mesh position/normal arrays, exact collision digest, portal/cap dimensions and byte-identical other assets. Without the optional baseline path it still checks the saved baseline collision hash and geometry contracts.
2. Opening the editable `.blend` in Blender 4.3.2 confirms all eleven changed/new meshes are closed and manifold. See `mainhall-junction-blend-check.log`.
3. Godot 4.6.3 headless reimport completed; `tools/blender/formal_import_check.gd` passes all four assets, convex proxy generation, exact stair bounds, materials and both UV sets. See `mainhall-junction-godot-import.log`. The editor emitted a non-blocking temporary user-settings save-path warning at shutdown; imported scene validation subsequently passed.
4. `tests/formal_walkthrough_test.gd` passes all 10 checks: three destinations, exact deck, descending and ascending the four steps, 0.44 m wading/source impulses, both room connectors and perimeter collision. See `mainhall-junction-walkthrough.log`.
5. `python -m py_compile` passes for the authoring generator and new Python regression test.

This worker did not launch a Godot GPU session. Same-camera rendered comparison and final GPU profiling are coordinated separately with the runtime/lighting changes; the geometry/data tests above must not be presented as visual-render acceptance.
