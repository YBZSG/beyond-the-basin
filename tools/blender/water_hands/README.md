# Explorer water-hand rig pass

This is an edit of the existing PoolCore explorer, not a new character. Inputs were the existing 42-bone V2 source, the current avatar_finish_candidate.glb, and the user's two 2026-10-23 hand screenshots (egg support and downward body view).

## Deliverables

- `pool_explorer_water_hands.blend`: editable FULL explorer, original rig/actions plus the appended hand joints, current full body/head meshes, original cloth UV channels/material names.
- `../../../assets/water_hands/pool_explorer_water_hands.glb`: exact current GLB container with only bare-arm/hand primitive replaced and 12 deform joints appended.
- `../../../assets/water_hands/hand_pose_contract.json`: measured palm anchors, hand axes, added bone names, and source-local neutral/relaxed/carry/release/swim quaternion poses.
- `build_water_hands.py`: reproducible CPU-only geometry, weights, full-source and surgical GLB assembly.
- `audit_water_hands.py`, `validation.json`, `posed_skin_audit.json`, `posed_skin_audit_R.json`: numerical validation and bounded CPU close-ups.

## Geometry and skin changes

Removed the separate inflated thenar/hypothenar/contact spheres and replaced them with one flatter asymmetrical palm loft. Finger widths taper continuously, short nails follow the actual distal surface, and the thumb retains a continuous web rather than a knuckle-like blob. The proximal palm follows the actual forearm axis, which differs from the hand axis by about 11 degrees; extending the hand axis into the forearm created an unwanted cuff-shaped ledge and was corrected.

Weights use four or fewer normalized influences. Connected web/MCP regions receive four bounded smoothing passes; disconnected finger gaps are never bridged. Each added distal bone and wrist support has real deform weights. This pass does not claim photoreal anatomy or full closed-fist support.

## Skeleton contract

Original 42 GLB node identities, skin-joint order, rest transforms, parent relationships and inverse binds are preserved. Original seven animation descriptors and buffers are unchanged. Code should continue resolving bone names rather than depending on engine-imported array order.

Added for each L/R side: Index3, Middle3, Ring3, Little3, Thumb3, WristSupport (54 total).

- Each `*3` is a child of its existing `*2`. Non-thumb heads lie at 55% of the existing segment; Thumb3 lies at 62%. The existing *2 head/tail/orientation is not edited. New distal rest orientation equals the parent segment.
- `WristSupport_L/R` is a child of Forearm and has exactly the Hand rest transform. It must receive half the Hand rest-relative rotation after animation and after runtime IK. It is NOT driven by an exported constraint.
- In Godot, use delta = inverse(hand_rest_rotation) * hand_pose_rotation; support_pose_rotation = support_rest_rotation * slerp(identity, delta, 0.5). Do not slerp the full local Hand rotation from identity.
- Measured palm depth at wrist→Middle1 78%: L 0.01870815 m, R 0.01871444 m. Use approximately 0.018711 m, not the previous 0.028 m. The complete raycast points are in the pose JSON.

## Preservation and numerical verification

All 17 unaffected body/head material primitives retain exact original index and attribute arrays. This includes clothing positions, normals, UV0, metric UV2, tangents, original weights/joints, and material descriptors. The revised GLB keeps the original binary data and appends only necessary replacement buffers.

Final arm/hand skin: 14,041 vertices, 27,894 triangles, at most four influences, maximum normalized-weight error 1.19e-7. Added distal bones influence approximately 196–335 exported vertices each, and wrist supports influence 1,096 / 1,109.

Both hands were numerically evaluated in neutral, relaxed, carry, release and swim poses. The left carry edge ratio p01/p99 is 0.924/1.074, and its absolute extreme is 0.790–1.382. The right hand has separate decimation topology and slightly larger isolated extremes; consult the right-hand JSON rather than assuming perfect numerical symmetry. All poses remain finite with no collapsed edges under the audited bounds. At 70-degree wrist flex, the cross-sectional covariance-area proxy retains 97.76% left / 97.82% right when the helper is driven, versus 91.65% left when left inert. This is a geometric proxy, not a measured volume or gameplay contact guarantee.

## Reproduction

From repository root:

    blender -b -t 2 --python tools/blender/water_hands/build_water_hands.py
    blender -b -t 2 --python tools/blender/water_hands/audit_water_hands.py
    HAND_AUDIT_SIDE=R HAND_AUDIT_RENDER=0 blender -b -t 2 --python tools/blender/water_hands/audit_water_hands.py

The first command reconstructs the source and hand GLB. The second produces left-hand numerical inspection and seven 340×440 CPU-only isolated close-ups. The third produces the independent right-hand numerical audit without rendering. No old source files are modified. No GPU scene or Android build was run.

## Acceptance limits

The motion-authoring tools consume this source and GLB, appending authored movement clips without re-exporting mesh data. Native engine checks must still verify held-object support, wrist bending, finger transitions, hand/clothing occlusion, swimming, release and the measured palm offset after runtime IK. CPU studio images are diagnostics only, not evidence that the actual gameplay issues are resolved.

## Finger-only runtime helper

`scripts/player/avatar_finger_poses.gd` was added as a disjoint integration helper. It never writes Hand, WristSupport, forearm or arm bones and rejects the old 42-bone rig. Call setup(skeleton) once, then apply(delta, held_body, hand_ik_contact_weight, action_state) after authored motion and grip IK, before WristSupport. Recommended state keys are state (Idle/Walk/Run/Wade/Swim/etc.), throw_release_age (seconds, default 99), and authored_fingers (whether new authored clips are active). The returned dictionary is telemetry.

Original dry Idle/Walk/Run use the calibrated relaxed pose. With a held object, contact weight blends into differentiated MCP/PIP/DIP carry rotations. Radius adaptation is limited to 0.82–1.12; thumb gain varies less. Authored no-hold swimming, wading, jumping and throw release pass through. The existing runtime throw-release interpolation is respected rather than double-smoothed. Ordinary drop has a 0.14-second bridge; regrab cancels it. Zero-delta calls do not advance an internal clock.

`test_finger_poses.gd` loads the actual final authored .scn. Wade, Swim and ThrowCharge tracks verify the local quaternion convention for all 30 finger joints: full Godot pose = rest rotation * JSON local delta. The only representation change is WXYZ to XYZW storage order; do not swap local Y/Z axes. Tests cover original-rig rejection, untouched non-finger bones, authored passthrough, 30/60/120 FPS, radius bounds, zero delta, ordinary drop and interrupted regrab. Results are in `finger_helper_validation.json`.

Headless tests need writable Godot data/cache paths in restricted execution environments:

    HOME="$PWD/tools/blender/water_hands/test_home" XDG_CACHE_HOME="$PWD/tools/blender/water_hands/test_home/cache" XDG_DATA_HOME="$PWD/tools/blender/water_hands/test_home/data" godot --headless --path . --script tools/blender/water_hands/test_finger_poses.gd

Exact measured palm anchors in Godot skeleton-rest coordinates:

- L: (0.3999798596, 0.8840587139, -0.0275000371)
- R: (-0.3999740481, 0.8840563893, -0.0275005903)

Equivalent Hand-local points from the actual imported skeleton:

- L: (-0.0209279060, 0.0671776533, 0.0010641515)
- R: (0.0209339261, 0.0671775341, 0.0010622740)

Round-trip anchor error is below 1.1e-7 m. Existing rest bone positions are unchanged. GLB node/skin-joint indices are preserved, but Blender's internal bone collection indices shift as it traverses the new child bones; resolve by name.
