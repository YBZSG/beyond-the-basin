# Bounded actual-bath VoxelGI study

Final status: completed native subdivision-64 test on 2026-10-22. Valid nonblack data and shared-volume operation, but negligible visual improvement. Candidate rejected; no 128 continuation or production integration. See [RESULTS.md](RESULTS.md). The plan below records the original bounded experiment.

## Decision being tested

Can one static-geometry, bath-local VoxelGI volume improve the actual circular bath's indirect-light depth without black ShaderMaterial baking, changed direct lighting/exposure, or a full-world lightmap migration?

This is **not** a proof of full-game performance or a replacement of source SWE/MPM/photon water. The test isolates the actual bath architecture with production materials and lights. Water, avatar and other rooms are absent. There is no stand-in water surface. Only the local geometry representation is precomputed; the preserved production light rig still supplies live light to VoxelGI.

## Geometry and scope

- Input: `assets/models/bath_junction_candidate/formal_bath_full_source_export.glb`, SHA-256 `f263ebbd828c03f5f5e0010856d671af667fbcc349f16f36a0ba60fcc8a59c01`.
- CPU GLB inspection: 70 visible meshes, 46,776 visible triangles, 687 original collision nodes, 4,137,224 file bytes. Native builder will verify collision shapes and three glazing meshes.
- Production `formal_room_builder.gd`, `pool_materials.gd`, and `pool_lighting.gd` are called, not reimplemented. BathBasinReturn's current shadow-off policy is preserved.
- One volume centered at local `(0, 2.5, 0)`, size `(20, 8, 20)` metres. Immediate portal returns are included; far vestibule ends deliberately lie outside it.
- First run: subdivision 64, approximately 0.3125 m cells, 64×32×64 field. 128, approximately 0.15625 m cells, is allowed only as one justified continuation for a promising resolution-limited result. No 256/512 or full-world sweep.

## Bake material correctness

Godot's documented static ShaderMaterial limitation makes direct baking unacceptable. Every visible static opaque surface temporarily receives a StandardMaterial3D proxy, with its exact original active and override references saved and restored before rendering.

- Constant plaster, dark and metal colors use their actual runtime pigment. sRGB/linear conversions are explicit.
- Ceramic uses the actual pigment and grout pigment mixed in linear space, using measured full-resolution atlas averages: face fraction 0.9656298161 and face-weighted modulation 0.9966822267. Wet darkening is area-averaged over each triangle at its centroid using the runtime waterline function. This is an approximation, not exact texel-by-texel world-projected baking.
- The isolated runtime also explicitly sets causticGain=0, because no live caustic atlases exist; this prevents unbound default textures masquerading as emission. No caustic emission or emissive substitute is baked. Every proxy has emission disabled; packed baked emission must be zero in every leaf cell.
- Actual glazing stays GI-disabled and shadow-disabled, with original transparent material untouched. Hidden collision meshes cannot participate.
- Roughness/metallic values are retained on proxies, but the voxelizer records albedo and emission rather than full directional BRDF. Narrow metal rails therefore remain a diffuse-color approximation. The current room has no upper-plaster mixed shader or optional expanded wet finish; the test rejects those unsupported cases if found.
- Data must contain populated nonblack leaves, matching octree cell counts, and zero emissive leaves. Data is saved as an external binary `.res`, reloaded, and compared before use.

## Fixed visual experiment

Native Vulkan Forward+, 960×540 display and render size, MSAA2×, TAA off, 2048 shadow atlases, production AgX/exposure1.12, production ambient0.18, production direct-light energies/shadows, SSAO on, SSIL/SDFGI off. This is a Medium-like diagnosis with native scale1.0 rather than Medium's scale0.9. No setting changes across A/B.

For wide entrance view, wall closeup, and upward roof view:

1. Capture volume absent.
2. Bake with temporary material proxies, restore original shaders, load the saved data.
3. Capture volume visible, data energy1, propagation0.5, two bounces, interior enabled, default bias1.5/normal bias0, dynamic range2.
4. Hide the volume and capture the identical cameras again.

The test fingerprints light transforms/colors/energies/bake modes/shadows and environment exposure/ambient/GI/fog state. It records a full image set. Numeric change is not visual acceptance. Inspect for receiver contribution, separation, cell leakage/banding, unnatural color, flat brightness lift, and off-state restoration.

One additional 512×288 SubViewport then shares the exact same World3D/scenario and one VoxelGI node. It uses the production source-capture linear-HDR environment and records GI on/off images, EXRs, complete finite/negative/large-radiance pixel scans, and renderer memory. This establishes a bounded shared-volume feasibility check only, not six cube faces, planar reflection correctness, or actual water integration.

## Memory and stopping rules

- Record baseline renderer texture/buffer/video memory, before bake, after hidden baked data, on-state, hidden again, one extra shared view, and removal. Record resource and raw octree/data/distance-field bytes separately from renderer memory.
- External supervisor samples process RSS at 0.5s cadence and terminates at 3.4 GiB observed RSS or 900s. A watchdog is not a kernel memory limit and llvmpipe memory is not target-GPU VRAM.
- Existing native lock plus process scan prevents overlap. No retries are automatic. First outcome expected inside 30 minutes after slot release, including image inspection.
- Stop after invalid/no contribution, obvious leakage/flatness, memory failure, or visual regression. A small resource alone is not success. Never integrate by default.

## Commands

Safe without engine slot:

```sh
python3 tests/bath_voxel_lighting/preflight.py
python3 tests/bath_voxel_lighting/run.py --describe
```

Only after the owner explicitly releases the native slot, from the supported graphical cloud terminal (the workspace exec namespace lacks the display). A fresh tag is mandatory; the completed evidence is `run64-02`:

```sh
python3 tests/bath_voxel_lighting/run.py --native-slot-granted --tag FRESH_RUN_TAG
python3 tests/bath_voxel_lighting/analyze.py docs/bath-voxel-lighting/FRESH_RUN_TAG
```

A 128 continuation additionally requires a written justification at `docs/bath-voxel-lighting/allow-128.txt`, a fresh evidence tag, and an explicit slot release. No production files or defaults are edited.

## Primary references

- [Godot4.6 VoxelGI setup and ShaderMaterial limitation](https://docs.godotengine.org/en/4.6/tutorials/3d/global_illumination/using_voxel_gi.html)
- [Godot4.6 VoxelGI API](https://docs.godotengine.org/en/4.6/classes/class_voxelgi.html)
- [Godot4.6 VoxelGIData API](https://docs.godotengine.org/en/4.6/classes/class_voxelgidata.html)
- [Godot4.6.3 voxelizer source](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/voxelizer.cpp), especially material conversion and 16-byte packed cell layout.
- [Godot4.6.3 VoxelGI source](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/voxel_gi.cpp), visible/static mesh filtering, external data and bake path.
- [Godot4.6.3 renderer GI source](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/environment/gi.cpp), per-instance voxel textures and runtime light updates. Shared World3D suggests reusable volume resources, but each viewport still has rendering/cone-tracing costs; the bounded test must measure rather than assume savings.
