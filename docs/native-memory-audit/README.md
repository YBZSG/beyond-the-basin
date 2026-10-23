# Native capture memory audit

Scope: read-only analysis of three existing native Vulkan Forward+ llvmpipe captures. No Godot/GPU run, production edit, quality reduction, process kill, or target-PC performance claim. Only this new audit folder and `tests/native_memory_audit/` were written.

## Decision

The integrated capture does **not** show a final child-RSS spike or convincing continuous per-frame accumulation. Most memory is established at startup/full-optics initialization, followed by a few scene/traversal-associated allocation steps and long plateaus. A bounded instrumentation A/B is warranted if attribution is needed; a production resource-retirement or shader change is not justified by these artifacts alone.

The process was terminated by SIGKILL, but its source is unknown. Do not label this an OOM, an RSS watchdog kill, or a time-cap kill.

## Corrections to the initial summary

- `water-feel-integrated-01` has **150 numbered PNGs**, `frame0000.png` through `frame0149.png`, not 145. Its JSON holds 145 entries because `capture_step()` saves at indices divisible by eight. Five later frames and the near-grip screenshot survived without their metadata being checkpointed.
- The final numbered PNG was written at relative **1066.805 s**; `integrated-v2-near-grip.png` at **1066.894 s**. The pending phase was still `ordinary_grab_scroll_carry_release`.
- Maximum sampled RSS was **3,137,048 KiB = 3063.523 MiB = 2.992 GiB**, first attained at 990.576 s. The last sample was lower: **3,131,988 KiB** at 1070.238 s. The run ended at 1070.503 s.
- `authored-depth-native-01` completed its visual report (`pass: true`) but its raw process result was **-6 / SIGABRT**, not a clean exit. Its harness uses direct `quit()`. `bath-aperture-native-01` uses `_safe_quit()` and exited zero. These are distinct execution outcomes, regardless of saved visual success.

## Evidence and clock discipline

The source is each capture's chronological `memory.json.rows` array, not a nonexistent `samples` array. It contains 2,744 / 2,472 / 4,149 valid RSS rows for bath / authored / integrated. The requested cadence is 0.25 s, but observed gaps reach 0.320 / 0.290 / 0.343 s because reading/writing the report adds overhead.

PNG time is `PNG mtime - same-run launch.json mtime`. `launch.json` is written immediately before `supervise()`. Relative memory-file completion time differs from recorded monotonic elapsed time by only 0.007 / 0.006 / 0.016 s. Nearest memory-to-PNG alignment is within 0.132 s. No absolute executor clock was used. These checks support approximate phase correlation; they do not turn a PNG timestamp into an exact allocator trace. Reports overwrite phase state and do not preserve phase timestamps.

`metrics.json` preserves numerical rows, phase windows, PNG headers and hash comparisons. `frame-memory.csv` maps every PNG to its nearest memory row. `input-inventory.json` hashes 369 existing inputs. The audit script never imports a capture runner.

## Integrated chronology

Memory in this table is MiB, not decimal MB. Times are relative to process launch (PNG-aligned rows use the closest sampled row).

