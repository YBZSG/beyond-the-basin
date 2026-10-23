# Optional explorer cloth finish candidate

This is an original, optional dry-cloth material candidate for the Pool Explorer V2. It does not replace the frozen V2 and is not a photoreal-character claim. The owner has wired an opt-in `--avatar-fabric-finish` path; full native bath validation is in progress as of 2026-10-22 21:17 UTC, not yet a gameplay acceptance claim. No purchased/downloaded textures, AI image edits, external models, new geometry, new skin weights or animation changes were used.

## Why a separate GLB was necessary

The original shirt and trousers use one oblique planar UV projection. Area-weighted analysis found more than 3:1 UV anisotropy on 18.47% of the shirt and 22.63% of the trousers. Simply putting a woven normal map on those UVs produces stretched fabric, especially along the sides.

`assets/textures/avatar_finish/avatar_finish_candidate.glb` therefore adds **cloth-only metre-space UV2 and tangents**, with the required seam vertex splits. It keeps the original UV0/albedo intact. The frozen GLB's complete original binary payload is retained as an exact prefix. Every original triangle-corner position, normal, color, UV0, joint and weight value is copied exactly. Non-cloth primitives, materials, skeleton/rest hierarchy, 42 bones and all seven animation samples are unchanged. There are **no new triangles or material surfaces**; the cloth has 1,237 additional seam vertices.

The main garment charts follow front/back side seams, shoulder/sleeve boundaries, trouser rise/inseams, and separate hem/neck/ankle caps. Existing disconnected collars, pockets and belt loops get separate charts. This is a bounded improvement on a procedural garment, not a production costume-pattern unwrap.

## Material scale and appearance

Each UV2 unit represents one metre at the existing unit-scale rig. Future uniform avatar scale changes must scale the texture repeat equally to retain physical yarn pitch; nonuniform scaling requires new validation. Each chart is area-normalized separately; grain is oriented along the panel's height. No atlas packing is allowed to rescale charts.

- Shirt: 32 yarns per 22.4 mm tile, nominal 0.70 mm pitch. Area-weighted 5th/median/95th pitch is approximately 0.642 / 0.701 / 0.765 mm in U, and 0.645 / 0.701 / 0.775 mm in V.
- Trousers: 32 yarns per 25.6 mm tile, nominal 0.80 mm pitch. Corresponding U pitch is approximately 0.747 / 0.800 / 0.882 mm, and V pitch is 0.749 / 0.800 / 0.880 mm.
- The new >3:1 anisotropy fraction is 0.00036% of shirt area and zero of trouser area. No UV-degenerate triangles remain. The very small remaining shirt outlier is not represented as a perfect unwrap.
- Original analytic plain weave / subtle twill: roughly 10 micrometres peak-to-valley relief, average normal tilt 1.4 degrees, maximum about 3.1 degrees. There is no geometry displacement.
- Absolute perceptual roughness is approximately 0.847–0.878 for shirt and 0.890–0.918 for trousers. Shirt specular is 0.30; trousers retain the original standard dielectric 0.50. The initial 0.28 trouser setting was rejected by native A/B because it darkened the leg regions by about 15/255 and obscured their form. No emission, custom light function, rim trick, clearcoat or unlit shine is introduced.

Both PNG normal maps use OpenGL tangent +X,+Y,+Z. The generator measures derivatives in metres and explicitly converts downward PNG rows to upward tangent +V. Blender's normal-map data is Non-Color. The append exporter follows Blender's glTF convention: V is flipped, tangent handedness is not. Tangents are calculated by Blender's MikkTSpace implementation and orthogonalized to the exact frozen normals because Blender internally quantizes custom normals. Maximum tangent/normal dot error is below 5e-8.

Normal and roughness textures are **linear data**, never sRGB color. Explicit import settings retain mipmaps, disable green inversion and use lossless data compression. The spatial shader uses `hint_normal` for normal textures and no `source_color` annotation for roughness. UV0 albedo retains its existing color handling. Four 512-square maps have a conservative RGBA8-plus-mips upper bound of 5.33 MiB, excluding renderer overhead; this is a resource estimate, not a measured VRAM/FPS claim.

