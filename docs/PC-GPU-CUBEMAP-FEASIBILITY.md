# PC GPU-only room cubemap: feasibility audit

Date: 2026-10-22. Status: **API-feasible, not implemented or GPU-validated**. This is a follow-on optimization proposal, not a blocker for the active visual milestone. No production code, render settings, bake, hardware selection, or remote publication changed; no Godot/GPU process was launched for this audit.

## 1. What the actual Medium run establishes

[`lightmap-memory-medium-full-01.json`](verification/pc-refine/lightmap-memory-medium-full-01.json), `ready_water.probe`, records one completed 6 × 1024 capture with no errors/cancellations:

- Total capture: **150,296.430 ms**.
- CPU mip worker: **73.032 ms**, about 0.049% of that total.
- Final `Cubemap.create_from_images` call: **76.249 ms**, about 0.051%; peak probe main-thread update was 78.737 ms.
- Last face readback latency: **24,245.482 ms**; maximum: **44,252.388 ms**. The JSON contains last/max, not six individual face durations, so it does not establish a 24–44 s range for every face.
- The frame-aware ticket recorded a frame delay of 2. The companion outcome/memory records describe the llvmpipe full-game run and normal exit. These are software-renderer timings, not target-PC performance.

The state machine in [`source_room_probe.gd`](../scripts/water/source_port/source_room_probe.gd), lines 300–346, cannot advance `_index` until each asynchronous callback has returned. That serial draw → callback retirement → next face chain is the strongest optimization target. Removing the already-short CPU worker alone would not explain or solve this measured delay. The total does **not** isolate GPU face render time from render-queue, callback and main-loop delay.

This room-reflection preparation path is distinct from water/particle simulation readbacks. Eliminating it does not by itself prove that splash motion stutter is fixed.

## 2. Original source fidelity boundary

The vendored [`engine.ts`](../source_provenance/beyond-the-basin-66a4543/app/pool-vct/engine.ts), lines 678–706 and 996–1000, creates a 1024 `HalfFloatType` cube target, captures one face per eligible frame, hides water, temporarily disables shadow auto-updates, then calls `PMREMGenerator.fromCubemap` on a later frame. It swaps `scene.environment` only after that result exists. Its temporary `generateMipmaps` suppression is not itself the PMREM filter.

[`liquid-surface-pass.ts`](../source_provenance/beyond-the-basin-66a4543/app/pool-vct/liquid-surface-pass.ts), lines 96 and 140–147, samples the resulting packed CubeUV environment at roughness 0.07 and derives CubeUV layout parameters from it.

The current Godot port instead generates ordinary per-face image mipmaps and uses `textureLod(environmentMap, R, .07 * max_mip)` in [`liquid_composite.frag`](../shaders/source_water/liquid_composite.frag). **A GPU implementation of those same ordinary mips preserves the existing port; it neither implements nor demonstrates equivalence to Three PMREM.** Keep all optical shader expressions, resolution, camera transforms/cull mask, capture exposure, terrain/lighting invalidation and publication behavior unchanged. PMREM and retaining stale reflections throughout replacement capture are separate optical changes.

## 3. Exact-build API evidence and integration traps

The existing [`extension_api.json`](../tests/fixtures/particle_gate_audit/extension_api.json) identifies Godot **4.6.3 stable official, single precision**, SHA-256 `89af44773166b2f6cfe45ccecbdc609a69eb33c95aa169d99472ac252be25a09`. It exports:

- Instantiable `TextureCubemapRD`, derived from `TextureLayeredRD → TextureLayered → Texture`, **not** `Cubemap`.
- `texture_rd_rid`, `RenderingDevice.texture_create`, nine-argument `texture_copy`, `texture_create_shared_from_slice`, and format/usage queries.
- Script-visible slice types `TEXTURE_SLICE_2D`, `CUBEMAP`, `3D`. No generic GPU `generate_mipmaps` method. Do not depend on newer array-slice enum/argument examples.