| Time / observable event | RSS MiB | Anonymous MiB | Shared-memory MiB | Interpretation |
| --- | ---: | ---: | ---: | --- |
| 45.946 s, baseline wide PNG | 2258.35 | 1837.17 | 338.63 | Already substantial before full water optics. |
| 49.814 s, baseline roof PNG | 2260.37 | 1837.73 | 340.09 | Before continuous-wall swap. |
| 69.614 s, continuous-wall wide PNG | 2326.37 | 1892.57 | 351.20 | +66.00 MiB since baseline roof, associated with load/swap/new draws, not isolated mesh cost. |
| 80.041–188.889 s, paused review | 2341.98 | 1892.80 | 366.58 | Exactly flat RSS across 431 rows; no accumulation while paused. |
| 189.508 s, visual-decision file | about 2342 | about 1893 | about 367 | Restored full optics immediately afterward. |
| 200.319 s | 2702.93 | 2129.23 | 491.04 | Large early allocation steps after restoring optical capture. |
| 327.572 s, first accepted full-water PNG | 2964.32 | 2319.78 | 561.87 | Full cube/planar/caustic readiness is recorded. |
| 347.536–390.684 s, 18 valve frames | 2962.11 → 2962.34 | +0.11 | +0.07 | Net +0.23 MiB, <0.94 MiB RSS range. |
| 412.241→412.750 s, first stair frames | 2962.39 → 3022.51 | +60.09 | +0.02 | A discrete ~60 MiB step, not a long ramp. |
| About 690–700 s, later stairs | about 3026.9 → 3036.8 | about +9.6 | small | Another limited step. |
| 823.432→823.694 s, end of descent/changed view | 3037.40 → 3061.63 | +24.88 | -0.66 | Another discrete step. |
| 902.967–1066.793 s, grab + near-grip | 3062.70 → 3062.76 | +0.02 | -0.02 | 36 numbered images, essentially flat RSS. |
| 1068.369–1070.238 s, final 1.87 s | 3063.27 → 3058.58 | 0.00 | +0.25 | RSS fell 4.69 MiB, mostly file-backed pages. |

Aggregate windows:

- Restoring optics, 189.142–327.358 s: **+620.95 MiB RSS**, comprising +426.97 MiB anonymous and +193.91 MiB shared memory. This interval includes the six-face capture and its supporting renderer resources, planar/caustics work and new scene draws. It is **not** a measurement of cubemap payload alone.
- First accepted full-water draw through the late pre-exit plateau: **+98.95 MiB across 741.83 s**. The stair phase accounts for about +100.27 MiB between its first and final PNG-aligned rows.
- Late plateau, 830.214–1069.445 s: **+0.172 MiB net, <0.946 MiB total RSS range over 911 rows**. This includes repeated PNG capture, metadata appends, grasping and near-hold settling.
- In the final 1.87 s, system-wide `MemAvailable` falls **477.71 MiB**, while child RSS falls 4.69 MiB and its anonymous RSS is unchanged. This is a system-level observation, not evidence that this child allocated that memory, and not sufficient to identify a killer or an OOM.

The last 0.266 s between the final row and process completion is unobserved. Sampling cannot exclude a short unsampled event. Conversely, it provides no evidence for one.

## Termination and supervisor

`tests/pc_material_finish_coherent_surface_runner.py:108–157` monitors only the child PID's `/proc/.../status`, plus system `MemAvailable`; it does not record total process-tree or cgroup memory. Its row list lives in the separate Python parent, not the Godot RSS being measured. It atomically rewrites the growing JSON on every poll, so sampling cadence and filesystem activity are not free.

The supervisor records `termination_action: null`. The RSS watchdog was 3,565,158 KiB (3.4 GiB), **418.08 MiB above observed peak**; the wall cap was 1200 s, **129.50 s after exit**. Raw -9 is converted to shell-style 137 by `128 - child.returncode`. This conversion is not an OOM classifier.

The attempted `memory.events`, `memory.events.local`, `memory.current`, `memory.max`, and `memory.peak` reads all failed in the runner's namespace. There is no cgroup event/counter evidence. A null watchdog action means this helper did not record firing either cap, not that an outside actor could not terminate the process.

## Comparison with earlier captures

| Run | Numbered PNG / report entries | Elapsed s | Peak RSS MiB (GiB) | Raw result | Final report |
| --- | --- | ---: | ---: | --- | --- |
| bath-aperture-native-01 | 80 / 80 | 702.023 | 2619.746 (2.558) | 0 | pass / complete |
| authored-depth-native-01 | 96 / 96 | 630.758 | 2790.582 (2.725) | -6 | pass / complete |
| water-feel-integrated-01 | 150 / 145 | 1070.503 | 3063.523 (2.992) | -9 | incomplete |

Bath's first motion image is about 2567.31 MiB. Most later movement remains near 2570–2578 MiB. Its **own** final screenshot/finish interval does show a +42.60 MiB step at 696.325–696.582 s (shared memory +64.16 MiB, anonymous -21.63 MiB), then releases about 503 MiB before the last recorded row and exits zero. The timeline does not distinguish the final extra screenshot, diagnostics, shader-parameter cleanup, or driver retirement as the step's cause.