## Files and editable sources

- `generate_avatar_finish.py`: original deterministic periodic height/roughness formulas; all tile size, pitch, relief and roughness parameters are editable here.
- `build_avatar_finish_candidate.py`: CPU-only seam selection, angle-based UV unwrap, per-chart metre normalization, tangent calculation and append-only GLB construction. It never renders or re-exports a rig.
- `avatar_finish_candidate_uv_source.blend`: editable cloth-only UV source, in the original GLB's Y-up metre coordinate system. It includes packed original albedo and new data maps with editable PBR nodes. It is deliberately **not** a replacement full-character rig source; the authoritative full rig remains the existing frozen V2.
- `export_edited_avatar_finish_uv.py`: after editing only `FabricMeters` in that Blend, exports `audit/avatar_finish_candidate_edited.glb`. Geometry, topology and object-transform edits are rejected; original normals, UV0, skins and clips are always copied from the frozen source. This does not overwrite the reviewed candidate.
- `audit/*height16.png`: high-bit-depth source-height diagnostics, not runtime assets.
- `audit/*vertex_provenance.npz`: explicit new-to-old vertex mapping.
- `audit/avatar_finish_candidate_uv_build.json`: original and new area-weighted UV metrics.
- `audit/avatar_finish_candidate_contract.json`: canonical GLB/data-map proof.
- `verify_avatar_finish_evidence.py`: CPU-only hash binding of the current API, shaders, maps and GLB to the latest completed native run; it reports any post-test drift instead of treating old screenshots as current proof.
- `audit/avatar_finish_candidate_reproducibility.json`: the repeated build reproduced UVs exactly; Mikk tangent floats differed by at most 1.8e-7. Accordingly, UV generation is numerically reproducible but the GLB is not promised byte-identical across Blender runs. Keep the final artifact's actual SHA with its evidence.

## Editable source and material portability

- **Map generation:** `tools/blender/avatar_finish/generate_avatar_finish.py`
  is the editable analytic source. It writes the four normal/roughness PNGs in
  `assets/textures/avatar_finish/`. The Blend does not regenerate these formulas.
- **Blender authoring file:**
  `tools/blender/avatar_finish/avatar_finish_candidate_uv_source.blend` contains
  only the shirt/trouser editing meshes, original `UVMap`, metre `FabricMeters`,
  and editable Principled/Normal Map nodes. Original albedo and new data-map
  PNGs are packed into that file; the new maps use Non-Color data and the correct
  metre repeat. These nodes can display/edit the finish in Blender, but no
  Blender render or cross-renderer appearance match is claimed. If PNGs are
  regenerated, reload and repack them to update the Blend's packed snapshots.
  This is **not a complete character rig/animation Blend**.
- **Full character and export boundary:** the authoritative full rig, skin and
  clips remain `assets/models/avatar_v2/pool_explorer_v2.glb`. The separate
  `assets/textures/avatar_finish/avatar_finish_candidate.glb` retains them and
  adds cloth UV2/tangents/seam splits. Its material, texture, image and sampler
  tables are unchanged from frozen V2: **the new cloth PBR texture assignments
  are not embedded in this GLB**. An independent GLB viewer therefore sees the
  original materials unless it recreates those bindings. The supplied UV-only
  exporter also does not transfer Blend material-node edits into the GLB.
- **Tested runtime appearance:** `scripts/player/avatar_finish_candidate.gd`
  binds the external maps to `shaders/avatar_finish_candidate.gdshader` after
  `PoolAvatar.setup()`. Package those files and the complete
  `assets/textures/avatar_finish/` directory together. A standalone portable
  glTF PBR material export would be a separate, unprovided deliverable requiring
  explicit UV2 texture transforms/data maps and matching dielectric settings.

For editable source packaging, include the full `tools/blender/avatar_finish/`
directory, the candidate runtime files above, and the frozen V2 assets required
by the builder. Exporting the cloth-only Blend directly is not a replacement
for the preserved full-rig candidate GLB.

## Reproduce (CPU only, no render)

