# Campaign state contract — varied systems (revision 2)

The itinerary still enumerates all **28 distinct source archetypes** in six chapters: `lost_shift` → `maintenance` → `return_water` → `five_memories` → `quiet_archive` → `daylight`. Original separately selectable map modes, avatar choices, controller, water and NR/RT are not replaced by this coordinator.

## Mechanics and source identity

`campaign_catalog.gd` retains all legacy item IDs/room specs for migration and source identity, **not a new collectible hunt**. `source_mode`, `source_index`, and `source_coord` distinguish archived Quiet Wing variants 8–10 from renderer mode `original`.

`campaign_objectives.gd` is a pure deterministic model:

- `initial(chapter)`, `valid(chapter,snapshot)`, `action(chapter,snapshot,index)`, `tick(chapter,snapshot,delta)`.
- Eight breaker network: isolate the faulty night-bath branch, preserve healthy branches, energize feeder, stabilize for eight active seconds.
- Three coupled four-detent valves: satisfy simultaneous pressure equations, then explicitly test at the service panel.
- Two three-way routing selectors and a dependent outlet: route both segments correctly before the outlet can open, then settle flow for six seconds.
- Spatial four-beat memory: correct architectural order followed by a separate verification station. Incorrect input resets only this sequence.
- Ventilation safety interlocks: isolation permits opening the vent, which permits running the motor; ten seconds of purge.
- Daylight alignment: two mirrors enable the main shutter, light charges for twelve seconds, then a separate dome release. Side-pool damping is optional and accelerates charging.

Stations persist physically, have independent recognizable geometry, readable plates and discrete mechanical feedback. HUD approach hints are indirect; it does not print XYZ or a key count. Bell and hinged locker are optional interactions and never progression requirements.

## State, clock and recovery

`campaign_state.gd` owns `objective`, `elapsed`, `relaxed`, `reduced_effects`, `legacy_credit`, `repairs`, chapter/visited/checkpoint and legacy inventory stamps.

- `operate(id)` accepts only the current chapter's known control and rejects operations while pending/completed. `collect(id)` remains a legacy API but **cannot unlock a v2 objective**.
- `advance_time(delta,playable)` accepts finite positive deltas capped at 0.25 s. Mechanism settling and elapsed pressure stop while not playable. Relaxed mode advances mechanisms but never the pressure clock.
- Runtime gates play time on focus, menu, collision/water readiness, all mandatory station mounts, and absence of loading/cinematic/return-recovery work. Alt-tab opens pause. Long stalled frames are not charged as wall-clock time.
- Pressure windows are 480/360/300/420/300/360 seconds. These are generous initial design budgets, **not measured human playtest completion times**. The next 120 active seconds gradually increase presentation severity; saturation does not kill the player, remove floors or lock mechanisms.
- `repair()` restores the window to 55% elapsed and keeps all objective progress; available at an entrance cabinet and in pause. Where a tight stair landing cannot safely hold two cabinets, the certified departure cabinet's handle also becomes emergency reset while corruption is active.
- `retry_chapter()` explicitly resets only the current chapter's mechanisms/window/checkpoint. Earlier chapters remain intact. UI asks for a second click within five seconds.
- `begin_transition()` saves a pending old-chapter marker. `finish_transition()` is allowed only after the coordinator confirms next-world identity, support/capsule clearance and water readiness. The final chapter has its own vignette but no fabricated seventh world.
- Readiness/prefetch waits are bounded (45 seconds). Cancellation/timeouts preserve the old solved objective. A failed rollback world rebuild locks resume and offers a preserved-progress rebuild, rather than exposing the wrong world under the old state.

## Save migration and corruption safety

The existing local filename `user://campaign_v1.json` remains the default to discover old saves. New payloads have `revision: 2`.

`restore(data)` validates into locals and does not mutate on failure. It accepts authentic revision-1 and revision-2 saves; numeric arrays from JSON are canonicalized to integer control/sequence values. Unknown/future/duplicate inventory, missing previous chapters, invalid checkpoints, NaN/infinite timers, malformed objectives and impossible pending/ending snapshots are rejected.

- Revision-1 completed chapters/ending remain completed.
- A fully collected current revision-1 chapter is considered solved, so an existing ready exit is never revoked.
- Partially collected current legacy objects remain recorded; new mechanisms start in a safe state with **30 seconds extra grace per retained object**. The menu explains the migration. They are not silently discarded or presented as a completed new puzzle.
- Pending saves restore the proven old chapter with pending cleared; never an unready next floor.
- Autosave occurs on operations/checkpoints, each ten active seconds, pause and quit. Offline time is not charged.

`campaign_store.gd` keeps fingerprint conflict detection, lock directory, validated temporary file, previous-primary backup and atomic rename. Corrupt primaries and stale locks are not overwritten or guessed away. Read-only backup recovery remains visibly read-only. The explicit “save recovery copy” button creates a new timestamped local file and remembers it in `campaign_profile.cfg`; original files remain untouched.

## Presentation boundaries

`campaign_transition.gd` provides six contained architectural vignettes; real world replacement occurs behind a deliberate full-black occlusion. This is **not simultaneous vertical worlds or a claim of seamless geometry**. Chapter and room cues never grant progression. See `ARRIVALS.md`, `STATION-KIT.md` (if present), and `tests/campaign/PRESENTATION.md` for their focused contracts.

Corruption is reversible light presentation, not structural destruction. It skips original animated/flickering fixtures rather than fighting source effects. Reduced-effects disables new outages and reduces cinematic motion; it does not promise to disable all legacy authored light animation.

## Verification limits

Run with writable HOME/XDG paths, e.g. `godot --headless --path . --script tests/campaign/test_state.gd`. Genuine solution helpers are in `objective_test_helpers.gd`. Runtime tests use real room collision for mounting, approach LOS and checkpoint capsule checks; asynchronous coordinator tests mock GPU water. Static/CPU/render-proxy tests are **not full Windows custom-NR/RT GPU, real water or human route/playthrough acceptance**. The matching Windows runtime is unavailable in this workspace; retain that qualification on delivery.
