# Source water resource lifecycle audit

Updated: 2026-10-22 after the engine-only native baseline/probe pair. The seven warnings are independently reproduced in the engine-only control, not fixed. The broader source-runtime ownership fixture remains separate.

## Observed warning and limits

`docs/verification/eight-hour/transition/historical-rid-warning-audit.json`
records nine shutdown observations, including terrace05 with an explicit exit code of 0. Each reports seven RenderingDevice texture
RIDs left at finalization, across both three-room and five-room scenes. The same
count occurs in startup-timeout runs with no completed cubemap and in successful
captures with six completed faces. This does not identify the owner or establish
per-room growth. It is distinct from the separate editor warning about
RendererRD TextureStorage high-level wrappers. A broader read-only search finds the same seven-count warning in 30 logs, including older original-world, mobile, and packaged runs; `rd-texture-warning-log-index.json` records their paths and hashes. Those matches alone do not establish test success or resource growth.

## Ownership paths reviewed

| Owner | Textures / aliases | Current disposal path |
|---|---|---|
| `SourceWaveSolver` | Eight native simulation/depth textures; three `Texture2DRD` outputs | Detaches wrappers, frees cached sets/pipelines/shaders and tracked native RIDs; epoch guard rejects stale work. |
| `SourceCaustics` | Native targets, every shared mip view, incoming masks; two output wrappers | Detaches wrappers, clears the three original and two optional floor-result cached-set maps, then frees tracked resources in reverse allocation order. The five optional floor-result buffer/shader/pipeline RIDs are also tracked in `_owned`; failed initialization immediately rolls them back. |
| `SourceLiquidSurface` | Owned dummy cube/DFG and render targets; one output wrapper; borrowed scene color | Detaches wrapper, frees targets and persistent RIDs, then drops caller-owned input references on the owner thread. Borrowed scene textures are not freed by the effect. |
| `SourceRoomProbe` | One sequential capture viewport and bounded high-level Cubemap cache | Cancels readback tickets, joins CPU mip jobs, queues viewport removal, drops cache/output/environment references. No directly owned RD texture allocation. |
| `SourcePlanar` | One capture viewport and its high-level output | Stops updates, disconnects completion callback, queues viewport removal and clears output. |
| Runtime/material bindings | Source-water shader samplers and camera compositor | Clears the five actual water texture parameters and the material library's two caustic samplers, removes compositor effects, then disposes the resource owners. The water surface does not have a cubemap sampler; that input belongs to the liquid compositor. |

No clearly untracked native texture allocation was found in these paths. This
review does not exclude a deferred-callback or engine-owned allocation issue.

## Why a nonzero RID is insufficient

