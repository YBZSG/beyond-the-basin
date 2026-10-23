# Near-carry contact candidate (isolated, not applied)

## Reviewed integration choice

Use **`integration.patch`**, identical to `yaw-goal-review/integration.patch`. This is the corrected **yaw-goal-before-state** variant. The earlier output-only visual-yaw variant passed hand/contact checks but failed the subsequently added release/remote body-yaw checks; it is superseded and preserved under `yaw-goal-review/output-facing-integration.patch`. Do not apply that old patch.

The corrected candidate passes **252/252** unchanged carry/contact cases plus **72/72** focused release/strafe/remote cases, with zero failures at 15/30/60/120 Hz. Seven CPU contracts and patch dry-run also pass. Production source, original water, model, camera, prop size and hand IK were not edited. Actual native rendered acceptance remains the owner's next gate.

## What caused the gap

The actual `authored-depth-native-01/native-v2-held.png` shows a sideways duck and floating palms. Its report records wrist requests 0.51078 / 0.51052 m versus unchanged maximum reach 0.47271 m, reach/contact weight 0.31558, and 75.3 / 60.0 mm palm error. Earlier pickup tests used only duck yaw 0.37, missing arbitrary pickup orientation.

`PoolPlayer.grab_prop` removes duck roll/pitch but preserves arbitrary relative yaw. `AvatarHandIK` correctly uses the full original compound duck hull; at sideways/backward yaw a far head/beak support point exceeds normal arm reach. The helper requests forward-facing duck presentation through the existing smooth 18/s quaternion servo, leaving egg/ball orientations intact. There is no pickup teleport, prop shrink, bone stretch, forced reach, anchor/camera shift or shoulder translation.

Orientation alone fixes the sideways duck but leaves a separate body-yaw edge: prior unheld strafe can retain ±π/2 internally, and held strafe allows a ±0.26 rad twist. The reviewed second change blends the desired body-yaw goal toward forward using the existing hold blend, before the existing 10/s body-yaw state update. Displayed and stored yaw therefore agree. It changes no individual bone or authored transition rate.

## Evidence

- `runtime-yaw_goal.json`: 252-case corrected full actual-Jolt controller/props + V2 AnimationTree + unchanged IK comparison. `candidate-summary.json` summarizes this corrected variant.
- Worst settled palm error **0.03474 mm**; minimum near contact weight **0.99999979**; maximum per-hand visible conservative radial gap **0.04491 mm**; maximum settled visible penetration **0.55690 mm**, below the unchanged 3 mm gate.
- 42,952 arm-geometry frames: maximum upper-arm length error **0.000253 mm**, forearm error **0.000126 mm**. Remote contact weight reaches zero. Pickup leaves the prop basis exactly unchanged.
- Twenty-four tilted/backward-duck approach skin checkpoints: no torso overlap or >3 mm visible hand penetration; deepest conservative radial penetration **1.443 mm**.
- Full corrected run: exit 0, **89.54 s**, peak **88,884 KiB (86.80 MiB)**. This is headless fixture cost, not gameplay performance.
- `yaw-goal-review/runtime-yaw_goal.json`: 72-case per-visual-sample actual-Jolt yaw-state trace. Corrected maximum stationary release drift **0.001070°**, compared with **89.9890°** for the superseded output-only variant. Stored/displayed mismatch ≤**5.96e-8 rad**. Both strafe directions, all props, release, held strafe and remote-return pass.
- `yaw-goal-review/contact-matched-comparison.json`: same production hashes and case identities as the 252-case unchanged baseline, which has **328 failed assertions**. Earlier orientation-only 55-case comparison leaves 27 failures confined to strafe/prior-strafe body yaw; its patch is retained in `orientation-only.patch`.
- `geometric-yaw-sweep.json`: exact serialized V2 rest rig / original compound-duck geometry, 25 pickup yaws × 3 body yaws × 3 camera pitches per variant. This is CPU reach analysis, not runtime acceptance. Forward, frontal wrist reach is 0.43644 m at default pitch / 0.45560 m looking down, within the unchanged 0.47271 m limit.
- `yaw-goal-review/README.md`, `yaw-goal-review/matched-yaw-comparison.json`, `yaw-goal-review/provenance.json` and artifact receipts retain the release counterexample, corrected implementation, sources and raw traces. Historical output-only reports remain intact and are explicitly not the final candidate.

## Scope and remaining gate

The runtime fixture compiles the exact yaw-goal insertion into an in-memory copy of the production Avatar and uses a Player subclass for duck orientation. Production files are not modified. The old output-only subclass remains available solely as a regression control. Synthetic shallow-water flags exercise the authored Wade clip; this does not claim production SWE/MPM or GPU/native validation.

The parent must still review native first-person hands, third-person carry/turn/drop, arbitrary-yaw pickup and 15/30 Hz timing in the actual authored bath. The original quaternion servo can rotate a backward duck quickly at pickup (maximum measured 0.4192 rad physics step at 120 Hz). It is continuous and passed sampled collision/skin checks, but perceived naturalness is not established numerically.

## Reproduction (explicit serial engine slot required)

Run `python tests/carry_contact_candidate_runner.py --variant=yaw_goal` for the full contact matrix, then add `--yaw-release` for the focused state traces. The latter with `--variant=facing` is an expected-failing regression control. Run `OPENBLAS_NUM_THREADS=1 python tests/carry_contact_candidate_contract.py -v` for CPU contracts. The runner uses an isolated writable temporary HOME/cache.

No acceptance thresholds were relaxed: near palm error <25 mm; contact >0.9; per-hand visible contact within 3 mm; no >3 mm visible penetration, torso overlap or arm stretching; remote relaxation, release/throw collision restoration and no player self-launch. New yaw checks additionally enforce stored/displayed agreement and <0.01 rad uncommanded stationary release/remote swing.