This is actual-build exported-class evidence, not a newly executed ClassDB or device-capability test. The [4.6 TextureCubemapRD documentation](https://docs.godotengine.org/en/4.6/classes/class_texturecubemaprd.html) confirms its intended RD-cubemap use.

Required adapter changes in a future implementation:

1. Probe `completed(texture: Cubemap)` and `texture: Cubemap` must accept a common cubemap-compatible `TextureLayered`/`Texture` contract. A cast is not sufficient.
2. [`SourceLiquidSurface.configure_environment`](../scripts/water/source_port/source_liquid_surface.gd), lines 95–99, accepts `Texture`, but infers max LOD only for `is Cubemap`. Blind substitution leaves max LOD **0**, instead of **10**, and changes the optical result. Pass validated max LOD explicitly or generalize the layered-texture check; preserve the shader's resulting LOD **0.7**.
3. Its render callback already obtains a global-RD texture from the resource's RenderingServer RID and binds `samplerCube`. That bridge can remain. Verify cube type, six layers, 11 levels and a valid initialized wrapper before publication.
4. Typed fixtures in `probe-cache-{contract,gpu}.gd`, `source_probe_scheduler_contract.gd` and `source_capture_color_native.gd` need adapter coverage, not weakened assertions. RGBH logical image output versus RGBAH GPU storage requires explicit RGB comparison/opaque-alpha handling, not a lossy format conversion.

## 4. Proposed GPU pipeline

Use the **global** RenderingDevice on its render thread, never a local RD. Preserve the single SubViewport and its six capture orientations.

1. Allocate an unpublished original `TEXTURE_TYPE_CUBE`: width/height 1024, depth 1, six array layers, 11 mip levels, sample count 1, matching physical HDR format. Required usages: sampling, storage, copy-to; copy-from additionally for validation or any copy-based staging. Query format support and filtering first. Reject unsupported formats without lowering precision/resolution.
2. After each requested viewport draw, resolve the actual viewport RD RID and validate size, format, sample count and copy-from usage. Copy base mip/layer 0 to candidate mip 0/layer `face`. Keep source and destination physical formats identical. `texture_copy` does not perform resizing, color conversion, alpha swizzling or filtering.
3. Generate each next level from the previous level with an explicit 2 × 2 ordinary average. Use **one-face, one-mip 2D shared views** for storage access; do not bind a cube as an `image2DArray` or wrap a shared slice as `TextureCubemapRD`. Start with separate compute lists per dependency level, letting RD track real read/write views. No cross-face convolution, seam blur, renormalization, gamma conversion or implicit derivative LOD.
4. Initialize a `TextureCubemapRD` with the **original** cube RID, then publish only after all six copies, all mip work and wrapper setup have been encoded in order. Cache that immutable result; never overwrite a published cube.

The [4.6.3 RD implementation](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/servers/rendering/rendering_device.cpp) supports layer/mip copies and single-face 2D views of cubes. The 4.6 documentation's restriction on *layer slicing* does not forbid these single-face views. Use the exact 4.6.3 call signature and documented 2D Z convention, then validate a real copy before integrating; do not copy a newer API example. [RD API reference](https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html).

### Exact mips are not a naïve `imageStore`

Godot's [CPU image implementation](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/core/io/image.cpp), `_generate_po2_mipmap`, `average_4_half` and `generate_mipmaps`, averages top-left, top-right, bottom-left, bottom-right components, then quantizes at **every** level. Its RGBH/RGBAH channel-count conversion uses a fast bit-preserving path.

Crucially, [Math::make_half_float](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/core/math/math_funcs.h) truncates mantissa bits and zeros sufficiently small outputs rather than applying ordinary nearest-half rounding. Hardware half stores and filtered blits are therefore not a demonstrated byte-equivalent replacement.

Proposed exact path: explicit ordered float32 arithmetic plus CPU-compatible half quantization/decoding before store. Prevent arithmetic reassociation and validate subnormal input handling. If float image reads cannot preserve the required input domain, investigate a supported integer shared view and explicit decoding; do not assume cross-format alias support. NaN/Inf and signed-zero behavior must be classified. If exactness cannot be established, keep this candidate off rather than silently relaxing parity. For RGBA32F, preserve float32 association and test that separate path, or explicitly leave that format on the existing path.

## 5. Ordering, cancellation and ownership

[RenderingServer](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html) defines `frame_post_draw` after viewport updates and provides `call_on_render_thread`; neither is a CPU-visible GPU-completion fence.

- Each face needs an immutable ticket containing generation, lighting revision, room key, face index, source identity and draw sequence. After post-draw, queue its copy. Advance/reorient the reused camera only after a small **copy-encoded acknowledgment**, not after a pixel readback or GPU fence. This prevents a deferred copy from observing the next face. Verify the acknowledgment/next-render ordering with distinct animated face markers.
- Keep cross-thread state in isolated RefCounted tickets with synchronization, not mutable Nodes. Do not mark a new request ready from an old completion. A canceled command already encoded cannot be undone; canceled candidates must never publish.
- Final acknowledgment means commands/wrapper are ordered for a later consumer draw, not that the GPU has physically finished. Validate the first actual sampling frame, not merely `texture != null`.
- Use RD's dependency tracking, not deprecated `barrier()`/`full_barrier()` as a guessed fence. `submit()`/`sync()` are local-device APIs and are not an acceptable global-RD fix.
- Wrapper assignment is render-thread work. [TextureLayeredRD source](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/scene/resources/texture_rd.cpp) shows its deferred setup and wrapper-only teardown. [RD texture storage](https://raw.githubusercontent.com/godotengine/godot/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp) rejects shared input RIDs and creates a non-owning shared view of the original allocation. **Dropping a wrapper does not free the original owned cube.**
- Introduce explicit lifetime ownership shared by cache, active publication, consumer and queued tickets. Merely adding `free_rid` on LRU erase would invalidate an externally retained texture. Retire only after consumer detachment/replacement and queued command encoding; free owned allocations on the render thread. Never free the borrowed viewport RID, consumer bridge RID or already-auto-freed dependent views twice. RD defers underlying destruction, but that does not make use-after-logical-free safe.
- Preserve capacity 6, room/resolution identity, full lighting revision invalidation, cancellation, cache hits and current availability/readiness distinction. Disposal must stop new work, cancel tickets, detach consumers, retire candidates/cache resources, disconnect signals, then release the viewport safely. Cover queued wrapper setup during shutdown.

## 6. Resource cost and non-claims

A 1024 RGBA16F cube is **48 MiB base / 67,108,848 bytes (~64 MiB) with all mips**. Six cached cubes are ~384 MiB; one builder adds ~64 MiB, plus the viewport, descriptors, temporary views and delayed retirement. RGBA32F doubles these figures. These are arithmetic payload sizes, not measured allocations or a RAM/VRAM improvement claim. Old RGBH may use different physical storage on different devices.

The proposal removes six CPU pixel transfers, CPU face images/mip work and final pixel re-upload from the optimized path. It does not remove six scene renders, GPU copy/compute bandwidth, main-scene cost or driver scheduling. Serial encoding acknowledgments can still consume frames. Faster capture also samples moving props/lighting/caustics at different times, so static image parity does not prove dynamic temporal identity.

## 7. Acceptance gates before default enablement

All gates below are **proposed, not run**. Stage them after the visual milestone; no new bake is needed.

1. **Capability and parser:** exact 4.6.3 editor/export builds expose the classes, methods and formats; validate global RD, cube/storage/sampling/filter capabilities and successful 2D → cube layer copy. No renderer upgrade, unsupported aliasing or quality fallback.
2. **Numerical oracle:** freeze the same six base faces. Compare all RGB components at every mip against the current `MipJob` on that engine: **0 mismatched base/mip values** for the exact path, across HDR ramps, asymmetric face labels, checkerboards, randomized half values, powers of two, rounding boundaries, near-zero/subnormal and signed-zero cases. Classify non-finite inputs explicitly. Compare logical RGB separately from RGBA padding; require opaque-alpha semantics when logical RGB was used. Test 1024/11 levels, not only tiny textures.
3. **Sampling optics:** unchanged shader hashes and constants; prove max LOD 10 and actual sample LOD 0.7. Sample cardinal directions, both sides of all cube edges, corners and fractional LODs in the real consumer. For matched frozen full-game A/B, require exact HDR input equality and no reproducible reflected-detail/exposure/orientation change; final tone-mapped images alone are insufficient. Animated-marker testing must show no duplicate/wrong face or half-built publication.
4. **Scheduling:** zero runtime pixel readback calls/bytes, zero CPU mip jobs and zero `create_from_images` uploads in the GPU path. Exactly six distinct successful face copies per completed miss; no callback-frame-delay gate between faces. Log request/draw/copy-encoded/mip-encoded/wrapper-ready/first-sampled frame IDs and wall times. Probe publication CPU p95 ≤1 ms and max ≤2 ms are initial target-PC goals, not claims; record render-thread encoding separately.
5. **Lifecycle:** repeated same-key requests; A→B→A before/after commit; cancel at each face/mip/wrapper stage; lighting refresh; resolution change; cache eviction with a retained external reference; pause/resume; immediate quit during copy. Require zero stale/partial publications, zero invalid-RID/thread errors, zero owned resources after disposal, bounded retirement, and no upward allocation trend over repeated cycles. Compare engine-baseline leaks rather than attributing unrelated existing leaks to this path.
6. **Actual PC full-game:** serial same-device A/B at unchanged Medium/High settings, scene, camera, source resolution and workload. Measure cold capture-to-first-correct-sample, transition frame-time p50/p95/p99/max, update/encode/GPU timings, memory high-water and rendered-frame count. Require lower repeatable cold readiness time and no material frame-time/memory regression; report sample counts and variability. A callback-count improvement alone is not a speedup result, and llvmpipe data cannot establish hardware FPS. Independently re-run splash-motion/readback acceptance because this change addresses room reflections only.

**Recommendation:** retain the current tested path and visual work unchanged. Next, if implementation is approved, build a quarantined tiny GPU copy/mip/ownership oracle first; proceed to a full-game candidate only after exact numerical and lifecycle gates pass. A full PMREM port remains separate work.

### Audited production identities

- `source_room_probe.gd`: `da0b2fed70109915843b88c618934915e738dcfee5851f794c1da596754229fa`
- `source_liquid_surface.gd`: `8087473a9dd9edce3c172391ed94ea3f1d370f44cde02995f2266178e5471685`
- `liquid_composite.frag`: `8190878f495672f49640d400f6f144edc0dd59f08631891ddeb6eec3e0aca882`
- Medium evidence JSON: `a6fe02b61e280d7236a19e3413cd708630e7b63df5fc79d0b56a748c679b6877`
