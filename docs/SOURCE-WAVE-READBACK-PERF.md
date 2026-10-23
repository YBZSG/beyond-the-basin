# SWE CPU readback: exact publication and timing

## Subsequent native callback milestone (2026-10-21)

The earlier standard-engine optimization below remains the exact GDScript
fallback. A later optional, strictly ordered CPU GDExtension removes its
remaining interpreted reduction. The **complete production callback** now
measures 36.268 → 0.978 ms median at unchanged 384², 31 alternating measured
iterations, with exact field bytes and reductions checked each time. This is a
97.3% reduction in measured CPU callback time, not a GPU/FPS/device claim.

Both production backends also pass an independent oracle executing literal
original-repository JavaScript and its Three half decoder. The native helper
has actual Linux x86-64, Windows x86-64 and Android ARM64 builds, a disable flag
(`--no-native-water-readback`) and the unchanged fallback. Linux is executed;
Windows/Android are cross-built and audited, not device-tested by this work.

See [exact execution improvements](SOURCE-WATER-EXACT-OPTIMIZATION.md) and
[`native/source_water/README.md`](../native/source_water/README.md) for evidence,
unsupported-platform limits, original fixtures, packaging and reproduction.
`readback_parser_backend` identifies the active path; `readback_native_ms`
measures the fused native stage. Existing convert/reduce/pack timings describe
the fallback rather than fictional subdivisions of the fused native call.

## Historical standard-engine scope and result

This change concerns CPU publication of the existing shallow-water readback, not the caustics shader. It does not change SWE equations, shader dispatches, the 384 × 384 production physics grid, readback cadence, fixed simulation step, source half-float format, or the 30 Hz synchronous-fallback cap. No GPU process was launched for this work.

The existing callback performs two interpreted loops over 147,456 texels. A CPU-only A/B using a real 1,179,648-byte RGBA16F payload found a material cost even without a GPU wait. The optimized implementation replaces scalar validation with native `PackedVector4Array` access and native finite checks, preserves the original ordered scalar energy/peak reduction, and extracts the three channels through native image conversion rather than interpreted per-element scatter.

On this shared host, Godot 4.6.3 official, nine measured iterations after two warmups:

| Path | Median | Min–max |
| --- | ---: | ---: |
| Immutable pre-change runtime callback | 63.715 ms | 59.172–87.915 ms |
| Updated runtime callback, instrumentation included | 35.903 ms | 32.111–48.444 ms |
| Two-loop reference parser | 59.965 ms | 52.462–80.681 ms |
| Fused scalar validation/scatter candidate | 51.855 ms | 47.134–73.189 ms |
| Fused Vector4 validation/scatter candidate | 39.723 ms | 35.244–54.180 ms |
| Native channel extraction candidate | 36.025 ms | 33.416–50.259 ms |

The captured runtime A/B reduction is 43.7%; an earlier A/B in the same session measured 38.3%. The shared host was not isolated from other work, so these are observed CPU costs, not a guaranteed speedup, game-FPS result, or a measurement of the user's device. Invocation order rotates each iteration. Every candidate is checked for byte-identical eta/u/v and exactly equal energy/peak.

Updated callback stage medians in the captured run:

- Half conversion / native packed access: 1.170 ms.
- Validation and original ordered energy/peak reduction: 32.256 ms.
- Native channel packing and atomic publication: 2.440 ms.
- Total instrumented parsing: 35.870 ms.

The remaining ordered GDScript reduction is still substantial. This change does not establish that all perceived caustic lag is fixed. The previously supplied High capture had `sync_reads = 0` and `async_lands = 4`; it does not support blaming synchronous fallback. A new GPU/game capture should use the separate timings below before attributing remaining lag.

Raw measured results: `tests/source_wave_readback_perf_results.json`.

## Exactness of the native path

1. Decode RGBA16F to RGBA32F with the same native image conversion used before.
2. Read each complete texel through `PackedVector4Array`. Require alpha exactly 1 and all components finite. This has been checked against all 65,536 possible half alpha patterns and every Inf/NaN pattern in each physical channel.
3. Compute energy and peak in the same texel order and with the same scalar binary64 expressions as before. No vector dot product, reassociation, approximation, or parallel reduction is substituted.
4. For channel 0/1/2, offset the decoded byte stream by 0/4/8 bytes and restore its original size with trailing padding. Native RGBA32F → RF conversion selects the first component of each texel. Only discarded components of the final texel contain padding. There is no spatial resizing, filtering, averaging, or simulation downsampling.
5. Build all three replacement arrays before publishing any of them. Publish fields and reductions together on the main thread, then emit `physics_updated`.

The path uses temporary byte/image arrays in exchange for fewer interpreted operations. No extra rendering resource, native extension, package, or platform-specific binary is required. The standard Godot 4.6 build's float32 packed-vector layout is exercised by exhaustive tests, including signed zero, subnormal halves, and maximum finite halves.

