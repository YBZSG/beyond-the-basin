# Ceramic reflection audit and bounded candidate

Audited source: `351fcd6f8f2bb5fe21851482e2526dfa262ef406`, 2026-10-24.
The supplied final tile photograph was inspected before reading the implementation.
It shows recognizable ceiling-strip images fragmented by individual tile faces,
not a perfectly flat mirror, pixel noise, or merely a sharpened final image.
This document is source/CPU evidence, **not a visual acceptance report**.

## Established findings

1. **Broad face shape is effectively absent.**
   `tools/materials/build_formal_ceramic.py:17-20,39-46` specifies 100 mm pitch,
   1.8 mm grout, 0.6 mm ease, 0.28 mm relief and only an 8 micrometre crown,
   then encodes normals to 8 bits. The art-pass provenance specifies the same
   crown. CPU inspection of both current source normal PNGs, excluding eight
   texels at tile edges, found only 127/128 in each normal XY channel.
   Their XY length is 0.005546 before the material's quiet-face gain; after
   multiplication by 0.08 it is 0.000444, approximately 0.0254 degrees. Formal
   materials additionally multiply by their normal strength (default 0.82).
   Formal tiles have identical near-zero mean face slope. These are source PNG
   measurements, not measurements of GPU-compressed textures. Reproduce with
   `python tools/materials/reference_wing/audit_legacy_faces.py`; the saved
   source hashes and numbers are in `material_evidence/legacy-face-measurements.json`.
2. **The face/edge split is an amplitude heuristic, not a geometric mask.**
   `art_pass_pbr.gdshader:42-44`, its RT counterpart:43-44,
   `ceramic_world.gdshader:190-194`, its RT counterpart:155-159, and
   `pc_source_ceramic.gdshader:58-65` classify normal amplitude between 0.025
   and 0.14, reducing smaller slopes to 8%. A useful modest face tilt inserted
   before this operation would also be suppressed. Source glaze slopes are
   encoded at 4x (`build_source_glaze.py:36-37`) but multiplied by 0.02 in the
   shader, leaving 8% of the authored physical slope despite an older comment.
3. **Distance fading removes bevels as well as face detail.**
   Formal raster uses a 12-60 mm world pixel footprint
   (`ceramic_world.gdshader:154-155,192`). RT replaces this with distance/600
   (:119-120,157): fade starts at 7.2 m and ends at 36 m independently of FOV,
   resolution and actual ray footprint. Source RT uses corresponding 15-90 m
   distances. This is not ray-cone texture filtering.
4. **Raster and RT roughness antialiasing differ.**
   Formal raster:195-200 adds normal variance capped at 0.00012 to roughness^4;
   RT:160-163 adds at most 0.000006. A 0.105 input can become 0.12467 versus
   0.10627 respectively. Existing parity tests compare final assignment lines,
   not these different variance inputs. This can widen highlights near edges;
   it is not proof of uniform whole-face blur.
5. **The production raster reflection path differs from the old tile lab.**
   `scripts/main.gd:244-246` and `pool_lighting.gd:125-129` disable SSR outside
   formal mode. Original/expanded/Poolrooms therefore rely on cached room
   probes for ceramic reflections, not the water planar mirror. Probe setup
   is at `pool_lighting.gd:414-431,560-569`. The project does not override the
   stock 256-face probe or half-size SSR defaults. The quality panel's mirror
   size goes only to water.planar (`desktop_quality_panel.gd:277-281`). The
   existing `tests/tile_finish/raster_lab.gd:112` always enables SSR, so a good
   image there would not validate production routing.
