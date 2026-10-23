# Single bath aperture/return redistribution

Status: **completed and rejected**, see [RESULTS.md](RESULTS.md). No production edits. This is one bounded
candidate, not a new lighting system or another GI bake attempt.

## Why this candidate

The current authored circular bath has a 3.6 m oculus and an 18.32 m outer diameter
vault. The actual native off/GI comparison and full-game bath screenshots show
nearly uniform grey plaster. SDFGI/voxel availability by itself is not evidence
that the room gains believable directional illumination.

The previous `aperture-balanced` candidate reduced ambient to 0.09 and increased
the same wide, central lights. Its native images remain flat; only its separate
safe basin-return shadow-off correction was retained. This study preserves that
accepted correction and changes **distribution**, not exposure or material gloss.

Inputs inspected as actual pixels:

- `docs/native-gi-cost/run01/off_before.png` and `sdfgi_4.png`: instrumented room
  without water, including a synthetic red GI control. Not beauty references.
- `output/current-water-feel/bath-aperture-native-01/study-*.png`: prior rejected
  broad-energy candidate and accepted shadow-off variant.
- `output/current-water-feel/water-feel-far-drop-640-01/` frames: actual water,
  duck and avatar images. These are mostly down-facing water views and do not
  establish ceiling acceptance.

## One fixed authored candidate

Keep the existing four local lights, actual sun, all colors, source positions,
glass, geometry, materials, exposure and rendering feature settings. Change:

| Existing component | Baseline | Candidate |
| --- | --- | --- |
| Bath active-room ambient | 0.18 | 0.11 |
| Two oculus native omni fills | 0.50 each | 0.12 each |
| Existing downward `BathOculusSky` | energy 0.65; angle 73; angle attenuation 0.3 | energy 2.0; angle 72; angle attenuation 0.65 |
| Existing `BathBasinReturn` | centre at (0,0.45,0); energy 0.55; angle 84; range 12; attenuation 0.8; angle attenuation 0.3 | actual sun-footprint centre at y=0.45; energy 1.55; angle 74; range 10.8; attenuation 1.0; angle attenuation 0.6 |

The return origin is computed from the real directional sun ray through the
oculus centre at y=6.025, intersecting y=0.45. It must remain inside a 4.2 m radius
within the basin or binding is rejected. It is not an arbitrary camera-relative
light. Its shadow remains off, including `desktop_authored_shadow=false`, and its
specular, indirect and fog contributions remain zero. Existing direct shadows
stay on. No light or shadow-map owner is added.

This redistributes an authored diffuse approximation. It is **not** a physically
flux-calibrated area-light integrator, solved water bounce, or a claim of more GI.
The native omni energy change also changes their collected analytic liquid-light
inputs in a full-game test. That illumination change is intentional. Photon
`layout.fixtures` positions/order/powers, photon formulas, source-water solver
math, and shaders are unchanged. Do not describe all water illumination as exact.

## Reusable reversible helper

`tests/bath_daylight/candidate.gd` is callable after the standard bath transition
tween settles: `bind(lighting, bath_room)`, `apply()`, `restore()`.

Binding requires the actual active formal bath, existing expected light types,
the real sun and a valid footprint. It takes the original snapshot once; rebinding
is rejected. Applying is idempotent. Restoration checks exact equality of the
saved environment/light values, metadata, identities and photon fixtures.
The helper is test-only and is not wired into travel, quality switching, or saved
preferences. It must not be left attached across room transitions.
For a later real-game use, explicitly notify the existing capture owners after
each final state change and wait for newly published cube/planar optics. The
isolated fixture refreshes the existing native fallback reflection probe equally
in every phase so it does not retain stale baseline metal reflections.

## Verification and bounded stopping condition

1. Static preflight without launching an engine; parse/configuration contract is
   prepared separately and still requires the serial engine slot.
2. One native isolated baseline/candidate/baseline sequence at 640x360, same
   three cameras: entry-wide, roof, wall closeup. Current GLB via the production
   builder/materials/light rig, 2x MSAA, no TAA, no new control objects. Water is
   absent, never replaced. SDFGI, SSIL, SSR, glow and volumetric fog are disabled
   equally, caustic gain explicitly zero because there is no live atlas.
3. Owner visually inspects the actual PNGs. Reject if it merely darkens the room,
   crushes portal/bench/stair readability, causes visible cone bands or noisy
   shadows, or fails to create convincing aperture-driven gradients. Pixel stats
   can support that decision but cannot choose the art direction.
4. Only if useful, request a separate serial actual-game A/B with real water
   optical publication. No acceptance from this isolated room alone.
5. No automatic parameter search or second candidate. Restore and stop on failure.

Native runner caps: 300 seconds and sampled 3 GiB RSS watchdog, one global engine
slot lock plus process precheck, fresh output tag, source hashes before/after.
The CPU-only contract caps at 75 seconds. These are watchdog bounds, not hardware
VRAM or target-GPU FPS measurements. Native visual launch must use the supported
graphical cloud terminal, not a fabricated DISPLAY or namespace workaround.

Original prepared commands (the valid CPU execution uses `contract02`; `contract01`
records the corrected Float32 expected-value assertion issue):

    python3 tests/bath_daylight/run.py --contract --tag contract01 --native-slot-granted
    python3 tests/bath_daylight/run.py --tag isolated01 --native-slot-granted

`--describe` is safe and never launches an engine. All authored files and outputs
stay under `tests/bath_daylight/` and `docs/bath-daylight/`.
