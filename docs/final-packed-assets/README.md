# Exact final PCK: bounded CPU asset and collision verification

Result: **PASS, 419 checks, zero failures**. This is deliberately a CPU-only, narrow asset/import/collision verification, not gameplay, native visual acceptance or Windows execution.

## Exact artifact and isolation

- PCK: `PoolCore-PC-WaterFeel-Repair-20261023.pck`, reconstructed from the final delta.
- SHA256: `54f5ff5f6c15ea854e70f30a9a5eca3096c0b9192db3b0852741ac296145e234`.
- Bytes: 157,631,396; PCK entries: 336.
- Runtime project version: `0.6.2-pc-waterfeel-20261023`.
- Godot: Linux 4.6.3 stable, headless/dummy renderer, no RenderingDevice.
- Run: `run-01`, exit 0, 4.609 seconds, sampled peak RSS 207,796 KiB (about 203 MiB), no supervisor termination and no engine warning/error lines.
- Both `cwd` and `--path` were the reconstructed pack directory. `--main-pack` was the exact PCK and `--script` was the external absolute fixture. The physical host had only the PCK and a hash-verified Linux test helper. It contained no source project, production script, asset fallback or fixture overlay.
- The runtime verified 114 selected virtual entry SHA256 values against the actual PCK directory. PCK bytes and physical host files were unchanged after execution.
- `Main` was instantiated off-tree only. `_ready` never ran, `_booted` remained false, and `world`/`water` remained null. The source GPU solver was never configured. No alternative CPU wave simulation was substituted.

## Covered results

- 21 packed runtime modules load and instantiate as scripts, with exact matching source hashes. This includes Main, fresh-process restart helper, player/avatar/carry/cloth helpers, formal and expanded catalogs/builders, water runtime, terrain/cache helpers, material and lighting libraries.
- All six formal imported models instantiate: arch, mainhall, arcade, sidepool, terrace and bath. Both legacy/current avatar models and the two return-valve/fitting models also instantiate. All ten packed imported-scene hashes match their current source-project imports. Mesh counts include imported hidden collision proxies and are not claims about visible draw calls.
- Actual packed formal room builder, Jolt collision rays and the unchanged source `build_depth_data` static function were exercised for all five formal rooms. The 256×256 depth arrays were finite and within 0–1.04 m. Measured basin depths are mainhall 0.44 m, sidepool 0.84 m, terrace 0.22 m and bath 0.94 m; arcade is dry.
- All 18 authored stairs were sampled at x = −0.8, 0 and +0.8 m, totaling 54 native collision/depth points. Sidepool and bath have six 0.65 m treads each. Maximum collision-to-authored stair-top difference was about 0.064 mm, well inside the 2 mm acceptance threshold. These are ray/support measurements, not capsule traversal, foot IK or foot-planting acceptance.
- The current cloth avatar loads with 42 bones, 26,616 weighted vertices and seven nonempty 37-track clips: Idle, Walk, Run, Hold, Wade, Swim and Climb. Shared skin/skeleton bindings and native camera layer properties pass. Exactly two metric-UV clothing surfaces accept the finish; disable, re-enable and restore pass. This does not prove rendered animation quality.
- Both valve models load with substantive imported geometry. This fixture does not exercise player aiming, valve interaction or live source-water injection.
- Packed water surface shader, raw source-water/fog shaders/includes/data and compute import mappings are present and byte-verified. The water-selected subset comprises 36 entries, including shader/import records; their referenced imported compute records are also included in the 114-entry origin guard. No GPU shader compilation/execution is claimed.
- All 16 terrain cache files (31,254,472 bytes) pass the production bounded reader's header, compressed/uncompressed SHA256 and decode checks. Fifteen prepared-terrain payloads pass production shape validation and match the current loaded-source algorithm signature; the remaining snapshot contains all five formal rooms. This is cache integrity/presence, not a live-geometry cache-key/cache-hit or GPU upload claim.
- Packed Original/Formal/Expanded labels and enum are intact; Original remains the default. Original and Expanded saved selections round-trip through isolated settings; the actual catalog returns original and expanded layouts. The off-tree UI includes the optional fresh-process restart control. No world switch, process restart or full startup was executed.
- Both packed readback parser branches pass an exact 2×2 half-float fixture: native Linux `native_exact` and `gdscript`. Solver configure was not called.

## Windows sidecar: static identity only

The current project's Windows helper and original delivered `pc-expansion-20261022/stage-play-03/native/source_water/bin/source_water.windows.x86_64.dll` are identical:

`fbad35d391c5d3d74e39118a26a50f6544bbe57e38e41407daf538c3940efa92` (14,848 bytes).

The binary passes static PE32+/x86-64/import-dependency/entry-symbol checks. The patch launcher requires this exact hash from the **original retained native folder**. The Play patch intentionally does not ship or overwrite that dependency. The Linux sidecar in the reconstruction host is test-only, not a Windows delivery dependency or part of the Windows delta. Absence of a new Play-staging DLL is therefore not a missing required delta payload. No Windows process was executed.

## Evidence and reproduction

- `SUMMARY.json`: concise result and exact evidence hashes.
- `manifest.json`: selected PCK hashes, ten imported-scene mappings, cache headers and sidecar identities.
- `run-01/report.json`: all runtime measurements and covered assertions.
- `run-01/launch.json`: exact command, engine/fixture/manifest hashes and supervisor bounds.
- `run-01/execution.json`: exit, sampled RSS/time, integrity and host preservation.
- `run-01/godot.log`: raw engine output, without errors/warnings.
- Fixture sources: `tests/final_packed_assets/prepare.py`, `fixture.gd`, `run_fixture.py`.

`prepare.py` performs no engine execution. An owner serial-slot grant is required before `run_fixture.py --serial-slot-granted --tag <fresh-run-name>`; it refuses an existing run directory, verifies the exact host, takes the shared exclusive engine lock, rejects another running engine, isolates HOME/XDG, and bounds execution to 300 seconds and 1 GiB sampled RSS. The successful run's temporary HOME/XDG was removed after engine exit; all evidence above remains intact.

Assertion approaches were adapted from `tools/release/pc_expansion_pack_guard.gd`, `tools/release/pc_expansion_pack_smoke.gd`, `tests/water_feel_release_preflight.gd`, `tests/water_feel_depth_audit.gd` and the current deeper sidepool/bath expectations in `tests/water_feel_deep_candidate.gd`. Old source-only visual/geometry results were not relabeled as packed runtime proof, and the broad production dependency scan was not repeated.

## Limits retained

This passing fixture does **not** pass or supersede the previously externally killed full-PCK Medium/Low native starts. It establishes neither the cause of those kills nor a fix. It is complementary to the separately owned native rig fixture. It is not proof of full main startup, source GPU optics/waves, live-world switching, target-Windows functionality, graphics quality or game performance.
