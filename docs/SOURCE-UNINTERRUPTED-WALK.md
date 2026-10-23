# Original-world uninterrupted CPU walk

## Verified behavior

The corrected fixture passes **76 checks in both the current runtime and the archived serial scheduler**. Each process verifies 16 published payloads against complete uncached depth, BVH and mask rebuilds from the immutable inputs present at that exact publication boundary.

Evidence: `docs/verification/eight-hour/transition/source-uninterrupted-{current,serial}-functional.{json,log}`. These runs overlapped native rendering and establish functional correctness, not isolated performance.

The fixture uses the production CharacterBody3D and held forward/sprint Input actions at 5.2 m/s, normal engine-driven 60 Hz physics and seed 250821. After one initial placement, the route is `(0,0) → (50,0) → (0,0) → (0,-50) → (0,0) → (50,0) → (0,0)`: 300 m, 12 room boundaries, 57.54 seconds. It never calls `complete_pending_streaming`, waits between legs, teleports between legs or builds references while moving. The destinations extend beyond the initial water field's 48 m half-domain. It waits for only the initial usable field, not all six prewarm origins.

Both corrected runs reach every destination with zero floor misses, incomplete destination rooms, 25-room residency shortfalls, unusable-water observations and field overruns. Cache occupancy stays at six; worker ownership stays at one for the archived scheduler and two for the new scheduler. Reference captures retain immutable arrays rather than copying geometry during movement; their measured observer cost is excluded from reported preparation-stage times and reported separately.

This is headless static-water preparation plus actual player collision/input. GPU wave stepping, dynamic props, final rendered frames and target-device FPS are not covered. A physics observation can span several engine steps under external load; the functional reports retain maximum observed displacement and frame counts rather than claiming one observation per simulated tick.

## Preliminary isolated pair, and its limitation

The earlier isolated serial/current pair is preserved as `source-uninterrupted-{serial,current}.{json,log}`. Both real movement routes succeeded, but those overall reports remain **FAIL** because the original test sampled the aggregate snapshot *after* the pump returned. The pump could clear or replace that aggregate after publishing, so some references used empty inputs. The test now captures immutable room values immediately before `_commit_terrain` and records outputs only after a successful publication. Production code was not changed to fix the fixture.

The isolated pair is descriptive scheduler evidence, not a completed all-check benchmark:

| Measurement | Archived serial | Current |
| --- | ---: | ---: |
| First usable exact field | 1,551.246 ms | 1,454.994 ms |
| Continuous route wall time | 57,553.766 ms | 57,537.376 ms |
| Post-route settle | 0 ms | 0 ms |
| New demand pending behind unrelated worker observations | 135 | 17 |
| Terrain jobs | 58 | 52 |
| Maximum workers / cache entries | 1 / 6 | 2 / 6 |
| Maximum measured total CPU stage per observation | 22.893 ms | 23.146 ms |

The 135 → 17 count is **not blocked-player time**. The existing valid terrain remained usable and the player continued moving in both cases. A single ordered pair does not establish statistical speedup; the total main-thread maximum did not improve. Every 50 m leg took approximately 9.59 seconds, and each collected only its ten entering rooms across two boundaries, not all 25 resident rooms.

Both runtimes used the same then-current exact preparation kernels and world implementation. The archived runtime copy differs from its preserved delivered source only by removal of its global `class_name` declaration to avoid a test-time name collision. Provenance and the shared source hash manifest are retained with the reports; all shared production script hashes were unchanged across the initial isolated pair.

## Follow-up boundary

A corrected, repeated isolated comparison is still useful when the GPU/CPU coordinator has a free window. Do not substitute the contended functional timings for that result. The independently controlled 97-check scheduler contract already covers bounded preemption, newest-demand selection, stale publication rejection, visited-first eviction, malformed-payload atomicity and orderly shutdown; its barriers are correctness instrumentation, not performance data.

## Short native out/back/revisit fixture, prepared for the serial GPU slot

