# Optional reference waves and camera look

## Scope and defaults

Both new switches default **OFF** and use a separate reference settings dictionary.
They do not reset, replace, or save over the existing wind, large waves, physics,
collision/depth, water color, reflection/refraction controls, or legacy camera look.
The first reference calls for directional mid-scale reflection breakup and edge RGB
separation; the second has an unfiltered, quiet corridor water surface. Neither
reference is evidence that a post-process can fix the ceramic material itself.

The existing wind modes are 0.48/0.23/0.115 m. The new modes are 1.8/0.95/0.52 m,
scaled by 0.6–1.6, moving at 0.24/0.21/0.17 m/s. At the default strength the summed
equivalent relief is about 4.8 mm; the hard maximum is 12 mm. This is explicitly a
**normal-only optical approximation**, not displacement or a new fluid simulation.
It affects the optical normal already used for reflection, refraction, Fresnel and
highlights. It does not alter silhouette, foam transport, caustic photon normals,
buoyancy, solver depth or collision. The existing refraction-offset clamp remains.

The modes use absolute world XZ and bounded integrated phases. There is no camera
anchor or solver-domain dependency. Direction and scale interpolate in world
coordinates; walking never drags the waves. Shallow depth and pixel footprint fade
the normal perturbation. OFF immediately gates the added slope to zero without
resetting phases or numeric settings. The controller never reads a GPU texture.

The reference look adds independently adjustable 0–8 output-pixel radial fringe,
0–0.02 centered grain and 0–0.16 vignette. Defaults are 0.8 px / 0.006 / 0.07. It
does not blur, boost exposure, denoise, or alter materials. The strong end of the fringe slider is an artistic lens effect matching the first reference; it is not optical water dispersion. The low default and OFF behavior are unchanged. Every screen-texture
sample has a half-pixel clamp and repeat is disabled. Grain may be frozen by the
QA-only reference_freeze_grain uniform. Existing Clean/CCD/VHS/Cold modes remain.

## Runtime adapter and parent integration contract

The render-only adapter and exact derived surface shader are supplied. The parent
owns choosing the PC runtime, the main UI, saved settings and world replacement.
Do not edit original source_water_runtime.gd: its hash belongs to the terrain-cache
identity. Do not change original source-water Settings.SLIDERS/LAYERS/DEFAULT.

1. Preload reference_look_settings.gd in the host. Initialize a separate dictionary
   with Settings.sanitize({}). Save/load it under its own config section. The
   sanitizer accepts malformed containers, drops unrelated keys, rejects wrong
   types/nonfinite numbers, clamps bounded values and wraps direction.
2. On PC, instantiate scripts/reference_wing/reference_water_runtime.gd, which
   extends the unmodified original runtime. It owns reference_waves and exposes
   set_reference_wave_settings(Dictionary) and reference_wave_status(). The
   controller never owns source settings or persistence.
3. The adapter overrides _apply_surface(material), switches only the known original
   and derived shader resources, publishes the reference uniforms, then performs
   the original material binding once. OFF or zero strength restores the exact
   original Surface resource. Diagnostic shaders are never replaced. Godot retains
   original material overrides across the resource swap; both isolated and actual
   production cold-state tests verify this behavior.
4. The adapter calls super._process(delta) exactly once. Its clock helper consumes
   each successful source _time publication once from _apply_surface, with a
   post-process fallback for frames with no surface materials. It uses the original
   configured, enabled, not-terrain-paused and terrain-ready guards. This follows
   readiness changes inside _pump_terrain rather than predicting them one frame
   early. Multiple rooms, quality rebinding and new surfaces cannot double-tick
   phases. There is no camera or solver-domain position input.
5. Main calls set_reference_wave_settings(values) on edits/world creation. This
   updates only shader identity and added optical uniforms, never original source
   texture bindings. Immediate OFF works while paused. It never invokes
   _bind_all, solver configure/step, caustics render, depth capture or readbacks.
6. The optional surface shader is derived from the untouched original with only:
   include res://shaders/reference_wing/reference_ripples.gdshaderinc; and add
   referenceOpticalSlope(worldPosition.xz, footprint, bed) to the existing optical
   slope used to construct N. Keep every original solver/height/normal calculation,
   reflection projection and refraction bound unchanged. OFF uses the original
   shader, so a new uniform or compiler branch cannot alter baseline output.
