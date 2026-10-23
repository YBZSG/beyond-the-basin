# Rejected: single bath aperture/return redistribution

Completed 2026-10-22 at approximately 22:34 UTC. **Do not integrate this
candidate.** The one bounded native comparison restored baseline exactly and
did not edit production. No full-game follow-up or parameter retuning was run.

## Visual decision

The candidate creates an asymmetric diffuse return gradient, but its main effect
is to darken the walls and large ceiling areas. The circular room remains grey
and does not gain convincing aperture-driven depth at ordinary viewing size.
The wall closeup reinforces this result. Its modest local ceiling gradient does
not compensate for the loss of readable pale-surface illumination.

This is a valid negative result, not an accepted lighting improvement. The
existing safe basin-return rail-shadow correction stays untouched.

Native images, all saved directly by Godot with no image postprocessing:

- [Baseline wide](isolated01/baseline_before-wide.png), [candidate wide](isolated01/candidate-wide.png), [restored wide](isolated01/baseline_after-wide.png).
- [Baseline roof](isolated01/baseline_before-roof.png), [candidate roof](isolated01/candidate-roof.png), [restored roof](isolated01/baseline_after-roof.png).
- [Baseline wall closeup](isolated01/baseline_before-wall_closeup.png), [candidate wall closeup](isolated01/candidate-wall_closeup.png), [restored wall closeup](isolated01/baseline_after-wall_closeup.png).

## Verification

- CPU contract: 26 checks passed, exit 0, no logged errors or warnings. It covers
  exact restoration of light/environment values, metadata and identities;
  idempotent apply; unchanged other authored rigs, sun and photon fixture list;
  correct computed return footprint; and no new lights.
- The first CPU contract failed three decimal literal equality assertions due to
  Godot native Float32 property storage. Only those expected-value assertions
  were corrected to approximate comparison. The exact baseline and idempotence
  equality checks remained strict. No candidate setting was changed.
- Native Godot 4.6.3 Forward+ llvmpipe, 640x360, 2x MSAA, no TAA: all nine native
  screenshots completed, exit 0, no engine error lines. Exact baseline and
  geometry/material identities restored, tracked source hashes unchanged.
- Total supervised native run: **155.88 seconds**. Peak sampled RSS:
  **1,471,784 KiB, 1.404 GiB**. The 300 s / sampled 3 GiB watchdog did not act.
- Renderer-reported allocation at all nine captures: **589.66 MiB**. This is an
  isolated cloud allocation observation, not target-device VRAM or FPS evidence.
- Teardown logged **14 leaked Texture RIDs**. Their ownership was not diagnosed;
  this is not warning-free execution. No further engine run was made to chase it.

The isolated fixture used the actual current 70 visible meshes / 46,776 triangles
/ 687 collision shapes and three glazing meshes. No red diagnostic panel, water,
substitute water, avatar or other rooms existed. SDFGI, SSIL, SSR, glow and
volumetric fog were disabled equally in all phases, with no live caustic atlas.
The existing fallback reflection probe was refreshed equally after each light
state. Therefore these images cannot validate actual water optical publication
or whole-game cost, and the rejected candidate was not escalated to that stage.

## Supporting pixel diagnostics

Post-hoc rectangles were selected after visual review. They support the observed
darkening but are not independent predeclared art gates. Values below are
display-referred 0–255 luminance, not linear-HDR energy.

| Receiver rectangle | Baseline mean | Candidate mean | Change |
| --- | ---: | ---: | ---: |
| Wide rear plaster | 122.21 | 95.20 | -27.01 |
| Wide left ceiling | 116.85 | 92.41 | -24.44 |
| Wide right ceiling | 116.85 | 115.02 | -1.83 |
| Roof broad ceiling | 120.98 | 90.53 | -30.45 |
| Wall-closeup plaster | 121.90 | 94.03 | -27.87 |

Baseline-to-restored whole-image mean absolute RGB differences are 0.01161
(wide), 0.000253 (roof), and 0.000424 (wall closeup) levels. The named plaster/
ceiling rectangles have zero off/off luminance drift. Increased local variation
is real, but it does not by itself make the lighting attractive or believable.

Evidence: [CPU contract](contract02/contract.json), [native report](isolated01/report.json),
[receipt](isolated01/receipt.json), [memory](isolated01/memory.json),
[source stability](isolated01/source-stability.json), [pixel analysis](isolated01/analysis.json),
[native log](isolated01/godot.log).

The reusable helper remains quarantined in `tests/bath_daylight/candidate.gd` as
a recorded rejected study. It is not referenced by production or enabled by default.
