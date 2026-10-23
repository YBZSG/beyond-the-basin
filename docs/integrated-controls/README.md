# Integrated production controls verification

Status: actual-production CPU/Jolt integration PASS on 2026-10-22 at 21:24 UTC. Full matrix: 80 trajectories, no failures, empty stderr and normal exit 0. The serial engine slot was released to the owner at 21:24:44 UTC. This test does not replace the owner's full-game rendered bath/wade/carry acceptance.

## What is actually exercised

`tests/integrated_controls/production_controls.gd` instantiates the production Player, Avatar, Props and unchanged hand-IK directly. It does not extend a candidate Player/Avatar, compile a patched source string, change a solver, force bone poses, overwrite gait phase or manually set swimming flags. A runtime identity check confirms that Player/Avatar instances use the production scripts.

The fixture executes the exact production controller callback once per genuine 120 Hz Jolt step. Its imported model's actual AnimationTree and IK callback are sampled at 15, 30, 60 and 120 Hz; the physics rate does not change. These are CPU animation samples, not rasterized/rendered frames or display frame-rate measurements.

Both the new default V2 asset and the separately selectable metric-cloth asset are loaded. Metric cloth uses the same production finish application as Main and must apply to exactly two surfaces. Source checks independently confirm Main's V2 selection and default-on depth response. Main itself is not instantiated by this isolated fixture.

## Bounded matrix

- Dry, 0.44 m and 0.94 m supported walk/sprint, at all four update rates, with both assets: 48 trajectories.
- V2 duck/egg/ball and metric-cloth duck: both strafe directions, all four update rates; left-side cases use a 0.94 m bath and right-side cases are dry: 32 trajectories.
- Every carry trajectory includes real unheld strafe/stop, backward tilted pickup/approach, held strafe/stop, wheel direction/zero-factor/fractional-factor/minimum/maximum clamp, remote relaxation, near return, stationary release, and collision restoration after separation.
- Each wading trajectory includes surface-height noise of ±5 cm, acceleration, steady movement, stop, idle and resume. It checks feet support, no false swim/deep latch, stable clip state, actual speed, distance-spaced footfalls, gait-phase integration, and identical travel/phase/event count across animation update rates.
- Every evaluated skeleton pose must be finite. Arm segment lengths remain within 0.1 mm of the imported rest rig. Settled carry keeps genuine palm error below 25 mm and contact weight above 0.9; CPU-skinned visible hand radial contact is within 3 mm and penetration is at most 3 mm. Stored/displayed yaw must agree; stationary remote/release yaw swing must remain below 0.01 rad.

The counts describe this finite matrix, not universal proof of natural movement. In particular, the approved shallow sprint cadence remains fast. Numeric contact and continuity are not a substitute for visible foot planting, soft animation transitions or human review of pickup rotation speed.

## Exact differences from the game

The room is a flat Jolt collision box. The water interface returns a controlled terrain depth, optional sinusoidal surface-height noise and zero current. It has no SWE/MPM state, solver, impulse methods, GPU resources, production room geometry, source-water interactions, stairs, camera input/rendering, reflection effects or audio. Props retain their production rigid-body integrator, shapes and original geometry, but production active-set scheduling is not attached. Input actions and wheel events are injected into the actual controller; pickup is called through its production method rather than a camera-selection ray. This isolates control/animation integration and intentionally leaves full-game environment acceptance with the owner.

## Reproduction

Source-only audit, safe while the engine slot is occupied:

    python tests/integrated_controls/static_contract.py

After explicit release from the native owner, with no other Godot process:

    python tests/integrated_controls/run.py --slot-released --parse-only
    python tests/integrated_controls/run.py --slot-released --quick
    python tests/integrated_controls/run.py --slot-released

The runner refuses a known concurrent Godot process, isolates runtime HOME/cache, stops on script errors, bounds elapsed time and retains stdout/stderr/execution reports. All production source/model hashes are checked before and after. Quick runs only the 15 Hz slice and is never labeled as the full four-rate result. No delivered baseline file or existing test is changed by this work.

## Executed observations

The full run completed in 92.12 seconds with peak child RSS 357,704 KiB (349.32 MiB). This is the bounded fixture's cost, not gameplay FPS or a performance promise. Production and model hashes did not change. The 39,596 actual animation/IK samples were finite; phase integration, render double-integration and normalized Walk/Run/Wade clip-seek errors were all zero. Identical travel, phase and footfall counts were observed across all four sampling rates.

| Supported depth | Actual walk speed | Actual sprint speed | Distance-implied walk cadence | Distance-implied sprint cadence |
| --- | ---: | ---: | ---: | ---: |
| Dry | 1.650008 m/s | 3.799995 m/s | 172.17/min | 190.00/min |
| 0.44 m | 1.247278 m/s | 2.194022 m/s | 142.55/min | 250.75/min |
| 0.94 m | 1.019057 m/s | 1.691939 m/s | 116.46/min | 193.36/min |

Cadences above derive from measured steady travel and unchanged stride; actual footfall event spacing was separately verified within one physics tick. They are not counts extrapolated from a short sample window or claims of human physiological realism. The 0.44 m sprint remains a fast gait by design; this integration proof does not resolve that broader art/tuning question.

- No ground-loss, swimming or deep-latch ticks in the supported steady intervals, including ±5 cm surface noise. The animation state did not flap.
- Final-quarter-second settled near grips had minimum contact weight 0.994999 and maximum palm error 1.267 mm.
- Maximum sampled visible-hand conservative radial penetration was 0.5003 mm, below the unchanged 3 mm gate. No torso proxy overlap was detected at the sampled settled poses.
- Maximum arm-length error was 0.000238 mm, and stored/displayed body-yaw mismatch was 5.95e-8 rad. Stationary remote/release drift was numerically negligible and below the 0.01 rad gates.
- The most abrupt backward-duck pickup rotation was 0.4192 rad per 120 Hz physics step. It was continuous and retained finite geometry; whether its speed feels natural remains a rendered/perceptual question.

The first quick attempt passed its six V2 wading trajectories, then stopped on a test-only Godot typed-array ternary assignment error. Only the new fixture's array construction was corrected. That initial log and execution receipt remain under `initial-fixture-error/`; the subsequent 20-trajectory quick slice and full 80-trajectory matrix both passed. No production fix, threshold relaxation or solver alteration was made in response.

Evidence: `summary.json` contains concise observations; `production-report.json` retains every actual animation/IK sample, footfall events and per-trajectory results; `production-execution.json` records process outcome and source hashes; `production-stdout.log` and `production-stderr.log` are the engine output. `static-contract.json` verifies production wiring and identical V2/metric-cloth node/skin/animation definitions. `quick-*` retains the passing 15 Hz slice.

Remaining owner gate: complete the actual native full-game trailing far-scroll, near-return, release and clean-quit sequence. The earlier full-game run's reported SIGKILL is not repaired or explained by this passing headless fixture.