Authored starts its numbered sequence at 2646.37 MiB and settles around 2790 MiB. Growth also occurs in steps, including 143.687–143.939 s (+25.34 MiB), 377.033–377.287 s (+39.13 MiB), and 514.204–514.460 s (+14.12 MiB). Its final RSS is flat before SIGABRT. Thus neither longer duration nor more PNGs alone predicts monotonic growth.

These are **not controlled feature A/Bs**:

- Same driver/thread setting, 960×540 output, Medium, no main SDFGI, fixed 15 Hz simulation. Cache path is shared, but actual cache hits and initial cache state were not measured.
- Bath uses the old avatar and a lighting A/B, selecting `return-shadow-off`; authored swaps in frozen V2 after initial Main setup, uses no visual-review wait, and a different camera/hold sequence.
- Integrated uses the separate **V2-derived metric-UV cloth GLB**, not the frozen V2 file. The runtime report names `assets/textures/avatar_finish/avatar_finish_candidate.glb`, and two cloth surfaces were applied. Its current embedded source hash matches frozen V2. This is consistent with V2 lineage, not an accidental claim that both assets are byte-identical.
- Integrated adds the wall A/B and retains the continuous-wall mesh, plus quiet valves and notebook, depth-speed response, and a longer recorded carry route. The underlying `formal_bath.glb`, `formal_rooms.gd`, and `source_water_runtime.gd` capture hashes are identical across all three. All three already reach the **same 0.94 m depth / -0.62 m basin floor**; “deeper geometry” is not a new integrated-only explanatory variable here.
- Current `source_liquid_surface.gd` matches bath and integrated but differs from authored. Other production hashes also changed between runs. All **16 tracked integrated paths** still match the launch record and were reported unchanged during capture. The tracked set is not the entire dependency graph: it omits, among others, the actual metric avatar GLB, room-probe/MPM/whitewater source and wall-swap helper. Current hashes of inspected dependencies are recorded separately, not misrepresented as historical capture hashes.

## Instrumentation versus production lifecycle

### Capture instrumentation: real overhead, but no observed retained-image chain

`tests/water_feel_integrated_native.gd:46–59` calls `root.get_texture().get_image().save_png()` every captured frame, then keeps a dictionary of player/avatar/facility state. It does not append the Image or PNG bytes to an array. `image_file()` likewise holds only a local Image. Final report size is 640,434 bytes; 150 numbered compressed PNGs total 28,884,993 bytes on disk. A decoded 960×540 RGB8 image is ~1.48 MiB (RGBA8 ~1.98 MiB); native readback/staging/allocator footprints can exceed this and are not profiled here.

Synchronous screenshot readback and PNG encoding are genuine non-gameplay work and can perturb timing or allocator high-water behavior. They cannot be declared innocent without an A/B. However, 36 final PNGs and repeated full avatar debug dictionaries coexist with only +0.055 MiB net RSS, so this trace does **not** support a growing retained-image list or a fixed multi-MiB-per-captured-frame leak. JSON byte size is not a measurement of Dictionary heap size.

### Cubemap: startup retention plausible; late leak not supported

Integrated readiness records exactly one completed capture, six faces, one cache entry, zero retired mip workers, no pending readback/mip work, and CPU-async backend. Capture time is 128.992 s; no synchronous probe readback or main-thread mip generation is reported. Earlier captures finish with the same one-cube/zero-retired-worker counters. The integrated report does not include a late probe snapshot, so later counters must not be invented.

Current `source_room_probe.gd` explicitly cancels/clears raw faces, transfers them into one mip job, clears worker input faces after mip creation, publishes one cubemap, trims its cache to six entries, and reaps retired jobs (`:301–425`, `:510–549`, `:573–592`). Six 1024-square HDR faces plus mip/copy/upload stages can contribute substantial startup memory; renderer targets and driver allocations add more. A plateau after readiness is compatible with retained renderer/cache capacity. It does not prove a leak, nor prove all driver resources were retired.

### Liquid surface / particles: bounded owners, insufficient live telemetry

