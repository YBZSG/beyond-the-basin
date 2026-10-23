# Native materials and lighting

## Source-to-engine translation

The geometry is the original Quiet Wing GLB export. `PoolMaterials` replaces only named material families (`Quiet Wing / tile`, `pale`, `plaster`, `brushed stainless`, and the remaining source palette); unknown materials are left intact. Shared geometry resources are not rewritten. Imported architecture is marked `GI_MODE_STATIC`.

The three supplied 2048 × 2048 Poly Haven CC0 maps remain registered to one signed, world-space triplanar projection. Repeat is **4 metres**, matching the source project's art-directed enlargement of the nominal 2 metre scan. Shared outer walls preserve the source's full-height glazed tile family; native material role `wall` is resolved through the source daylight/decay tile palette. The original authored GLB plaster arches, upper piers and ceilings remain matte plaster, while their source-defined splash bases remain ceramic.

The scan's brown pigment is neutralized using the source's measured linear-color reference while preserving its real tile and grout response. The material is a nonmetallic dielectric with restrained glaze. The source roughness map separates ceramic faces from porous grout. Normal amplitude is 0.22; unresolved normal detail fades and adds a small variance correction to roughness. There is no second synthetic grout grid, fine noise, dirt grain, displacement or emissive material fill. Normal orientation is OpenGL +Y, with explicit BC5-compatible Z reconstruction. No green-channel inversion is performed.

Roles `wall` and `floor` are available. The optional standalone `wall` material supports a dado split, but the source-faithful runtime shell resolves its walls to the full-height `tile` family. `pale` stays ceramic, appropriate for deck and splash details. Vaults and upper arches use plain rough plaster, not tiled or glowing ceilings. Source-derived changes to pale/ivory aim for restrained warm readability under native lighting.

## Texture import requirements

After the first Godot import, keep these settings in the three JPEG `.import` sidecars:

- All three: `mipmaps/generate=true`; `compress/mode=2` (VRAM compressed); `detect_3d/compress_to=0` (explicit settings, not an automatic subsequent mode switch).
- Normal: `compress/normal_map=1` (enable); `process/normal_map_invert_y=false`.
- Albedo and roughness: `compress/normal_map=2` (disable).
- Roughness can use `roughness/mode=2` (red) and the normal path as `roughness/src_normal` for Godot's import-time normal-aware roughness filtering, but the shader already performs restrained runtime variance filtering. Avoid adding both aggressively.

Only albedo uses the shader's `source_color` conversion. Normals and roughness are linear data. All samplers repeat with linear mipmaps and anisotropic filtering. Configure the project's default anisotropy to 16× for the PC target.

## Real illumination, not baked-image replacement

`PoolLighting.configure_environment()` assigns the WorldEnvironment and creates one shadowed directional sun named `ApertureSun`. Do not add a second directional key. Real geometry blocks it; the oculus and other authored roof openings admit it. `add_room_lights(room, variant)` is idempotent and creates the source-position double-tube fixtures at x = −9 / +8, z = −5, y = min(7.3, ceiling − 0.7). The vaulted hall's suspensions stop at the actual curved roof, rather than requiring imaginary openings.

Godot does not have a native dynamic rectangular area-light equivalent to Three's LTC rectangle. Each visible fixture therefore uses two broad, soft-shadowed spotlights and a weaker colocated omnidirectional opal component. This is an explicit approximation, not a claim of exact LTC parity. Tube spot/opal proxies and the diffuse aperture source have zero direct specular: reflected highlights come from the real elongated emitter meshes and sky via native SSR/probes, not clipped spherical surrogate highlights on the water. Real wall lamps and the sun retain their native specular response. Small, visibly modeled wall lamps provide motivated perimeter illumination; local lights all cast real shadows. Daylit variants also receive a shadowed diffuse source positioned at the actual roof aperture. Source-seeded survival, power decay, ballast flicker and the WFC exit lamp are read from room metadata. Dead fixtures keep their dark glass; surviving flicker drives the actual lights and visible emission together. Exposure does not change as the player crosses a portal.

Forward+ provides native SDFGI (6 cascades, 0.2 m near cells, occlusion enabled), subdued SSIL, contact SSAO, SSR, AgX tonemapping and faint volumetric atmosphere. A small neutral ambient floor preserves legibility without making the plaster self-lit. Glow has zero blanket bloom and an HDR threshold; only actual bright emitters contribute. The old Three lightmap is neither sampled nor called Godot GI.

Each room has a one-time, shadowed, box-projected ReflectionProbe fitted to its 32 m footprint and actual ceiling. Its capture origin is 2.4 m above the floor datum. Architecture is on visual layer 1; water must be on layer 2 so it receives room reflections but does not capture itself. Daylit probes retain visible sky through the actual aperture; enclosed rooms are interior probes. Water's own screen-depth caustic pass is the sole caustic modulation; ceramic adds none.

## Verification

`tests/rendering_contract_test.gd` checks actual 2K resource dimensions, physical scan scale, matte plaster, GLB role preservation, static GI flags, native environment settings, exact fixture positions, idempotence, and reflection volume/capture masks. It is a **headless data/API test**, not evidence of final raster quality. Run it after editor import. Final lighting/normal/roughness review must use real Forward+ game frames from Godot, with enough frames for native GI and probe captures to settle.

Official Godot 4.6 API references used:
- https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html
- https://docs.godotengine.org/en/4.6/classes/class_environment.html
- https://docs.godotengine.org/en/4.6/classes/class_reflectionprobe.html
- https://docs.godotengine.org/en/4.6/classes/class_light3d.html
- https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_images.html
