# Bath wall junction: staged geometry candidate

Status: **candidate only, not integrated**. No production GLB, production `.blend`, or `tools/blender/build_formal.py` was edited. No Godot or GPU launch was performed. The parent owns the full-runtime A/B and final acceptance.

## Useful finding

The shipped bath consists of independently beveled `Bath_Wall` (1.48–3.2 m) and `Bath_UpperDrum` (3.2–4.6 m). Direct triangle inspection found:

- 156 lower-wall cap triangles and 216 upper-drum cap triangles at the same y=3.2 plane.
- 15.089 m² of overlapping opposing horizontal cap area.
- The independently beveled inner lips are about 8 mm behind the intended inner wall at the join, producing a narrow real groove.

Identically lit, CPU-only isolated-geometry renders show that groove in the original and its absence in the candidate. This proves a geometric discontinuity was present and removed. It does **not**, by itself, prove the cause of the dotted line in the full Godot runtime screenshot.

## Candidate construction

One closed watertight plaster shell replaces the two visible solids. The 3.2 m surface edges share vertices and smooth normals; there are no horizontal caps across existing wall sectors. The only horizontal y=3.2 surfaces are the genuine overhead headers across the east and south portals. The exact original angular breaks, radii (8.80/9.16 m), wall bounds, and the external 8 mm/three-segment edge treatment are retained. This is not an overlapping cover ring.

`Bath_UpperDrum` remains as an empty reference node. Every original `COLLISION_` proxy is unchanged, including names, vertices, triangle indices, normals, transforms and metadata. No new collision geometry exists.

## Files

- `assets/models/bath_junction_candidate/formal_bath_continuous_wall.glb`: byte-prefix-preserving A/B candidate, 4,571,612 bytes. It deliberately retains now-unused source buffer data to prove preservation.
- `assets/models/bath_junction_candidate/formal_bath_full_source_export.glb`: the same candidate geometry directly exported from the full editable scene, 4,137,224 bytes. This compact version is preferable for eventual delivery after runtime acceptance. Its unrelated mesh attribute bytes, transforms and metadata are also proven exact. Node/accessor numbering changes, as expected in a fresh export.
- `tools/blender/bath_junction_candidate/formal_bath_continuous_wall.blend`: editable full scene.
- `tools/blender/bath_junction_candidate/build_candidate.py`: repeatable bounded generator, loading the current production source read-only and replacing only the two visible wall solids.
- `tools/blender/bath_junction_candidate/rejected-full-rebuild.patch`: an evaluated but **rejected** full procedural rebuild approach. It constructs the correct wall and preserves collisions, but the original global UV2 packing changes unrelated meshes. Do not adopt this patch as-is. Use the preservation-safe editable-scene generator above. The isolated evaluation is retained under `generator_review/` for audit only.
- `assets/models/bath_junction_candidate/saved_source_wall_roundtrip.glb`: minimal read-only export from the saved-and-reopened candidate `.blend`, matching the inserted candidate mesh attribute bytes exactly.

## Passed checks

- 756 unrelated editable objects have exact geometry, normals, UV layers, transforms, material roles and metadata signatures.
- All 687 original collision proxies are identical.
- All 756 unrelated GLB meshes have byte-identical POSITION, NORMAL, UV and index attribute streams.
- The complete original binary payload is byte-identical in the prefix-preserving variant.
- New wall: 2,040 authored vertices, 2,048 authored polygons, zero boundary edges, zero nonmanifold edges, zero loose vertices, positive volume, no degenerate faces.
- Exported triangle manifold: all 6,120 unique welded edges have exactly two incident triangles.
- 5,963 finite unit normals; 572 metre-space UV0 samples; all 4,080 UV2 triangles finite, bounded, noncollapsed and free of positive-area overlap.
- Portal rays at y=1.55, 2.4, 3.18 pass through both actual doors. Rays at y=3.3 hit the overhead header.
- West/north wall rays around y=3.2 now stay at exactly the 8.8 m inner radius, including at the former joint.
- Saved `.blend` reopened read-only: all 756 unrelated object signatures and the new wall signature match. Re-exported new-wall vertex, normal, UV and index bytes exactly match the candidate.
- The new wall uses 4,080 triangles instead of 6,264, removes one visible mesh/draw, and leaves all other visuals untouched. No runtime performance claim is made.

