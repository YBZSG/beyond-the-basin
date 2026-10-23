# PoolCore DLSS runtime

The normal Godot project remains loadable in stock Godot 4.7. The optional PC
upscaler is detected through the NVIDIA fork's `Streamline.get_capability()`;
neither GPU names nor the presence of a menu selection count as support.

## Pinned dependencies

- Engine: <https://github.com/NVIDIA-RTX/godot/tree/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76>
  (`nvidia-pt-dlss`, Godot 4.8-dev). This is an experimental NVIDIA branch.
- Runtime: <https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16>
- SDK archive: `streamline-sdk-v2.14.16.zip`, SHA-256
  `32041e51db0cab709a271b72a352281b690c2abbd669a827809401a5dd23956b`.
- Build: Python 3.13, SCons 4.11.1, Visual Studio 2026 x64 C++ tools, Windows SDK
  10.0.26100.0. The fork supplies its own Streamline headers (2.10.0).

Extract dependencies outside the Godot project. For 0.6.11, apply
`engine-taa-rg16f.patch`, `engine-fg-rt.patch`, then
`engine-camera-visibility.patch` and `engine-scene-retirement.patch` to the pinned upstream source.
The FG/RT patch includes the old SR dispatch log; do not apply `engine-dispatch-log.patch`
a second time. The patches have been checked against the downloaded source archive.

`engine-fg-rt.patch` adds verbose SR/RR dispatch evidence and DLSS-G presentation
counters, disables FG when an upscaler context is destroyed, fixes RT output and
RR guide texture formats, handles fragment discard through an any-hit shader,
and avoids double-freeing deformed BLAS during shutdown. The discard adaptation
is validated for this project's fragment code, not arbitrary third-party shaders.
`engine-taa-rg16f.patch` fixes the fork's native TAA fallback: its RG16F velocity
history was being copied with an RGBA16F-only shader, and the copy region used
output resolution instead of internal resolution. The patch adds an RG16F copy
variant and corrects the region. This is also tested at 75% and 125% scaling.

`engine-camera-visibility.patch` makes primary RT rays respect the camera layer
mask and near plane. Hidden first-person head meshes remain available to secondary
rays. This fixes the RT-only head/hair occlusion while swimming. The application
also excludes expanded and formal maps from RT until their shaders are adapted.
`engine-scene-retirement.patch` gives TTL eviction the same BLAS ownership as
shutdown: freeing the owned vertex buffer retires the dependent BLAS if still live;
the old mesh index buffer may already have freed it during a map replacement.

Build the editor, then its matching release export template, from that source:

```powershell
python -m SCons platform=windows target=editor arch=x86_64 d3d12=no accesskit=no use_streamline=yes dev_build=no debug_symbols=no optimize=speed -j12
python -m SCons platform=windows target=template_release arch=x86_64 d3d12=no accesskit=no use_streamline=yes dev_build=no debug_symbols=no optimize=speed -j12
```

Use the SDK's production `bin/x64/` runtime, preserving its NVIDIA signatures:
`sl.interposer.dll`, `sl.common.dll`, `sl.dlss.dll`, `nvngx_dlss.dll`,
`sl.dlss_d.dll`, `nvngx_dlssd.dll`, `sl.dlss_g.dll`, `nvngx_dlssg.dll`,
`sl.nis.dll`, `sl.pcl.dll`, `sl.reflex.dll`, `NvLowLatencyVk.dll`.
Put them beside the editor/exported EXE, together with applicable SDK licenses.
The fork requests these plugins at initialization; availability does not enable
ray reconstruction, path tracing, or frame generation. The desktop panel enables
2x frame generation with Reflex when supported. Hardware path tracing with RR
is an explicit experimental option, currently restricted to the original pool.
Transparent water and its captures retain rasterization, not ray-traced refraction.

Import and export an isolated project copy using this editor. Point that copy's
Windows release custom template at the matching `template_release` executable.
Do not overwrite the stock editor, export templates, Android project, or the
working 4.7 import cache. Package the native water DLL alongside the EXE/PCK.

## Verification

`run_qa.py` creates a separate `APPDATA` under `output/dlss/<name>` and copies the
player's settings into it. Run `controls` on the NVIDIA runtime and `fallback`
on stock Godot or with an unavailable DLSS runtime. Pass `--case Off` or
`--case Quality` for uncapped, same-scene wall-clock timing and walking captures.
The Python runner accepts an editor/runtime with external script support, plus
`--project` or `--pack`. For the actual exported EXE, pass `--release --case Quality`
(or `Off` / `DLAA`) and its path as `--engine`. This uses the built-in
`--qa-benchmark --qa-user-water` path: 120 warmup frames, 360 measured frames,
saved water settings, frozen props, and no editor/script override.

Successful capability detection and a viewport enum alone are insufficient:
check the successful SR-dispatch log, absence of rendering/script errors,
screenshots, water movement, and mode switching. Measure performance after
compilation has ended. GPU timing for the main viewport excludes other viewports
and standalone water compute; wall-clock frame time includes the complete frame.

The panel preserves native scale/MSAA/TAA choices while DLSS owns those settings.
Off restores them. Missing capability falls back to them. Quality is the initial
DLSS choice; Balanced, Performance and native-resolution DLAA are also available.
Existing water/lighting quality settings remain independent.

## Frame generation and hardware path tracing (0.6.8)

Use `check_fg_rt.gd` through `run_qa.py --script check_fg_rt.gd --case fg-rt`
with a matching editor executable. It checks raster/FG/RT switching, actual
TLAS instances, walking/avatar/water, room travel, resize, DLSS Off/re-enable,
and persistence. The strict runner treats failed RT shaders as failures even
when the engine silently substitutes a fallback shader. Stock Godot uses
`--case fallback` to verify unsupported features remain inactive.

For the release executable use `--release --case Balanced --fg on --rt on`
(or off for either switch). It records actual game frame times and window focus.
Verbose logs contain `slDLSSGGetState` counters every 120 render frames. Count
presented frames and elapsed microseconds separately; never label game FPS as
FG display FPS. Minimized/background windows may stop generating extra frames.
The release template omits editor-only TLAS statistics; use the editor with the
same exported PCK for those, and RR dispatch/error/visual checks on the release.

The RT ceramic and architecture shaders preserve shared parameters. They replace
pixel derivatives, implicit texture bias and the unsupported normal-matrix
builtin with RT-compatible calculations. Capture environments explicitly keep
path tracing off. Material-library entries are switched as well as live meshes,
so newly streamed rooms inherit the selected mode. The second scene retains
rasterization until its separate shaders are adapted.

## Camera, foam and expanded-floor regression (0.6.11)

`check_camera.gd` uses the production controller and skinned model with a test-only
deep-water fixture; the production original pool stays 1.04 m deep. It captures
swim/stop/look-up/look-down in raster and RT, returns to wading, then checks carrying.
`check_water_artifacts.gd` walks through the real water, captures foam on/off and
its decay, then requests RT in all four expanded room types. It checks 961 floor
collision samples per room and restores the saved RT request on returning to the
original pool. Use both with `run_qa.py --script <name>` and the final exported PCK.
Screenshots still need visual inspection; collision samples cannot prove rendering.

Frame-generation capability and toggles remain available, but the 0.6.9 observation
of 1.00x presented frames remains unresolved. Do not infer extra frames from an
active flag or reuse the historical 0.6.8 FPS claim as current verification.
