# Original rigged Pool Explorer

An original procedurally modeled adult explorer, made against the included AI-generated front/side/back reference sheet. This is a modest game-ready interpretation with realistic human proportions, not a scan-quality or photoreal character.

## Deliverables

- `pool_explorer.glb`: self-contained skinned runtime asset, meters, +Y up and −Z forward in Godot.
- `explorer_reference_ai.png`: AI-generated modeling reference, not used as an in-game billboard or texture.
- `avatar_manifest.json`: geometry, skeleton, weight and clip statistics.
- `avatar_source_verification.json`: actual `.blend` reopen and animation-deformation checks.
- Editable Blender source: `tools/blender/avatar/pool_explorer.blend`.
- Reproducible generator: `tools/blender/avatar/build_explorer.py` (Blender 4.3.2).

All geometry, rigging, materials and animation were created for this project. No downloaded character meshes, external character rigs, motion-capture files, branded clothing or paid assets are included. The original reference image was produced with built-in image generation.

## Skeleton and animation

42 bones in one connected hierarchy rooted at `Root`; central `Hips`, `Spine`, `Chest`, `Neck`, `Head` chain, clavicles, arms, hands with finger bones, legs, feet and toes. Individual limb chains are connected at their joints; hip and finger branches retain conventional anatomical offsets. Every runtime mesh vertex is skinned and normalized. Maximum four exported influences per vertex.

Seven in-place skeletal clips: `Idle`, `Walk`, `Run`, `Hold`, `Wade`, `Swim`, `Climb`. Walk/run/wade use authored analytic two-bone leg placement to keep the stance foot near the floor. This is not terrain-aware runtime foot IK or a motion-captured gait. Swimming and climbing are presentation states only; the existing controller owns all movement and water behavior. No new collider or physics body is included.

## First-person integration

`PoolAvatar` in `scripts/player/pool_avatar.gd` is a visual-only child of the existing feet-root `CharacterBody3D`:

1. Instantiate the script and attach it to the player.
2. Call `setup(player)`; the `ViewCamera` is discovered automatically.
3. `set_first_person_camera(camera)` can override the discovered camera.
4. `get_debug_state()` reports loaded clips, skeleton, animation blends and head/shadow configuration.

The mesh remains feet-centered in the asset. A 0.13 m +Z visual offset aligns the torso behind the unchanged 1.6 m first-person eye, without changing camera position, player collision, movement or yaw. The character inherits player yaw, not camera pitch. Look-down tests must verify the actual lower-body view rather than merely a hidden head.

Body geometry uses reserved render layer 17 (`1 << 16`, 65536), not the static environment layer 1. `Head_Explorer` (face, neck, ears, eyes and hair) uses reserved layer 18 (`1 << 17`, 131072), excluded from the main camera. Planar reflection cameras must include both layers 17 and 18 to show the complete character; a static room cubemap using mask 1 excludes avatar geometry. A separate shadow-only instance shares the exact same head mesh, skin and skeleton on layer 17; the reflection-visible head has shadow casting disabled to avoid duplicate head shadows. Main-camera head clipping therefore does not remove the head's world shadow.

The controller reads planar velocity and existing `held`, `climbing`, `_in_water` and `_swimming` states. It blends idle/walk/run continuously, filters the Hold pose onto upper-body tracks, and transitions smoothly into water/climbing presentation. It never duplicates native movement or collision.

## Checks and limitations

- `tests/avatar_runtime_contract.gd`: blended bone motion, hold filtering, visibility layers, shared shadow skin, unchanged controller/camera/capsule.
- `tests/avatar_runtime_asset.gd`: imported skin weights, dimensions, skeleton, clips, animation extremes and stance-foot behavior.
- `tests/avatar_runtime_projection.gd`: CPU-skinned triangle occlusion checks at 4:3 and 16:9, demonstrating actual leg/foot visibility without moving the camera.
- `tests/avatar_runtime_visual.gd`: native visual fixture for full-body poses and actual look-down views.
- Blender preview images are CPU studio renders, not gameplay screenshots.
- Native fixture evidence records its renderer explicitly. The first visual run used Godot Compatibility on Mesa llvmpipe (software rasterization), so it is not a hardware-GPU performance result.

The face and clothing are intentionally simple procedural assets. Shoulder deformation, grasp contact, advanced locomotion and terrain-aware IK remain areas for a future artist pass; current movement/collision behavior is deliberately preserved.

## Final proportion checkpoint and evidence

The final bounded refinement narrows the shirt chest, shoulder bridge and upper sleeves, while preserving the continuous armhole surface. Palm and finger geometry and matching hand/finger rest bones are 12% larger. The skeleton names, hierarchy, clip names and first-person offset are unchanged.

Godot can preserve PNGs previously extracted from a GLB. The generator therefore synchronizes `pool_explorer_explorer_shirt_weave.png` and `pool_explorer_explorer_pants_weave.png` to the embedded, low-contrast generated fabric images. Keep these PNGs beside the GLB when replacing an older version.

`tools/blender/avatar/avatar_evidence_versions.json` records exact GLB and source hashes. Native fixture captures in `tools/blender/avatar/qa_project/captures/` depict the preceding, corrected first-person fit version, not this final proportion refinement. Their visual evidence remains useful for the 0.13 m camera fit and head/shadow presentation, but does not prove the later layer-17 isolation or avatar mirror-clip shader. Final appearance must be judged from its own CPU previews or the subsequent full-game run. Both native fixture runs used software llvmpipe; no hardware-accelerated performance claim is made.

## Planar water and static probe integration

`shaders/avatar_body.gdshader` wraps the imported material surfaces at runtime, retaining their PBR colors, textures and scalar properties. It clips fragments below world Y 0.318 only for cameras with reserved reflection marker 524288. This matches the source architecture's planar reflection convention. The main camera explicitly excludes both head layer 18 and the mirror marker, and includes body layer 17, so submerged legs remain visible normally. The shadow-only head uses the same pose and render layer 17. The source GLB remains a portable standard-material asset; the Godot adapter supplies this project-specific shader.

Camera mask checks demonstrate geometry eligibility, not a native proof of reflection pixels or shadow behavior inside every probe. Object-specific grasp/contact IK, environment-aware hand placement while climbing and terrain-aware foot IK are not provided. The existing controller remains the sole authority for collisions and movement.
