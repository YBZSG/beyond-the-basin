# Quiet exploration notes candidate

Status: **not integrated; production default is off**. No existing controller, geometry, water, rendering, materials, audio, input, settings or scene file was edited. The only production candidate is `scripts/gameplay/exploration_notes.gd`. `integration.patch` is a proposal, not an applied change.

## What it adds

A passive notebook remembers the room archetypes actually encountered and up to 4,096 entered coordinates for each exact `(seed, spawn mode)` identity. Original, formal and expanded are separate notebooks even with the same seed. Expanded worlds correctly distinguish their original-room fallback archetypes from the four expanded modules; formal variant 11 cannot alias expanded variant 11. Seed values are decimal strings in JSON, preserving the full signed 64-bit integer range rather than rounding through JSON numbers.

An optional inherited-theme Label in the existing pause-menu column gives a quiet summary: mode and seed, recorded places, encountered room types, the first six type names, and any saving/capacity issue. No HUD overlay, rewards, objectives, completion percentage, popups, combat, sound, collectible effects, external requests or global input listener are added. The existing menu ScrollContainer handles the extra text. The adapter creates no font or theme resource.

There is intentionally **no distance counter**. Teleports and scene switches cannot become invented walking distance. Only the destination coordinate, not any implied intermediate path, may become a discovery.

## Actual project interfaces and ordering

- `PoolWorld.get_room_coord(position)` determines the player's current sector.
- `PoolWorld.current_room` and `is_room_ready(coord)` must agree with that physical position.
- `get_layout(coord)` supplies the actual seed, coord, variant, mode flags, expanded-module identifier and room name. Unknown or inconsistent layouts are not guessed or recorded.
- `room_loaded` is not observed: it includes surrounding streamed rooms the player never entered.
- `room_changed` is not observed: `initialize()` and `teleport_to_room()` emit it before the player is warped.
- The proposed host hook calls `observe_player_room(world, player.global_position)` after the existing `world.update_player_position(...)`, and once after `_create_world()` finishes the real player warp.
- `begin_world(seed, mode)` selects scope but does not itself create a record or consume capacity.
- After an accepted room observation, repeated samples of the same coordinate do not fetch layouts, append entries, write files or update UI. Existing world/ready checks remain read-only.
- No standalone `_process`, `_physics_process`, `_input`, timers, signal subscriptions, thread or monitor exists in the candidate.

The proposed flag is desktop-only `--exploration-notes`. Even if the integration patch is accepted later, sessions without that flag do not instantiate the notebook, read/write its files or add its UI. Android and mobile preview remain untouched. The experimental formal lighting preview shares the same formal notebook because it uses the same authored room identity, not a new map.

## Deliberate bounds

| Item | Bound and behavior |
| --- | --- |
| Stored worlds | 24 seed/mode identities. The 25th new identity is not recorded; earlier worlds are never evicted. Revisiting an existing identity still works. |
| Coordinates per world | First 4,096 distinct coordinates are retained. On the next new coordinate, a persisted limit flag becomes visible. Last observed coordinate and new valid archetypes can still be updated. The coordinate count is not presented as a complete lifetime total. |
| Coordinate components | Canonical integers from -1,000,000 through 1,000,000. Out-of-bounds/non-finite position samples are ignored; the world/player is never clamped or modified. Formal records are restricted to the five actual authored coordinates. |
| Archetypes per world | 32 maximum, with an allow-list matching current catalogues (8 original, 5 formal, up to 12 in expanded). Unknown future archetypes are not silently mapped to existing ones. |
| Names | Nonempty, at most 96 characters, no newline/tab controls. No markup is interpreted. |
| File size | 4 MiB before parsing or committing. Over-limit files are preserved and opened read-only, not truncated. |
| Menu summary | First six discovered archetype names plus an additional-type count. Full bounded records remain in the data file. |

No unbounded visitation list or texture/mesh allocation is introduced. Array membership is bounded to 4,096 entries and is done only on a changed coordinate. Full document serialization is bounded but can pause the menu briefly on slow storage; no target-PC frame-time claim has been made.

## Persistence and failure behavior

The default file is `user://exploration_notes_v1.json`. An enabled instance loads once. Normal saving occurs only when the existing menu opens and on orderly quit, not per physics tick or per entry. Consequently, a crash before the next menu/save may lose the newest in-session discoveries. Existing committed records are not deliberately removed.

