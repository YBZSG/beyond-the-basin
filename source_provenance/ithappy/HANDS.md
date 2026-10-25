# Local deterministic hand adapter

The original `avatar_hand_ik.gd`, `avatar_finger_poses.gd`, and original 54-joint pose contract are unchanged. The separate ithappy profile requires the exact 44-name parent map, finite unit-scale rest transforms, two phalanges per finger, valid lengths, and no WristSupport/third phalanges. Mismatches are rejected.

The shared arm solver is visual only; its new subclass has separate palm anchors and contact-plane tangent. Nothing here changes controller, object physics, throws, camera, water, RT or NR.

## Source mesh measurement

Local Blender BVH raycasts against the actual uploaded rest body, starting at 68% of wrist-to-Middle1 and directed toward the palm interior-facing surface:

- Runtime Hand_L (source RightHand): local contact `(-0.0194578264, 0.0762481764, 0.0029789258)` m.
- Runtime Hand_R (source LeftHand): local contact `(+0.0194578264, 0.0762481764, 0.0029789258)` m.
- Both ray distances: `0.0289871674` m. Wrist-to-Middle1: approximately `0.107675` m.
- Ray normals in respective hand-local frames: `(−/+0.9914919, 0.1280602, −0.0233388)`.

The contact frame and finger bend axes derive from each imported rest skeleton's wrist, knuckles and palm plane, not copied bone-local axes from the original avatar. The new-rig contact tangent tilts fingers upward (`forward + 0.8 * up`) to reduce excessive wrist bending in near carry. Twenty finger channels alone receive conservative carry curls; release decays back to authored animation. No missing distal joints are invented.

Three runtime-generated `ThrowCharge`, `ThrowRelease`, `ThrowRecover` clips are deterministic six-track two-arm poses calculated from actual limb lengths/rest frames. They are **not** supplied motion capture or source-authored animations. Recovery samples the imported idle pose. Actual release timing and force remain the existing player's responsibility. No swimming animation is introduced.

## Evidence and limits

`tests/ithappy_hand_contract.gd` loads the actual exported GLB. Isolated Godot 4.6.3 headless test passes: exact rig contract; finite rotations; 20 finger channels with protected bones unchanged; mirrored curl signs; reachable ball/egg/duck anchor targeting; far-target release without bone stretching; contact clearing/drop; three finite six-track throw clips; rejection of a corrupted finger parent. Log: `output/ithappy/hand-contract.log`.

At the test's near-carry location, geometric anchor error is below one micrometre and wrist bend approximately 45.4 degrees. This verifies **bone-anchor math only**, not skinned surface clearance, complete finger contact, animation attractiveness, or native GPU rendering. Native first-person and reflected third-person review of all three prop types remains required.
