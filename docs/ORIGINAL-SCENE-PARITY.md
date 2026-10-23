# Original scene restoration: pinned commit 66a4543

The original source of truth is `66a4543602d9e774db07c2da12ce1d40d522532c` in the original repository. It is **not** the later modified Three working tree and **not** the older delivered formal Godot build. The optional authored main hall is preserved separately; its presence must never replace or reseed original procedural rooms.

## Concrete differences corrected

- Original `world.ts` selects **eight** variants, not eleven, and has exactly six anchored coordinates: `(0,0)=0`, `(0,-1)=3`, `(-1,0)=6`, `(1,0)=5`, `(0,1)=4`, `(1,1)=7`. Removed the three injected authored-wing anchors from original generation and restored `floor(rng()*8)`. The unused authored GLBs and separate formal builder remain available.
- Kept original 32 m spacing, basin top −0.72 m, water level 0.32 m, 8 m portal openings, 5.4 m portal headers, source ceiling heights, six original anchored destinations, per-coordinate corruption and RNG draw ordering.
- Original ceiling panels and skylight reveals use pale ceramic, not the later substituted plaster.
- Original arch geometry is represented by the same 5.3 m piers and semicircular 3.5/4.6 m inner/outer radii. Restored the original explicit pier collision/prop-rejection bounds ending at world y=5.3. The native ring additionally retains its real triangle collider.
- Restored source sign composition: 0.72 × 0.9 m board, original board/ink colours, thin inset frame, 44 px-equivalent bold serif notice and separate 16 px-equivalent monospace footer. Sign text, positions, rotation and corruption variants match the source. Native font rasterization can differ from browser canvas rasterization.
- Native sphere tessellation now maps Godot's rings+1 to Three's heightSegments: props/static spheres 16×12, beach ball 64×48. Rods use source 32-sided cylinders. The beach-ball longitude seam is rotated from native +Z to the original −X without altering its seeded body yaw.
- Restored original-style immutable architecture batching by live material, shadow state, layers and indexed state. Original default-seed startup geometry goes from 2,492 separate meshes to 105 draw meshes (seed 1337: 2,601 to 117) without removing triangles, collision or independent notices. Source emissive-only meshes remain visible but carry the same optical-BVH exclusion as original MeshBasicMaterial.
- Prop shader materials are duplicated and receive the source pigment and roughness. Previously ShaderMaterial props silently inherited later architecture-role roughness. Shared architecture resources are not modified.

## Source streaming, not an inferred redesign

The comment at original `engine.ts:580` describes the outer ring as geometry-only, but the executable code still runs complete `generate()` for all 25 rooms, registers their floating props, and includes all their colliders and ladders. The `far` flag excludes outer rooms from selected lights and reflection BVH, **not** from generation of their props, signs, ceilings or balconies.

Godot therefore keeps all 25 complete rooms and updates `room.far` metadata plus `layout.far` on crossing: nine inner rooms and sixteen outer rooms. No speculative 9-full/16-empty-shell replacement was introduced. The formal environment remains on its separate path.

## Independent regression evidence

The prior fixture generator imported `room-catalog.ts` and `curated-wing.ts`, files absent from the original commit. That validated the later rewrite, not the user's original scene. The generators now read each input with `git show <pinned commit>:<path>` and reject any mismatch with the vendored provenance copy. They execute the actual original `buildChunk` generator and original prop builder; renderer/batching callbacks alone are inert for scene measurement.

2026-10-21 headless Godot 4.6.3 results:

- `world_parity.gd`: 120 source RNG, layout and complete 12×12 WFC fixtures passed, including negative/large coordinates and eight seeds, including original default seed 250821.
- `world_room_parity.gd`: 60 full original room fixtures passed, including all 25 default-seed startup rooms; 1,509 seeded prop positions, kinds and yaw values plus surviving fixture positions/powers.
- `original_geometry_parity.gd`: 5,854 primitive shape/transform/material-role records, 2,722 source solid bounds, 125 sign records and 96 ladder base/top/exit triplets passed across those 60 rooms. Coverage includes all eight variants and corruption branches.
- `original_batch_parity.gd`: 60 rooms / 5,854 prebatch meshes become 257 material-group draw meshes. All 1,268,364 triangle-corner positions, normals and UVs match within native float/normal-packing precision, with identical group identities, collision counts, notice ownership, far classification and idempotent rebuild behavior.
- `original_prop_parity.gd`: all three prop kinds, nine visual parts, original physical tuning, material isolation, source sphere subdivisions and beach-ball seam direction passed. Every byte of the 1,024 × 512 RGBA beach-ball texture matches the source SHA-256 (2,097,152 bytes).
- `world_streaming.gd`: all eight source variants appear in the 25-room startup set, with no injected authored-wing instances; 2,601 source meshes produce 117 draw meshes for seed 1337. Collision floor/portal rays, initial completion, room crossing, far classification and distant teleport passed.

Raw log: `verification/original-world-parity-2026-10-21.log`.

Regenerate fixtures from this project directory:

```sh
node tools/source-world-reference.mjs ../poolcore
node tools/source-world-room-reference.mjs ../poolcore
node tools/source-prop-reference.mjs ../poolcore
```

These are geometry/CPU evidence, not a claim of identical rendered pixels or GPU performance. Godot and Three have different font rendering, GI, rasterization, native contact resolution and water-rendering backends. Integrated lighting/material/startup changes are verified separately. No GPU render was launched for this focused geometry pass.
