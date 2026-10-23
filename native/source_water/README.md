# Exact source-water CPU helpers

A small optional **CPU-only** Godot 4.6 GDExtension for parsing the existing
RGBA16F shallow-water readback, preparing incoming-light occlusion masks, and
rejecting wholly inert particle domains before unchanged host packing.
It changes no solver equations, texture sizes,
GPU shaders, readback cadence, or publication/lifecycle semantics. The GDScript
solver remains responsible for those and retains its exact fallback.

## API and exactness

`SourceWaterReadback` extends `RefCounted`, has no mutable per-instance state,
and exposes:

```gdscript
var helper: Object = ClassDB.instantiate("SourceWaterReadback")
var result: Array = helper.parse_rgba16f(bytes, width, rest_depth)
```

Success is exactly `[eta: PackedFloat32Array, u: PackedFloat32Array,
v: PackedFloat32Array, energy: float, peak: float]`. Failure is an empty Array.
Pass the solver's **actual binary64 REST_DEPTH value**, not a newly rounded
literal. Every RGBA16F texel must have finite h/u/v and alpha bits `0x3c00`.
Dimensions must describe the complete square payload. Invalid dimensions,
nonfinite depth, malformed pixels, or allocation errors return no partial data.

Half conversion preserves all finite binary16 values exactly, including signed
zeros and subnormals. Fields are decoded directly into three independently
owned PackedFloat32Arrays. Sequential binary64 reduction uses the original
`total += h*h + (u*u + v*v)*rest_depth/9.81`, with the same operation/texel order.
There is no FMA, reassociation, fast math, SIMD dot product, parallel reduction,
or approximate arithmetic. Compile flags enforce this on every shipped target.
All three fields and reductions are private until the call returns. The caller
must still validate its request/generation and publish the result atomically.

The only native export is `source_water_library_init`. The implementation uses
Godot's C ABI and engine-owned arrays. It has no external library imports,
no C/C++ runtime dependency, and no OS, network, file, or graphics access.
The helper is reentrant; simultaneous calls use independent temporary arrays.

## Exact incoming-light mask API

```gdscript
var masks: Array = helper.build_occlusion_masks(boxes, lamps)
```

- `boxes: PackedFloat32Array`: six floats per AABB in original traversal order,
  `[position.x, position.y, position.z, end.x, end.y, end.z]`. Compute `box.end`
  **in Godot before packing**, preserving its Vector3 binary32 addition.
- `lamps: PackedFloat32Array`: exactly six floats, `[lamp0.xyz, lamp1.xyz]`,
  from the two effective Godot lamp positions. Power is not a kernel input.
- Success: exactly two independent 65,536-byte PackedByteArrays in lamp order.
  Malformed lengths, nonfinite components, or allocation failure return `[]`.
  Empty boxes are valid and return two all-255 masks. Zero-size and inverted
  bounds retain the old kernel behavior; the helper does not repair AABBs.

This is a direct native implementation of the existing ordered slab kernel,
not a spatial approximation or BVH replacement. It retains two complete
256×256 lattices, the 32 m footprint, `.31` start plane, axis/box order, original
parallel test `-1e-8 < delta < 1e-8`, and strict `.005`/`.995` segment cutoffs.
Ray starts and `end - start` are rounded to binary32 exactly where Godot's
Vector3 does so. Subsequent component subtraction, division, min/max and
near/far comparisons are binary64, just as GDScript scalar floats are.
No reciprocal approximation, FMA, fast-math, reduced grid, extra early exit,
cross-request mutable cache, or worker-global scratch buffer is introduced.

The mask accelerator targets standard **single-precision Vector3 Godot
builds**. Custom double-precision engine builds must use the GDScript mask
fallback, rather than silently downcast geometry. The runtime integration
checks class/method availability and vector precision; unsupported platforms,
missing/older helpers, `--no-native-water-masks`, or an invalid result retain
the unchanged exact GDScript path. The readback API is unchanged.

## Exact inert-domain prefix API

`find_next_particle_candidate(data, previous, removed, emerged, start, blend,
base, h)` returns the first particle that reaches the original host callback
boundary, or the array's complete particle count if none can. Malformed input
returns -1. Inputs are read-only and no callback, event, state mutation or
packing is moved into C. The running engine's actual `lerpf` utility is used;
all surrounding binary64 operations keep strict, non-reassociated semantics.
NaN/Inf and signed-zero behavior retain the original prefix decisions.

Production uses one call per domain and only skips a wholly inert domain. If a
candidate exists, its entire original host loop runs from index zero. Missing
or older helpers, `--no-native-water-particle-gate`, and invalid native results
retain the original GDScript path. Helper instances are lazy and released at
disposal. This does not change APIC equations, steps, caps, interpolation,
interactions or GPU submission. Detailed numerical, lifecycle and real-state
replay evidence is in `docs/SOURCE-NATIVE-PARTICLE-GATE.md`.