6. **Clearcoat is not transported into the pinned RT BRDF.**
   The pinned NVIDIA custom-fragment interface declares coat outputs, but
   closest-hit conversion copies only the fields present in MaterialResult:
   albedo, alpha, roughness, metalness, specular, emission and normal. Increasing
   coat in a project shader consequently cannot repair this RT reflection.
   [Closest-hit conversion](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/scene_raytracing_raygen.glsl#L343-L358),
   [material result](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/raytracing_material_eval_inc.glsl#L3-L11).
7. **Native RT further flattens grazing normals.**
   The pinned BRDF enables a geometric N dot V threshold of 0.4. Below it,
   shading-normal perturbation is reduced by approximately N dot V / 0.4;
   the resulting normal is used for both shading and RR guides. At 0.1 only
   about 25% remains. This is intentional below-hemisphere protection and is
   not changed by this candidate.
   [Constants and implementation](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/brdf_inc.glsl#L155-L168),
   [clamp](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/brdf_inc.glsl#L869-L876),
   [BRDF and RR use](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/raytracing_closest_hit_common_inc.glsl#L409-L478).

## Not established

- The existing ORM-alpha correction is already present and is not repeated.
  Art roughness importer correction affects G, but the current glaze formula
  limits its influence to plus/minus 0.0048. It cannot alone turn a face matte.
- Mipmaps and anisotropic sampling are requested. RT ordinary texture() calls
  have no explicit ray derivatives/LOD; non-fragment implicit sampling does
  not provide raster footprint filtering. Do not label this 'overblurred RT
  mips': aliasing followed by reconstruction is a separate hypothesis.
  [Khronos GLSL specification](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.html).
- RR or NR being the main blur source is unproven. Production requests 1 spp,
  three bounces and denoiser enum 1. Thin bright dielectric reflections can be
  challenging at low sampling, but no native paired diagnostic was run here.
  NR is a whole-frame SDR pass after tonemapping, without per-material masks.
  Existing one-to-four layer controls cannot create missing physical face shape.
- Stock raster defaults include a roughness limiter; record its actual state
  in any experiment instead of blaming it without an ablation.
  [Godot 4.6 project settings](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html).

## New-only implementation boundary

Only the reference-wing material family is changed. The six accepted ceramic
shaders, original water, custom engine patches, production reflection routing,
and NR controls remain untouched. The parent integration owns new RT-pair
registration and scene selection. Initial values are a candidate, not an
accepted appearance: 100 mm tile pitch; 0.075 face roughness with small batch
variation; nonmetal F0 0.04; rough grout; independent analytic per-cell face
shape with centre tilt up to 0.35 degrees per axis and a 50 micrometre crown.

The face is represented by a bounded smooth height polynomial, not per-pixel
noise. Its centre gradient is the specified tilt; the height and derivative
reach zero at cell boundaries. This keeps the separate 0.28 mm joint relief
coherent without inventing an entire flat mirror or an unbounded tilted plane.
Shader and offline map generation share the exact cell hash and polynomial.

## NR-off validation plan

Use a fixed metric wall/floor, three modelled emissive ceiling strips and a
colored geometric subject. Keep exposure, lights, cameras and dimensions fixed.
Compare exact legacy art pearl, new control at legacy roughness with face shape
off, shape-only, roughness-only, and combined. Use close, grazing and distant
views plus short lateral motion. NR stays OFF for material selection.

Record the real probe/SSR path separately from an SSR-assisted lab. On the
matching custom NVIDIA engine compare the same frames with RT/RR, including
normal/roughness guides and unfiltered output if supported. Only then compare
NR off/on. Preserve water and disable unrelated display filters during material
judgment. Success means identifiable strips within faces, cell-correlated
offset/bending, rough joints, and no pixel sparkle, global mirror or motion smear.

CPU/headless tests cover finite fields, hash/math parity, normal orientation,
metric scale, source preservation, bindings and material selection. They do not
establish GPU sampling, native RT/RR/NR quality, frame time or visual acceptance.

## Implemented source candidate and scope

The new `ReferenceMaterials` adapter resolves only explicit `ref_tile_*`
roles and `ref_grout`. Pearl, teal, pink and dark-teal pigment maps are
separate albedos, not global scene tint. Dry-floor counterparts retain their
palette and use face roughness 0.26; changing a wall ablation does not change
that dry finish. No slip-resistance certification is implied.

`tools/materials/reference_wing/surface_math.py` generates the shared shader
math and the high-precision offline reference normals. The runtime evaluates
face slopes analytically and decodes a separate linear bevel-slope map with
an exact neutral byte. The Blender helper uses matching 16-bit full-normal
or bevel-only maps, compensates the standard glTF V conversion once, and can
reproduce control/shape-only/roughness-only/combined ablations without editing
lights, scene geometry, UV scale or the original water.

The initial CPU stair image shows identifiable strip images but still has
visible sampling noise and broad/clipped bright boundaries. It is not visual
acceptance. A fixed, un-denoised 64/256-sample crop comparison has now separated
sampling from roughness and face shape. See `material_evidence/CPU_CROP_REVIEW.md`
for the matched images and bounded conclusion.
Matching-engine NVIDIA RT/RR and NR-off/on validation remains pending.
