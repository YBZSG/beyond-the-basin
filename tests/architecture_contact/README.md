# Architectural contact and continuous native walking QA

This is a diagnostic harness, not a change to the game, source water algorithms,
controller, materials, production quality settings or authored geometry. Final
geometry is read from the real exported GLBs and geometry.json, never substituted
with test primitives. Old evidence stays in its original output directory.

## Headless contact and route contracts

Run only after the parent has completed the final asset import:

```sh
mkdir -p /tmp/poolrooms-contact-qa-home /tmp/poolrooms-contact-qa-cache /tmp/poolrooms-contact-qa-data
export HOME=/tmp/poolrooms-contact-qa-home
export XDG_CACHE_HOME=/tmp/poolrooms-contact-qa-cache
export XDG_DATA_HOME=/tmp/poolrooms-contact-qa-data
GODOT=/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64
"$GODOT" --headless --path . --fixed-fps 120 \
  --script res://tests/architecture_contact/contact_contract.gd \
  -- --output=res://output/contact-walk/contracts
```

Checks cover:

- Every exported BOX proxy mesh in all three rooms corresponds to the final
  geometry metadata and an actual production BoxShape3D collider.
- Exact correspondence consumes a multiset of bounds rather than treating duplicate
  Blender names as unique. Godot decimal-name sanitization is handled explicitly.
- Every repaired Lanes pier is probed against actual visible mesh triangles:
  basin floor, embedded footing bottom, footing top, shaft underside, side face.
- All 24 portal jamb lips are checked against actual exported stair triangles.
- Twelve outboard north/west wall-base queries verify real production-built
  adjoining rooms with architecture-only physics rays.
- Every shaft excludes water in the actual source solver's CPU depth preparation
  at Medium and High grid sizes, using production collision shape geometry.
- Continuous authored water depth is zero inside shafts, .36 m above exposed
  footings, and .54 m in the adjacent basin. The .14 m lip is finer than the
  Medium .25 m grid; quantization is reported, not hidden or silently altered.
- The actual unmodified PoolPlayer physically approaches and presses into all
  eight repaired piers and retreats, including underwater approaches.
- One continuous route uses automatic player physics and normal movement input,
  without any position or velocity writes after the initial spawn.
- Existing three-room dry perimeter, portal stairs, basin stairs, circular
  gateway and between-room regression routes retain their original tolerances.

The inherited authored-depth sampler is explicitly not GPU optical water.

## Native graphical capture (serial launch owned by parent)

```sh
"$GODOT" --path . --rendering-method forward_plus --rendering-driver vulkan \
  --fixed-fps 8 --resolution 768x480 \
  --script res://tools/poolrooms_wing/native_contact_walk.gd \
  -- --output=res://output/contact-walk/native
```

Run on the approved cloud renderer, not an arbitrary execution terminal. It is
one Lanes room, with the real GLB, RoomBuilder, materials, lights and source
SWE/detail/photon-caustics/planar-reflection pipeline. It reuses the existing
SurfaceOpticsOnly allocation boundary: no avatar, MPM splash, volumetric splash
compositor, cubemap or full-world streaming. SDFGI is disabled only inside this
diagnostic; source optics use the existing Medium preset unchanged. Doorway
continuity is not accepted by this single-room capture and needs the separate
connected-room review.

The fixture explicitly sets max_physics_steps_per_frame to 32. `--fixed-fps 8`
advances 120 Hz real controller physics with up to 15 physical steps per rendered
frame. The JSON records actual physical ticks, integrated simulation time,
positions, eye position, inputs, wet/grounded/wall state and locomotion epoch.
It does not infer simulation progress from image count. Frames are RETIMED
DIAGNOSTIC EVIDENCE, NOT a real-time FPS or hardware-performance result.

Only initial placement calls warp_to. Thereafter the fixture applies forward
input and yaw/pitch look input; the unmodified controller owns acceleration,
gravity, floor snapping, actual .32 m-radius capsule collision and the camera's
1.6 m eye with its normal step smoothing. The route descends the actual north
basin stair, crosses the basin, presses against a submerged pier, stops, turns,
retreats and returns up the same stair to dry ground. A separately labelled
external camera provides the low contact angle after the route. This camera is
not presented as player movement and does not move the player.

Outputs include per-phase first-person PNGs, a bounded 8 fps frame sequence,
external low-angle PNG, and native-contact-walk.json. Encode the frame sequence
at its declared simulation rate, e.g. `ffmpeg -framerate 8 -i frames/%04d.png ...`.
Do not call the encoded video real-time FPS. Use `--no-frame-sequence` for the
same motion with snapshots and trace only. Use `--dry-contact-geometry` for an
explicitly dry geometry diagnostic; it does not claim source-water acceptance.

## Genuine keyboard interaction

Omit `--fixed-fps` for ordinary wall-clock interaction and add `--interactive`:

```sh
"$GODOT" --path . --rendering-method forward_plus --rendering-driver vulkan \
  --resolution 768x480 --script res://tools/poolrooms_wing/native_contact_walk.gd \
  -- --interactive --output=res://output/contact-walk/interactive
```

WASD moves the actual player, mouse looks, Shift sprints and Space jumps.
Escape releases mouse capture; click to resume; F10 saves report and exits.
No replay or autonomous path driver runs in this mode. This is still the same
bounded single-room diagnostic, not a substitute for full-world acceptance.

Headless input validation injects real events and proves jump/Esc/click routing.
Captured mouse rotation is explicitly skipped when the display backend cannot
capture a mouse; the report does not claim interactive mouselook acceptance.
