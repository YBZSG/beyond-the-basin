# Reference-wing native light binding

## Scope and result

`reference_lighting.gd` is a `PoolLighting` subclass used on PC. Only rooms with
`layout.reference_wing` use its new binding/selection. Legacy and formal creation
delegate to the original implementation. No original lighting, exposure, sky,
GI settings, source-water solver, photon algorithm, or global material is changed.

The catalog retains each complete authored JSON light as `fixture.reference_light`.
There is exactly **one native light per enabled fixture**, not a pair or an array
of samples for each rectangular emitter. The current five contracts contain
17 / 9 / 7 / 4 / 10 native fixtures, 47 total. Disabled lounge camera/fill lights
are not reinstated. Fixtures start hidden until the manager selects them.

The adapter honors position, direction, color, energy, range, cone, emitter radius,
authored shadow permission and the user's shadow toggle. A stable current-room
first selection keeps at most **27 renderer-visible positional lights and four
shadow-enabled lights** across the reference wing. Retired hidden rooms consume
neither budget. Freed weak references are removed; rebuild and cross-mode tests
cover reuse of the same room coordinate. The active room retains authored fixture
order, so turning in place does not reshuffle its shadow maps. Only neighbor
fixtures use the inherited view-score concept. Four is the **raster shadow-map property
budget**, not a four-light path-tracing shadow-ray limit.

## Why spots, not an invented area-light API

Reviewed the exact NVIDIA engine revision pinned in `tools/dlss/README.md`:
`135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, plus the project's local patch scope.

- [Native light implementation](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/scene/3d/light_3d.cpp)
  exposes `AreaLight3D` in that newer engine, but this does **not** establish a
  rectangular path-traced light. The stock cloud 4.6.3 API is also different.
- [RT light gathering, approximately lines 2769–2950](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/forward_clustered/render_raytracing.cpp)
  maps positional lights to `SPOT` only when their type is `LIGHT_SPOT`, otherwise
  `OMNI`. It uploads spot half-angle, attenuation and normalized local **−Z**.
  It does not upload rectangular dimensions, a cull mask, or a shadow-enabled flag.
- [RT light buffer and direct evaluation](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/raytracing_lights_inc.glsl)
  represent omni/spot emitters with a spherical radius. The cone test is real.
  Positional direct evaluation unconditionally tests visibility with a ray.
  Setting `shadow_enabled=false` does not remove that path-tracer cost.
- [RT closest-hit shading, approximately lines 441–461](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/shaders/raytracing/raytracing_closest_hit_common_inc.glsl)
  adds material emission at ray hits. Emissive strips can appear in reflections
  and contribute through sampled bounces, but are not converted into a separately
  importance-sampled rectangular-light list by this light gatherer.
- [Pinned Light3D contract](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/doc/classes/Light3D.xml)
  defines color as sRGB and energy as a nonphysical multiplier. GI and volumetric
  fog ignore the light cull mask. A cull-mask-zero dummy Omni is therefore **not**
  a safe universal non-rendering water input. No such dummy is created.

Source fingerprints: RT gather file SHA-256
`76945a49b1b326930eef67c8aa0f83708241f3bb425b2fae776069129febe079`;
RT light shader SHA-256
`e8a77e349feedda1fc457b6444348102a471dc8415a008f24a201d6ddb04e1d3`.
This is source-level support evidence, **not** execution on the custom engine.

## Authored metadata and approximation

- `native_type`: `spot`, `omni` or `point`. If absent, a nonzero `direction`,
  `emission_direction`, or `target - position` selects a spot. Otherwise use the
  explicit point type. Unsupported `area_preview` with no direction is rejected.
- `position`: room-local Godot XYZ metres, used without an arbitrary offset.
  The room transform applies once. A vertical direction chooses a nonparallel
  orientation up axis so neither upward coves nor downward strips produce NaNs.
- `native_energy`, otherwise `energy`, otherwise existing `fixture.power × .07`.
  There is **no** automatic conversion from source preview Watts.
- `color_space: "linear"` marks the RGB values assigned to Blender `Light.color`.
  The adapter encodes them with `Color.linear_to_srgb()` for native `light_color`.
  Native raster/PT and the unchanged liquid collector decode once, preserving
  the author's actual linear radiance. Unlabeled/explicit `srgb` values are not
  encoded a second time. Numeric tests cover dark, pastel and saturated samples.
- `range`: 1–20 m. `attenuation`: default 2. `spot_angle_deg`: half-angle,
  default 80°, bounded to 1–89°. `spot_angle_attenuation`: default .25.
- `emitter_radius`: default .005 m. This is a tiny spherical proxy, not the width
  or length of a rectangular strip. In particular the bath light centers are
  close to their diffusers, so a larger sphere could intersect them. Final actual-mesh clearance tests check all 47 enabled sampling spheres, not only nominal metadata.
- `native_specular`: default 0. The visible strip/window geometry supplies its
  shaped glint, rather than adding a round point-light specular blob.
- `shadow`: authored permission in addition to the four-light manager budget and
  the desktop quality setting. All fixtures retain the original source energy
  conversion metadata for water.

Historical bath cove trials required explicit upward 85° half-cones / .15 cone attenuation because
useful ceiling rays are only 10–20° above horizontal. A narrow spotlight would
miss the actual center-cap receiver. Even this broad cone remains a point/spot
approximation to the approximately 4.188 m × .035 m authoring area emitter.
Fixture seating/clearance is geometry-owned and must be rechecked when a fixture
center, lens, lip or hood moves. The final bath disables all eight cove lights and uses four enabled supported practicals. Its left-portal emitter is inside the connected corridor, aimed out/down, with an amber color and 75° half-cone. The rejected outside washer/hood is not a runtime asset.

## Water remains the original point-input transport

The original liquid collector searches only `OmniLight3D`. Replacing those nodes
with spots without adapting the collector would silently remove droplet lighting.
The **reference-scene-only** runtime therefore recaches actual Omni and Spot nodes
after `super.add_room`, and overrides only light collection. It uses the same
position rebasing, sRGB-to-linear color, `energy × source_power_per_energy`, decay,
priority/ranking, shadow flag and 27-entry slice as the unchanged source method;
for a Spot it reads `spot_range` instead of `omni_range`.

Omni inputs are numerically identical to the source collector in the contract
test. Spot fixtures reach the liquid/droplet input exactly once. There is no extra
renderer light and no double native illumination. Neither droplet optics nor the
photon solver gains an angular cone: both still receive the original **point
approximation**. The source `_effective_lamps` / `SourceCaustics.set_lamps` also
retain their original **two effective photon-lamp** limit, unlike the 27-entry
liquid/droplet collector. With the current room catalogs these are the first two
alive fixture entries, not all native fixtures. Candidate fixture reordering can
therefore change photon inputs and the stable first-four shadow selection and
must be deliberate. Photon selection/formulas and source physics are untouched.

## Reproducible Blender native-shape diagnostic

`tools/blender/reference_wing/native_light_proxy.py` can be imported into a source
candidate with `apply_native_proxy(scene, geometry_dict, watts_per_energy=100.0)`.
It hides all author lights in memory and creates one Blender POINT/SPOT per native
fixture, with matching positions/directions, double the Godot half-angle, the
native spherical radius, and decoded native sRGB color (which restores authored
scene-linear RGB when the metadata says `linear`). It preserves geometry,
materials/emission, world, camera and exposure. It never saves a source file.

CLI, without rendering:

```sh
blender -b tools/blender/reference_wing/water_sources/octagonal_bath.blend -t 4 \
  --python tools/blender/reference_wing/native_light_proxy.py -- \
  --geometry assets/models/reference_wing/octagonal_bath.geometry.json \
  --report output/reference_wing/bath_native_proxy.json
