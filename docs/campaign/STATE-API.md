# Campaign state contract

The mainline catalog enumerates **28 distinct room archetypes**: 8 source procedural types, 4 expanded facility rooms, 3 Poolrooms Wing rooms, 5 reference rooms, 3 archived Quiet Wing rooms, and 5 formal rooms. It does not claim to enumerate an infinite procedural map or duplicate art-pass replacements as new maps.

Order: `lost_shift` → `maintenance` → `return_water` → `five_memories` → `quiet_archive` → `daylight`.

`campaign_catalog.gd` exposes `chapters(seed)`, `chapter(index, seed)`, `item_by_id(id, seed)`, and `room_key(Vector2i)`. Each chapter includes `id`, `title`, `mode`, `objective`, `departure_label`, `story`, `items`, and `room_specs`. Each item has a globally unique ID, label, source room coordinate, room key, room name, and a provisional local placement. Runtime must validate floor/clearance/line of sight and may reposition a collectible to a nearby safe surface; catalog positions alone do not establish navigability. A room spec separates `source_mode`, `source_index`, and `source_coord` from displayed mode. The archived Quiet Wing is explicitly `source_mode="quiet"`, variants 8–10, even though its renderer mode is `original`.

`campaign_state.gd`:
- `State.new(seed=250821)` starts at chapter zero and its first catalog room.
- `collect(id) -> bool`: only the current chapter's not-yet-collected key, never a future/unknown item. Physical loss of a display prop cannot remove inventory.
- `visit(room_key) -> bool`: accepts a current chapter room coordinate string such as `0,-1`; returns whether newly discovered, and always moves the checkpoint to a valid room. `visited` internally uses `chapter_id:room_key` identities.
- `can_depart()`, `begin_transition()`, `finish_transition()` return bool. Begin requires every current key, sets a pending marker without advancing. Finish is called **only after the next world's collision/landing is ready**. It advances once, or marks the sixth chapter completed. `cancel_transition()` keeps keys and current chapter.
- `serialize()` produces revision-1 JSON-safe data. `restore(data)` validates into locals, leaves this instance unchanged on failure, and returns `{ok, reason, recovered_pending}`. Pending saves deliberately restore the old chapter with all keys and pending cleared, never an unready next room.
- Restore rejects future/unknown/duplicate keys, skipped chapters with missing earlier keys, invalid checkpoints, noninteger numeric fields, and impossible ending state.

`campaign_store.gd`:
- `load_state(path="user://campaign_v1.json")` returns `{ok,state,status,reason,writable}` and `fingerprint` for valid primary loads. Status is `new`, `loaded`, `recovered_transition`, `backup_read_only`, `corrupt_read_only`, or `blocked`.
- `save_state(state,path,expected_fingerprint="") -> Error` uses a temporary file, validates it, preserves the prior valid primary in `.bak`, and atomically renames the new primary. Use the most recently loaded fingerprint when available to detect stale writers. Reload after a successful save to obtain its current fingerprint.
- A corrupt primary is **never overwritten**. A backup can be used for gameplay recovery but is read-only; runtime should visibly indicate unsaved progress and offer a deliberate new-save/restore workflow, not silently reset it.
- Only safe `user://` paths are allowed. `.lock` prevents overlapping writers. Interrupted `.tmp` files and stale lock directories are preserved rather than guessed away. No network/cloud save is used.

Test: `godot --headless --path . --script tests/campaign/test_state.gd`. Use a writable HOME/XDG directory in restricted environments. This suite is pure CPU state/IO, not a visual or Windows runtime acceptance test.
