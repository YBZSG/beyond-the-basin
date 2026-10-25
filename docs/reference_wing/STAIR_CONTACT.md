# Cyan stair contact diagnosis

2026-10-24. CPU/headless, Godot 4.6.3/Jolt; fixed 60 Hz process and independently tested 15/60/120 Hz physics. No production controller, geometry, collider, renderer, imported asset, or fluid-solver file was changed for this investigation.

## Finding

The continuous walk snag is real, reproducible, and a recovery-contact query mismatch, not an oversized riser or hardware/rendering failure. It occurs on `COLLISION_Cyan_EastEntry_Tread_03` at feet `(0.7061953, 0.1512297, -73.7639008)`.

At the stuck state the production controller requests velocity `(1.2499522, -0.0817500, -0.0096140)`, is grounded, and has no active step-snap pause. `_try_step` tests horizontal motion without reporting recovery contacts. `move_and_slide` subsequently reports the tread's steep corner but leaves essentially zero net displacement, so the unchanged movement intent repeats the same state.

The decisive contact sample is preserved in `tests/reference_wing/stair_contact_results.json`:

- Horizontal query, margin 0.001: no hit.
- Horizontal query, body margin 0.002: no hit. Merely aligning margins does **not** fix this.
- Full motion including gravity, margin 0.001: tread 03 hit, normal approximately `(-0.89229, 0.45146, 0)`.
- Full motion including gravity, margin 0.002, recovery disabled: no hit.
- Horizontal query, body margin 0.002, `recovery_as_collision=true`: tread 03 hit, normal approximately `(-0.89058, 0.45483, 0)`.
- Actual slide contact: tread 03, normal approximately `(-0.89140, 0.45322, 0)`. Final velocity becomes zero; movement-intent state remains nonzero.

The claim is limited to the observed mismatch in collision-query semantics. This is not a claim that Jolt or all stair handling is generally broken.

## Reproduction and state dependence

The fixture builds exact authored collision proxies directly from the exported geometry contracts. It does not load GLBs, instantiate rendered architecture, run an editor/import pass, or need a GPU. The water node supplies the same static authored depth profiles used by the existing walkthrough.

1. The entrance approach uses 1,021 exact proxies and the first eight original waypoints. All seven preceding leg endpoints reproduce the original walkthrough to floating-point precision; the same eighth-leg snag follows.
2. A shorter cyan-only reproduction uses 95 exact proxies. Warp to the recorded position, settle grounded state, then restore `_move_velocity=(1.2499522,-0.0096140)` and horizontal `velocity` before forward input. At 120 Hz this reproduces the exact snag.
3. The identical warp without restored movement intent climbs. Restarting from rest is therefore not a valid negative reproduction of the continuous-walk defect.
4. Strongest test: run the whole entrance approach with the unchanged source controller, wait for 46 consecutive stationary ticks at the exact snag, then enable the test fallback on that **same body**, without warp, velocity reset, or state reconstruction. One legal step immediately moves from `(0.7061953,0.1512297,-73.7639008)` to `(0.7166116,0.3370000,-73.7639847)`, a rise of 0.1857703 m, and the player clears the staircase.

The approach tests deliberately stop once `x>2.4` on the final leg. They preserve the historical heading toward `(5.4,-73.8)` but do not claim that wall-adjacent waypoint itself was reached. Correcting later route corners and validating the entire five-room circuit is separate work.

## Recommended narrow implementation

Use a **new reference-wing-only `PoolPlayer` subclass**, selected only for the reference-wing mode. Do not change default source-world controller behavior.

The subclass should:

1. Call `super._try_step(delta, was_grounded)` first and return its successful result unchanged.
2. If that fails, retain all original gates: grounded, not rising, nonzero horizontal travel, steep contact normal, upward-facing landing, `STEP_HEIGHT` limits, upward clearance, and raised forward clearance.
3. For the fallback's first contact query only, use `test_move(global_transform, travel, wall_hit, safe_margin, true)`.
4. Retain the original landing ray, maximum step height, eye offset, 0.16 s snap pause, gravity, and all remaining motion behavior exactly.

The tested implementation is `_try_step`/`_margin_step` in `tests/reference_wing/stair_contact_player.gd`, mode `fallback`. The equivalent clean, reviewable subclass for installation is `tests/reference_wing/stair_contact_recommended.gd`. Its first call delegates to the unchanged source and its fallback retains every original guard. The instrumentation's margin-only, default-margin recovery, and full-motion modes are diagnostic ablations, **not** proposed production alternatives.

The existing production controller is unchanged; SHA-256 at diagnosis: `3ac9b9a47703483c60c8631b4379fb9f910f773bf06c1245dd1c825960391651`.

