# Poolrooms Wing CPU contracts

Run from the project root with official Godot 4.6.3 after importing the final assets. Use an isolated writable user directory so the production settings/notebook tests never touch a player's saves:

```sh
mkdir -p /tmp/poolrooms-contract-user/{cache,config,data}
export HOME=/tmp/poolrooms-contract-user
export XDG_CACHE_HOME=$HOME/cache
export XDG_CONFIG_HOME=$HOME/config
export XDG_DATA_HOME=$HOME/data
godot --headless --path . --script res://tests/poolrooms_wing/mode_contract.gd
godot --headless --path . --fixed-fps 120 --script res://tests/poolrooms_wing/movement_contract.gd
```

Reports are written to `output/poolrooms_wing/contracts/`. A failed case produces a nonzero process exit. Movement thresholds are fixed in the test and copied into its report.

## Coverage

- Original and Expanded generation are compared with frozen pre-wing catalogue fixtures from commit `980531f6d25c6ba9581d20036dd6765319b5f93d`. Fixtures omit their global class registrations and redirect only the Expanded preload; the source and fixture hashes are in `fixtures/baseline.json`.
- Ten seeds (including negative and 32-bit boundary seeds) and 121 coordinates each exercise original/expanded generation and the wing's exact three-anchor override. Outside the anchors, only the explicit `poolrooms_mode=true` metadata is allowed to differ.
- Production mode lists, CLI source wiring, default opt-out, deterministic room data, water bounds, dry spawn points, restart argument filtering, rejection guards, atomic settings, notebook records and corrupt-save preservation.
- Production PoolWorld/RoomBuilder collision and unmodified PoolPlayer at 120 Hz: spawn support, all authored dry perimeter circuits, every cardinal entry staircase, each basin stair down/up, stopped dry/wet stability, circular gateway clearance and blocking, and actual two-way shared thresholds between the three new rooms plus an Expanded fallback room.
- Real production capsule width is 0.64 m and height is 1.64 m. A separate 0.64 m wide, 2.0 m tall physics capsule query checks extra standing headroom along dry circulation and circular-door routes.

## Deliberate limits

The water sampler is a deterministic test fixture over the catalogue's authored water rectangles, exclusions and stair AABBs. It does not initialize or validate source SWE/MPM, rendered water, waves, currents, reflections, GPU behaviour or frame-time performance. Headless fixed-step execution is not a performance benchmark. The CLI branch is checked as source wiring rather than launching the full game. No restart process is spawned. Android, PCK export, and published builds are not tested here.

The notebook tests use production persistence and validation, with a ready-room stub for observation. The movement test separately loads actual room geometry and ready-state production paths. The movement routes deliberately do not assume that the centre of every room is dry.
