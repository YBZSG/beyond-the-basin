# Campaign mechanical station kit

## Integration

`campaign_interactables.gd` owns authored geometry, shared materials, coarse static collision and immediate mechanical state feedback only. It never decides puzzle completion or handles input, audio, placement, timers or saving.

- `build_station(spec: Dictionary) -> Node3D`
- `update_station(node: Node3D, spec: Dictionary, view: Dictionary) -> void`
- `pulse_station(node: Node3D) -> void`: optional .36-second smooth lens-scale response to a player action; repeated calls replace/kill the previous tween, no luminance blink.
- `ArrivalLamp0` / `ArrivalLamp1` / `ArrivalLamp2`: separate courtesy lenses, top-to-bottom, unique materials. Smoked neutral albedo `344345`; emission enabled with warm `ffe0ab` color and neutral energy 0. Arrival presentation may ease emission energy and must restore 0; never mutate shared kit materials.
- `ArrivalVane`: independent hanging inspection tag Node3D, exposed by `arrival_visual_nodes` metadata. Arrival presentation may sway x/z rotation within ±.35 radians and must restore zero; gameplay never touches its pose.


- `spec`: objective `kind`, `index`, `id`; optional `plate` overrides a short attached mechanical plate.
- `view`: objective `value`, `active`, `solved`; optional `readings` (three coupled pressures), `stable` (0–12 s charge). Missing fields are safe zero defaults.
- Origin is the floor, front is **+Z**, target approximately origin + `(0,1.24,0)`.
- Declared stationary envelope: **1.3 m wide × 1.8 m high × 0.8 m deep**. Maintain **1.2 m clear in front** for standing/operation. Optional locker door swings forward to about local z=.71, inside this operation clearance.
- Runtime must validate support, standing space, collision clearance, approach orientation and LOS. Do not put the kit inside source architecture or on a passage/exit. The kit alone proves none of those placement conditions.

Three simplified StaticBody boxes (layer 1, no response mask) approximate foot, stem, and upper body. No rigid bodies or per-lever colliders. Tiny geometry cannot snag players. Runtime clearance is deliberately larger than visible hardware. No flashing/strobing, new light nodes, particles, timers or `_process` handlers.

## Meaningful silhouettes and feedback

- **Breaker:** single operating lever flanked by ceramic fuse cartridges; binary lever pose and lamps; only night fault index 4 has black insulation scorch marks and isolation warning.
- **Pressure:** braced pipe risers, red handwheel, calibrated gauge and numeric detent plate. Service panel has three independent coupled-pressure needles and target equations physically attached.
- **Flow selector:** brass listening/flow horn, tactile selector, curved-route vs twin-pipe inset diagram, numbered setting. This geometry does not claim to synthesize sound; runtime owns audio.
- **Memory:** table/rail fixture carrying one spatial pictogram, raised confirmation pose. Stair station contains the order ledger; window, column and octagon have redundant distinct symbols. Round room is confirmation, not an extra note.
- **Ventilation:** open-frame fan housing, safety grille, moving louvers. Isolation closes the damper; opening the vent opens louvers. Motor state advances the rotor pose (not continuous spinning). Attached interlock sequence plate.
- **Light:** three-legged reflector stand, independently aimed mirror and fixed target mark; shutter uses linked opening louvers and charge needle.
- **Repair/egress:** guarded reset/release handles with attached labels, warm lamps.
- **Optional:** bell clapper changes physical pose; locker door opens. Runtime may integrate these as non-objective toggles. The kit does not auto-place extra clutter.

Success and active lamps are warm white/amber, never green (green remains reserved for corruption). Geometry uses ten cached materials; repeated updates allocate no meshes, materials or nodes. Controls retain their actual setting after chapter success rather than snapping all hardware into an invented pose.

## Verification and limits

Run with writable isolated XDG directories:

```sh
XDG_DATA_HOME=/tmp/campaign-station-qa/data \
XDG_CONFIG_HOME=/tmp/campaign-station-qa/config \
XDG_CACHE_HOME=/tmp/campaign-station-qa/cache \
godot --headless --path . --script res://tests/campaign_interactables_contract.gd
```

Final focused result: **2,027 checks, zero failures**, **827 MeshInstance3D objects across the complete 28-station itinerary**, **10 shared materials plus 3 private arrival-diffuser materials per station**. Checks cover every exact kind, optional kinds, finite geometry and declared bounds, collision count, no dynamic physics/lights, embedded plates, visible state change, repeated-update stability, restoration to initial pose, no node growth, coupled-gauge ordering, full-charge pointer, and warm-white rather than green success color. These are CPU/data checks, not native visibility, placement, physics navigation or frame-time acceptance.

`tools/campaign/export_station_gallery.gd` exports the actual procedural meshes to `/tmp/campaign-station-qa/stations.glb`; `tools/campaign/render_station_gallery.py` renders this export in Blender. The gallery image is **actual procedural geometry preview, not gameplay**. Blender does not export/render Godot Label3D plates here, so blank plate surfaces in that preview do not demonstrate in-game text legibility. No source architecture, water, controller, licensed avatar, or original mesh was edited by this kit.