7. Replace the existing inline camera shader with reference_camera_look.gdshader,
   not a second pass. On desktop, use camera CanvasLayer 0 below HUD/menu layer 1.
   Main calls Settings.apply_camera(material, dictionary, legacy_mode) and sets
   rect.visible = Settings.camera_visible(dictionary, legacy_mode). The helper
   returns false for Clean + OFF and for Clean + all-zero reference intensities,
   giving a no-draw identity instead of merely copying screen pixels.
8. Keep Android on its original runtime/UI/shader path. Quality changes, menu
   toggles and world replacement must preserve the independent saved dictionary.
   A replacement runtime receives the dictionary once before its first publication.

## Automated checks

From the repository root:

    python3 tests/reference_look/test_source_contract.py
    python3 tests/reference_look/run_cpu_contract.py --report output/reference-look/module-contract.json
    python3 tests/reference_look/run_adapter_contract.py --report output/reference-look/adapter-contract.json
    godot --headless --path . --script res://tests/reference_look/production_parse_contract.gd

The second command copies only the new modules into an isolated temporary project,
uses official Godot 4.6.3 with the headless dummy renderer, and never starts the real
game, native extension or RenderingDevice. It checks numeric bounds/gradient,
phase integration, immediate OFF, independent switches, input validation, config
roundtrip, immutable submitted uniforms, a zero-effect bypass and a small Canvas
layout fixture at 720p, 1080p, portrait and ultrawide sizes. Its quality/menu checks
are module invariance checks, **not production UI integration tests**.

The adapter runner executes the actual adapter against an explicitly isolated
lifecycle double. It checks paused OFF, original uniform retention, diagnostic
preservation, all source guards, ready-during-pump, streamed surfaces and one clock
advance regardless of material count. It does not run the production solver.

The production parse contract loads the real base/dependencies and instantiates
the actual adapter, but deliberately leaves it unconfigured. It verifies inherited
API compatibility, original shader restoration and untouched solver/caustic/wind
state without constructing a world, invoking an import, or allocating GPU fields.

The source contract protects 22 original water/runtime/wind/SWE/terrain/caustic
files, including every terrain-cache algorithm and context source, with baseline
SHA-256 hashes. It also checks the original time/publication order and proves the
derived shader contains only the two documented optical additions. These checks
do not compile GPU shaders or certify the matching custom-engine pipeline.

## Target Windows visual test matrix

Use the user's custom Godot 4.8/NVIDIA build, identical room/camera/quality/exposure
and saved original wind values. Confirm materials with the new filter OFF first.

1. Hold the camera fixed on a tiled corridor and a visible reflected light. Capture
   a continuous 6–10 second segment with both additions OFF; then waves ON/look
   OFF; then waves OFF/look ON; then both ON. Do not use different rooms as A/B.
2. For each state capture a matched 30-frame, fixed-60-Hz sequence after 120 warmup
   frames. Record engine/device, room, camera transform, quality, wind/reference
   settings, render scale/TAA/RT/NR and the reference-wave phases. This is visual
   evidence, not a performance benchmark because capture causes readbacks.
3. Examine traveling reflection/refraction shape, shallow edges, stationary-camera
   shimmer, far-water aliasing, diagonal tile lines, and left/right screen borders.
   Walk and rotate with unchanged wave settings: ripples must remain world-fixed.
4. On a frozen comparison frame, toggle reference waves OFF and verify the exact
   original shader resource is rebound. Compare filter OFF against Clean and
   reference-enabled/all-zero against Clean. Those paths hide the post rectangle.
   Time-changing water cannot be assessed for pixel equality from unrelated frames.
5. Keep HUD/menu visible while enabling max fringe/grain: glyphs, crosshair and
   controls must remain clean and clickable. Resize 1280×720 → 1920×1080 →
   3440×1440, reopen menus, switch Low/Medium/High/Ultra, switch rooms, restart and
   reload settings. Verify zero resets to existing wind and independent controls.
6. Exercise legacy CCD/VHS/Cold with reference disabled, then enabled. Switching
   reference OFF must restore the selected legacy effect without changing it.
   Test camera-look slider zero values individually and all together.

No target GPU screenshots or custom-engine visual acceptance were produced in the
cloud. The environment has no display/graphics socket, and that restriction was
not bypassed. No synthetic imagery is presented as engine output.