## Supported artifacts and packaging

- `bin/libsource_water.linux.x86_64.so`: baseline x86-64/SSE2 Linux ELF.
- `bin/source_water.windows.x86_64.dll`: baseline Windows x86-64 PE DLL.
- `bin/libsource_water.android.arm64.so`: baseline ARMv8-A Android ELF,
  API 24 target, compatible with 16 KiB page alignment.

The standard `source_water.gdextension` enables Godot's native-library export
discovery. Windows exports must include the DLL beside the exported executable
at the engine-selected dependency path. Android exports must contain the SO in
the APK's native `lib/arm64-v8a` directory, not merely as a PCK/raw asset.

**There are no macOS, iOS, Web, x86-32, Windows ARM64, or Linux ARM64 binaries.**
Godot's standard descriptor has no unsupported-platform silent-skip option.
For those export targets, omit this descriptor/native dependency from the
project's platform-specific export and use the existing GDScript fallback.
Unsupported editors may log a missing-native-library error during auto-import;
the solver's ClassDB existence check must not create a hard native dependency.
For deployments needing zero such diagnostics, use a platform-specific project
or gate descriptor installation rather than pretending an unsupported binary
is available. No untested Apple artifacts are supplied.

Linux is runtime-tested with Godot 4.6.3 official. Windows and Android have real
cross-built binaries with audited architectures/exports/dependencies, but were
**not executed on Windows or Android in this task**. Package and device checks
remain the responsibility of the full-game release verification.

## First headless import on Godot 4.6.3

