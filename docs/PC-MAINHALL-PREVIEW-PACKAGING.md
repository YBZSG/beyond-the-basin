# PC preview packaging receipt

This is a packaging checklist, not a new visual/performance acceptance report.
The delivered baseline is untouched. Android work remains paused.

## Shipping scope

- Ordinary launch still starts the original world with the user's selected
  graphics/GI settings; fresh desktop defaults remain High + original MPM water.
- Optional launch: `PoolCore-Native.exe -- --pc-mainhall-lightmap-preview`.
  The menu's experimental PC preview checkbox is a session-only rebuild action.
- Label this **experimental, mainhall-only native lightmap preview**. It disables
  actual SDFGI in all three views; requested/saved GI is preserved. The other four
  formal rooms retain direct/ambient light but are not indirect-lighting-equivalent.
- If the native bake cannot validate, the original visual remains and the UI
  visibly reports BAKE UNAVAILABLE. Headless intentionally follows this fallback.
- The production stripe correction is separately owned by the main patch:
  FormalSunlitBasinBounce no longer casts its duplicate shadow.

## Required production resources

Include the existing staged candidate and its real native resources:

- `scenes/lighting_lab/runtime_mainhall_candidate.tscn`
- `assets/lighting/runtime_mainhall_candidate/native_indirect.lmbake`
- `assets/lighting/runtime_mainhall_candidate/indirect_00.exr`
- Their Godot import remaps/dependencies, the normal formal GLBs/materials, and
  the production preview helper (ordinary script dependency).

Only the 16 current terrain-cache files listed in
`verification/pc-refine/mainhall-preview-terrain-paths.txt` are needed in the PC
pack. SHA256 and byte sizes are recorded in `mainhall-preview-terrain-manifest.json`.
They total 31,416,886 bytes. Exclude obsolete derived cache files from the export
without deleting source/history. QA scripts, tools, reports, alternate lighting
lab scenes and unused plaster textures do not belong in the production pack.

Keep `script_export_mode=0` for this release: existing terrain-cache identity
intentionally hashes loaded script source. The preview installer itself uses
ResourceLoader and loaded metadata, not raw .gd/.tscn hashes, so it is remap-safe.
A source-mode PCK test is not evidence that a binary/compiled-script export was
executed; do not describe it as such. A compiled export could make the separate
terrain cache fail closed if source is unavailable.

## Verification receipt

`mainhall-preview-cpu-suite.json` currently passes six cases and pins 22 inputs:
resource/harness checks (17), five-room optical equality (2,014), actual runtime
cache reader (five rooms plus all 16 file hashes), actual normal startup (34),
flagged startup (34), and GI idempotency (5). Optical equality includes complete
expanded/snapped/transformed triangle order, material optics and collider identity,
not just AABBs. The current genuine CPU terrain rebuild took 26.4 seconds and all
15 derived payloads round-tripped byte-exactly. It was not a light bake.

Parent export verification uses a fresh isolated XDG data/config/cache directory:

`godot --headless --audio-driver Dummy --main-pack /absolute/BUILD.pck --script /absolute/tests/pc_mainhall_preview_exported.gd`

Repeat in a separate fresh isolated directory with
`-- --pc-mainhall-lightmap-preview`. Require `production_pack_attached:true`,
`pass:true`, and no SCRIPT ERROR/ERROR. Tests stay outside the shipping PCK.
This checks actual Main default/fallback and remapped scene/native user/atlas
metadata; it does not prove native pixels. Source-only smoke reports the pack
flag as false and cannot substitute for this check.

The parent-run `mainhall-preview-production-03` completed with exit 0 in 353.02s
under the 360s watchdog, sampled peak RSS 3,899,892 KiB (about 3.72 GiB). It
installed 147 native users / 223 surfaces with all 254 collider identities intact,
kept all three views PhysicalSky/SDFGI-off through 29 guarded draws, saved an
actual 1280×720 terrain/caustic/matched-planar image, and passed real W/D/S/A input
movement. Full source-cube readiness completed later and was separately reported.
This is bounded cloud native functional evidence, not target-PC FPS or visual
photorealism acceptance. Source-mode production-PCK checks remain a separate gate.

Keep failed native runs as evidence. Native surface readiness, screenshot size,
actual input movement and full source-cube readiness are separate gates. Do not
promote installation-only/CPU/cache success to photorealism, complete-water,
compiled-export, target-PC FPS or native preview-exit acceptance.