In Godot 4.6.3, detaching a `Texture2DRD` frees its RenderingServer wrapper and
zeros its dimensions, but its separate RD getter retains the historical handle.
Its `get_rid()` can create a placeholder after detachment, so the diagnostic must
not call it then. [Texture2DRD implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/resources/texture_rd.cpp#L49-L108).

RenderingServer registration creates borrowed shared RD views of the caller's
texture. These views and the original allocation are different handles, and
must be tested separately, never freed twice by the caller.
[TextureStorage implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp#L1618-L1696).

## Prepared native proof

Only the parent native-GPU coordinator may run:

```sh
bash tools/run_native_lifecycle_bisect.sh --native-slot-granted lifecycle-01 3
```

The wrapper runs separate baseline and runtime-camera processes, three cycles
each, with a 180-second process bound and 15-second termination grace. It refuses
an occupied Godot slot and never overwrites evidence. The fixture has additional
isolatable `materials`, `probe`, `planar`, `runtime`, and `runtime-room` modes.

### Native ReflectionProbe control, prepared 23:22 UTC

```sh
bash tools/run_native_lifecycle_bisect.sh --native-slot-granted lifecycle-native-probe-01 3 baseline,native-probe,runtime-camera
```

This optional mode adds just one built-in `ReflectionProbe` to the same native
cube/camera/color-background baseline. It creates no source-water owner or
custom cubemap. Three cycles retain one shared World3D, and the report records
that identity. It observes sixteen drawn frames, not an invented public native
capture-complete signal. The completed standalone control below now reproduces the exact count; the broader source-runtime mode has not been run by this pair.

The engine's atlas allocates seven color texture handles, but its clear path
does not retire them. The standalone native pair corroborates this source-level hypothesis. It does not authorize freeing borrowed engine handles or prove every full-world owner is clean.
[Godot 4.6.3 allocation/cleanup](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L1238-L1256).

An even narrower two-file standalone project excludes game script preloads and
the native helper entirely. It checks that the helper class is absent:

```sh
bash tools/run_native_lifecycle_bisect.sh --native-slot-granted lifecycle-isolated-probe-01 3 baseline,native-probe isolated
```

Its PASS marker means the bounded cycles completed; shutdown warning parsing is
still separate. This small project is suitable for a future engine bug report,
but no report has been published and no engine change is proposed here.

`tests/source_runtime_lifecycle_gpu.gd` records initialized native texture RIDs,
existing wrapper shared views and any populated owned uniform-set caches on the
render thread. It retains external references to the owners and all six
high-level wrappers during explicit disposal. After an ordered barrier and
scene cleanup it requires actual `texture_is_valid` / `uniform_set_is_valid`
checks to fail and wrapper dimensions to be zero. Only then does it release those
extra references and sample post-cleanup memory.

The paused minimal fixture may record zero cached uniform sets and does not
exercise active liquid draw targets. Those paths are covered separately by the
exact-water rendering microtests; their absence must not be mistaken for extra
coverage here. Global memory plateaus are supplementary, not proof that every
native handle is freed.

`tools/profile_runtime_lifecycle.py` preserves fixture results, per-owner
liveness counts and process exit status separately from actual shutdown leak
warnings. An incomplete or killed run cannot establish clean teardown.
The parser now explicitly rejects a fixture PASS followed by a timeout or
duplicate process-exit markers, and exposes any non-leak runtime/script errors.
The lifecycle and walk runners share a native-namespace lock; this does not
replace the parent's coordination with other graphical jobs.

Preparation validation passed: Godot 4.6.3 `--headless --check-only`, Python
compilation and shell syntax. That preparation check alone does not establish GPU ownership cleanup; the larger source-runtime fixture remains distinct from the completed isolated pair below.

## Serial wrapper process-exit guard

The lifecycle launcher now checks for any surviving Godot process after each
actual child exit and stops before launching the next mode if one remains. Its
log records `NATIVE_LIFECYCLE_PROCESS_REMAINING=0/1`. The parser rejects a
surviving process or contradictory check markers even when a fixture printed
PASS and its immediate command returned zero. Fifteen CPU parser contracts cover
this plus missing/duplicate exits, duplicate or malformed fixture reports,
contradictory PASS/failure data, timeouts, runtime errors and separate engine
leak warnings. No native lifecycle run is implied by these parser checks.

For the short engine-only pair, the wrapper accepts an optional fifth argument for the per-mode wall budget. For example, `bash tools/run_native_lifecycle_bisect.sh --native-slot-granted lifecycle-isolated-probe-01 3 baseline,native-probe isolated 70` permits 70 s per mode plus a 15 s termination grace each, approximately 170 s maximum for both timed-out modes. Timeout or surviving-process outcomes remain failures, and a survivor prevents the next mode. The default stays 180 s per mode for larger owner fixtures. This cap describes the wrapper, not a success result; the completed isolated pair below records the actual outcome.

## Completed isolated native result

The parent ran the unchanged standalone project on official Godot 4.6.3,
Forward+ / llvmpipe. `verification/eight-hour/lifecycle/lifecycle-isolated-probe-01-summary.json`
and its two input logs record:

- Baseline: three successful cycles, exit 0, no surviving Godot, no runtime
  errors and **zero** leaked Texture RIDs.
- One native `UPDATE_ONCE` probe added to the identical scene: three successful
  cycles, exit 0, no surviving process or runtime errors and **seven** leaked
  Texture RIDs at finalization. There is no source-water owner, custom cubemap,
  custom RD allocation, game script preload or native helper in this project.
- Each mode retains one World3D throughout its three cycles. Post-cleanup texture
  bytes are exactly `[20635648, 20635648, 20635648]` for baseline and
  `[527425536, 527425536, 527425536]` for native probe: no growth after the first
  cycle. These renderer memory totals include retained atlas/cache resources;
  the difference is **not** the size of the seven leaked handles.
- The actual atlas defaults are 256-pixel faces and 64 slots. Sixteen frames per
  created probe are observed, without inventing a public capture-complete flag.

This establishes that a native probe alone causes the same shutdown warning in
this isolated setup and supports the identified atlas cleanup omission. It is
not a game leak fix, a full-world per-room growth result, or proof that every
source-water owner is clean. No production resource ownership changed.

### Public shutdown API assessment

CPU-only introspection of this exact 4.6.3 executable finds
`RenderingServer.has_method("scenario_set_reflection_atlas_size") == false`,
with `scenario_set_environment == true` as the control. The former is also
absent from the documented [4.6 RenderingServer script API](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html).
A GDScript fixture cannot safely invoke that internal atlas-size operation.
Therefore no pretend release variant, borrowed-RID cleanup or engine rebuild
was introduced. This does not assess an unexposed C++ call's behavior.
