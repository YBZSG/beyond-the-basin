# Anatomical hand provenance

The active `hanging_hand_original.obj` is **not wholly original geometry**. Its
legacy filename is retained for scene compatibility. It derives from:

- Asset: **Hand  - Realistic** (the two spaces occur in the official object name)
- Author: **Dan Ulrich**
- License: **CC0 / public domain**
- Distributor: Blender Studio and Blender community, **Human Base Meshes v1.4.1**
- Official listing: https://www.blender.org/download/demo-files/ (Human Base Meshes card: “49 MB – CC0”)
- Official download: https://mirror.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip
- Retrieved: 2026-10-27 UTC

Evidence: the selected object's asset metadata says author `Dan Ulrich`, license
`CC0`, description `Realistic scan data model with multiresolution details`.
The bundle README says `All provided assets are public domain under the CC0 license.`
A separate unused text datablock in the full bundle mentions the Rain Rig's CC-BY
license; no Rain Rig object, material, rig, or data is included in this extraction.
The chosen hand's explicit per-asset license and bundle README are both CC0.

`tools/late_references/source/anatomical_hand_cc0_base.blend` is a data-only extraction of this hand with its
entire original multiresolution stack applied (the official asset has one multiresolution level: 831 base vertices become 3,300). `docs/late_references/superseded_hand_pose_a/hand_anatomy/multires-preservation-audit.json` verifies the extracted coordinates exactly equal the official evaluated multiresolution result; no authored scan deformation was discarded. The external bundle was loaded using
`--disable-autoexec`; no embedded scripts were run. The full bundle is not shipped. The source-base directory has `.gdignore` so Godot does not accidentally import the reference hand as a game scene.

Current C4 changes: monumental compact suspended pose, source-landmark rigid
phalanges with normalized dual-quaternion joint transitions, a short rounded
rearward wrist termination, retained geometric nail folds/dorsal joint creases,
surface subdivision, outward normals, and OBJ export. No new ridge/noise pass was
added during the C4 correction. Generator:
`tools/late_references/sculpt_hand.py`.

Neutral source/posed orthographic studies and editable posed Blender file are in
`docs/dreamcore_annex/hand_pose_c4/` (current C4),
`docs/dreamcore_annex/hand_pose_b/` (retained roof-connected B baseline) and `docs/late_references/superseded_hand_pose_a/hand_anatomy/` (historical A/source study). Anatomy review deliberately uses plain clay,
not stone textures, cinematic shadows, or camera tricks.

## Acquisition hashes
- Official ZIP SHA-256: `811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515`
- Clean extracted base SHA-256: `feb101e877d9cbf266f68b0bc6055ccf2cdd0e5f1d11c578146a1d36a274b306`

The three initially added straight palm grooves were rejected during neutral anatomy review and removed. The final palm retains the source anatomical volumes without schematic carved lines.

Current active generator is `tools/late_references/sculpt_hand.py` for compact C4.
C4 removes the invented roof-connected forearm constraint: the reference and user
request did not require it. The sculpture is deliberately suspended; no physical
roof attachment is claimed. Source-scan MCP/PIP/DIP/tip centers and preserved bone
lengths are recorded in `docs/dreamcore_annex/hand_pose_c4/source-landmark-rig.json`.
The fixed lowest-fingertip anchor is inherited from B; nominal min world Y remains
0.68m. Existing limestone maps, triplanar mapping, all lighting/ambient/exposure,
room geometry and shared player/water code are unchanged.

Roof-connected B evidence remains under `docs/dreamcore_annex/hand_pose_b/`, and
pose A ce163f20 under `docs/late_references/superseded_hand_pose_a/`. Neither is the
active C4 mesh. Existing limestone provenance remains in
`HANGING_HAND_STONE_PROVENANCE.json`. Root accepted the C4 direction for scoped
integration; final user visual acceptance and native GPU appearance/performance
are not implied by the source/CPU proofs.
