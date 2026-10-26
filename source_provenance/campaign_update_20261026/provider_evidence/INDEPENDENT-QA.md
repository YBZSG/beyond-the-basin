# Independent campaign quality review

## Established evidence (Linux Godot 4.6.3)

- Authentic old-save migration and adversarial restore: 1,285 checks.
- Six real mechanical solutions, invalid/repeated actions, collect-all bypass rejection, active-time pause/roundtrip, late repair/retry and transition recovery: 635 checks.
- Malformed objective/accessibility/counter snapshots, atomic store, stale writer, corrupt-primary backup read-only and orphan-temp evidence preservation: 696 checks.
- Mid-puzzle JSON save/reload after every solution action boundary: 52 checks.
- Actual loaded-world outage integration:268 checks across six native-lighting setups, eligible candidates18/14/12/26/6/17, at most one fixture fully off, same-room safety illumination retained, exact reset, reduced effects never black, unknown/single-light ownership skips safely. Light3D-state evidence, not pixels.
- Explicit read-only recovery-copy action:8 checks; original corrupt primary and valid backup untouched, new writable copy restores proven backup progress, restart profile selects copy.
- Real physics target/range/facing/thin-wall/own-collider/freed-node/input debounce/menu fixture: 13 checks.
- Integrated timeline with actual transition stages, fade alpha and actual replacement player Camera3D ownership: 129 checks. All six stage modes visibly play while alpha<.05; camera activation alpha1; handoff alpha>.99. Success/cancel/timeout/save failure/safe-skip end with correct camera and no lingering black overlay. World, water and mount readiness are explicitly mocked.
- Actual main menu construction and all six Chinese inspection modals fit 1280×720 and1920×1080. Long content scrolls; close/read/recovery controls remain accessible. Advanced GPU-water panel alone omitted.
- Real main pause + production player: carried prop retained; charged throw canceled without throwing; dragged prop safely released under original pause policy; close restores enabled player. Q has no original binding outside campaign.
- Actual production room geometry: all28 puzzle front approaches, six exit handles and six repair handles have supported capsule clearance and targeting LOS; all28 checkpoints clear with standard2cm floor tolerance. One reference exit/repair deliberately shares a cabinet to avoid obstructing the stair landing.
- Grounded/wading sampled collision graph covers required locations in five chapters; reference upper/lower graphs are linked by an actual production ReferencePlayer120Hz staircase descent/ascent and exit-approach run. A second continuous real-controller run reaches colonnade and cyan objectives through17 waypoints, ending in actual cyan target selection; only initial spawn warp.

## Bugs found and corrected during review

1. GDScript inferred-type parse failure in objective stable condition.
2. Correct memory sequence became floats after JSON reload; strict Array equality prevented confirmation. Fixed canonical integer restoration; all action-boundary reloads now pass.
3. Freed station typed assignment threw before is_instance_valid; validity now checked before cast.
4. Reference departure gate failed placement silently; robust search/readiness guards added.
5. Expanded entry capsule intersected three first-cabinet collision shapes; spawn/entry clearance reservation added.
6. Stations narrowed connecting doorway centerlines; portal lead-in reservation added.
7. Unproven optional court bell/reference locker omitted instead of shipping unverified interactions.
8. All E prompts fell back to generic terminal text; station metadata now carries actual mechanism names.
9. Full solutions were initially printed on ordinary approach; default HUD now subtle, detailed Chinese reading requires intentional Q and pauses the clock.

## Evidence boundaries / remaining acceptance

- Sampled connectivity is not a full controller playthrough of every objective. It approximates grounded movement, step/fall clearance and wading; it does not certify all jumps/free-swim/animation paths.
- No actual custom Windows runtime or GPU water/NR/RT visual test was available. No screenshot, native-fluid readiness, performance, animation, mobile device or subjective visual-polish claim follows from headless success.
- Parent/art specialist owns offline visual renders and final presentation judgment. QA diagrams are explicitly labeled collision samples, not game screenshots.
- Final source/asset protection audit PASSED after restoration of all28 original importer sidecars:1,550 baseline files compared, zero missing originals and zero protected modifications. Default-world/character hooks reviewed; source guards pass9 reference-look and15 NR-controls tests. Tested source hashes are recorded; final core aggregate independently passed16/16 with its230-file mutation guard.

## Reproducibility

Tests, logs, compact JSON and tested-source hashes live under `tests/campaign/independent/`. External `campaign-quality-review/` retains original1,550-file baseline hash manifest, exact baseline sources, isolated projects, intermediate diagnostic failures and full sampled point clouds. An error-free exit requires no SCRIPT ERROR/ERROR in logs; Godot can otherwise report fixture check passes after a dependency compile failure.

## Explicit historical/open limits

- Historical wall/ceiling thin bright seams in the earlier screenshot were not reproduced on the target NVIDIA/custom engine. Perimeter overlaps and connector frustum checks do **not** demonstrate that screenshot defect fixed.
- `tools/release/validate_pc_expansion_pack.py` remains absent (verified in this final source), while `tools/release/test_validate_pc_expansion_pack.py:11` imports it. Earlier full unittest discovery therefore hit `ModuleNotFoundError`; no fabricated validator replacement was supplied. Selected campaign/headless passes must not be described as full repository discovery passing.
- Actual custom-Windows GPU water/NR/RT/performance, complete human playthrough and subjective movement/puzzle feel remain unaccepted. Offline256-sample previews and CPU route evidence are not substitutes.
