# Credits and asset provenance

- Original project: YBZSG/beyond-the-basin, https://github.com/YBZSG/beyond-the-basin . The owner's existing project license is not replaced by this handoff.
- Native scripts and shader translations are project-specific migration work. This delivery does not impose an unrelated open-source license on the owner's work.
- Four Quiet Wing GLBs are original project-authored geometry, copied unchanged from the V4.1 model handoff. No POOLS model, texture, audio or other game asset was copied.
- Ceramic scans: Poly Haven, `rounded_square_tiled_wall`, CC0. The original 2K diffuse, OpenGL normal and roughness files are included unchanged. See `assets/textures/NOTICE.md`, https://polyhaven.com/a/rounded_square_tiled_wall and https://polyhaven.com/license .
- Seventeen OGG clips are copied unchanged from the user's source project. This handoff does not assert ownership or a new redistribution license for user-supplied recordings.
- Godot Engine 4.6.3, MIT. See `docs/licenses/GODOT_LICENSE.txt`, `docs/licenses/GODOT_THIRD_PARTY_COPYRIGHT.txt` and https://godotengine.org/license/ . These engine and third-party notices are retained for the Godot project and do not relicense the project's own code or assets. This source-only branch does not redistribute the Godot editor, export templates, Windows EXE/PCK or Android APK. No private signing key or keystore is included.
- The interface uses system fonts (Noto Sans CJK / Microsoft YaHei / fallback), not a redistributed proprietary font.

## Current source-water / formal-scene edition

- `assets/models/formal/*.glb` and `tools/blender/source/*.blend` are new project-authored Blender geometry, with regeneration scripts, not POOLS assets.
- The original water-optics generator input and third-party notices are preserved in `source_provenance/`; the full original Web application is not part of this branch. See `source_provenance/README.md`, `docs/SOURCE_LIQUID_LICENSES.md` and `docs/audit/source-caustics-third-party-license.txt`.
- This Git branch contains the editable Godot project, not exported EXE/PCK/APK downloads. Existing native platform helper libraries remain included with their source and notices. Current validation limits are recorded in the root README; Android work is paused. No private signing key is included.

## Windows 0.6.13 (2026-10-26)

- The Windows installer bundles the patched NVIDIA Godot 4.8-dev engine at upstream commit `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, with the patches in `tools/dlss/`. The bundled Godot, Streamline and NVIDIA SDK notices retain their original terms; they are not relicensed by this project.
- Optional ithappy Creative Character was supplied by the user. Its original mesh/texture files are excluded from public Git source; the playable installation incorporates the derived model in game resources. Attribution and provenance are in `source_provenance/ithappy/`. This notice grants no separate rights to extract or redistribute the character.
- The source repository contains no player profiles, signing keys, proprietary SDK headers, compiled Godot editor or NVIDIA runtime DLLs. The separately published Windows installer includes the required runtime files and corresponding notices.