Godot has a confirmed editor documentation shutdown race when a fresh project
first discovers a GDExtension and immediately exits headlessly. The deferred
extension-doc generator can run after its document store is destroyed. This
is tracked in [Godot #111048](https://github.com/godotengine/godot/issues/111048)
and [#111645](https://github.com/godotengine/godot/issues/111645).

Local clean-project controls reproduced: newly discovered helper exits with
SIGABRT, the no-extension control exits 0, and startup-prelisted helper exits
0. A traced isolated build completed registration and failed before extension
deinitialization; its stack is in the editor documentation-generation region.
These diagnostics did not alter the shipped helper binaries.

For automated first import/export, the packaging runner prelists the standard
`res://native/source_water/source_water.gdextension` entry in
`.godot/extension_list.cfg`, preserving any existing entries, before launching
Godot. This loads it at engine startup, the same lifecycle as later launches.
Do not treat a nonzero first-import exit as success or silently suppress it.
The fallback and normal target export discovery remain unchanged. Controls and
logs: `docs/verification/eight-hour/water/native_import_lifecycle.json`,
`native_import_trace.log` and `native_import_abort_stack.log`.

## Build and reproduce

Requires Clang/LLD 19 or compatible, Bash, and Python 3. Godot-cpp, MinGW, the
Windows SDK, Android NDK, and any target libc are unnecessary because the C
extension is fully freestanding. Nothing is installed globally.

```sh
cd native/source_water
./build.sh all
python3 verify_binaries.py
./run_tests.sh
```

For a compatible Debian Linux x86-64 host without a compiler on PATH, the
optional acquisition helper downloads only checksum-pinned official archives
into an explicitly supplied directory **outside** the project:

```sh
python3 acquire_toolchain.py --destination /absolute/external/llvm19
export SOURCE_WATER_LLVM_ROOT=/absolute/external/llvm19/root/usr
./build.sh all
```

This local route requires the host's existing `libLLVM19` and ordinary compiler
host dependencies. It does not silently download dependencies or invoke apt.
Alternatively set `CLANG`, `LD_LLD`, and `LLD_LINK` to an existing compiler.
Toolchain package provenance is in `toolchain-packages.json`. Generated object
files stay in the ignored `build/` directory, which has a `.gdignore` marker so
Godot cannot misread Windows `.obj` files as Wavefront models. Final DLL/SOs
are intentionally not ignored. Builds now stage every requested target in the
same filesystem and atomically rename completed libraries, never truncate
the mapped library inode of a running editor. A failed compile publishes no
requested artifact. No signing keys are used.

Regenerate the vendored official header only when intentionally updating the
API target: run `godot --headless --dump-gdextension-interface` from `vendor/`.
The bindings use interface methods and opaque, aligned engine values, not
internal container layouts.

## Tests and observed performance

`./run_tests.sh` uses sandbox-local XDG directories and CPU-only `--headless`:

- Native contract: 72,823 assertions, all 63,488 finite half encodings against
  Godot's actual Image RGBAH-to-RGBAF conversion in every physical channel;
  signed zeros, subnormals, maximum finite halves, exact ordered energy/peak.
- All 6,144 physical-channel Inf/NaN cases, every alpha encoding, malformed
  lengths, hostile dimensions, nonfinite depth, repeated lifetime/ownership,
  four simultaneous threads sharing the same stateless helper.
- An isolated startup-loaded project tests the typed native ptrcall ABI with
  1,000 calls. Runtime integration can use dynamic ClassDB lookup instead.

Standalone core memory/UB checks:

```sh
cd ../..
gcc -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
  -fno-omit-frame-pointer -fno-fast-math -ffp-contract=off \
  tests/source_native_readback_core.c -o /tmp/source-native-core-test -lm
ASAN_OPTIONS=detect_leaks=0 /tmp/source-native-core-test
```

ASan and UBSan passed. LeakSanitizer cannot run under this execution sandbox's
ptrace arrangement, so it is explicitly disabled and **no LSan pass is claimed**.

`tests/source_native_readback_perf.gd` alternates the native helper and the prior
exact GDScript parser, checking every output byte and both reductions after
every call. On the shared Linux host, Godot 4.6.3, 384², 31 measured iterations
after three warmups: GDScript median **35.775 ms**, native median **1.056 ms**,
**97.05% lower measured CPU parsing cost**. Native range: 0.915–1.789 ms;
GDScript range: 33.177–52.127 ms. This is not a game-FPS result, GPU measurement,
or promise about a user's device. Raw samples: `verification/benchmark.json`.

```sh
godot --headless --path . --script tests/source_native_readback_perf.gd -- \
  --output=/tmp/source-native-benchmark.json
```

`verify_binaries.py` records SHA-256s, size, architecture, sole export, zero
imports, nonexecutable stack, and Android page alignment in
`verification/binaries.json`. No GPU/windowed/xvfb test was run for this helper.

### Incoming-mask verification

```sh
native/source_water/run_masks_tests.sh
native/source_water/run_masks_integration.sh
gcc -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
  -fno-omit-frame-pointer -fno-fast-math -ffp-contract=off \
  tests/source_native_masks_core.c -o /tmp/source-native-masks-test -lm
ASAN_OPTIONS=detect_leaks=0 /tmp/source-native-masks-test
godot --headless --path . --script tests/source_native_masks_perf.gd
```

- `tests/fixtures/source_incoming_mask_old_reference.gd` is a hash-locked,
  verbatim pre-native GDScript kernel, not a call back into optimized code.
- Full-byte parity covers 25 synthetic cases plus 25 actual original-world
  room origins at seed 250821, including all encountered room variants:
  **6,553,600 matching mask bytes**. Synthetic cases include parallel and
  near-parallel rays on either side of the tolerance, signed zeros, thin,
  degenerate and inverted boxes, endpoint thresholds, huge finite components,
  intersections, and seeded random geometry.
- Five additional authored-room fixtures compare both native and production
  wrapper outputs with archived full masks from the old GDScript High bake,
  including the curved bath's 691 filtered solids. All 655,360 additional
  bytes match. Fixtures preserve the archived masks and use the exact authored
  effective lamps populated by the real lighting function.
- The independent JavaScript oracle executes the unchanged `rayBlocked`
  body from pinned source commit `66a4543`. An explicit input-boundary adapter
  supplies Godot's rounded Vector3 starts and deltas; this is not a claim that
  untouched browser binary64 scene coordinates equal Godot binary32 geometry.
  All 55 full-mask cases (7,208,960 bytes) also match that independent
  scalar-kernel authority.
- The standalone core ASan/UBSan suite covers 250,000 random finite-bit-pattern
  rays, exact `.005`/`.995` exclusion boundaries, 14 full masks, output guards,
  and malformed/nonfinite input. LeakSanitizer remains intentionally disabled.
- Native dynamic-call ownership, four simultaneous calls, input immutability,
  malformed lengths and nonfinite components pass. The isolated typed ptrcall
  fixture passes 1,001 calls. Original readback contracts and its 1,000 typed
  calls are rerun after the mask addition, without changing its API.
- Production wrapper integration passes with native enabled, explicitly
  disabled, and completely absent. A rejected nonfinite input returns to the
  old GDScript kernel; no partial native mask is published.

Detailed results and raw timing samples are in `verification/masks_*.json` and
`verification/masks_*.log`. The real-room CPU benchmark includes packing and
alternates old/new implementations; it compares all mask bytes after every
call. These are shared-host CPU measurements, not game-FPS/GPU or device claims.

On the shared Linux host, Godot 4.6.3, the seed-250821 origin room with 109
filtered solids, nine alternating measured iterations after two warmups:
old GDScript median **8,930.159 ms**, native including packing **115.480 ms**,
**98.7069% lower measured mask CPU cost**. Native range: 100.240–134.309 ms;
old GDScript range: 8,517.500–9,932.735 ms. Raw samples and caveats are in
`verification/masks_benchmark.json`.

`test_atomic_build.py` builds only in an isolated temporary copy. It verifies
three-target reproducibility against shipped hashes, proves already-mapped
old library bytes/inodes remain intact across replacement, injects a failure
after one target compiles and verifies no target was published, and checks
staging cleanup. Its results are in `verification/atomic_build.json`.
