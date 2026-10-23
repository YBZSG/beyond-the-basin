# PC WaterFeel repair release candidate, 2026-10-23

## Frozen playable identity

- Version: 0.6.2-pc-waterfeel-20261023.
- Exported and independently reconstructed PCK: 157,631,396 bytes.
- SHA256: 54f5ff5f6c15ea854e70f30a9a5eca3096c0b9192db3b0852741ac296145e234.
- Main SHA256: 2a7e068c53a3b85571ca2b187c99a7356b6567a9a591bbf52daa0da7721370b3.
- Export exit 0. One existing nested test-project scan warning, no export script errors.
- Source water/player/model algorithms and assets are not replaced by the external test fixtures.

## Implemented, not photoreal completion

Formal sidepool depth is 0.84 m and circular bath 0.94 m, with six treads and a final landing. Water height stays +0.32 m and dry deck +0.52 m. Other rooms are not globally deepened. Original eight procedural variants plus its six anchor coordinates, Expanded's four additional types, and Formal's five authored spaces remain selectable.

The supported-wading response and shallow-water sprint cap reduce excessive cadence without replacing the distance-driven gait or source water solver. The imported 42-bone, seven-clip procedural character has refined hands, reach release and orientation, plus two reversible metric cloth shader surfaces. It is not a scanned human, sophisticated finger-contact simulation, or wet-clothing system.

The circular bath wall is now continuous rather than coplanar capped segments. Collision proxies remain intact. Two quiet optional return valves are discoverable on the sidepool east deck and circular-bath north deck; aim within about 2.1 m and press E. Their weak wakes only run with ready water. A local exploration notebook records genuinely visited rooms.

## Transition safeguards and uncertainty

Phased retirement waits for old node deletion and render-queue order before replacement allocation; reentrant selection is rejected without mutating an in-flight request. This is not proof of immediate GPU/OS reclamation or hitch-free teardown. Some background work still joins synchronously.

The separate 'Restart into selected world' button is explicit, optional, and supported by the supplied verified adjacent-PCK launcher contract. It saves selection and settings, invokes normal shutdown, and requests the same executable again. It never restarts automatically at startup. Unsupported editor/custom-script invocations remain open with an explanation. Its small native adjacent-PCK fixture passed one actual restart; production-water restart and Windows execution remain unverified.

The user-reported black/neon-green result after live switching has not been naturally reproduced or proven fixed. New event-only POOLCORE_WORLD_LIFECYCLE engine-log records retain selected mode/seed, renderer/driver, viewport AA/filter and root scenario identity without a GPU readback or upload.

## Validation hierarchy

1. Final source controls/settings: 135 checks across three isolated processes; eight readiness checks and release preflight pass. The readiness fixture was updated to assert the intentional SWITCHING WORLD / RELEASING PREVIOUS WORLD label, rather than the former PREPARING label.
2. Restart Main atomic-save guard: 12 checks. Tiny native adjacent-PCK restart: 34 checks, two processes exiting 0. PowerShell launch is statically reviewed with explicit process waiting and native argv encoding; it was not executed on Windows.
3. Exact reconstructed PCK native rig fixture: 75 frames at fixed15Hz, 42 bones/seven clips, two cloth surfaces, supported wading/stop/near-far-return/drop, exit0. Cloud Forward+ llvmpipe, 51.59s wall time, peak sampled RSS1,253,068KiB. This uses controlled water contact/lighting and injected prop setup, not full source-water optics or normal picking.
4. Earlier actual full-world source capture: Medium640x360, complete source cubemap/planar/photon readiness, ordinary near/far scroll and release, exit0. Its water/player/rig source identities are unchanged in the final pack. Main's later lifecycle/UI/log changes are not retroactively covered by that capture. The longer valve/stair/wading clip is a partial run that ended externally after its recorded section.
5. Final full-world exact-PCK Medium and Low startup attempts were externally terminated before readiness: 7.55s/1,738,688KiB and38.64s/1,740,584KiB respectively. Neither watchdog fired. The cause is unconfirmed, and those tests are NOT passes. The historical Low harness also incorrectly demanded output from disabled caustics; its rerun predicate is corrected and the exact executed version is preserved. No rerun is claimed.
6. Historical engine-only Godot4.6.3 probe controls independently reproduce seven shutdown Texture RID warnings. Current source regeneration keeps the root World3D/scenario. This does not explain every warning, the fourteen-warning lighting study, external terminations or the black/green report. No speculative RID free was added.

## Scope limits

There is no measured target Windows GPU FPS, no Android update, and no achieved photoreal claim. Fixed-step clips are motion illustrations, not frame-rate evidence. Rejected lighting/GI variants and non-beneficial visual experiments were not enabled as defaults. Exact exported-asset CPU checks are recorded separately under docs/final-packed-assets.

## Exact final-PCK CPU gate

419 checks passed with zero failures, exit0 in4.609s and207,796KiB peak sampled RSS. This includes114 selected entry hashes,21 modules,6 formal models,5 collision/depth rooms,54 stair points,42-bone/seven-clip avatar,2 cloth surfaces,2 valve models and16 caches. It excludes Main._ready, graphics, GPU solver, traversal, live switching and Windows execution. The sealed report is docs/final-packed-assets/SUMMARY.json; the original Windows DLL remains a verified baseline dependency, not part of the Play delta.
