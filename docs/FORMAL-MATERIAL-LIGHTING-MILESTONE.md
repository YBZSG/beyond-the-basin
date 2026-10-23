# Authored formal hall: material and indirect daylight study

## Scope

This milestone changes the separate authored formal destination. Original seeded rooms retain their own source ceramic shader, pigment values, source light positions/colour/power/survival, default selection and water algorithms. Switching back to the original scene restores its previous sky colours, ambient, exposure, contrast, SDFGI feedback and ambient-occlusion strength.

This is not a claim of photo-realism or target-PC performance. CPU/data checks do not establish rendered quality. Only actual native screenshots made after this revision can do that.

## New authored ceramic

The old rounded-square scan had broad dark joints and a strong rounded edge, making close stairs read as cobbles. The formal-only replacement is an original deterministic analytic PBR material, not a photographed or measured scan:

- 4096 × 4096 map, 16 × 16 tiles, 1.6 m repeat: 100 mm pitch.
- 1.8 mm grout, 0.6 mm eased ceramic edge, 0.28 mm joint recess.
- 8 μm face crown and subtle tile-batch colour/roughness differences; no per-pixel dirt/noise embossing.
- Albedo without baked lighting; OpenGL tangent normals; independent linear roughness/variation/coverage texture.
- Actual filtered grout coverage approximately 3.44%, rather than the old shader's 20.1% approximation.
- Mipmapped high-quality texture compression and derivative-aware specular filtering preserve calm distant surfaces.
- Coping and nosings suppress the 100 mm atlas joint grid because they already have physically modelled large-format joints. A second grid would contradict their construction.

Maps and provenance: `assets/textures/formal_ceramic/NOTICE.md` and `material_manifest.json`. Generator: `tools/materials/build_formal_ceramic.py`. Original licensed Poly Haven maps remain unchanged and correctly attributed in their existing notice.

## First daylight adjustment

Formal plaster is a separate neutral matte resource, without texture normals or emission. The formal sky's lower hemisphere no longer introduces an olive cast; direct sun is near-neutral warm daylight. Existing directional light energy/direction, aperture occlusion, two effective source-water emitters and all source caustic/optical calculations remain unchanged.

Uniform formal ambient is reduced from 0.24 to 0.18, not increased to hide dark geometry. AGX contrast and contact occlusion are made less crushing; native indirect feedback is allowed more iterations. No additional fill lights are included in this first pass. `PoolLighting.capture_lighting_changed` emits after the immediate palette commit and after its mood tween completes, allowing capture owners to refresh actual lighting without per-frame rebuilds or copying main-view tonemapping into linear HDR captures. Runtime review must decide how much more physically motivated indirect illumination is needed.

## Native LightmapGI feasibility study

Godot's official documentation says LightmapGI can bake only in the editor, requires valid UV2 and size hints, and can provide dynamic-object irradiance through probes. It cannot bake in an exported game. Runtime reflections still require a sky/reflection probe.

References:
- https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html
- https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html

Actual Godot 4.6.3 CPU inspection found valid Blender UV2 but zero size hints on all initial mainhall meshes. `LightmapGI` has no GDScript-exposed bake method. Therefore this study does not claim a successful bake from a headless call.

`tools/lighting/prepare_formal_lightmap_lab.gd` creates a disposable isolated scene using Godot's native `ArrayMesh.lightmap_unwrap` at 0.18 m. Current preparation yields 107 static architectural receivers and approximately 425k hinted texels without unwrap errors. The 66 thin metal fittings receive dynamic probes rather than spending diffuse-lightmap UV charts on fasteners and grating. The saved scene is reloaded to check that deleted collision meshes do not reappear, the external `.lmbake` path is retained, and all dynamic caustic emission is explicitly disabled during bake. It includes sky, the unchanged directional sun in dynamic/indirect bake mode, four diffuse bounces, directional lightmaps and dynamic-object probes. It deliberately has no artist fill proxies. Original runtime geometry and imported GLBs are not overwritten.

Scene: `scenes/lighting_lab/formal_mainhall_lightmap_lab.tscn`.

The native coordinator can open this scene in the real Godot editor, select `Bake_Mainhall_Indirect`, and perform one bounded Bake Lightmaps attempt. The save target is `assets/lighting/formal_mainhall/study_indirect.lmbake`. Before bake, that resource is an empty placeholder and is not evidence of lighting.

After a successful editor bake, `tests/formal_lightmap_native_probe.gd` loads the actual scene and refuses to produce a success image if lightmaps/users are empty. It verifies receiver paths and captures actual Godot renderer pixels with a JSON manifest. Even this does not establish production integration; that requires attaching the validated data to the real scene and checking the same gameplay cameras. Future geometry changes invalidate the study and require regenerated UV2/data.

## CPU verification

Focused results in `docs/verification/eight-hour/material-lighting/`:

- Physical map contract: 29 checks.
- New material/lighting isolation contract: 33 checks.
- Formal daylight/material contract: 185 checks.
- Shared rendering/source fixtures contract: 2,679 checks across 60 source-room layouts.
- Original scene presentation contract: 114 checks.

These are CPU/resource contracts only. Native shader compilation, image quality, successful editor bake and production bake integration are separate gates.

## First native comparison and expansion status

The actual same-camera mainhall image `output/eight-hour/material-04-formal-main.png`
completed with terrain/cubemap readiness and live caustic frames. It is a genuine
renderer result, not a material mockup. Fine ceramic, coping and mounted rail
geometry read more cleanly, but the broad arch soffits still lack convincing
indirect daylight. The windows have little exterior visual context, and fine
joints are subpixel at the distant wall. This result is **not accepted as a
finished lighting/art milestone**. The native editor LightmapGI study is the
next validation gate; an empty `.lmbake` file is not success.

A geometry-normal audit of the three central arch soffits found mean agreement
of approximately 0.999 with their expected inward ellipse normals and triangle
winding. Their darkness is not explained by flipped normals. The fix must
supply spatially motivated irradiance rather than flattening the whole scene
with higher uniform ambient.

The newly registered terrace `(0,-2)` and circular bath `(-1,-2)` have explicit
coordinate-based lighting profiles instead of inheriting the sidepool fallback:

- Terrace effective origins are inside its measured 12 × 9 m open-sky rectangle.
  One broad downward sky sample complements the two modest effective emitters;
  no upward whole-courtyard fill is added.
- Bath effective origins are within its real 3.6 m-diameter oculus. One downward
  oculus sample and one restrained diffuse return from the pale basin provide
  localized fallback illumination. The return has no caustic/specular emission
  or recursive indirect energy.
- Reflection boxes are sized to each room and exclude the water render layer.
  Their ambient mode is disabled; ambient remains the existing formal 0.18.
- All first-three-room light positions, powers and rigs stay unchanged.

After the five-room geometry import, the all-room daylight/material contract
passes 225 assertions across 17 panes and 38 opaque frames. The added aperture
contract passes 52 checks; material/source restoration remains 33 and physical
ceramic remains 29. These new rooms still require native image review.

## Native bake disposition, 2026-10-21 20:50 UTC

The native editor study completed after 14m11.94s but failed HDR finite-data validation. The primary radiance slices contain 1,320,522 NaN components. An independent BPTC mixed-format import error was isolated and repaired through lossless RGB16F import without changing any baked pixels, but this does not repair the invalid radiance. Both saved-data and native-probe tests now reject it. Production remains on the normal SDFGI runtime. No baked-lighting visual acceptance or integration is claimed.
