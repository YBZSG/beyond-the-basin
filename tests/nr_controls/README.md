# NR control / experimental layer source contracts

## Scope and actual verification

This change prepares source for a rebuilt optional NVIDIA Godot runtime. It does not update an installed EXE/PCK and does not establish that NR works on this cloud machine. The available stock Godot cannot exercise these NGX paths.

Run the CPU-only checks:

```sh
python -m unittest discover -s tests/nr_controls -p 'test_*.py' -v
python -m py_compile tools/dlss/run_qa.py tools/dlss/build_nr.py
```

The suite applies the additive patch to the original C++/header and render-hook context embedded in `engine-dlss-nr.patch`, plus independently verified pinned graph-callback source context, checks structural contracts, compiles/runs the actual SDK-independent numeric-validation header, and tests the Python QA profile/evidence helpers. It does **not** apply the complete patch stack to a downloaded engine, compile Godot/NGX/Vulkan, exercise SDK ABI, produce images, measure VRAM/frame time, or prove temporal stability. Source substring checks are guards, not GPU simulations.

## Native implementation

`engine-dlss-nr-controls.patch` is applied **after** the existing NR patch. The original integration remains an unmodified base patch.

- Default: one evaluation, intensity `1`, local tone `.1`, local structure `.5`.
- Experimental layer choice: integer `1`–`4`. Each active layer has its own NGX feature handle, temporal history and output texture. Layer N reads the previous output, not the original input. A returned duplicate feature handle is rejected rather than silently sharing history.
- All layers receive the same selected strengths, scene depth, motion vectors, jitter and uniform control mask. Reusing scene guides after appearance changes is an explicit approximation, not new flow-aware water guidance or semantic material masking.
- Inter-layer compute barriers order shader writes and reads; all outputs are declared to the render graph. An inherited pinned-engine bug also receives a conservative fix: `RenderingDeviceGraph::add_driver_callback` now declares `ALL_COMMANDS` execution stages, rather than the empty default, so callback entry/exit dependencies cover external compute and fallback transfers. This applies to driver callbacks generally and needs native correctness/performance validation; it is not proof of improved frame time.
- Output-size, layer-count and network-preset changes wait for GPU idle before releasing all features and rebuilding the resource context. A strengths/input/gap/camera change resets history. Strength changes alone do not recreate features. No per-layer or per-frame steady-state `vkDeviceWaitIdle` is added.
- Every target/input/output/mask/depth/MV texture is checked with `texture_is_valid` before use and callback-data allocation. A rejected callback enqueue deletes the untransferred frame payload and returns without replacing the original target. Invalid cached resources latch failure rather than reallocating every frame.
- Any init, capability, creation or evaluation failure leaves/restores the original pre-NR frame, never a partly enhanced chain, and latches native failure until renderer shutdown. Nothing reports an effective partial chain.
- FG exclusion, single-view SDR Vulkan/DLSS prerequisites, HUD placement, water code and current renderer settings remain unchanged. Turning NR off stops dispatch, but its cached textures and feature/history allocations remain until recreation or renderer shutdown; off is not a promise to free VRAM. A locked main target that becomes smaller than 960 pixels wide or multiview reports bypass immediately; incidental capture targets remain ignored.

