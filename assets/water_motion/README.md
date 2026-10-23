# Explorer water and action motion

An animation-only revision of the current Explorer character, not a replacement character. The final runtime asset uses the compatible 54-bone hand revision. All original 42 bone names and rest transforms remain. The new fingers and wrist-support joints are authored as part of the same motion.

## Assets and provenance

- `explorer_water_motion.scn`: compressed, self-contained Godot PackedScene for runtime. Includes mesh, skin, materials, textures, and animation library. Does not depend on editor-generated `.import` files.
- `explorer_water_motion.glb`: editable interchange asset. The entire source GLB binary prefix and mesh/skin/material/UV0/UV2/tangent JSON records are unchanged. Only animation records and new accessor arrays are appended.
- `../../tools/blender/water_motion/explorer_water_motion.blend`: full editable rig, exact hand-revision mesh, preserved actions and nine new/replaced actions. It is not the earlier cloth-only UV editing file.
- `motion_validation.json`: per-clip CPU sampled geometry, exact preserved-action hashes, loop seams, IK reach/sole measurements, source/output hashes.
- `runtime_scene_validation.json`: native Godot import/reload, 54-bone inventory, animation tracks, clothing UV2/tangents and dependency checks.
- `../../tools/blender/water_motion/saved_source_validation.json`: independent reopen proof that saved mesh, UV, skin, materials, rest rig and five preserved action curves are exact, with 14 editable actions and RELEASE marker at frame 0.
- `pose_sheet.png`: CPU skeletal phase diagnostic only. It is not a mesh render, live gameplay capture, or proof of visual quality in the game.

The upstream full mesh/rig is `assets/water_hands/pool_explorer_water_hands.glb` and `tools/blender/water_hands/pool_explorer_water_hands.blend`. Hand poses are calibrated by `assets/water_hands/hand_pose_contract.json`. Their geometry/weight audit is separate from this animation audit.

## Animation contract

All authored keys are 120 Hz, frame zero origin, LINEAR interpolation. Blender is +Y forward/Z up; Godot/glTF is −Z forward/Y up. The Root bone is never translated. The controller exclusively owns player movement, jump trajectory, collision and physics launch. Hips translations are bounded visual articulation, not root-motion travel.

| Clip | Length | Loop | Contract |
| --- | ---: | :---: | --- |
| Wade | 1.40 s | Yes | 1.05 m full left/right gait, left front contact at phase 0, right phase +0.5, 62% stance, raised knee recovery and restrained arm sweep |
| Swim | 2.40 s | Yes | Calm coordinated outsweep/insweep/recovery/glide; synchronized frog kick; authored horizontal Hips pitch, no second runtime pitch |
| SwimIdle | 2.20 s | Yes | Upright scull with alternating tread and quiet torso bob |
| JumpRise | 0.25 s | No | Planted start, lift into airborne leg/arm readiness; no player trajectory |
| JumpAir | 0.60 s | Yes | Slightly asymmetric airborne tuck and restrained arm balance |
| Land | 0.30 s | No | Both soles supported; knee/hip compression and recovery |
| ThrowCharge | 0.45 s | No | Two-hand chest readiness; upper-body only; runtime contact IK remains authoritative while held |
| ThrowRelease | 0.25 s | No | RELEASE marker at **0.000 s**; immediate controller launch, opening fingers and forward extension/follow-through |
| ThrowRecover | 0.35 s | No | Upper-body recovery to natural relaxed fingers |

Idle, Walk, Run, Hold and Climb source action curves and GLB animation records are preserved exactly. No throw clip contains Root, Hips, leg, foot or toe tracks. New hand poses use distinct MCP/PIP/DIP flex, bounded thumb opposition, and 50% wrist-support delta. Runtime may recompute support after hand IK.

## Swimming visual placement

The capsule and camera stay upright. Swim authors its own forward body pitch. At the authored root, the Head bone is approximately Y 1.086–1.153 and Z −0.593…−0.569 in Godot. With a gameplay root at water−1.48 and the existing model Z+0.13 offset, initial body-only corrections of about +0.40 m Y and +0.45 m Z bring the head near the unchanged camera/waterline. Blend those offsets with Swim weight, not SwimIdle weight. Native runtime QA must verify final head/face placement and camera clearance; the values are not camera-motion instructions.

## Reproduction

From the project root, with Blender 4.3.2 and Python/numpy:

```sh
python tools/blender/water_motion/run_bounded.py
```

The bounded driver is CPU-only, two threads, no render; it terminates above 1.2 GB RSS or 180 seconds. It overwrites only this feature's outputs. `--draft --no-save` samples without producing the GLB/.blend.

