# Sealed wading pace decision

**Accepted by the owner as bounded gameplay tuning.** The existing Depth Response toggle now applies the validated helper immediately after the original depth-speed calculation. Source-only post-integration gate: **12/12 PASS** at 2026-10-22 21:48:40 UTC. No additional engine run was requested or performed after owner integration.

- **0.44 m shallow sprint:** actual native candidate 1.788254 m/s, versus 2.194004 m/s baseline. Cadence falls from 250.74 to 204.37 steps/min while keeping the exact 0.525 m step and imported 1.05 m Wade cycle.
- **Tradeoff:** 18.49% lower travel speed, or 22.69% more time over a fixed distance. Sprint remains 43.37% faster than shallow walking. This is a gameplay choice, not a claim of physiological realism.
- **Preserved exactly:** dry movement, water through 0.15 m ankle depth, ordinary walk, 0.94 m supported walk/sprint, genuine deep swimming, original acceleration/braking and distance-driven phase. No new threshold at 0.40 m; the filter smoothly joins the original depth response.
- **Native candidate proof:** 36 A/B trajectories, four pose-sampling rates, real Jolt 120 Hz and imported V2 AnimationTree. Shared phase, render double-integration and clip-seek errors are zero. No supported-water state flap. All production hashes stayed unchanged during the test.
- **Contact residual:** 1,458 flat-stance pairs stayed within 0.263 mm of the planted ankle reference; worst candidate-versus-baseline worsening was 0.0204 mm. Actual imported leg tracks have 30–31 keys rather than the source samples 0–120. Small native interpolation residuals remain; no new animation or import change is claimed.
- **Rejected:** a timing-only 0.72–0.75 m step would skate 24.18–27.90 cm per stance. Stretching that old foot path instead exceeds rig reach by 53.54–64.06 mm. Those results remain in static-audit.json, not silently replaced by the pace option.
- **Audio honesty:** wet audio remains existing continuous, actual-speed-driven stir/swish loops. This does not create foot-contact-synchronized water audio. Source water forces, wave formulas, SWE/MPM/photon math, collision and the imported clip are untouched.

The first absolute velocity-gate failure is retained in initial-velocity-gate/. It also failed unchanged baseline because differentiating a sub-millimetre residual exaggerates instantaneous velocity. The final test reports that velocity and additionally checks meaningful accumulated contact displacement and baseline-relative change; no runtime tuning or clip change was made to hide it.

Production Player before: b4c7a26b45c9c2a41ad3bf944bc6c0a1dc92d0028e0b24186d4a66b39fe3e4cf

Production Player after owner apply: dfebb72d8bf054712d12b3032a40295b96a9b78e002b73c2dfbf2f9962c1ad7b

Evidence: native-summary.json, native-report.json, native-execution.json, contact-comparison.json, imported-clip-keys.json, production-call-gate.json and verified-source/. Native A/B is not a full-game rendered or post-integration runtime acceptance.