`tests/source_uninterrupted_walk_native.gd` loads the normal main scene with fresh settings and requires the original world plus shipped High. It preserves the project's default window/viewport rather than lowering its resolution. After its first usable terrain field, it makes one explicitly declared initial placement at `(0, -0.64, 15.25)`, then holds production forward/sprint input across the `z=16` portal and back twice. The four legs are 1.5 m each before the 0.14 m waypoint tolerance. There are no between-leg teleports, preparation waits, manual world/water pumps or quality overrides. Unlike the earlier CPU comparison's explicit 60 Hz setting, this native fixture preserves the project's actual **120 Hz** physics.

The observer runs after the production callbacks on every physics step. That prevents several batched physics ticks in a slow rendered frame from skipping the turn point. It reports first versus repeat visitation separately from actual cache-hit counters; a repeat visit is not automatically labelled a cache hit. It also records simulated time, wall time, observer overhead, worker-stage samples, main-thread water-stage maxima, floor/destination/field continuity and bounded worker/cache occupancy. A temporarily larger residency set is allowed while old collision shells are retained, but fewer than 25 rooms fails the fixture.

The CPU-only observer contract passes **17 checks** with the production CharacterBody/input and a synthetic flat floor, fake room publication and fake water status. This verifies observer mechanics only, not actual rendered transition performance. Its accelerated fixed-fps wall time is not a performance result. Evidence: `docs/verification/eight-hour/transition/native-walk-observer-contract.log`.

A second **18-check** observer run limits rendered updates to 15 Hz while retaining ordinary 120 Hz physics. It completes the same 119 physics steps in only 17 rendered updates. Every leg endpoint and every crossing tick matches the one-step-per-rendered-frame run exactly, proving turns and the final input release do not wait for the next rendered-frame sample. Evidence: `native-walk-observer-batched-contract.log` and `native-walk-observer-comparison.json` in the same directory. This remains a synthetic CPU test, not native water validation.

Parent coordinator launch, only when the native GPU slot is free:

```sh
bash tools/run_native_uninterrupted_walk.sh --native-slot-granted native-walk-01
```

The wrapper uses fresh per-tag settings, refuses existing Godot processes or overwritten evidence, allows 300 seconds for initial preparation and 180 seconds for the short route, then enforces a 540-second whole-process limit plus a 15-second termination grace. It appends the real process exit code to the log. Native execution remains pending; neither script parsing nor the synthetic observer contract establishes a graphical pass. Optional direct-script `--distance=35` extends the route beyond the original 48 m half-domain, but is deliberately not the short default.

The walk and lifecycle wrappers also share a native-namespace lock, held across the lifecycle pair, to prevent a between-process race. They still require the parent's explicit serial slot coordination. `tools/profile_native_walk.py` writes a separate `-process-summary.json` only after the child exits: a route PASS followed by a timeout, crash, missing/duplicate exit marker, or script error is not a successful run. Shutdown TextureRID warnings are retained separately and prevent a clean-shutdown claim even when movement passed. Eight CPU-only walk-log tests and nine lifecycle-log tests cover these distinctions.

The native wrapper also records a post-exit Godot-process survivor check. The analyzer now requires exactly one valid `SOURCE_NATIVE_WALK_PROCESS_REMAINING=0` marker in addition to the fixture result and exit 0. Missing, duplicate, malformed or surviving-process evidence fails closed. All 12 CPU parser cases pass; this does not substitute for the queued actual native route.

## Promoted prop active-set observations

The queued native route now binds all production script/shader bytes and its
observer at start and finish and rejects mid-run source changes. It separately
records the actual pre-warp source-spawn prop/eye snapshot and the route's one
controlled portal placement; neither is conflated with the synthetic
`(0, 1.6, 0)` 60/640 fixture. Start/end and every crossing retain actual manager
ownership, active/inactive/total counts and cumulative force-call deltas.

