# Wading cadence: retain the authored foot path

Status: bounded native A/B passed on 2026-10-22 at 21:46 UTC; the CPU engine slot was released immediately afterward. The worker did not edit production Player, Avatar, audio, imported V2 or water solvers. The owner subsequently integrated the exact preload/call under the existing Depth Response toggle; all 12 source-only checks passed at 21:48:40 UTC. Post-integration Player SHA-256 is `dfebb72d8bf054712d12b3032a40295b96a9b78e002b73c2dfbf2f9962c1ad7b`. No full-game rendered or perceptual acceptance is claimed.

## Decision

Reject a timing-only longer Wade stride. V2 has a **1.05 m full cycle / 0.525 m step**, 62% stance, and contact travels exactly −1.05 m per normalized phase. It is not an arbitrary tempo parameter. The exported leg lengths total 0.765913 m and the authored minimum reach margin is only 6.903 mm.

- Retiming that unchanged clip to 0.72–0.75 m per step produces **24.18–27.90 cm of forward stance skating** per foot contact.
- Naively stretching its fore/aft foot path to match instead exceeds leg reach by **53.54–64.06 mm**.
- A legitimate longer-stride solution needs a new matching stance/swing path with validated knee/hip reach and acceleration contact behavior. That is not a safe one-line cadence change.

The smallest bounded candidate is an optional **supported-wading sprint pace ceiling**, leaving the existing distance-driven cycle and all imported animation untouched. `scripts/player/wading_stride_candidate.gd` supplies only the scalar speed filter. `tests/wading_stride_candidate/prepare.py` makes an isolated Player copy with one added call, for A/B only. It does not edit production or claim the copy is production integration.

## Pace option and agency tradeoff

The ceiling is unchanged through 0.15 m ankle water and fades smoothly to 1.75 m/s at 0.50 m knee depth. The band is gameplay tuning guided by this exported rig's approximately 0.115 m ankle and 0.500 m knee heights, not a hydrodynamic law. A C1 monotone soft minimum joins it to the existing 0.40–1.05 m depth response, without a new speed discontinuity at 0.40 m.

At 0.44 m the target becomes **1.788263 m/s**, rather than the measured baseline 2.194022 m/s: **18.49% slower travel** and approximately **204.37 steps/min instead of 250.75**. It remains **43.37% faster than the 1.247278 m/s shallow walk**. That is a real agency cost, not a free animation improvement. The selected tempo is an art/gameplay candidate, not a claim about human physiology.

0.94 m supported walking (1.019057 m/s, 116.46/min) and sprinting (1.691939 m/s, 193.36/min) remain unchanged. Dry movement, ordinary walking, genuine deep swimming, unsupported motion and invalid depth samples bypass the filter. It does not change collision, intent acceleration/braking, swim latch, water forces, source SWE/MPM/photon math, root transforms or bones. Only actual traveled distance still advances gait.

The owner-selected integration places the optional filter inside the existing Depth Response branch, immediately after its original speed calculation. Switching that option off restores the original delivered speed code path. `owner-integration.patch` is a proposal only; this worker does not apply it to production. A meaningful test must retain the source 8 m/s² acceleration and 10 m/s² braking, preserve stops/resumes and not add a wall-time phase.

## Audio coupling: important limitation

`step_water` is a water-interaction event, not an audio footfall. `PoolAudio.interaction` does not play a clip for it. Wet audio uses the existing continuous stir and swish loops, independently sampled from actual displacement; their pitch is `clamp(0.85 + speed × 0.07, 0.85, 1.15)`. Therefore neither the rejected stride curve nor this pace cap can truthfully claim shared wet-audio/animation foot contacts.

The cap naturally slows that existing loop pitch slightly because measured movement slows, but it neither changes the recordings nor invents timed contact audio. Dry footfall audio remains untouched. A future wet-contact-audio pass must be a separate bounded design, not hidden in this pace fix.

## Evidence and commands

- `static-audit.json`: actual exported V2 forward kinematics, rig reach, unchanged contact reference, rejected stride comparisons and source hashes.
- `curve-contract.json`: 110,001 scalar depth samples; finite, monotone, never faster than original, exact ankle and 0.94 m preservation, and sampled C1 transitions.
- `candidate-patch.json`: one-call source-copy delta. Reverse-patching must exactly recover production aside from its removed global class name.
- `native.gd`: prepared actual Jolt 120 Hz controller / V2 AnimationTree A/B, with 15/30/60/120 Hz pose samples, dry/ankle/shallow/deep-supported/deep-swim trajectories, acceleration/deceleration, idle/resume/reversal and depth ramps. It measures the real imported ankle trajectory in the flat stance interval and validates unchanged limb lengths. Water is a controlled terrain/surface interface, not an SWE/MPM simulation.

Source-only:

    python tests/wading_stride_candidate/static_audit.py
    python tests/wading_stride_candidate/curve_contract.py

The following native commands describe the executed PRE-INTEGRATION baseline. After owner integration, the preparer deliberately refuses that changed Player hash instead of silently applying the cap twice or relabeling the new Player as the old baseline. No post-integration engine rerun is needed for the requested source-only gate. With the exact archived pre-integration baseline and an explicit owner slot grant:

    python tests/wading_stride_candidate/run.py --slot-released --parse-only
    python tests/wading_stride_candidate/run.py --slot-released --quick
    python tests/wading_stride_candidate/run.py --slot-released