The file schema is `{"schema_version":1,"worlds":[...]}`. Each world stores an exact string seed, mode, ordered unique coordinate strings, unique `{id,name}` archetypes, last coordinate and the coordinate-limit flag.

Save sequence:

1. Create a same-directory `.lock` directory exclusively. A cooperating concurrent writer cannot enter the transaction.
2. Verify the primary still matches the fingerprint that this session loaded/committed. An externally edited or missing primary blocks replacement.
3. Write `.pending`, flush and close it, then parse/validate and compare its contents before committing anything.
4. When a primary exists, write and verify `.backup_pending`; rename it atomically onto `.bak` to retain the previous verified primary generation.
5. Rename `.pending` atomically onto the primary, without deleting the old primary first. If replacement is unsupported/fails, preserve the original and pending copies and switch to read-only.
6. Release the lock. No delete/reset UI is included.

This is same-filesystem atomic replacement with a rolling verified recovery generation, not a guarantee against every filesystem/device/power-loss failure. Godot FileAccess.flush does not expose a portable directory-fsync contract. The directory lock coordinates this implementation's writers, not external editors that ignore it; fingerprints reject detected outside changes but cannot promise cross-process compare-and-swap against a noncooperating editor.

- Malformed, oversized, incompatible or future-schema primary: **leave it unchanged**. If `.bak` validates, show that recovery copy read-only. New observations can remain in this session, with a visible read-only warning; no automatic reset or downgrade is performed.
- Missing primary plus a backup: read the backup if valid, but do not silently promote it or create a replacement primary.
- Existing `.pending` or `.backup_pending`: preserve it, show interrupted-save/read-only status, and stop writes rather than overwrite an unreviewed candidate.
- Busy lock: retain dirty in-memory data; a later explicit menu save can retry. A crash may leave a stale lock. Do not remove it until no other notebook writer is running.
- Write, verification or rename failure: retain the previous primary and any pending recovery copies; show status in the menu. No automatic file wiping or repeated background retries.
- Invalid single record/unknown fields: reject the whole document as writable, rather than dropping the record and saving the remainder over it.
- Orderly quit performs a best-effort save. If storage is still blocked, existing committed data is safe but newer in-memory discoveries will not survive process exit.

Recovery is deliberately manual: close running instances, back up every related file, inspect the JSON/version and choose a validated copy to restore. Do not delete a corrupt primary or interrupted pending file before retaining a copy. This candidate has no destructive migration or reset operation.

## Integration proposal, not approval

`integration.patch` contains seven small host touchpoints: one optional member, opt-in creation, post-spawn scope/observation, post-world-update observation, menu save/refresh, an inherited-theme menu Label, and orderly-quit save. `integration-base.json` identifies the source used to generate it. It currently applies in dry-run only. Review it against any concurrent main.gd edits before integrating.

After acceptance, a real-scene test must still verify original → formal → expanded → original, same/different seeds, pause/resume, actual walking, direct travel and regeneration, saved-state restart, UI wrapping at supported resolutions and an actual desktop filesystem (including Windows replacement behavior). Check that turning the flag off restores the unchanged ordinary menu and does not access the notebook. Do not enable this by default on the basis of CPU tests alone.

## Tests

CPU fixtures and source/specification checks:

```sh
python3 tests/exploration_notes_generate_fixtures.py
python3 tests/exploration_notes_cpu_test.py
python3 -m py_compile tests/exploration_notes_cpu_test.py tests/exploration_notes_generate_fixtures.py tests/exploration_notes_run.py
patch --dry-run -p1 < docs/exploration-notes/integration.patch
```

Native CPU-only contract, **only after the owner grants the serial runtime slot**:

```sh
python3 tests/exploration_notes_run.py --serial-slot-granted --timeout 60
```

The launcher uses an isolated XDG user-data/config/cache tree inside `docs/exploration-notes/validation/`. The native test creates a unique directory under that user data, never the real player's notebook. It tests actual PoolWorld coordinate/catalogue methods without initializing a world, constructing terrain, instantiating source water or running gameplay. It covers physical-entry/pre-warp ordering, teleport destination-only recording, three mode identities, expanded fallbacks, signed seed bounds, deduplication, file round trips, previous-generation recovery, corrupt/future/interrupted files, coordinate/world bounds, external-change refusal, lock retry, and inherited-menu UI placement. The launcher enforces a maximum 60-second process timeout and records logs, source hashes and results. These are native logic/filesystem tests, not full-scene, image, GPU, Windows or performance acceptance.

See `validation-status.md` for completed versus pending validation.
