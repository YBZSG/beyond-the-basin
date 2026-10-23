# Low-frame-rate runtime clock investigation

Date: 2026-10-22. Engine: Godot 4.6.3 official, Jolt. Scope of this investigation: tests and documentation only. All matrices below were recorded before the timing change; production scripts, Android files, delivered patch, and immutable baseline were untouched. After these findings, the parent applied the single PC-only project setting. Its separate startup verification and exact hash transition are in RUNTIME-CLOCK-CANDIDATE.md; the pre-change evidence below was preserved.

## Decision

A narrow **PC-only maximum of 16 physics steps per main-loop frame** is a justified next candidate. Keep 120 Hz physics, the normal Godot delta clock, and all sealed particle scheduling limits unchanged. Do not promote 24 as a splash fix or substitute raw wall time only in water.

The original 120 Hz / 8-step combination begins slowing the entire engine below 15 main-loop callbacks/second. Sixteen steps moves that threshold to 7.5 callbacks/second, restoring ordinary game time at 10 callbacks/second without unbounded catch-up. At least 10 callbacks/second are independently required by the sealed particle hosts' maximum 0.100 simulated seconds per callback. This candidate addresses upstream clock clipping, not GPU throughput or readback latency.

Setting justified by the pre-change evidence, subsequently applied as a separate candidate:

    [physics]
    common/max_physics_steps_per_frame.pc=16

The isolated startup fixture confirms desktop feature override 16, base setting 8, and 120 Hz. Android was not run or changed; the candidate's feature scope is PC only.

## Actual engine reproduction

Run from the project:

    bash tests/runtime_clock_run.sh
    bash tests/runtime_clock_run.sh --room-cost

The optional second command includes the whole-room CPU matrix. Run it serially with other performance work. The script uses a writable temporary HOME and XDG directories. Both commands are headless and require a null RenderingDevice. **Do not add --fixed-fps:** Godot explicitly bypasses the max-step clamp with that flag. Reruns replace the ordinary result paths; the original pre-change JSON/logs and their SHA-256 manifest are separately preserved in docs/verification/pc-refine/runtime-clock-pre-candidate/.

The first test uses Engine.max_fps to impose real main-loop pacing. A pausable process-delta accumulator, an undamped native RigidBody3D moving at 1 unit/second, a CharacterBody3D using move_and_slide, and the actual sealed whitewater host receive ordinary engine time. The whitewater fixture contains one long-lived drop and static spatial callbacks. A separate always-processing observer measures monotonic wall time. There is no GPU MPM execution.

Measured seconds advanced per wall second, after 5 warmup frames and over 12 sampled frames:

| Physics cap | Imposed callbacks/s | Process clock / wall | Physics clock / wall | Actual whitewater / wall |
|---|---:|---:|---:|---:|
| 8 | 10 | 0.668 | 0.667 | 0.667 |
| 8 | 5 | 0.333 | 0.333 | 0.333 |
| 16 | 10 | 1.002 | 1.002 | 1.002 |
| 16 | 5 | 0.667 | 0.667 | 0.500 |
| 24 | 10 | 0.997 | 0.993 | 1.000 |
| 24 | 5 | 1.000 | 1.000 | 0.500 |

Small differences reflect actual wall-clock pacing, physics jitter/fixed-step rounding, and retained particle backlog across cases. These are imposed callback rates, not measured graphical hardware FPS.

All 12 cases passed their bounded-clock and motion checks. The native body and controller matched integrated physics time within the test's one-tick/float tolerance. No frame exceeded its selected physics-step cap. With SceneTree paused, process accumulation, native body/controller displacement, and particle progression were exactly zero. Resume worked without wall-clock catch-up. At scale 0.5, cap24/5 yielded approximately 0.500 engine seconds per wall second; at scale 2, approximately 1.999. Whitewater retained its own finite throughput limit under fast time.

Evidence:

- tests/runtime_clock_clipping.gd
- docs/verification/pc-refine/runtime-clock-clipping.json
- docs/verification/pc-refine/runtime-clock-clipping.log
- tests/fixtures/runtime_clock_pc_override/
- docs/verification/pc-refine/runtime-clock-pc-override.log

## Independent particle limit, not a clock-only cure

The unchanged whitewater host permits 6 steps of 1/60 second per callback, with at most 0.25 seconds of retained backlog. The unchanged MPM host permits at most 2 batches of 36 steps at 720 Hz per callback, also 0.100 simulated seconds before other feedback/admission gates. MPM throughput here is a source-code upper bound, not a GPU measurement.

At 5 callbacks/second with cap24, the engine provided approximately real time, but the actual whitewater host advanced only half real time and discarded about 1.2 seconds across the 2.4-second sample after its backlog filled. Raising the engine cap alone cannot remove that independent limit. At cap16/5, the engine advances about two-thirds real time and whitewater about half; this is expected bounded overload, not a synchronization fix.

