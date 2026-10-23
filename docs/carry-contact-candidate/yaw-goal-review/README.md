# Carry yaw-state integration review

The first output-only body-facing candidate is superseded. It passed the prior 252-case hand/contact matrix, but that matrix did not assert body-yaw continuity on release. Do not interpret its contact pass as full animation acceptance.

## Confirmed bug

After an actual unheld strafe and stop, internal `_body_yaw` remains about ±π/2. The first candidate displayed `facing_yaw(_body_yaw, _hold_blend)` but left this state stale. On drop or remote scroll, decaying hold blend reveals the old angle. Actual Jolt traces measured up to **89.9890°** of uncommanded stationary release rotation, **14.9146°** after held strafe, and a comparable remote-scroll rebound. The old candidate fails 168 new yaw assertions over the same 72 cases. All these failures are yaw consistency/continuity assertions, not contact regressions.

## Narrow correction

Blend `wanted_yaw` toward forward with the existing hold blend **before** the existing 10/s exponential `_body_yaw` update. Preserve `_model.rotation.y = _body_yaw` without an output-only correction. The stored state therefore follows the displayed orientation, while normal movement yaw and existing transition rates remain authored. Duck presentation still uses the unchanged rigid-body orientation servo; no geometry, shoulder translation, forced reach, camera or carry-distance edits are involved.

`integration.patch` is not applied. The prior output-only patch is retained as `output-facing-integration.patch`; its original passing fixture is preserved in `passed-output-facing-runtime.gd.txt`. The current runtime fixture retains the old `facing` variant for direct comparison and compiles the exact new yaw-goal insertion into an in-memory production Avatar script for `yaw_goal`.

## Actual numerical result

- 72 corrected cases pass with zero failures: duck/egg/ball × 15/30/60/120 Hz × both strafe directions × stationary drop, held-strafe drop, remote return.
- Maximum stationary release drift after prior strafe: **0.001070°**. Held-strafe/remote-return release drift is below 0.00000005°.
- Maximum stored/displayed yaw difference: **5.96e-8 radians**, versus the superseded variant's approximately π/2.
- Near grip/contact, CPU-skinned hand/torso checks, remote relaxation and arm lengths remain strict. Maximum corrected upper-arm length error: 1.94e-7 m; forearm error: 1.26e-7 m.
- The inputs and case identities match exactly; see `matched-yaw-comparison.json`. Full per-visual-sample traces are preserved in `runtime-facing.json` and `runtime-yaw_goal.json`.
- Corrected focused run: exit 0, 45.46 s, peak RSS 169,424 KiB (165.45 MiB). Superseded run: expected exit 1, 45.67 s, 167,560 KiB. These include trace retention/JSON and are not game performance measurements.
- Seven CPU contracts pass; the proposed patch passes `patch --dry-run` against unchanged production files. Parse log is clean.
- `scalar-state-replay.json` is earlier code-equation evidence only, not a second actual-physics measurement.

The parent owns native rendered acceptance. This numerical fixture does not establish first-person appearance, complete source-water behavior or perceived pickup/turn timing.

## Reproduction (serial engine slot required)

Run `python tests/carry_contact_candidate_runner.py --variant=facing --yaw-release` (expected failure), then `--variant=yaw_goal --yaw-release` (expected pass). The full original contact/skin matrix is `python tests/carry_contact_candidate_runner.py --variant=yaw_goal`. No production script is modified by these fixtures.

## Full carry matrix recheck

The corrected goal-before-state variant also passes the unchanged **252/252** contact/geometry cases with zero failures, at all four sample rates. The baseline has 328 failed assertions on the identical case identities and production hashes. Worst settled palm error is 0.03474 mm, minimum contact weight 0.99999979, maximum settled visible penetration 0.55690 mm. All 42,952 arm-geometry samples pass; the 24 approach skin checkpoints retain zero torso overlap and no hand penetration over 3 mm. The full corrected run exited 0 in 89.54 s, peak RSS 88,884 KiB (86.80 MiB). See `contact-matched-comparison.json` and `../runtime-yaw_goal.json`. The root `../integration.patch` now matches the corrected patch here, not the superseded output-only version.

The serial engine slot was explicitly released to the parent at 2026-10-22 20:20:06 UTC. No production file was edited by this work.
