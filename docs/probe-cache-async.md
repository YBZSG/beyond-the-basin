# Native PC room probe: asynchronous readback and immutable cache

The runtime keeps the source cubemap contract: six 1024 × 1024 faces at `(origin.x, 3.4, origin.y)`, a 90° capture camera, source face/up ordering, architecture/props layer only, and a linear HDR capture environment. The existing `Image.generate_mipmaps()` algorithm is unchanged. This is an ordinary mip chain, **not** Three.js GGX PMREM convolution or a PMREM CubeUV atlas.

## What changed

- `request(origin)` is idempotent while that origin/resolution/lighting revision is pending or already published. Repeated requests cannot perpetually restart the six faces.
- A bounded LRU retains up to six completed, immutable `Cubemap` objects, one per origin and resolution within the current lighting revision. A hit publishes the exact existing resource without rendering, GPU readback, mip generation, or texture upload. The default costs roughly 64 MiB per RGBA16F cubemap, up to 384 MiB GPU storage; driver/CPU staging and temporary resources add overhead.
- One face is rendered at a time. After `frame_post_draw`, a `RenderingServer.call_on_render_thread` callback obtains the **global** RenderingDevice and its viewport RD texture. `texture_get_data_async` snapshots that face without an explicit GPU synchronization/readback stall. The viewport is not reused until its face result arrives.
- Mutex-protected, independent RefCounted callback tickets never access the probe Node or scene tree. They can safely outlive cancellation/disposal. Canceled callback results are discarded.
- Godot opaque HDR viewport textures are logically RGBH but backed by RGBAH RD storage. The worker reproduces the engine’s logical-format conversion before mips, preserving the old `get_image()` channel format and pixels without a synchronous readback.
- Six completed face buffers are transferred to a private WorkerThreadPool job. Only that job creates/mutates its Images and generates mipmaps. Completed tasks are reaped before their results are read. Obsolete generations cannot publish or contaminate another room/revision.
- Final `Cubemap.create_from_images` remains a one-time main-thread publication/upload and is measured explicitly. Async downloads still consume bandwidth and render time. This is not a claim that the entire capture is GPU-only or that all PC frame stalls have been eliminated.
- Unsupported renderers/formats fail visibly rather than silently reverting to synchronous readback, LDR, reduced resolution, or a different water algorithm.

## Integration contract

Unchanged: `configure(camera, environment)`, `request(origin)`, `update()`, `refresh_lighting()`, `completed(texture: Cubemap)`, `dispose()`.

`refresh_lighting()` is now **explicit invalidation**, not a helper to call every time a room is requested. It increments the revision, clears the cache, cancels the active generation, and copies the complete source Environment with the original linear-capture overrides. Request the active origin afterward. This prevents incorrectly reusing an old lighting configuration. Changes to external lights or geometry must also be announced by the caller, since their state cannot be inferred from an origin alone.

Use `invalidate_room(origin)` when geometry/fixtures at the same known origin actually change. Do not invalidate merely because an unchanged cached room is revisited. A new `configure` clears old world state.

An uncached switch or invalidation clears the currently published texture and emits `completed(null)` if necessary. The existing liquid-surface consumer already accepts a nullable Texture and uses its no-environment branch, so the previous room/lighting cannot remain bound while the correct capture finishes. A cache hit publishes the correct Cubemap immediately.

Shutdown may wait for already-running **CPU-only** mip jobs to finish, then reaps them. Gameplay update never waits for incomplete worker tasks or GPU readback. No queued callback touches a freed Node. `dispose()` is idempotent.

## Instrumentation

`diagnostics()` includes requests, deduplicated requests, cache hits/misses/evictions, capture starts/completions/cancellations, face reads, invalidations/errors, active stage/generation/revision, and timing values in milliseconds:

- `last_readback_ms` / `max_readback_ms`: asynchronous wall latency, **not main-thread blocking duration**.
- `last_mip_worker_ms`: worker CPU-stage wall time, outside gameplay main thread.
- `last_upload_ms` / `max_upload_ms`: final Cubemap publication/upload call duration.
- `last_capture_callback_ms` / `max_capture_callback_ms`: main-thread `frame_post_draw` callback dispatch cost, including any direct execution under a single-thread renderer.
- `last_update_ms` / `max_update_ms`: observed probe `update()` duration, including upload on publication frames.
- `last_capture_ms`: full uncached capture latency across frames.
- `synchronous_readbacks` and `main_thread_mip_generations`: zero by construction; this applies to the runtime probe, not validation instrumentation.

## Validation

`godot --headless --path . --script tests/probe-cache-contract.gd` checks deduplication, exact source orientations/resolution, cache identity/revision/resolution/LRU behavior, cancellation, generation rejection, disposal, and worker-generated mip bytes against the unchanged Image algorithm.

`godot --path . --script tests/probe-cache-gpu.gd` is a **serial native GPU test**. It captures at 1024, compares every final face and mip byte to the old `ViewportTexture.get_image()` reference path, verifies HDR highlights, cache hits, lighting invalidation, cancellation, and disposal. Its synchronous reference readbacks are deliberately test-only; timings from this diagnostic run do not represent runtime capture throughput. Native GPU test execution must be coordinated with the main validation run to avoid concurrent GPU workloads.

## Godot 4.6 API references

- [RenderingDevice async texture readback](https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html#class-renderingdevice-method-texture-get-data-async): callback delivery occurs after queued frames; transfer bandwidth can remain costly.
- [Render-thread call dispatch](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#class-renderingserver-method-call-on-render-thread): required for safe global RD access.
- [WorkerThreadPool](https://docs.godotengine.org/en/4.6/classes/class_workerthreadpool.html): every task must eventually be waited/reaped.
- [Thread-safe API guidance](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html): worker code owns private Images; live scene-tree work remains on the main thread.

Verified parser/runtime API version: Godot 4.6.3 stable official (`7d41c59c4`). Native GPU compatibility is established separately by the coordinated GPU test, not by a headless pass.

## Recorded validation: 2026-10-21

- Godot 4.6.3 headless contract: **43 assertions passed**.
- Serial native Vulkan/Forward+ test on Mesa llvmpipe: **86 assertions passed, exit 0**, with no runtime errors or resource-leak warnings. All six 1024-square RGBH faces and their complete mip chains matched the prior synchronous reference byte for byte. See `tests/probe-cache-gpu.log`.
- This software-rendering diagnostic observed at most **0.269 ms** in the capture callback, **52.105 ms** for one-time final upload, **88.972 ms** for the last CPU mip job (off the main thread), and **1.123 s** last uncached capture latency across frames. It is not a hardware-PC FPS claim or a clean performance benchmark, because reference readbacks run in the test. Cache hits do not repeat those stages.
- The first test exposed the RGBH-versus-RGBAH logical-format distinction; the worker was corrected to reproduce Godot’s original conversion, and the strict comparator was retained. No lower-resolution/LDR fallback was added.
