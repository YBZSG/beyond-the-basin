# Frame-aware cubemap readback watchdog

## Failure and engine contract

The first full-game baked-light comparison never reached its comparison hook.
Its source cubemap delivered two faces in 38.443 s and 25.443 s, then the third
ticket crossed the old unconditional 30 s limit before delivery. This was not
another terrain miss or stale-origin restart: all five authored payloads hit,
and there was one committed capture and one lighting invalidation. Evidence is
`verification/eight-hour/material-lighting/full-game-baked-comparison.log`.
These are software-renderer wall times, not target-device performance.

Godot's asynchronous texture downloads are frame-delayed. The 4.6.3 device
stores a request in the current frame slot and invokes its callback after that
slot's fence completes when the slot is reused. `get_frame_delay()` returns the
actual number of frame slots. The main device uses at least two, rather than
assuming the configured default is necessarily the device's actual value.
[API documentation](https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html#class-renderingdevice-method-texture-get-data-async),
[4.6.3 frame retirement and callback implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/rendering_device.cpp#L6174-L6248),
[actual frame-delay accessor](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/rendering_device.cpp#L6008-L6010).

## Narrow production correction

Only `scripts/water/source_port/source_room_probe.gd` changes:

- The render-thread ticket records actual submission time,
  `RenderingDevice.get_frame_delay()` and `Engine.get_frames_drawn()`.
- A missing callback trips the ordinary 30 s soft timeout only after that
  frame-delay window plus two additional main/render scheduling-boundary frames.
  Ordinary process/physics ticks are not mistaken for completed drawn frames.
- An independent 120 s total-ticket hard cap still rejects stopped rendering,
  a never-submitted ticket, or indefinitely delayed delivery.
- Already available results take precedence. A result arriving between the
  initial poll and watchdog check also suppresses timeout under the ticket mutex.
  Cancelled tickets remain inert and incomplete cubes are never published.
- Diagnostics and timeout messages carry elapsed time, actual device delay,
  elapsed drawn frames and the exact deadline reason.

No source resolution, quality, face order, image bytes, mip construction,
capture environment or synchronous fallback changes. The two extra frames are
an explicit conservative boundary allowance, not an asserted engine callback
delay. The watchdog is only checked when the main loop runs; it cannot recover
a driver that blocks the entire process. It also does not block player input.

The probe is not a static-terrain dependency, so this edit leaves the exact
terrain algorithm and authored snapshot keys unchanged. A requested full
rebake/revalidation is still recorded, with the previous bundle preserved.

## Verification

`tests/source_probe_readback_watchdog_contract.gd` passes 27 CPU checks with
explicit synthetic monotonic times and drawn-frame counts. It exercises the
actual inherited capture advance path with only the clock and error-reporting
seams replaced, and holds the independent draw gate to prevent GPU work.
Coverage includes the observed 38.44 s healthy delay, both deadline boundaries,
two/four-frame device queues, stopped rendering, never/late submission,
completion before watchdog, exact received bytes and cancelled late callbacks.
It is not a native rendering proof.

Existing cube-cache tests pass 43 checks and actual main/world scheduler tests
pass 38. One cold-profile scheduler run emitted an ObjectDB/resource shutdown
warning; its immediate verbose repeat was clean. Both used the headless dummy
renderer, so this is not evidence about RenderingDevice Texture RIDs.

Reports: `verification/eight-hour/transition/probe-readback-watchdog-contract.*`,
`probe-watchdog-cache-contract.log`, `probe-watchdog-scheduler-contract.*`, and
`probe-watchdog-scheduler-verbose.log`. All completed with actual exit code 0.
The corrected full native comparison and isolated resource bisect remain the
parent coordinator's serial jobs; this document does not claim they have run.

The coordinated refresh passed all 15 derived payload reloads, 106 unchanged
core-byte comparisons and all 15 loads through each of the five actual early
targets. `verification/eight-hour/transition/probe-watchdog-cache-manifest.json`
is the authoritative refreshed asset-byte/report index. The original terrain
algorithm and raw-snapshot key are unchanged, as expected for a probe-only edit.
The concurrent native prop probe means the 23.99 s bake duration is not an
isolated performance measurement.

The parent subsequently ran the frozen probe through the tiny native capture/color fixture in both Forward+ and Mobile. Both completed all six asynchronous faces, terminal mips, cube upload and LOD sampling, with 50 checks and normal exit per renderer. Reports are `audit/source_capture_colors/native/{forward_plus,mobile}.json` and bind the current probe SHA. This is small-scene native proof, not yet validation of the observed long-frame full-scene watchdog case.

At the subsequent full-game native readiness checkpoint, all six High-1024 faces and the completed cube were published with one capture, zero errors/cancellations and one correct committed target. The capture took 276.2 s wall time under llvmpipe and final upload took 85.3 ms. The largest delivered transfer was 27.45 s, so this run proves the full-scene path but does not independently exercise the >30 s grace branch. The comparison process was still active at this checkpoint; no clean-exit or final A/B claim is inferred from readiness. The earlier failed run is preserved as `verification/eight-hour/material-lighting/full-game-baked-comparison-attempt01-readback-timeout.log`.

The parent coordinator later confirmed that this hot-swap comparison ended with SIGKILL/exit 137 during its baked-lighting refresh. Therefore it is not a successful complete A/B run or clean-shutdown proof. The earlier completed High-1024 cube remains a valid intermediate observation only. The termination cause is not established by the exit code and must not be attributed to the watchdog or the seven shutdown Texture RIDs without evidence.
