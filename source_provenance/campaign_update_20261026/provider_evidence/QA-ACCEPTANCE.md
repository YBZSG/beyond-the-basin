# Independent acceptance summary — frozen source

**Engine:** official Linux Godot4.6.3, headless. Tests ran in separate snapshots; no target-PC or GPU acceptance is implied.

| Area | Established result |
|---|---|
| Legacy migration/restore |1,285 checks pass;20 authentic revision1 fixtures preserved |
| Six mechanics/timer/recovery |635 checks pass; no collect-all bypass; pause/reload, gradual corruption, repair/retry |
| Adversarial save/store |696 checks pass; corrupt original and backup preserved, stale writers blocked |
| Mid-puzzle reload |52 checks pass; every solution-action save boundary tested |
| Real interaction fixture |13 checks pass; thin-wall LOS/range/facing/freed-target/debounce/menu |
| Integrated cinematic timeline |129 checks pass; actual stage/camera/fades,6 modes, cancel/timeout/save-error/safe-skip; preparation mocked |
| Actual loaded-world outage |268 checks pass; production room ownership and lighting, candidates in all6 chapters, max1 full outage, same-room safety lamp, exact reset, reduced-effects no blackout |
| Read-only recovery copy |8 checks pass; explicit separate copy, untouched original bytes, restart selection |
| Menu/inspection |1280×720 and1920×1080 pass;6 Chinese dialogs fit; carry preserved, charge canceled without throw, original safe drag-release policy |
| Placement/checkpoints |All28 mechanism fronts and28 checkpoints clear;6 exits and6 repair handles valid; one shared exit/repair cabinet |
| Route evidence |49/49 admitted handles covered by collision samples:28 mechanisms+6 exits+6 repairs+9 optional. Reference upper/lower samples linked by actual120Hz staircase roundtrip. Not a full controller playthrough |
| Actual controller traversal |Continuous17-waypoint entry→colonnade→cyan-objective walk passes, final real target selected; separate stair descent/ascent/exit approach passes. Only initial spawn warp |
| Protected originals |1,550 baseline files compared; zero missing originals, zero protected changes, all28 original importer sidecars restored |
| Source regressions |Reference-look9/9 and NR-control15/15 guards pass |

## Evidence and reproduction

- `qa-*.json` records compact physical/UI/timeline/outage results and exact tested-source hashes.
- `qa-collision-route-overview.png` is a **collision sampling diagram, not a game screenshot**.
- Reproducible independent scripts, legacy fixtures and logs: `../../../tests/campaign/independent/`.
- Detailed methods/limitations: `../INDEPENDENT-QA.md`.
- Selected core campaign aggregate and mutation guard: `../../../tests/campaign/final-cpu-results/summary.json`.

## Explicit non-acceptance / historical limits

1. No actual custom-Windows/NVIDIA GPU water, NR/RT, performance or full human playthrough. Offline previews and source/physics evidence do not establish subjective feel or pixel correctness.
2. The older screenshot’s thin bright wall/ceiling seams were not reproduced or visually accepted on the target runtime. Perimeter overlaps and connector camera/frustum tests do **not** prove that screenshot problem fixed.
3. `tools/release/validate_pc_expansion_pack.py` is still absent; `tools/release/test_validate_pc_expansion_pack.py:11` imports it. Historical full unittest discovery failed with `ModuleNotFoundError`. No substitute was fabricated; selected test passes are not a full-repository-test claim.
4. Physical fixtures use actual static room geometry and mounted campaign stations; the global dynamic floating-prop simulation and GPU fluid solver are not reproduced. Sampled routes approximate supported movement/wading/steps; they do not certify every jump, free-swim or animation path. Actual controller runs cover the explicitly recorded reference routes, not the whole campaign.

No remaining known critical progression blocker was found within these tested scopes. All original character/controller/water/rendering/room assets remain untouched.