Native runner refuses another known Godot process, bounds elapsed time, isolates runtime user/cache directories and records source hashes, stderr and exit outcome. A successful candidate A/B is still not full-game rendered acceptance or an actual-production runtime integration result. The owner can inspect its source-level application with `python tests/wading_stride_candidate/production_gate.py`; that gate does not launch Godot.

## Executed native result

The final 36-case matrix completed in **27.80 seconds**, exit 0, empty stderr, peak child RSS 78.66 MiB. These are isolated test costs, not game performance measurements. All production hashes stayed unchanged during that run. Baseline Player SHA-256: `b4c7a26b45c9c2a41ad3bf944bc6c0a1dc92d0028e0b24186d4a66b39fe3e4cf`.

- 32 trajectories: production A/test-copy B × dry, 0.10 m ankle, 0.44 m shallow, 0.94 m supported-deep × 15/30/60/120 Hz pose sampling. Physics always executes at 120 Hz.
- Two genuine 2.00 m deep-swim trajectories and two gradual 0.10→0.55→0.10 m depth ramps.
- Each ordinary trajectory includes walking acceleration/steady movement, sprint acceleration/steady movement, braking, idle, resume and direction reversal. Ripple-height noise is ±5 cm; terrain depth is stable unless the test deliberately ramps it.
- Native helper guard tests and an 11,001-depth-sample scalar sweep execute the real GDScript implementation.

| State | Production actual speed | Candidate actual speed | Outcome |
|---|---:|---:|---|
| Dry walk / sprint | 1.650005 / 3.800011 m/s | Exact same | Preserved |
| 0.10 m ankle walk / sprint | 1.250000 / 2.200012 m/s | Exact same | Preserved |
| 0.44 m walk | 1.247273 m/s | Exact same | Preserved |
| 0.44 m sprint | 2.194004 m/s | **1.788254 m/s** | **250.74→204.37 steps/min** |
| 0.94 m walk / sprint | 1.019053 / 1.691946 m/s | Exact same | Preserved |
| 2.00 m deep-swim walk / sprint input | 1.250000 / 2.200012 m/s | Exact same | Preserved |

The unaffected complete trajectories retain identical total distance and final phase, not merely approximately equal speeds. Across all four render-sampling rates, actual travel, final phase and event count are identical. Phase-integration, render double-integration and normalized Walk/Run/Wade seek errors are **zero**. Original 8 m/s² acceleration and 10 m/s² braking remain bounded, stops freeze phase and emit no phantom events, and supported cases never flap into Swim or the deep latch.

The real imported skeleton yielded **1,458 consecutive flat-stance sample pairs**. Maximum distance from that stance's first measured planted ankle was **0.262700 mm**. The candidate's largest increase versus its matching baseline was only **0.020312 mm**. Leg-length error stayed below **0.000567 mm**. These are ankle-contact proxies on a flat Jolt floor, not shoe-surface or terrain-IK acceptance.

The first full matrix intentionally remains in `initial-velocity-gate/`: it failed a new absolute instantaneous ankle-velocity gate in production A as well as candidate B at 60/120 Hz. That gate measured differentiation of sub-millimetre native interpolation residuals, not accumulating skating. The revised gate measures actual planted-stance displacement (<1 mm) and candidate-versus-baseline worsening (<0.1 mm), while still retaining and reporting every instantaneous velocity. The maximum was 31.19 mm/s for unchanged ankle-depth sprint, but the full stance moved only 0.263 mm. No controller, clip or gate input was changed to obtain this result.

`imported-clip-keys.json` separately confirms the shipped Godot Wade leg rotation tracks have **30–31 keys**, whereas the raw GLB contains the original samples 0–120. This follows the existing 30 Hz import setting and is consistent with the small native residuals; the cap does not change import settings. This inspection does not claim a causal A/B of different import rates.

The actual speed reduction increases fixed-distance shallow sprint travel time by about **22.69%**. Water interaction timing naturally changes with the slower actual travel, but neither source wave-impulse formulas nor SWE/MPM/photon math are changed. Existing wet audio remains speed-driven continuous loops, not newly synchronized footfalls.

Final concise evidence is in `native-summary.json`; `native-report.json` includes sampled contact anchors/poses, events and per-segment results. `candidate-evidence-manifest.json` and `verified-source/` preserve the tested helper/copy/fixture sources. The original quick run is a 12-case subset and is not represented as the full matrix.

## Owner integration gate

`production_gate.py` verifies one exact helper preload and one exact call inside the existing Depth Response branch, after the original response. Removing those two additions must recover the original Player code (ignoring only blank/comment lines). It separately verifies unchanged Avatar, audio, depth-response and V2 bytes, the native-tested helper hash, and all three original step-distance constants. Its `production-call-gate.json` receipt is a **source-only** post-apply check, not a post-integration runtime/render claim.

Seal note: the live prepare.py gained only a post-integration baseline-hash refusal after the native pass. The exact preparer used for the passing run remains in verified-source/prepare.py. No runtime helper, native fixture, clip, or production source was changed by that guard.
