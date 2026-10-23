# Pool Explorer V2: bounded anatomy candidate

This is an original editable arm/hand refinement of the existing Pool Explorer, modeled against the project's already-generated neutral explorer reference. It is a separate candidate, not an automatic runtime integration. No downloaded meshes, paid assets, external rigs, or mocap have been used.

## Files

- Runtime candidate: `assets/models/avatar_v2/pool_explorer_v2.glb`
- Editable source: `pool_explorer_v2.blend`
- Reproducible generator: `build_explorer_v2.py`
- Compressed original source seed: `pool_explorer_original_seed.blend`
- Optional existing-bone pose data: `assets/models/avatar_v2/grip_poses.json`
- Asset statistics and source-space palm measurements: `assets/models/avatar_v2/avatar_v2_manifest.json`
- CPU audit renders: `audit/renders/`
- Exported GLB comparison: `audit/glb_contract.json`
- Reopened .blend skin/topology/deformation verification: `audit/source_verification.json`

The native source retains the packed original AI-generated turnaround. The reference is not used as a runtime billboard or texture. `audit/seed_provenance.json` identifies the source captured before any changes.

## What changed

- Rebuilt bare forearms, wrists and hands as two continuous closed skin surfaces. The old disconnected wrist rim is gone.
- A tapered forearm, flattened asymmetric palm, thenar/hypothenar relief, metacarpal arch, distinct knuckles, separated thumb, and individual finger pads replace the mitten-like geometry.
- Digit vertices use their own existing two-bone chain, with controlled root/PIP blending. No vertex is weighted to two different digits.
- Small conforming nail plates replace the old floating nail ellipsoids. Subtle vertex-color variation preserves ordinary glTF PBR and the runtime material adapter's vertex-color path.
- Finger motion now curls toward the palm in each bone's native local frame, rather than using a shared global rotation axis.
- Only a restrained sleeve-fold adjustment, toe-upper taper and crossed laces were added elsewhere. No enlarged shoulder bulk, changed sole/floor contact, new collider or camera change.

## Preserved integration contract

- Exactly 42 bones. Every rest matrix, hierarchy, bone name, inverse bind matrix and bone count is unchanged.
- Exactly seven clips: Idle, Walk, Run, Hold, Wade, Swim, Climb. All exported time samples and durations are unchanged.
- All non-finger animation values are byte-identical in the GLB comparison. Locomotion, upper arms, wrists, feet, gait phase and root motion are not rewritten.
- `ExplorerRig`, `Body_Explorer` and `Head_Explorer` retain their names. Head mesh coordinates are unchanged.
- Blender +Y forward, exported Godot -Z forward, meters, feet-root origin, original 1.73 m height.
- Skins are normalized and use at most three influences per vertex.
- Source-space hand-IK contact remains at the original Hand-to-Middle1 78% anchor with 28 mm inward palm offset. The actual reduced palmar surfaces are measured in the manifest; error is under 1 mm. This is not a substitute for native carried-object contact testing.

## Supported hand poses

The seven clips contain relaxed finger curl, shallow large-object carry curl, or open swimming hands. `grip_poses.json` also contains a moderate cupped-grip target. These are local rest-relative quaternions in WXYZ order for the existing 20 finger bones; no new bones are added. Runtime code may blend these after arm IK, but this candidate does not add such code or persistent skeleton overrides.

Thumb1 root motion was isolated as the cause of a triangular web pinch, even in the first ordinary-carry trial. Supported poses now keep Thumb1 in its already-opposed rest orientation while articulating Thumb2 and the four fingers. Same-angle CPU diagnostics confirmed that this removes the carry fold. An extreme closed-fist/power-grip trial was also rejected because it pinched the thumb/index web. Its diagnostic image is explicitly marked rejected. It is not included in the pose library or clips. The moderate poses should not be mistaken for an object-specific finger collision/contact solver.

## Honest limits

This remains a modest procedural game model, not a scan-quality or photoreal character. The original face, hair and most clothing still look simple. The new hands are more anatomically legible, not a final high-end character-art pass. Two phalange bones per digit limit a full fist. GPU performance, native IK contact, actual first-person visibility, reflections and runtime import must be checked by the owner before selecting this candidate.

All images in this directory are genuine static Blender Cycles CPU renders of the saved geometry. They are not game screenshots, a replacement for runtime evidence, or performance claims. The hand audit isolates the actual left-arm geometry only to remove occlusion by the torso/trousers; it does not change the source asset.

## Reproduce and audit

From the project root:

    blender -b -t 4 --python tools/blender/avatar_v2/build_explorer_v2.py
    python tools/blender/avatar_v2/audit_glb_contract.py
    blender -b -t 4 --python tools/blender/avatar_v2/verify_source_v2.py
    blender -b -t 4 --python tools/blender/avatar_v2/render_audit.py

No command launches Godot or a GPU renderer. The generator reads its own immutable source seed after first use and writes only the two V2 directories. The audit compares against `assets/models/avatar/pool_explorer.glb`; if that baseline is later intentionally changed, select the corresponding preserved original before drawing conclusions.

## Owner integration checklist

1. Review the dorsal/palmar before-and-after audit and complete figure.
2. If selected, point a separate native fixture at this GLB; do not blindly overwrite the current shipping asset.
3. Check actual first-person look-down, relaxed arms and near/far carry contact with the unchanged hand-IK anchor. The palm is preserved, but the separated thumb and new curl can change fingertip clearance.
4. Verify vertex colors through the existing avatar material adapter, head culling/reflections, surface count and draw cost.
5. Keep the new GLB/source/hash evidence together. Do not label old runtime captures as V2 captures.

## Final bounded budget

The frozen candidate has 49,653 total triangles (40,179 body + 9,474 unchanged head), versus 44,477 in the original (+11.6%). The body remains at 11 runtime surfaces; nail color shares the skin surface rather than adding a draw. There are no new texture maps. The source has 42 unchanged rest bones, seven clips and at most three influences per vertex. These are asset counts, not measured runtime performance.

Frozen GLB SHA-256: `cf30e23b692db289228921f1c128a3c7cd79022c53f98c4962ea05d2caa25f17`

Final labeled comparisons: `audit/hand_before_after.png` and `audit/supported_hand_poses.png`. `audit/render_manifest.json` binds final renders to this exact GLB and .blend; diagnostic/rejected trials are excluded.