Current `source_liquid_surface.gd` creates instance buffers once, rebuilds render targets on size change, frees the previous target list, reuses shadow buffers when dimensions match, and uses engine-managed descriptor caching (`:127–147`, `:257–258`, `:336–353`, `:369–393`, `:431–445`, `:573–624`). Per-frame producer arrays replace stored references rather than append to a history. These ownership paths make unbounded intentional accumulation less plausible, but are **static code evidence**, not measurements of RD/driver retirement.

MPM has explicit limits of three patches, three snapshot slots per patch, four presentation samples and two queued batches; patch destruction clears pending host records and queues RD buffer frees (`source_liquid_mpm.gd:14–24`, `:915–925`, `:1231–1244`). Whitewater caps particles at 1024 and compacts expired particles in place. No current trace records pending RID queues or live allocation bytes.

Importantly, both completed older reports show **zero MPM batches dispatched and zero snapshots received**. Those walks are not a sustained splash-lifecycle test. Integrated lacks final liquid telemetry; do not infer that it exercised, or did not exercise, MPM from a “water ready” bit. The valve sends only weak existing SWE `push_wake` input; its recorded two toggles/one pulse and essentially flat valve-phase RSS do not indicate a runaway spray emitter (`facility_devices_candidate.gd:316–344`). Notebook state is bounded and room observations deduplicate; its final menu stage was never reached.

### Continuous-wall helper

The helper loads/instantiates the full candidate PackedScene once, extracts the replacement wall mesh, frees the temporary source node tree, hides the old drum, and intentionally retains old/new wall resources for reversible restoration. There is one guarded `_state`, not repeated per-frame scene instantiation (`bath_wall_scene_swap.gd:9–48`). Its observed A/B interval adds about 66 MiB, so its initialization residency is worth measuring if the budget is tight. That number is not an isolated geometry byte count, and the late flatline does not point to repeated helper leakage.

## Bounded next experiment, only if owner schedules it

1. **Do not rerun the entire 194-frame harness unchanged.** At the measured last 35 frame intervals (4.684 s each), the 44 remaining numbered frames imply about 206 s more, or completion around **1272.9 s before final menu/exit work**, beyond the existing 1200 s cap. This is a diagnostic scheduling estimate, not a benchmark. Keep caps; split the remaining carry/release/notebook acceptance into its own bounded route rather than lower water fidelity or raise limits.
2. For memory attribution, keep identical current source hashes, assets, lighting, water settings, camera/input path, rendered-frame count and already-chosen wall state. Remove only the human review wait. Compare one arm with existing per-frame PNG capture against one arm with only phase-checkpoint PNGs; keep equal sparse state telemetry in both. Use isolated copies of the same verified cache state, or explicitly mark the cache uncontrolled. Run serially under the existing cap, never concurrently.
3. At startup, full-optics readiness, first stair growth, settled wade, post-grip, and after several ordinary drain frames, record monotonic phase times, process RSS/PSS/smaps, `water.debug_stats()` including probe/terrain/MPM/whitewater counters, liquid surface owned/target RID counts via read-only inspection, scene-target rebuilds, and actual `Performance` resource/object/static-memory monitors. Observe unchanged production lifetimes; do not force a sync/cleanup in the measured gameplay interval. The difference in same-frame RSS plateaus and lifecycle counts is the decision criterion, not total elapsed time alone.
4. If both arms converge after warmup and remain flat, stop blaming capture retention; investigate initial renderer/material/candidate residency only if the memory budget requires it. If one owner/counter rises across otherwise identical cycles without returning, target that owner with a focused lifecycle reproduction. An actual repeated-splash case must be separately admitted before claiming anything about MPM retirement.
5. Record accessible cgroup counters if available; if still unavailable, preserve that limitation. Do not infer OOM from exit137, system `MemAvailable`, or a watchdog threshold that was never reached.

## Reproduction

From the project root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/native_memory_audit -v
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_memory_audit/analyze_capture_memory.py
```

Five pure-Python tests passed: correct `rows` key, chronological ordering, nearest-row alignment, plateau deltas, and failed process-status rows. Existing PNG signatures/dimensions were read, not rendered. No GPU or target-PC tests were run.