From the project root:

    python3 tools/blender/avatar_finish/generate_avatar_finish.py
    python3 tools/blender/avatar_finish/run_cpu_uv_build.py
    python3 tests/avatar_finish_candidate_contract.py

The wrapper limits Blender to two threads, observes RSS and stops above 1 GB. For an artist's UV-only edits, save the supplied Blend and run:

    blender -b -t 2 --python tools/blender/avatar_finish/export_edited_avatar_finish_uv.py
    python3 tests/avatar_finish_candidate_contract.py --candidate tools/blender/avatar_finish/audit/avatar_finish_candidate_edited.glb --report tools/blender/avatar_finish/audit/avatar_finish_candidate_edited_contract.json

The tools directory is excluded from Godot imports via `.gdignore`, so the editing Blend and audit outputs cannot trigger a second Blender import.

Edit `FabricMeters` only. The original `UVMap` remains an albedo reference. An edited export is a new candidate requiring its own native comparison. The runtime guard deliberately accepts this candidate layout, not arbitrary UVs.

## Optional integration contract (owner controlled)

The owner is validating the opt-in `--avatar-fabric-finish` integration in the full native bath. The helper is `scripts/player/avatar_finish_candidate.gd`; the isolated lit PBR shader is `shaders/avatar_finish_candidate.gdshader`. The following setup order remains required; the material authoring tools do not enable it automatically.

1. In the owner's test-only spawn path, set `avatar_scene = null` and `model_path = AvatarFinishCandidate.CANDIDATE_PATH` **before** calling `PoolAvatar.setup(player)` or adding an avatar that auto-runs setup. Alternatively assign the candidate PackedScene directly to `avatar_scene`. The real loader gives `avatar_scene` precedence over `model_path`, and `setup()` will not replace an already loaded `_model`; changing only the path afterwards is insufficient. Do not overwrite `pool_explorer_v2.glb`.
2. After setup has installed the avatar's planar-aware PBR materials, create `AvatarFinishCandidate` and call `apply_to(avatar)`.
3. Require `applied_surfaces == 2` and inspect `skipped`. Only exact imported shirt/trouser material names are accepted. Missing metre UV2/tangents and the original V2 are refused rather than receiving a knowingly stretched texture. Unknown custom shaders are also left alone.
4. Keep the helper alive. `set_enabled(false)` gives a same-shader material A/B; `restore()` reinstates exact previous surface overrides without changing mesh, rig or animations. Restore does not overwrite a later third-party material change.
5. First validate native close-ups, first-person look-down, animated seams, reflection/head-culling paths and carried objects. Only then select this candidate in the main game.

The shader preserves the existing planar-reflection clip marker and PBR adapter parameters. It uses ordinary lit PBR outputs, not a separate lighting model. It adds two texture samples only on the two cloth surfaces and no new rendering pass. The game/controller/quality controls remain untouched.

## Water response boundary

No wetness is currently connected or guessed. In particular, this material does not darken an entire avatar from a general `in_water` flag and does not apply a fixed world-height wet stripe to dry rooms. A later optional dampness interface must receive a verified contacted water volume and current surface height, clear invalid contact promptly, affect cloth below that contacted waterline only, and retain broad roughness. Dry A/B verification comes first.

## Native comparison

`prepare_native_fixture.py` stages a small separate project in `/tmp/avatar_finish_candidate_stage`; it does not start an engine. `run_native_avatar_finish_candidate.sh` must be launched by the owner from the already-verified native terminal so it inherits DISPLAY. It uses the established Godot 4.6.3 engine, Forward+ with the existing llvmpipe Vulkan ICD, four software-render threads, the shared serial QA lock, isolated HOME/XDG, a 1,228 MiB aggregate-RSS guard, 90-second import watchdog and 180-second rendering watchdog. It always writes a completed exit receipt, including failure.

The fixture captures 12 matched baseline/candidate views: full figure, shirt front and macro, sleeve side, trousers front and macro. It also verifies refusal of the original non-metric V2 and reversible material restoration. These are isolated actual native material captures, **not gameplay, hardware-GPU performance, Windows-device or photorealism evidence**. The baseline is the same planar-aware PBR shader with the new finish disabled.

