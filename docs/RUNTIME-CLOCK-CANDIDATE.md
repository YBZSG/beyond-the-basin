# PC runtime clock candidate

Date: 2026-10-22. Status: exact single-setting candidate applied by the parent; actual current-project headless startup verification passed. The sealed splash delivery and immutable baseline remain separate.

## Exact change and verified startup

Only this project.godot line was added:

    common/max_physics_steps_per_frame.pc=16

Godot 4.6.3 read the actual project at startup, without test-time Engine property overrides:

- Desktop PC feature true; Android feature false.
- Jolt Physics, still 120 physics ticks/second.
- Base max steps remains 8.
- PC feature override and effective Engine max steps are both 16.
- Null RenderingDevice, no graphical/native GPU launch.
- Removing exactly that one line restores the complete pre-change project bytes.
- All eight production script hashes recorded by the pre-change actual-room benchmark still match.

Pre-change project SHA-256:

    d92c7eb2a14d97644825eb96f868ec6f95fab2b8325aa82de3bb45484cbb0ee8

Candidate project SHA-256:

    0483260e05154d6bf0fe67e092f5bb3645695731c78baa49119d2a4f5f7b96ce

Android was not executed. The feature-scoped change leaves the base value and all existing Android/mobile settings intact; no Android work was resumed.

## Evidence and limit

All pre-change clock, body/controller, whitewater, pause/time_scale, and 25-room/640-prop CPU matrix evidence is retained unchanged in RUNTIME-CLOCK-CLIPPING.md and its linked JSON/logs. A preserved copy of the original JSON/logs with a SHA-256 manifest lives in docs/verification/pc-refine/runtime-clock-pre-candidate/. The candidate startup test reads this preserved baseline, so a later matrix rerun cannot silently replace the comparison baseline.

At imposed10 FPS, that actual-Godot matrix changed process progress from approximately0.668 to1.002 seconds per wall second when the finite cap rose from8 to16. Actual unchanged whitewater followed at approximately1.002. The original-room physics bracket increased from35.75 ms median for8 ticks to48.69 ms for12 ticks, with60.18 ms sample maximum. These are CPU-only measurements, not full rendered frames.

**Compact caveat:** Reduces cap-induced slow motion at10 FPS and increases bounded physics work; not a GPU/FPS speedup or a sub10-FPS fix.

No target hardware FPS or native visual acceptance is claimed. The candidate still requires the bounded native end-to-end gate described in RUNTIME-CLOCK-CLIPPING.md. The actual unchanged whitewater result at5 callbacks/second remains approximately half real time even with a24-step engine cap.

## Reproduction

With writable HOME/XDG directories, run:

    godot --headless --path . --script tests/runtime_clock_candidate_startup.gd

Artifacts:

- tests/runtime_clock_candidate_startup.gd
- docs/verification/pc-refine/runtime-clock-candidate-startup.json
- docs/verification/pc-refine/runtime-clock-candidate-startup.log

This startup test does not rerun or overwrite the pre-change clock/CPU matrix.

## Subsequent native startup smoke

The full-game existing-lightmap diagnostic `lightmap-memory-medium-full-01` subsequently started with the actual PC120 Hz /16-step override, completed all six source cubemap faces, captured two matched-planar images, and exited normally in235.687 seconds. Its recorded project hash matches this candidate. This is a graphical startup/disposal smoke, not a native10-FPS splash or real-time throughput validation. The timing matrix above remains the evidence for the engine-delta correction.