## Why not alter architecture or add a hidden ramp?

- The visible/physical stair is already an ordinary sub-0.32 m staircase. The implicated move is about 0.1858 m, well within the controller's existing admissible range.
- A continuous invisible ramp across the stair profile can depart from the visible tread by almost one riser, roughly 0.185 m. That invites precisely the visible foot-floating/contact mismatch that the scene must avoid.
- Shifting or beveling only a collision proxy trades exact authored surface agreement for a phase-specific contact change. This diagnosis does not establish a robust collision-offset workaround, and none is proposed.
- The recovery-aware fallback resolves the exact live stuck state with no altered surface, no extra support, and no increased step-height allowance.

## Results

### Minimal exact-contact A/B

At 15 Hz and 60 Hz, baseline and fallback both clear and have identical endpoint coordinates. No fallback step is used.

At 120 Hz, baseline remains at the recorded snag; the fallback clears, using exactly one recovery step. This establishes time-step sensitivity without treating a lower physics rate as a fix.

### Synthetic regression matrix

48/48 cases pass: baseline and fallback, each at 15/60/120 Hz, for eight fixtures:

- Ordinary 0.18 m step.
- Maximum 0.32 m step.
- Too-high 0.45 m obstacle, blocked without a step.
- Low ceiling with only 1.54 m clearance above the step, blocked without a step.
- Fixed-heading side-edge contact whose forward landing ray misses the tread, no step onto unsupported space.
- Reverse traversal/down-step, returning to the floor.
- Diagonal ascent.
- Stop, settle, restart; no residual idle drift.

All 24 baseline/candidate fixture pairs produce **identical numeric endpoints**, and none invokes the fallback. Every accepted step is grounded and within the unchanged 0.325 m numerical allowance used by the original controller. The fallback does not broaden these fixture outcomes.

An initial edge fixture steered back toward the step as it slid sideways, so its landing ray legitimately entered the tread at 15/60 Hz. Both baseline and fallback behaved identically. That fixture was corrected to maintain a fixed heading, actually testing the intended missing-landing condition; no production behavior was changed to satisfy it.

### Exact approach replays

- Baseline: same snag, same preceding leg endpoints.
- Fallback enabled from the start: staircase cleared, one recovery step on the preceding tread; ordinary source steps remain in use.
- Fallback enabled only after the actual snag: staircase cleared, exactly one recovery step at the recorded third-tread contact. No body replacement, warp, or reset.

### Ablations at the seeded 120 Hz snag

- Margin 0.002, recovery disabled: still stuck.
- Margin 0.001, recovery enabled: still stuck.
- Margin 0.002, recovery enabled: clears.
- Full gravity motion with default margin: clears, but rejected as the preferred design because floor/gravity contacts unnecessarily broaden the initial stair query.

## Files and reproduction

- `tests/reference_wing/stair_contact_player.gd`: test-only source subclass and contact instrumentation.
- `tests/reference_wing/stair_contact_recommended.gd`: exact proposed reference-only subclass, with no instrumentation or production installation.
- `tests/reference_wing/stair_contact_probe.gd`: exact authored-proxy reproduction and live recovery.
- `tests/reference_wing/stair_contact_matrix.gd`: isolated 48-case regression matrix.
- `tests/reference_wing/stair_contact_run.py`: repeatable runner, validates expected failure as well as success and rejects script errors.
- `tests/reference_wing/stair_contact_results.json`: durable evidence, source/geometry hashes, terminal contact, matrix, approach summaries, and ablations.

Run from the project directory:

```sh
python tests/reference_wing/stair_contact_run.py
python tests/reference_wing/stair_contact_run.py --full
```

The runner isolates HOME/XDG and raw logs/reports under `/tmp/poolcore-reference-contact`. It starts headless runtime scripts only, never shared editor imports. `--full` adds the original entrance-approach failure and same-body late recovery.

Some fast headless runs emitted Jolt's worker-job-capacity warning; the exact stuck state and recovery reproduced despite it. No visual/FPS/fluid or whole-circuit success is claimed from these CPU tests. Production installation and a corrected continuous five-room walkthrough remain the integration acceptance steps.

## Integration update

The reviewed subclass was copied to `scripts/reference_wing/reference_player.gd` and selected only when main spawn mode is `reference`. The source PoolPlayer file remains unchanged. The corrected 48-leg continuous five-room circuit passes with actual GLB architecture/collision:318.168149m, five rooms discovered, returning to upper floor4.681217m. No intermediate warp. See `output/reference_wing/integration/walkthrough.json`; static exact water-depth fixture, no graphical/fluid/Windows claim.