Godot 4.6.3 import must use the tiny isolated project, not an editor-wide scan of shared game assets. Set writable XDG data/cache locations and disable core dumps on restrictive execution hosts:

```sh
ulimit -c 0
XDG_DATA_HOME=/tmp/water-motion-godot-data \
XDG_CONFIG_HOME=/tmp/water-motion-godot-config \
XDG_CACHE_HOME=/tmp/water-motion-godot-cache \
godot --headless \
  --path tools/blender/water_motion/import_workspace \
  --script ../build_runtime_scene.gd -- \
  "$PWD/assets/water_motion/explorer_water_motion.glb" \
  "$PWD/assets/water_motion/explorer_water_motion.scn" \
  "$PWD/assets/water_motion/runtime_scene_validation.json"
```

The importer embeds textures, verifies the clothing metre-UV contract and every expected clip, writes the compressed PackedScene, and reloads/instantiates it. No texture files or editor `.import` copies are generated. The Blender file is beneath the existing `.gdignore` authoring directory.

## Limits

The sampled geometry checks validate finite, consistent bone lengths and bounded contact/reach. They do not prove runtime IK ordering, camera occlusion, capsule behavior, or final artistic quality. Those require the separate native controller and visual acceptance tests. Android uses the preserved old model and is not part of this upgrade.

## Swim pole regression correction

The initial fixed elbow pole approached the shoulder-to-wrist axis near phase 0.42 and caused a rapid arm-plane roll. The final Swim uses an outward/downward anatomical pole. The new exporter rejects any Swim bone step over 4 degrees per 120 Hz sample. Final authored maximum is 3.1953 degrees; the separate production live test measured 8.83 degrees maximum per 60 Hz tick during steady swimming. Stop-to-tread transition blending is a separate runtime acceptance case.

## Bounded foot-clearance acceptance

`scripts/player/avatar_foot_clearance.gd` is a separate visual-only helper. Final actual-route CPU checks at 15/30/60 Hz and the exact packed native fixture passed within the bounded scope recorded in RELEASE-ACCEPTANCE.json. It is not the old rejected terrain IK implementation. It changes only UpperLeg, LowerLeg and Foot rotations on each side, using exact original chain lengths and the currently authored knee pole. It restores the authored foot orientation and never writes the pelvis, root, camera, collider, translations, scales or persistent overrides.

The helper skins 304 actual sole vertices per foot, caches their bone-world transforms, and queries five static architecture rays per foot. It accepts only one coherent plane up to 30 degrees; flat planes under 2 degrees deliberately preserve the authored pose. A current grounded controller floor-normal hint skips all rays and skin work on known flat ground when no correction remains. Only the minimum upward displacement is requested (1 mm swing / 3 mm support clearance), bounded at 16 cm. It does not lock feet, move the body, stretch legs, or follow the floor while airborne/swimming. Steps, ledges and discontinuous planes intentionally reject rather than guessing a highest surface.

Release is relative to the newly evaluated authored pose. It exactly integrates a 1.2 m/s maximum release speed with an 18/s exponential finish, using finite frame times up to 100 ms; no stale world-space foot target survives. Grounded flat hints release an existing correction before the fast no-op path resumes.

`tests/water_motion/foot_clearance_contract.gd` and `foot_clearance_validation.json` cover:

- 480 samples on an actual static 21.14-degree ramp: worst skinned sole clearance −138.4 mm before / +1.0 mm after, maximum chain-length error below 0.6 micrometres, no caps or failed solves.
- 168 fresh flat samples: exactly unchanged bone quaternions.
- Previously ramp-corrected state to known-flat stopped state, JumpRise/JumpAir and Swim: all 608 skinned sole vertices return to the fresh source pose, with no retained extra lift, horizontal displacement or floor query during release. The known-flat stopped test exercises state release, not a traversed ramp/flat geometric boundary.
- 15/30/60/120 Hz release: identical full-skin endpoints at 0.2, 0.4, 0.6, 0.8 and 1.0 seconds, with zero extra lift by 0.6 seconds.
- Helper-only software CPU microcost: about 0.4 ms median on the tested ramp, 0.002 ms on the known-flat fast path. This is not a target-PC frame-rate claim.

Production integration, support-boundary behavior and visual acceptance remain separate checks. This is not general terrain, stair or foot-locking support.

Final acceptance retains the >30-degree connector, incoherent seam and early swim-to-wade foot-correction limits. This is not Windows or full-world acceptance. No production or binary asset bytes were changed for this documentation clarification.
