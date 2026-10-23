# Experimental PC mainhall lighting preview

Normal launch is unchanged: the original world remains the fresh-user default,
with the chosen graphics preset and requested SDFGI. The five formal destinations,
controllers, water, props and collision geometry remain available.

Opt in for this session using either:

- `godot --path . -- --pc-mainhall-lightmap-preview`
- Main menu: **实验主池厅烘焙 / EXPERIMENTAL PC PREVIEW**. This explicitly rebuilds
  into the formal mainhall. Uncheck to rebuild back into the preceding world;
  choosing either normal Starting World also exits the preview.

This is an **experimental mainhall-only native bake**, not production-lighting or
photorealism acceptance. SDFGI stays off in the main, planar and source-cube
viewports before their first draw and across quality/streaming/capture updates.
The other four formal rooms retain direct and ambient light but are **not
indirect-lighting-equivalent without SDFGI**. Android/iOS/mobile-preview ignore
the flag and do not expose this control. No mobile build was changed or tested.

Requested GI and graphics preferences remain independent of the temporary
actual-GI override. Changes the player explicitly makes to graphics controls
still save normally; the preview never writes an automatic GI-off preference.
Exiting restores the current requested GI. The forced formal spawn is not saved.

## Validation and fallback

The runtime uses the existing Godot 4.6.3 native SH bake, not a new bake. It loads
through ResourceLoader, compatible with exported resource remaps and compiled
scripts. Before atomic replacement it checks provenance metadata, original/live
material identities, receiver transforms/bounds, 223 surface bindings, 147 native
users/UV/slice data, 65 dynamic receivers, 11 glazing meshes, native probe/storage
hashes, and the single 256×256×48 RGBH texture array. All 254 original collision
shapes keep their identity. No extra physics, light rig or camera can be imported.

Build-time checks pin the original GLB, staged scene, native data and source EXR.
The optical-equivalence CPU test compares all five complete production snapshots
byte-for-byte before/after the mainhall swap, including indexed expansion,
`.0001` snapping, scalar transforms, optical flags/materials, 194,844 triangles,
1,222 colliders/solids, and all room/quality depth/BVH/mask identities. This makes
current authored terrain snapshots valid for both original and baked visuals.
Any source change invalidating the cache signature requires genuine regeneration
with `tools/cache/bake_formal_terrain.gd --all-quality`, not a renamed stale cache.
The current cache manifest/report is `mainhall-preview-terrain-bake.json` in the
verification directory; old bake reports are preserved.
Runtime does not read excluded QA reports or hash raw `.gd`/`.tscn` files, and does
not perform 48 atlas layer GPU readbacks. The build/package gate owns atlas byte
integrity. Old QA-only preparation hashes are intentionally not a runtime gate.

Any missing/incompatible bake leaves the original visual intact and displays
**BAKE UNAVAILABLE / ORIGINAL VISUALS** in the menu and live HUD. It never claims
that a failed bake is working. While preview is requested SDFGI remains off;
exit the preview to restore normal requested GI. Headless therefore intentionally
reports unavailable native radiance, even though loaded resource checks pass.

## Dedicated QA

CPU-only, isolated preferences, actual Main startup and checkbox/control paths:

`python tests/pc_mainhall_preview_run_cpu.py`

Includes source build pins, real loaded-resource checks, unflagged and flagged
startup, all five formal teleports, capture/quality/streaming GI exclusion,
visible safe fallback, settings persistence, exit/reentry and GI idempotency.
Reports are `docs/verification/pc-refine/mainhall-preview-*.json` and `.log`.
These results do not claim native rendered quality or GPU performance.

GPU coordinator only, serial slot, ≤360 seconds / sampled RSS watchdog 4.8 GiB:

`python tests/pc_mainhall_preview_runner.py --describe --warm-cache --tag production-next`

After granting the slot, replace `--describe` with `--native-slot-granted`.
No GPU run is launched by the CPU suite. The native fixture instantiates the
actual production Main with only the production preview flag, fresh High
preferences and a 1280×720 window. There are no QA lighting/GI/water overrides,
no transplant, and no manual lightmap-install call. It checks all three actual
pre-first-draw environments, waits for real terrain, closes the menu with a real
Escape, then waits for actual caustics and matched planar reflection. Photon
readiness must not be awaited with the startup menu paused. It saves the surface
image first, then attempts short
real W/D/S/A movement on the original dry-deck spawn. Full source-cube readiness
is reported separately, never inferred from the surface image. Native preview
exit is intentionally not run because restoring three SDFGI volumes is outside
this preview-only memory budget; actual checkbox exit is CPU covered.

For an ordinary production PCK, keep QA scripts outside the pack and use:

`godot --headless --audio-driver Dummy --main-pack /absolute/BUILD.pck --script /absolute/tests/pc_mainhall_preview_exported.gd`

Run with fresh isolated XDG data/config/cache directories. Repeat with
`-- --pc-mainhall-lightmap-preview` to check exported preview fallback and GI
exclusion. This runs actual exported Main and resolves compiled/remapped
resources without requiring QA scripts or docs in the shipping PCK.

Windows export must include only the preview's required lab scene and bake:
`scenes/lighting_lab/runtime_mainhall_candidate.tscn`,
`assets/lighting/runtime_mainhall_candidate/native_indirect.lmbake`, and
`assets/lighting/runtime_mainhall_candidate/indirect_00.exr` plus their importer
remaps. Other lighting lab assets may remain excluded. Android remains excluded.