```

Add `--render output/reference_wing/bath_native_proxy.png --samples 24 --resolution
512` only when the shared render slot is available. The image is stamped as a
Blender proxy, not a Godot/NVIDIA result. Its report retains author area Watts and
native energy separately, plus all actual proxy bindings.

The fixed diagnostic convention is **100 Blender Watts per native energy unit**.
It is not photometric equivalence: e.g. the current stair 24 W author area light
has native energy 4, so this diagnostic uses 400 W, not 24 W. Stair energy has not
been natively calibrated. Lounge's retained native energy 1 is provisional,
separate from its 160/70 W author lights. No silent .24 stair retune or lounge
intensity optimization is included. Godot/Blender cone-falloff functions, inverse-
square normalization, range cutoff, emissive bounce, tone mapping and indirect
transport differ; some Blender light controls are renderer-specific. The helper
tests shape/footprint assumptions, **not matching brightness or final glints**.

## Validation and remaining acceptance

Run the actual production node/collector contract:

```sh
python tests/reference_wing/lighting_run_contract.py
blender -b --factory-startup --threads 2 \
  --python tests/reference_wing/lighting_blender_contract.py
```

Reports: `tests/reference_wing/lighting_contract_report.json` and
`lighting_blender_report.json`. They include exact source/geometry fingerprints,
binding parity between GDScript/Python, real native transforms/energy, quality
toggles, cross-mode lifecycle, freed/rebuilt rigs, actual `add_room` light caching,
and original Omni versus new Spot liquid-input tests. They require no editor
import, GPU, cloud renderer, PC connection or original-water configuration.

Still unverified here: custom 4.8/NVIDIA shader execution, native screenshots,
GPU frame times, final brightness/glints, and the visual consequence of only four
raster shadow maps. Unshadowed raster lights can leak through occluders even when
their positions/directions are correct. The user's local fixed-camera raster/PT
review is the acceptance stage; author-only AREA renders cannot substitute for it.