Godot's relevant native implementation is in [Image](https://github.com/godotengine/godot/blob/4.6/core/io/image.cpp); available packed-vector/byte APIs were also checked against the actual 4.6.3 engine API dump.

## Source timeout and fallback audit

Baseline: [`shallow-water.ts` at 66a4543602d9e774db07c2da12ce1d40d522532c](https://github.com/YBZSG/beyond-the-basin/blob/66a4543602d9e774db07c2da12ce1d40d522532c/app/pool-vct/shallow-water.ts), `requestReadback`, `flushReadback`, and `parseReadback`.

- The source retires an unfinished async request after **more than** one simulation-clock second. A retired promise completing later is recycled, not parsed. The previous Godot callback could still parse and publish that late result. Production requests now carry monotonic IDs; retirement, reconfiguration, and disposal invalidate the active ID. A late callback cannot overwrite physics or clear a newer pending read, even when a reset reuses the same simulation timestamp.
- A current callback from an old terrain/rebase generation releases its pending request but never publishes its pixels. A genuine transport failure remains a failure even if the terrain generation changed while it was pending, matching the source's failure-before-generation check.
- The timeout still uses the simulation clock, not the newly added wall-clock metrics. Synchronous fallback still has the source 1/30-second cap. No speculative sync read has been added.
- `async_lands` now counts accepted current-generation async completions before payload validation, matching the source. `sync_reads` counts completed synchronous reads, including a malformed/stale payload, rather than only successful publications. `readback_publishes` separately counts usable physics updates.
- Async API errors, timeouts, stale results, and malformed pixels are now separate counters. `rejected` describes malformed payloads; `readback_async_errors` describes async transport failures.
- For compatibility, `readback_bytes` remains the received byte total for current-generation callbacks; unlike the original TypeScript request-byte counter, it is not a measure of all submitted GPU transfer traffic.

## Runtime diagnostics

`SourceWaveSolver.debug()` now includes:

| Key | Meaning |
| --- | --- |
| `pending_ms` | Wall-clock age of the currently outstanding request, zero when none. |
| `readback_latency_ms`, `readback_latency_max_ms` | Request enqueue to main-thread callback start, excluding parsing. |
| `readback_rd_queue_ms` | Request enqueue to entering the read API on the render thread. This includes preceding queued render work. |
| `readback_transfer_ms` | Read API start to callback-ready, or synchronous return. Includes engine/GPU scheduling and transfer overhead; **not** a pure GPU timestamp. |
| `readback_delivery_ms` | Callback-ready to main-thread deferred delivery. |
| `readback_sync_ms` | Last synchronous API wall duration, independent of whether its payload publishes. |
| `readback_parse_ms`, `readback_parse_max_ms`, `readback_parse_total_ms`, `readback_parse_count` | Main-thread parser cost, including rejected payloads, but excluding downstream signal subscribers. |
| `readback_convert_ms` | Native half decoding and packed access. |
| `readback_validate_reduce_ms` | Validation and unchanged ordered reductions. |
| `readback_pack_ms` | Native channel extraction and publication. |
| `async_lands`, `sync_reads`, `readback_publishes` | Completed reads versus accepted physics publications. |
| `readback_timeouts`, `readback_async_errors`, `readback_stale`, `rejected` | Distinct failure/retirement causes. |
| `async_failed` | Whether subsequent readback requests use source synchronous fallback. |

These diagnostics measure CPU wall time and queued delivery. They do not invent GPU duration data. Counters and accumulated timing remain lifetime diagnostics across repeated `configure()` calls; pending age is cleared and active IDs are invalidated.

## Verification and reproduction

Passed, CPU-only:

- `source_wave_readback_contract.gd`: 30 assertions; all 63,488 finite half encodings in all three fields, exact reductions, all 6,144 nonfinite channel cases, all 65,535 invalid alpha patterns, wrong-length payloads, signal-time atomicity, generation/disposal guards, timeout retirement, reused timestamps, async-error ownership, and stage accounting.
- `source_wave_readback_perf.gd`: production-sized deterministic half-byte fixture; every path checks all field bytes and exact reductions in every iteration.
- Existing `source_wave_contract.gd`: 27 assertions.
- Existing `source_field_shift_test.gd`: 30 assertions.
- Existing `source_coupling_test.gd`: 16,057 comparisons, no failures.

From the project directory:

```sh
godot --headless --path . --script tests/source_wave_readback_contract.gd
godot --headless --path . --script tests/source_wave_readback_perf.gd -- --output=/tmp/readback-perf.json
```

For an exact old-runtime A/B, preserve the old solver before editing, then add `--baseline-script=/absolute/path/to/old-source-wave-solver.gd`. The captured pre-change solver SHA-256 was `40ab04ee531509a2d559648c59a4d9b70c61d155b6ff78d14371cd8f817e41ef`. The benchmark also embeds the old two-loop parser, so candidate and runtime comparisons remain available without that external snapshot.

No GPU validation was claimed by this CPU-only work. Run the existing global-RD wave test or the parent game capture once the shared GPU slot is available to verify callback timing in the full scene.