The first native run at `audit/native-20261022T194502Z/` passed import, both-surface application, original-V2 refusal, restore and all 12 captures. Render peak aggregate RSS was 866 MiB and render wall time was 47 seconds on llvmpipe. Shirt/sleeve detail was restrained with no new visible seam; the initial trouser specular 0.28 was visually rejected for darkening leg regions by about 15/255. The corrected 0.50 repeat at `audit/native-20261022T201118Z/` is accepted as an isolated dry candidate: trouser-region mean signed change is only +0.57/255, full-figure p99 absolute RGB difference is 2/255, all 12 captures and reversibility checks pass, render wall time is 19.07 seconds and peak aggregate RSS is 741 MiB. The current runtime files hash-match that native run. The separate matched-motion fixture and `run_native_avatar_finish_candidate_motion.sh` implement the short test-only follow-up in `avatar_finish_candidate_motion_plan.md`; the owner-launched motion run at `audit/motion-native-20261022T204109Z-14778/` passed its technical checks: 480 frames, 240 exact pose/camera pairs, and three pixel-verified lossless FFV1 clips. Native rendering took 144.04 seconds with 767.15 MiB peak RSS; output is 169.07 MiB. Independent owner playback acceptance remains pending. Each pair uses manual animation samples and exact binary pose/camera hashes. This does not modify the accepted static fixture or material. The old color texture still has low-contrast stretched bands on sleeves visible in both baseline and candidate; these are not fixed by preserving UV0. Static captures do not establish moving-view shimmer, animated seams or gameplay acceptance. Final native evidence is written under `audit/native-<UTC>/`, with the latest successful run path in `audit/latest_native_result.txt`.

## Technical references

### UV2 tangent direction audit

`avatar_finish_candidate_tangent_audit.py` checks the actual final GLB against
triangle Jacobians without launching an engine. Its append-only result is
`audit/avatar_finish_candidate_tangent_direction_audit.json`. Both the builder
and editable-UV exporter compute MikkTSpace explicitly from `FabricMeters`
after chart rotation/normalization and write the resulting `TANGENT` accessor.
The frozen V2 has no original tangent accessor. Godot 4.6.3 preserves a supplied
accessor; its UV0-based fallback runs only when tangents are absent.

The area-weighted median/p95 angle between exported tangents and projected
UV2 U derivatives is 0.263°/3.598° for shirt and 0.293°/2.810° for trousers.
The same comparison against UV0 is 64.35°/177.86° and 91.17°/177.18°.
Nonzero UV2 residuals are expected because smoothed Mikk vertex frames are not
identical to every incident triangle's derivatives. The V flip, retained
handedness, PNG up-positive green channel and shader phase offset are audited
together. Do not add a UV rotation, negative repeat, or a UV0 normal map to this
single tangent frame without producing a corresponding frame.

This is not a perfect-unwrap claim. Two unchanged source shirt slivers, with
7.45 nm shortest edges and combined area 1.25e-10 m², have source winding/custom
normal disagreement. One small sleeve triangle has skewed UV2 (U/V angle 7.16°)
and one negative smoothed-bitangent/raw-V projection; its complete area is
2.49e-6 m², or 0.000356% of shirt area. These are disclosed in the report and
were not silently dropped from the UV2 statistics. No mesh/material tuning or
native rerender was performed for this audit.

- Godot 4.6 StandardMaterial3D normal conventions and lit PBR behavior: https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html
- Godot texture import data-map behavior: https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_images.html
- The installed Blender 4.3 glTF exporter (`io_scene_gltf2/blender/exp/primitive_extract.py`) was inspected for its UV V conversion and unchanged tangent-sign export; the isolated append code follows that convention.
- Godot 4.6.3 supplied-tangent import and missing-only generation: https://github.com/godotengine/godot/blob/4.6.3-stable/modules/gltf/gltf_document.cpp#L1447-L1454 and https://github.com/godotengine/godot/blob/4.6.3-stable/modules/gltf/gltf_document.cpp#L1631-L1669
