# Native DLSS Neural Rendering prototype

> 2026-10-24 controls update: this delivery is source-only. The earlier Windows
> build and dispatch observations below belong to the pre-existing repository
> handoff, not validation of the new 1–4-layer patch. No updated EXE/PCK is included.

This optional engine patch calls NVIDIA's NGX Vulkan NR API with real scene color,
depth and decoded Godot motion vectors. It does not replace Super Resolution with
a renamed DLL. The SDR scene is processed after tonemapping and before Canvas/HUD.
The water solver is unchanged. The local playable update also adds the requested
Poolrooms Wing, the formal hall RT material adaptation, wetter ceramic finishes,
and an explicit NR control mutually exclusive with frame generation.

The isolated Windows test build uses the matching patched editor executable as a
game runtime. It is a local experimental build, not a new release export template.
Use `Launch-PoolCore-NR.cmd` and `Launch-PoolCore-NR-Off.cmd` in the packaged folder.
Both use the packaged `profile/`. They set NR on/off; NR-on also forces FG off.
They preserve saved DLSS, RT and other graphics choices.
They preserve the ReShade Vulkan-layer exclusion used by the normal launcher.
The existing installed player profile is not modified.

Only `PoolCore NR dispatch OK` in the native log establishes an executed NR pass.
Requests, capabilities and menu labels do not. Missing support/runtime produces a
bypass; enabling FG or turning DLSS off also bypasses this isolated prototype.
The prototype deliberately does not combine NR with FG.

## Dependencies and rebuilding

- NVIDIA Godot commit `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`.
- The four existing engine patches from README.md, followed by `engine-dlss-nr.patch`
  and the additive `engine-dlss-nr-controls.patch`. The original NR patch stays unchanged.
- NR package `rtx-remix-ngx_sdk_dlnr@2`, obtained from the official Remix Packman
  dependency and remote configuration. `NR_DEPENDENCIES.json` records the official
  URL and exact downloaded files. Keep this SDK outside the repository.
- NGX base loader/header files from NVIDIA/DLSS commit
  `9981c6350dc58c0ce21f024fd65e31e851c31689`; arrange the static loader as
  `<ngx-base>/lib/nvsdk_ngx_s.lib`, with its headers in `<ngx-base>/include/`.
- Read the NVIDIA RTX SDKs LICENSE delivered with the package. It permits SDK
  integration into an application and requires notification before commercial
  release. The Remix source license does not replace the SDK license.

```powershell
python tools/dlss/build_nr.py --engine C:/path/to/fresh-pinned-godot --nr-sdk C:/path/to/ngx_sdk_dlnr --ngx-sdk C:/path/to/ngx-base --apply
```

Omit `--apply` on subsequent incremental builds. The script passes SDK locations
through process-local `POOLCORE_NR_SDK` and `POOLCORE_NGX_SDK`; the patch contains
no machine-specific paths. Builds without the NR SDK compile a no-op NR stub.
Production signed `nvngx_dlssnr.dll` belongs next to the executable, with the SDK
license, alongside the existing signed Streamline runtime.

Runtime opt-in: `POOLCORE_DLSS_NR=1`. The SDK-recommended, version-pinned network
is the default. `POOLCORE_NR_PRESET=B` explicitly selects its lightweight fallback.
The original defaults remain tone strength 0.1, structure strength 0.5, intensity 1,
with an explicit full control mask and one evaluation.

### Optional controls and experimental layers (source-only update)

The additive controls patch accepts a finite 0–1 intensity/local-tone/local-structure
snapshot and an optional 1–4-layer chain. Each layer owns a separate feature/history
and output; it consumes the preceding layer's color. It is not repeated SR or a cosmetic
pass-count label. The same scene depth/MV guides are reused across the chain, which is
an explicit approximation. More layers add processing and memory cost and are not
promised to improve quality; default remains one. Water simulation/material settings
and the FG exclusion are unchanged.

The panel/native contract uses `POOLCORE_NR_CONTROL_V1` requests and a current-process,
fresh `POOLCORE_NR_STATUS_V1` acknowledgement. Applied layers are reported only after
all native evaluations return success; missing/old-engine status is not success.
The source update does not update an existing packaged EXE. A matching rebuilt engine
is required. Full native compilation, GPU dispatch, visual/motion quality, timing and
memory checks have **not** been performed for the new layer/control code.
See [source contracts, status schema and validation gate](../../tests/nr_controls/README.md).

## Verification and limits

```powershell
python tools/dlss/run_qa.py nr-timing --engine C:/path/to/PoolCore.exe --pack C:/path/to/PoolCore.pck --script check_dlss_nr.gd --case timing --nr on
```

Use `--nr off` for the matched baseline. `--case controls` exercises SR/DLAA/off,
resize, wading, camera motion and HUD. `--nr-capture` enables exact-dispatch input
and output PNGs after scene warmup; exclude that run from performance comparison.
`gpu.csv` records total GPU VRAM and utilization once per second, including loading.
`--nr-expect-bypass` is reserved for deliberate missing-runtime/stock-engine checks.

The prototype accepts one eligible main SDR Vulkan viewport with active DLSS
inputs; XR, HDR output, 2D MSAA and FG combinations are outside this test scope.
History resets on input changes, resize, processing gaps and abrupt camera changes.
All external NR resources participate in the renderer's resource graph. Feature
release/recreation waits for GPU work to finish. Failed evaluation restores the
unprocessed frame, then disables further NR work.

Water retains its existing rasterized transparency/captures; this patch does not
add flow-aware refraction motion vectors or per-material NR masks. Static image
changes do not prove stable water or hand detail during arbitrary movement. NR
does not establish a fix for the separate FG jelly/stretching report. Local test
results and remaining visual limits are recorded in the accompanying evidence.

## All-scene local update (2026-10-24)

Original, formal, expanded and Poolrooms now share the RT/RR switch. New streamed geometry receives the matching RT shader in one deferred material refresh per batch. Water keeps its existing raster capture path. Tile faces are glazed and nonmetallic; grout and plaster stay rough. Expanded and Poolrooms passed real RR/NR dispatch and late-room material checks. A polished-tile capture showed the diagnostic object's reflection on production dry tiles. The subsequent tile-edge normal separation has not been runtime-checked: the user requested an immediate source handoff without further validation. Launchers include expanded mode and preserve user RT choices and NR/FG exclusivity. The local installed PCK has not been updated to the final normal changes; source, candidate export and installed package are distinct. See `.agent/HANDOFF.md` for the handoff boundary.
