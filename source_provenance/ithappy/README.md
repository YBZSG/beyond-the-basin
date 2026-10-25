# ithappy Creative Character — local integration provenance

User-supplied `creative_character_free.blend`, author **ithappy**, integrated locally on 2026-10-25. Source SHA-256: `6865dfe83c6a3ea95e102a2fc0dde09cd94bec19f25344fce23f3fc5b26acf56`.

The user identified this as the Fab Creative Character free model. The listing has a **NoAI** label; the exact license attached to the user's acquisition has **not been established**. This document does not grant a license, assert CC0/open-source status, or authorize redistribution. No third-party generative-AI/image processing or asset upload was used. Blender conversion and preview rendering were deterministic, local operations with auto-execution disabled (`-Y`).

## Distribution boundary

- Original `.blend` stays outside this repository.
- `assets/models/avatar/ithappy_explorer.glb` contains derived third-party mesh, animation and embedded original texture data. It is deliberately git-ignored and must be **excluded from public source archives, GitHub pushes and standalone asset distribution** pending confirmation of the actual acquisition license. Its `.import` metadata is ignored too.
- Source code, exporter and this notice may be reviewed without that asset. Runtime selection must retain the original character fallback when the optional GLB is absent.
- The old `PUBLICATION-FILES.json` is historical, not authorization to distribute this new asset. A packaging operator must explicitly exclude the third-party GLB and any generated imported/cached copies from public source distributions; do not rely on `.gitignore` for ZIP packaging.
- Any eventual private playable package including the model also requires the owner to confirm applicable license terms. Do not ship the raw source or an extractable standalone model as a paid/public asset pack.

## Conversion

Reproduce with Blender 4.3.2:

```sh
blender -b -Y /private/path/creative_character_free.blend \
  --python tools/avatar/export_ithappy.py -- \
  assets/models/avatar/ithappy_explorer.glb /private/path/outfit-preview.png
```

Selection is one coherent casual pool outfit: source body, T_Shirt_009, Shorts_003, Shoe_Slippers_002, Hairstyle_male_012 and Male_emotion_usual_001. All alternate garments, hats, gloves, props and authoring-sheet objects are removed. Modular object layout offsets are reset. Head-weighted body geometry, hair and face are separate `Head_` meshes for the existing camera visibility layers. Original packed `Textures_4.png` is embedded unchanged; no generated textures are used.

The 44 actual bones remain 44; no fake third phalanges or wrist supports are added. Rest geometry is rotated 180 degrees about Blender Z to match existing Godot -Z forward. Source Left/Right names map to runtime R/L so runtime L remains +X. Bone locals and action channels are renamed consistently; Spine1 maps to Chest. All root-location channels are zeroed because the existing CharacterBody controller owns translation. The 29 provided named actions are retained (A-pose and the unrelated unused gas-mask action are excluded). There is no source swimming action and none is synthesized by this exporter. Runtime action aliases and supplemental visual-only grip handling are separate from these source clips.

The exporter also writes an audit JSON containing selected objects, bone mapping/rest endpoints and action names. Blender previews are **asset previews, not game/GPU/playability acceptance**.

## Local asset checks (2026-10-25)

Final GLB SHA-256: `1a2f0b8982c236f8e814678dde0fdf787ea968fc91c51b17d498c8511083a21b`.

`python tools/avatar/validate_ithappy_glb.py assets/models/avatar/ithappy_explorer.glb` passes: exactly 44 joints, seven intended mesh nodes, one embedded original PNG, 29 animations, finite animation values, zero Root translation in every action, retained forward rotation for idle/walk/run, and actual nonconstant rotation tracks for idle/walk/run/jump-start/jump-loop/jump-end/climb. No assumption that an action name proves animation: an initial NLA export incorrectly contained static tracks and was replaced by per-action export with NLA disabled.

Head separation is a whole-face partition **after** subdivision is baked, preserving shared border positions and all faces. An initial vertex-deletion partition left a visible neck gap; this was corrected before the final asset. Deterministic Blender renders of the actual exported-and-reimported GLB were viewed for front idle, side idle and three-quarter walk; the final renders show the intended outfit, continuous neck, skin deformation and forward-facing orientation. These are limited asset checks, not the custom Windows NR runtime, first-person camera clearance, interaction/grip or gameplay acceptance. The render utility is `tools/avatar/render_ithappy_preview.py`; its outputs are local/private and not public source assets.

## Local adoption, 2026-10-26

The user explicitly approved using this character locally and omitted swimming because there is no deep-water area. The character is now selectable in the local playable package. This records the local integration request, not a determination of third-party license terms. No GitHub push or publication was performed. Current evidence is in the outer workspace evidence/character-switch-20261026 directory.
