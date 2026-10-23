# Deeper-only wading response candidate

Status: staged and NOT integrated. Source/equation and actual-controller native contracts PASS. The native-test slot has been released. No rendered or perceptual approval is claimed.

## Chosen response

Preserve the existing 1.25 m/s walk and 2.2 m/s sprint through 0.40 m terrain depth. Smoothstep down to 1.00 / 1.65 m/s by 1.05 m. Remain bounded there for supported deeper wading. These values are deliberate gameplay tuning, not measured physical drag or a replacement water solver.

This is narrower and more conservative than the earlier staged 0.85 / 1.35 m/s curve. Importantly, it does not interpolate back toward dry speed in negligible water, which would produce about 188 walking footfalls/min with the unchanged wading stride. Shallow water retains the delivered response exactly.

| Stable terrain depth | Walk m/s | Sprint m/s | Walk footfalls/min | Sprint footfalls/min |
| --- | ---: | ---: | ---: | ---: |
| 0.02–0.40 m | 1.250 | 2.200 | 142.9 | 251.4 |
| 0.84 m side pool | 1.061 | 1.785 | 121.3 | 204.0 |
| 0.94 m bath | 1.019 | 1.692 | 116.5 | 193.4 |
| 1.04 m original expanded bath | 1.000 | 1.650 | 114.3 | 188.6 |

All cadences use the existing 0.525 m distance per footfall; values are steady-state predictions, not measured native results. The unchanged shallow sprint cadence remains fast. Fixing that would require a broader coordinated gait/footstep change, intentionally outside this candidate.

## Boundaries

- Three small Player insertions: preload, default-off exported flag, and guarded speed selection. Review-only patch: `integration.patch`.
- Only the existing in-water speed branch calls the candidate. Dry movement and existing acceleration/deceleration remain unchanged.
- Require the runtime's `depth_at` method before using the candidate. Do not use the legacy ripple/feet-height fallback for this response.
- The entire `_deep_water` latch bypasses the curve, not just instantaneous `_swimming`. Swimming, swim jumps and short transient non-swimming phases inside deep water retain the old water speed.
- Swim hysteresis remains enter 1.25 m / exit 1.10 m. The spring, thresholds, root, collision capsule, stairs and camera are untouched.
- No gait time multiplier, no animation slowdown, and no frame-rate throttle. Actual movement slows; the unchanged distance-driven Avatar and footfalls consume that actual travel.
- SWE/MPM, source-water impulse formulas, audio/event policy, models, and Avatar source are untouched. Existing speed-dependent impulses and event strengths naturally evaluate the lower actual movement speed; their algorithms are not replaced.
- Disable `depth_wading_response_enabled` at runtime to restore old speed selection. Removing the three insertions also removes the integration completely.

A transition into genuinely deep water changes movement mode and therefore may select the original 1.25 / 2.2 m/s swimming target. The existing acceleration bounds the resulting velocity change. The curve is monotone within the supported wading mode, not across mode switches.

## Reproduce

CPU-light source/equation audit and regeneration of the non-applied patch:

    python tests/wading_depth_candidate_prepare.py

Only after the coordinator releases the native-test slot:

    python tests/wading_depth_candidate_run.py --slot-released

The native test loads the real Player source, applies the exact three patch insertions in memory, removes only its duplicate global class declaration, and executes that actual controller with real Jolt collisions. Original, disabled and enabled variants share the real imported Avatar and AnimationTree. It verifies:

- Dry, shallow 0.20/0.40 m, side pool 0.84 m, bath 0.94 m and original 1.04 m walk/sprint.
- Exact disabled versus unmodified original controller traces.
- Monotone bounded helper response, smooth joins, invalid-sample safety, deep-latch bypass.
- Actual physics speed, acceleration/deceleration, stop/resume, distance footfalls and wading half-cycle alignment.
- Horizontal-water/physical-collision-ramp entry and exit under normal movement input.
- 5 cm noisy waves over the 0.94 m bath with stable terrain depth.
- Genuine deep flotation and swim jump, comparing enabled/disabled against original frame by frame.
- Runtime disable/re-enable.
- 15/30/60/120 Hz Avatar updates over the project's unchanged 120 Hz controller/Jolt. All render rates must produce identical distance, gait phase and footfall count. This is not a test of changing the project's physics rate.
- No source/model mutations during the run.

Evidence is written under this folder. The full-game motion/contact capture remains a separate acceptance gate; a numerically slower gait does not prove improved visible sole planting or water contact.

## Executed verification

Godot 4.6.3 native headless run: exit 0, 204 cases, 354,281 checks, zero failures, empty stderr. Final run took 155.46 seconds; peak child RSS was 454,616 KiB (about 444 MiB). All four Avatar update rates passed with the project’s unchanged 120 Hz Jolt/controller.

- Every disabled trace matched the actual unmodified original controller exactly for the recorded numeric/state fields. Enabled deep-water traces also matched exactly, including swim jumps and transient non-swimming states inside the deep-water latch.
- Maximum distance-phase integration error, render double-integration error, and normalized clip-seek error were all 0.0. Footfall timing stayed within one physics tick of the wading half-cycle.
- At 0.94 m, measured walk speed averaged 1.019063 m/s, with 116.50 footfalls/min over the sampled steady forward interval. Sprint averaged 1.691937 m/s. The finite footfall-count observation window is not a new gait tuning value.
- No production Player, Avatar, Main, or model file changed. The review patch is still unapplied.

The first matrix exposed a test-only assumption: direction reversals use the original controller’s 10 m/s² braking rate while crossing zero. That assertion failed equally in original, disabled and enabled modes. The test now distinguishes reversal braking from ordinary 8 m/s² forward acceleration; the complete matrix was rerun, rather than accepting the failed run. The initial assertion failure summary is retained for provenance.

Key evidence:

- `run-summary.json`: native exit, elapsed time, peak RSS and unchanged production files.
- `controller-summary.json`: concise measured results and parity scope.
- `controller-report.json`: all 204 cases, footstep events and 10 Hz trace excerpts.
- `controller-stdout.log` / `controller-stderr.log`: actual native process output.
- `analytic-response.json` / `source-invariants.json`: CPU-light curve and unchanged gait/threshold invariants.

Still required before claiming the original water-feel complaint fixed: the coordinator’s full-game rendered motion/contact review after integration and enablement. This candidate proves coherent depth-dependent travel and cadence, not visible sole contact or source-water rendering quality.