This is a bounded custom integration experiment, not an Omniverse attribute copied into Godot. NVIDIA documents experimental iterations 1–4 with separate histories and warns of additional processing/memory cost and no guaranteed quality improvement: [official controls](https://nvidia-omniverse.github.io/ovrtx/sensors/cameras/render_modes/dlss_nr.html#controls). Keep one layer while exploring strengths. Layers are not a room-transition stutter fix.

## Process-local UI contract, schema 1

The panel writes a single JSON snapshot to `POOLCORE_NR_CONTROL_V1`. The pre-existing `POOLCORE_DLSS_NR=1` remains the opt-in. Example request, not runtime evidence:

```json
{"revision":7,"layers":2,"intensity":1,"tone":0.3,"structure":0.6}
```

Fields omitted or malformed fall back to original defaults; missing/invalid JSON is nonfatal. Strengths are finite, clamped 0–1; nonfinite values use each original default. Layers are integral and clamped 1–4; nonintegral/nonfinite values fall back to 1. Revision is a nonnegative integer through 2^53−1 (the exact JSON-number integer range, stored as int64), otherwise 0. The UI increments revision only for a real requested configuration change. No other environment variable silently multiplies layer count.

Native writes `POOLCORE_NR_STATUS_V1` after state/config transitions and at most a one-second interval while unchanged and the main viewport is rendering. Native state includes:

- `schema`: 1.
- `process_id`: current native process, to reject inherited status from a different executable process.
- `emitted_msec`: monotonic Godot ticks, to reject a stale acknowledgement when rendering stops. No heartbeat is promised while the renderer is stopped/minimized.
- `supported`: whether this build contains the NR-controls path and SDK. This is **not** a hardware-support claim.
- `capability`: `unknown`, `available`, or `unavailable` from the native capability path.
- `state`: `off`, `waiting`, `active`, `bypassed`, or `failed`; `reason` explains it.
- `requested_revision`, `requested_layers`, `requested`: latest sanitized request, with the latter containing layers/intensity/tone/structure.
- `applied_revision`, `applied_layers`, `applied`: the complete last successful native chain while active. In other states these are `-1`, `0`, `{}`.
- `successful_frames`: complete-chain API successes, not a measurement of displayed FPS or visual quality.

Example successful status, illustrative only:

```json
{"schema":1,"process_id":1234,"emitted_msec":2500,"supported":true,"capability":"available","state":"active","reason":"all_layers_dispatched","requested_revision":7,"applied_revision":7,"requested_layers":2,"applied_layers":2,"successful_frames":42,"requested":{"layers":2,"intensity":1,"tone":0.3,"structure":0.6},"applied":{"layers":2,"intensity":1,"tone":0.3,"structure":0.6}}
```

Before first opt-in, a supported rebuilt engine can report `state=off`, `capability=unknown`, `applied_layers=0`. A rebuilt engine without the SDK reports `supported=false`, `capability=unavailable`, `reason=engine_without_nr_sdk`. An old engine has no new protocol acknowledgement. UI must not equate DLL existence, saved settings or absent status with applied layers. Current-process/fresh schema-1 `active` status must match the UI revision before claiming that request dispatched; inspect paired frames and motion separately.

## Windows-only transport boundary

The pinned Windows OS implementation copies `GetEnvironmentVariableW` into a caller-owned buffer and writes with `SetEnvironmentVariableW`. No shared CRT `getenv` pointer is retained. This review found no Windows pointer-lifetime blocker for the process-local JSON bridge. The pinned Unix implementation uses raw `getenv`/`setenv` without a Godot lock; this transport is **not certified for a future Linux/macOS NR engine**. The supplied build route targets Windows only. A port must replace or synchronize that bridge before claiming multithreaded safety.

## QA launch routing fix

`run_qa.py --nr on/off` now updates the copied profile's `graphics.nr`, not only the environment. It leaves unrelated settings and saved NR strengths/layers intact. This setup happens once; a subsequent explicit live-panel change is not continuously overwritten. `--nr off` is rejected as a baseline if any successful NR dispatch appears in the log. NR-on still requires success (unless deliberate bypass is requested) and rejects evaluate failures.

## Remaining validation gate

A separately authorized matching engine/SDK build and NVIDIA-capable runtime must establish:

1. Full pinned-tree patch application and C++/NGX ABI compatibility, including no-SDK build.
2. Actual dispatch for each layer count, distinct feature creation, matching status revisions, and controls reaching native eval values.
3. Off/bypass/missing-runtime/FG/HDR and failure fallback, including a failure at a later layer.
4. 1→4→1 switching, resize, DLSS mode changes, processing gaps, camera cuts, scene/viewport replacement and shutdown, with validation-layer/resource checks.
5. Matched original-vs-final captures and moving water, hands and room transitions, with HUD unchanged.
6. Uncapped frame time, GPU time and VRAM for 1/2/3/4 layers after warmup, excluding capture stalls. More layers need not look better and can exacerbate stutter.

The inherited primary-target lock still selects the first eligible main-sized viewport. Replacement by a new target requires runtime review; status freshness prevents an old active acknowledgement from remaining valid indefinitely, but does not prove target replacement is supported.
