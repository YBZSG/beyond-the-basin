# Exact incoming-light mask acceleration

## Result

The optional freestanding `SourceWaterReadback` GDExtension now also exposes
`build_occlusion_masks(PackedFloat32Array boxes, PackedFloat32Array lamps)`.
It preserves the existing readback method and all three actual platform
artifacts. It performs no rendering, graphics calls, filesystem operations,
thread scheduling, or application-state publication.

On a shared Linux host with Godot 4.6.3, a paired, alternating CPU benchmark
of the real seed-250821 origin room (109 filtered solids) measured:

| Path | Median | Observed range |
|---|---:|---:|
| Immutable old GDScript kernel | 8,930.159 ms | 8,517.500–9,932.735 ms |
| Native exact kernel, including input packing | 115.480 ms | 100.240–134.309 ms |

Nine measured iterations followed two warmups. Every returned mask byte was
compared after every call. The median CPU-time reduction is **98.7069%**.
These are not GPU timings, FPS measurements, target-device results, or a
guarantee about a user's computer.

## Preserved numerical contract

- Exactly two 256×256 R8 masks, original row/column/lamp order and 32 m domain.
- Original `.31` start plane, finite-segment slab intersections, ordered AABB
  traversal, axis order, original early exits and `.005`/`.995` cutoffs.
- Each box is packed in original order as `[position.xyz, end.xyz]`.
  **Godot calculates `AABB.end` before packing.** Passing size and recomputing
  end with a different precision would violate the contract.
- Vector3 construction and `end - start` use binary32. Subsequent component
  subtraction/division and scalar near/far calculations use binary64.
- No reduced lattice, alternate BVH, fast-math, FMA, reciprocal approximation,
  reassociation, added intersection shortcut, or shared mutable work buffer.
- Success returns two independently owned complete arrays. Invalid packed
  lengths, nonfinite components or allocation failure return an empty array.
  Empty geometry is valid; degenerate and inverted boxes are not normalized.
- The production wrapper falls back to unchanged GDScript for missing/older
  libraries, disabled acceleration, invalid results and custom double-precision
  Vector3 builds. `--no-native-water-masks` forces the reference route.

## Verification

1. **Immutable old GDScript:** a hash-locked, verbatim pre-optimization kernel
   compares all mask bytes for 25 synthetic and 25 real original-world room
   fixtures. All 6,553,600 bytes agree. Cases include thin/intersecting/degenerate
   and inverted bounds, parallel tolerance boundaries, signed zeros, finite
   segment thresholds, huge finite values and seeded random scenes.
2. **Authored-room goldens:** five archived old-GDScript High-bake results
   compare exact native and production-wrapper outputs. All additional
   655,360 bytes agree, including the curved bath's 691 filtered solids.
3. **Independent original authority:** the unchanged literal `rayBlocked`
   JavaScript body from pinned commit `66a4543` agrees on all 55 cases,
   totaling 7,208,960 bytes. A documented boundary adapter supplies Godot's
   binary32 vector starts/deltas to the original binary64 scalar kernel.
   This does not assert that unmodified browser binary64 scene coordinates
   and Godot binary32 scene geometry are interchangeable at all boundaries.
4. **C core:** ASan/UBSan pass 1,102,520 assertions, including 250,000 arbitrary
   finite-bit-pattern rays, exact segment cutoffs, 14 full masks, canaries and
   rejection tests. LeakSanitizer is disabled because of the execution
   sandbox's ptrace arrangement; no LSan result is claimed.
5. **Godot ABI:** dynamic-call ownership/lifetimes, immutable input buffers,
   four simultaneous calls, malformed inputs and 1,001 typed ptrcalls pass.
6. **Production integration:** 13 assertions each pass with native enabled,
   explicitly disabled and completely absent. Native-rejected nonfinite
   input reaches the unchanged GDScript fallback.
7. **Readback regression:** all existing 72,823 readback assertions, 1,000
   typed readback calls and the readback ASan/UBSan suite still pass.
8. **Artifacts:** Linux x86-64, Windows x86-64 and Android arm64 cross-builds
   have the expected architecture, exactly one export and zero runtime
   imports. Android retains 16 KiB ELF page alignment. Linux is executed;
   Windows and Android are statically audited, not runtime-tested here.
9. **Atomic builds:** isolated rebuilds reproduce all shipped hashes, replace
   output inodes rather than truncate mapped files, preserve old mappings,
   publish nothing after an injected later-target failure, and clean staging.
   No live project library was replaced during that atomic-build test.

The first formal fixture export incorrectly paired default lamps with authored
golden masks. Independent old-GDScript recomputation identified that mismatch
as fixture input provenance, not a native-kernel difference. The exporter was
corrected to populate lamps through the real authored lighting function;
every archived golden mask byte was left unchanged, and all five pass.
The failed-fixture diagnosis is retained in the verification directory.

## Reproduce and evidence

Run from the project root:

```sh
native/source_water/run_masks_tests.sh
native/source_water/run_masks_integration.sh
native/source_water/run_tests.sh
godot --headless --path . --script tests/source_native_masks_perf.gd
python3 native/source_water/verify_binaries.py
SOURCE_WATER_LLVM_ROOT=/absolute/path/to/toolchain/root/usr \
  python3 native/source_water/test_atomic_build.py
```

Core sanitizer commands and toolchain details are in
`native/source_water/README.md`. All tests here are CPU-only `--headless`;
no native-windowed, GPU, xvfb or graphics job was launched for this work.

Evidence is under `native/source_water/verification/`:
`masks_contract.json`, `masks_formal_goldens.json`,
`masks_original_reference.json`, `masks_benchmark.json`,
`masks_integration.log`, `masks_sanitizers.log`, `masks_typed.log`,
`readback_after_masks.log`, `readback_after_masks_sanitizers.log`,
`binaries.json`, and `atomic_build.json`.

Final library SHA-256s:

- Linux: `723507e33308bcc7c87b48abdbe11b7df040ee6b8b2923df7d265ad2282e5092`
- Windows: `eb5e971edb7c3e6112ea4bf58f3bfb0c479e36e50088a72f7e1aafbd2dc601b8`
- Android: `d59f4a6431fee6f9e14eb837f94efa414fa593c9501fc057f370b61be2269047`
