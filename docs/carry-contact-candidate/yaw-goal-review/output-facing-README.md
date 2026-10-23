# Near-carry contact candidate (isolated, not applied)

## What is being repaired

The actual `authored-depth-native-01/native-v2-held.png` shows a sideways duck and floating palms. Its report records requested wrist distances of 0.51078 / 0.51052 m versus an unchanged maximum reach of 0.47271 m. The honest reach fade reduces contact weight to 0.31558, leaving 75.3 / 60.0 mm palm error. The old regression spawned every duck at yaw 0.37 and did not expose arbitrary pickup yaw.

`PoolPlayer.grab_prop` currently removes duck roll/pitch but preserves pickup-relative yaw. `AvatarHandIK` correctly uses support points on the complete original compound duck hull. A sideways or backward duck can therefore put a support point on the distant head/beak instead of the near side of its broad body. Extending bones, shrinking the duck or disabling reach fade would hide the cause rather than repair it.

## Minimal candidate

`avatar_carry_contact_candidate.gd` requests identity local carry orientation only for ducks. The existing `PoolPropBody` 18/s quaternion servo smoothly presents the duck forward. It does not teleport the prop at pickup; it leaves egg/ball pickup orientation, prop dimensions, camera, hold anchor, collision, release/throw and free buoyancy unchanged.

The separately tested second-stage option makes the visual body face the carried object using the existing hold blend. This addresses an independent edge: the current visual body retains prior strafe yaw even while stationary, and permits a ±0.26 rad twist while carrying. It does not move individual shoulders or modify bone lengths. Orientation-only must be evaluated before opting into this second stage.

No production Player, Avatar, Main, HandIK, water or model file is edited by this candidate. The test uses in-memory subclasses and the current imported V2 avatar with the original 42-bone rest rig. `integration.patch` combines the tested orientation and visual-facing changes. `orientation-only.patch` retains the narrower first experiment. Both are supplied for review only and neither is applied.

## Evidence and status

- `geometric-yaw-sweep.json`: CPU-only exact serialized V2 rest rig and unchanged native duck compound geometry; 25 pickup yaws × 3 body yaws × 3 camera pitches per variant. This is reach analysis, not a Jolt or rendered acceptance result.
- At zero torso twist the forward-facing duck requests 0.43644 m wrist reach at default pitch and 0.45560 m when looking down, both within the existing 0.47271 m maximum.
- Runtime fixture: `tests/carry_contact_candidate_runtime.gd`, actual production controller + Jolt props + unchanged IK + V2 AnimationTree, sampled at 15/30/60/120 Hz, with CPU-skinned hand and torso checks. Synthetic shallow-water flags exercise the authored Wade clip; this does not claim production SWE/MPM or GPU/native appearance validation.
- Full combined candidate runtime: **252 cases passed, zero failures**, sampled at 15/30/60/120 Hz. Report: `runtime-facing.json`; execution/resource receipt: `runtime-facing-execution.json`. This uses the helper's canonical duck orientation and whole-visual-body facing blend; neither shoulder translation nor arm stretching is used.
- Worst settled palm error: **0.03474 mm**. Minimum near contact weight: **0.99999979**. Worst per-hand visible scaled-radial gap: **0.04363 mm**. Worst settled visual penetration: **0.55690 mm**, below the unchanged 3 mm threshold.
- 42,952 sampled arm-geometry frames: maximum upper-arm length error 0.000253 mm; forearm error 0.000126 mm. All remote grip weights reach zero; pickup leaves the prop basis exactly unchanged at the call boundary.
- Twenty-four sampled tilted/backward-duck approach checkpoints: no torso overlap, no visible hand penetration deeper than 3 mm (worst conservative scaled-radial penetration 1.443 mm). The existing rotation servo remains in use; actual rendered pickup timing still needs native review.
- Candidate runtime completed with exit 0 in 94.54 seconds, peak resident set 88,416 KiB (86.34 MiB). This is headless fixture cost, not a gameplay performance claim.
- The matched full baseline retained **328 failed assertions across the same 252 cases**. `matched-comparison.json` verifies both variants use identical production/model hashes and case identities; baseline failure is expected-failing regression evidence. The orientation-only comparison removes the sideways-duck failure but does not fix the independent prior-strafe / carry-twist issue.
- Native camera appearance / complete production-water acceptance is still pending the owner's separate run.

## Runtime commands (only after serial-slot permission)

Use Godot 4.6.3, `--headless --path . --fixed-fps 120 --script res://tests/carry_contact_candidate_runtime.gd -- --variant=baseline --quick`, then repeat with `--variant=orientation`. Baseline failure is expected and retained as regression evidence, not counted as a candidate pass. The complete candidate matrix omits `--quick`; the optional body-facing variant is `--variant=facing`.

The fixture retains strict existing acceptance thresholds: settled palm error <25 mm, contact weight >0.9, no visible penetration deeper than 3 mm, visible surface contact within 3 mm for each hand, no torso proxy overlap, no arm stretching, remote hands relax, release/throw collision restoration, and no player self-launch. Model and source hashes are recorded in every runtime report. Rendering/native acceptance remains the owner's next gate even if the isolated fixture passes.


## Regression interpretation and integration handoff

The final orientation-only quick run has 27 failed assertions, all confined to current held-strafe or prior-strafe visual-body yaw. Its four cardinal duck pickup yaws now have full settled reach. The same 55 quick cases on the unchanged baseline have 68 failures; the combined candidate has zero. The complete matched baseline/candidate runs have 252 cases each and identical production/model input hashes. Baseline side-facing duck palm errors remain roughly 68–73 mm across 15/30/60/120 Hz; the candidate closes these without changing the 0.47271 m reach limit.

Apply `integration.patch` only after reviewing it. It adds a helper import and a duck orientation policy in Player, and a helper import plus one visual-yaw expression in Avatar. It changes no Main, HandIK, PropBody, camera, prop scale, hold distance, model/skin data, or original source-water implementation. The test's `FacingAvatar` suppresses the first unchanged hand solve, evaluates the same authored animation, changes only the visual model yaw, then runs the unchanged solver once. The patch performs that same visual-yaw choice before the authored clip sampling and single solver call.

The remaining acceptance gate is a native image/clip in the actual authored bath with this patch applied by the owner: arbitrary-yaw duck pickup, 15/30 Hz approach timing, first-person hands, third-person torso turn/relaxation, scrolling away and dropping. The existing exponential quaternion servo can rotate a backward duck rapidly at the beginning of pickup (maximum measured physics orientation step 0.4192 rad at 120 Hz); it is mathematically continuous and did not penetrate in sampled checkpoints, but visual naturalness is not established by this numerical fixture.

Execution note: Godot uses an isolated writable temporary HOME/cache for this fixture. Initial environment setup and a typed-array fixture issue were corrected before the recorded final numerical comparisons. No production code was modified. The test compares copied pickup bases exactly instead of using a quaternion self-angle, which can report about 0.00069 radians from floating-point roundoff even when the underlying basis is unchanged. This corrects the measurement, not the no-teleport requirement.