Per-tick observations verify callback ownership, error state and disabled
contacts on marked-inactive bodies. They are post-player counts only: they do
not incorrectly recompute the radius predicate against an eye which moved
after the manager's priority -1000 callback. Samples are bounded to 64 changes,
and observation time is included in the fixture's separate observer cost.
The first-field startup timer is explicitly labelled as beginning after
synchronous main-scene insertion, not total process startup. These additions
change only test/diagnostic files, not prop production code or terrain caches.

### Separate held-input smoke

After the route observer has stopped, `source_held_input_smoke.gd` selects an
existing active prop in the current room. It checks the floor normal, empty
player capsule and unobstructed prop ray before its separately reported
controlled start pose. That placement is not added to traversal distance or
crossings. The production player then receives actual viewport mouse events:
left press, wheel up/down, maximum/minimum clamp, fractional restore and left
release. No direct `grab_prop`, hold-distance assignment, new prop or force
integration bypass is used. The report records the unchanged body identity,
real promotion parent, manager selection and force deltas across release.

The small CPU contract passes 10 checks on a synthetic floor with the actual
production player, prop bodies and manager. It also proves missing action
bindings and unavailable targets fail closed. This is not graphical proof.
The native wrapper is capped at 600 s plus 15 s termination grace, with 300 s
startup, 180 s route and a 60 s interaction expectation plus shutdown margin.
The interaction's elapsed-time failure check cannot preempt an engine frame;
the outer timeout is the hard process bound. The native coordinator must keep
the game in focus and the bound production/test source unchanged until exit.

## Actual native attempt 01: incomplete, not a pass

`verification/eight-hour/transition/native-walk-01-analysis.json` binds the
original report, process summary and preserved fixture-source archive. The
full-quality original world reached its first field after 254.879 s measured
from scene insertion. Its 180 s movement budget was checked after a long frame
at 195.865 s: only ten rendered frames and 80 physics ticks (0.667 simulated
seconds) had advanced. Two legs and three actual crossings covered 3.467 m,
so the four-leg gate correctly failed; exit was 1 with no surviving process.
The held-input smoke was not run after that failure.

For the observed portion there were zero floor, unfinished-destination,
water-domain, residency or input-pause violations. Cache entries stayed at six,
workers at one and two real terrain cache hits occurred. Actual prop selection
was 64–67 bodies, with callback ownership intact, 5,190 force calls and no
inactive-contact violations. Tracked bodies briefly rose from 640 to 708 during
overlapping streamed rows. The actual spawn-eye sample `(10, 1.5, 12)` was still
menu-paused and correctly reports zero active bodies; it is not an active-spawn
performance measurement or the separate synthetic 60/640 fixture.

Initial original-world worker preparation was fresh: both disk and memory hit
counts were zero, and jobs had started. The log's `cached: 1` means **one memory
cache entry**, not a disk-hit flag. Its 1,192.641 ms worker timing is current-run
work (BVH 1,062.771 ms, masks 108.215 ms). Later cached publications repeat
stored payload timing; those values are historical, not fresh rebuild times.
Main-thread extraction totaled 98.884 ms across slices, max 11.529 ms, and the
first commit took 5.390 ms. These CPU timings do not explain away the much
longer software-rendered wall time and are not target-device benchmarks.

### Staged shorter variant, not executed at preparation

`bash tools/run_native_uninterrupted_walk.sh --native-slot-granted native-walk-short-01 --short-four-metre-route`
uses four 1.0 m legs centered on the same portal, not teleport crossings. Its
240 s route and 90 s held-input expectations fit within a 650 s outer timeout
plus 15 s termination grace. Production quality, physics cadence and movement
speed are unchanged. The batched-render CPU observer passes 27 checks, including
four real crossings and full player-capsule clearance at all turn points.
Actual distance is recorded separately from the nominal 4 m waypoint path.
Recording has priority; this prepared variant is not graphical evidence until
its own native report and clean process outcome exist.