Evidence: `glb-verification.json`, `blend-geometry-report.json`, `saved-source-reopen-proof.json`, `original-junction-evidence.json`, and accompanying logs.

## Diagnostic renders

- `original-junction-cpu.png` and `candidate-junction-cpu.png`: identical close-up camera and grazing light, at the actual y=3.2 joint.
- `original-portals-cpu.png` and `candidate-portals-cpu.png`: isolated shell view showing the real open portals and overhead headers.

These are isolated Blender CPU diagnostics, not replacement game screenshots. Cycles was explicitly set to CPU, two threads, 64 samples, 640×400; the peak guarded process RSS was approximately 274 MiB, below the 768 MiB cap. No renderer-memory limit was bypassed.

## Reproduce before integration

Run from the project root with `/usr/bin/blender` (the installed binary is Blender 4.3.2):

```sh
python tools/blender/bath_junction_candidate/run_guarded.py --log docs/bath-junction-candidate/build-candidate.log -- /usr/bin/blender -b -t 2 --disable-autoexec --factory-startup --python tools/blender/bath_junction_candidate/build_candidate.py
python tools/blender/bath_junction_candidate/splice_and_verify.py
python tools/blender/bath_junction_candidate/run_guarded.py --log docs/bath-junction-candidate/saved-source-reopen.log -- /usr/bin/blender -b -t 2 --disable-autoexec --factory-startup --python tools/blender/bath_junction_candidate/prove_saved_source.py
python tools/blender/bath_junction_candidate/run_guarded.py --log docs/bath-junction-candidate/cpu-render.log -- /usr/bin/blender -b -t 2 --disable-autoexec --factory-startup --python tools/blender/bath_junction_candidate/render_diagnostic.py
```

`splice_and_verify.py` intentionally compares against the untouched production baseline. Preserve that baseline if production is subsequently replaced. The rejected patch was actually rebuilt in an isolated directory: it preserved geometry/normals/UV0/collisions, but changed unrelated UV2 and some triangulation order. `generator-review-proof.json` intentionally records `pass: false` for that rejected alternative, not for the delivered candidate. It must not replace the preservation-safe candidate.

## Remaining acceptance

Run the candidate in the actual full game at the existing accepted-lighting camera and settings. Inspect the former dotted y=3.2 seam, portal headers/reveals, ceiling junction, wet-basin/stair views, collision traversal, and runtime frame/memory behavior. Do not broaden lighting or water changes to compensate for this narrowly scoped geometry candidate.

## Narrow runtime A/B helper

`assets/models/bath_junction_candidate/bath_wall_scene_swap.gd` provides `apply_to_bath(bath_root)` and `restore()`. Instantiate the script as a RefCounted and retain that instance until restoration. It loads the compact export, borrows only its `Bath_Wall` mesh, frees the temporary candidate scene, assigns that mesh to the existing bath wall node, and hides the old upper-drum node. It uses the exact current shared plaster material instance. It never replaces the room, adds/removes scene nodes, changes collision, touches production files, or alters lighting/water settings. It rejects missing/ambiguous nodes, unexpected surface counts/materials, and mismatched local transforms before changing anything.

Apply after the standard material assignment and preferably before native optics/BVH capture. The helper deliberately does not alter or silently rebuild those caches. A fresh capture per comparison is the strongest full-game check. The helper has been source-reviewed but not parsed or run in Godot here, because Godot launches remain reserved to the parent's serial slot.

The full procedural rebuild experiment's failure is a strict byte-preservation failure from global UV2 repacking and resulting triangle-index changes, **not evidence of a runtime geometry/collision regression**. Its generated positions, normals, UV0 and collision match; the preservation-safe delivered GLB and `.blend` do not have those unrelated changes.