Conversely, replacing only water's delta with raw monotonic wall time while leaving original 120/8 body/controller timing would ask water to advance approximately three times faster than those bodies at 5 callbacks/second. Pause and time_scale would need new explicit handling too. This is not recommended.

The existing native sample patch-release-medium-a03.png.json reports 472.816–7369.290 ms wall intervals on software Vulkan, with startup/cubemap work included. Neither cap16 nor cap24 makes such sustained overload real-time. There is no hardware-FPS claim.

## Actual original-world CPU cost

The heavier matrix was run only after the parent's graphical slot ended. It constructed the unchanged seeded production world, including:

- Seed 250821; 25 complete rooms and interiors.
- 640 original spawned props and 1,933 static collision shapes.
- Production controller, Jolt body/contact logic, and current source-activity selection; typically 66–67 nearby force calls per tick.
- Production conversion of 1,921 supported water-depth colliders into the 768-square High depth grid, plus 384-square physics fields.
- Production water sampling/event paths using a frozen zero-wave/zero-flow snapshot. GPU submission, rendering, readback, lighting, streaming, and terrain rebuilding were deliberately excluded from timed samples.

Controller input alternated forward/backward every 120 physics ticks in the spawn corridor. All 96 sampled frames retained floor contact, with finite player positions; lowest feet Y was approximately -0.718783. Across each case, accumulated process delta and physics steps/120 differed by less than 0.000341 seconds. No step cap was exceeded and production input hashes were unchanged.

Observed CPU wall-time bracket per main-loop frame:

| Cap | Imposed callbacks/s | Physics ticks/frame | Median ms | p95 ms |
|---|---:|---:|---:|---:|
| 8 | 10 | 8 | 35.750 | 56.753 |
| 8 | 5 | 8 | 35.724 | 45.030 |
| 16 | 10 | 12 | 48.690 | 60.177 |
| 16 | 5 | 16 | 64.962 | 116.875 |
| 24 | 10 | 12 | 44.375 | 50.608 |
| 24 | 5 | 24 | 91.012 | 101.094 |

Each case uses 5 warmup and 16 sampled frames. This p95 is the maximum of that small sample and is not a stable hardware performance percentile. Cases ran sequentially in one evolving scene, so differences between equal-tick cases should not be interpreted as speedups. Consecutive within-frame physics-signal intervals were typically about 3.6–4.3 ms median per step.

The bracket starts at the first physics_frame signal and ends at late-priority process observation. It excludes intentional inter-frame sleep and initial native synchronization before the first signal; it includes the remaining native simulation, controller/prop work and minor dispatch overhead. It is not a cycle-accurate profiler result or full-game frame budget.

For the specific 10-callback/second target, cap16's 12-step median of 48.69 ms and sample maximum 60.18 ms are acceptable evidence for a bounded experiment. The CPU cost is real: more game time requires more physics work. A native end-to-end test must still establish the combined rendering/water budget.

Evidence:

- tests/runtime_clock_room_cost.gd
- docs/verification/pc-refine/runtime-clock-room-cost.json
- docs/verification/pc-refine/runtime-clock-room-cost.log

## Bounded next gate and stopping condition

This investigation is complete. The separate candidate is startup-verified; its remaining acceptance gate is:

1. Keep the PC-only 16-step override confined to that candidate, with the sealed delivery untouched.
2. At an actual sustainable imposed 10-callback/second native workload, confirm process and body clocks remain within one 120 Hz tick and supplied water time tracks wall time to within normal pacing tolerance. Record the extra CPU physics work and actual wall intervals.
3. Confirm particle queue/admission/readback guards remain finite, pause/resume is unchanged, no stale publications or native errors appear, and Android's base timing remains 8.
4. Accept only the upstream 10–15 callback/second slow-motion improvement. Do not chase 5-callback/second particle real time by raising budgets or creating an unbounded catch-up loop. Stop if the candidate cannot sustain its intended workload; that is a separate throughput problem.

## Official engine references

[Engine 4.6 documentation](https://docs.godotengine.org/en/4.6/classes/class_engine.html) describes the slowdown threshold, finite-step guard, and time_scale semantics.

[Godot issue 94632](https://github.com/godotengine/godot/issues/94632) confirms that both process and physics time slow under the cap, rather than this being only a water integration error.

[Godot 4.6 main loop](https://github.com/godotengine/godot/blob/4.6-stable/main/main.cpp#L4474-L4478) subtracts skipped fixed-step time from process delta and caps the loop; its fixed-fps path is intentionally exempt. The test uses the actual installed 4.6.3 engine.
