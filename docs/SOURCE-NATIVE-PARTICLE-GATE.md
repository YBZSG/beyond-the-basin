# Exact inert-patch host gate

Status at 2026-10-21 22:29 UTC: **integrated into production**, including all
three rebuilt target binaries. The actual shipped helper passes readback,
mask, gate, fallback/lifecycle and real APIC snapshot CPU replay contracts.
The full native splash and refreshed export package checks remain release gates.

## Measured target and conservative scope

The existing three-domain native regression has 41,418 simulated particles. Its
late frame reports 7.776 ms host packing despite zero visible particles. Earlier
frames still contain thousands of visible particles. Thus reducing only render
buffer allocation/upload cannot remove the late-frame scan cost.

The candidate adds one read-only native eligibility scan per patch. It skips the
original inner host loop only if **every** particle would be rejected before
any surface/depth callback, event, mutation or render packing. If even one
candidate exists, the entire original loop still runs from index zero. No
particle state, return/drop handling, interpolation, solver substep, particle
cap, simulation lifespan or GPU submission policy changes.

The exact original prefix is:

1. Reject removed particles or density below 0.5.
2. Compute the same interpolated world Y from float32 storage and binary64
   scalar arithmetic.
3. Reject only un-emerged particles below `base - 0.06`.

NaN/Inf behavior is not replaced with a finite-value filter. A NaN Y remains a
candidate so the unchanged host body performs its original callbacks/deletion.
The helper validates all array shapes and indices before access. An invalid
input returns -1, leaving the original loop in place rather than dropping work.

The binding invokes the running engine's actual `lerpf` utility (4.6.3 hash
998901048). This deliberately preserves engine-specific interpolation behavior,
including any contraction internal to that engine function. The surrounding
binary64 operations use strict compiler flags with contraction/reassociation
disabled. The method is not registered if its required utility is unavailable.
Production integration must also check class/method availability and retain an
explicit disable switch plus the unchanged GDScript fallback.

## Why not the more aggressive sparse loop?

A sparse cursor experiment moved the next-eligible search into C repeatedly.
Although promising on mostly inert patches, it regressed dense/returned-particle
synthetic workloads. A 32-particle backoff reduced but did not eliminate that
tradeoff. Those experiments remain archived, not selected for production.
The conservative one-scan gate does not add a native call or extra cursor branch
per visible particle. Timings under concurrent software rendering are not used
as a target-device performance claim. The later paired actual-snapshot results
are below.

## Completed evidence

The isolated project is `tests/fixtures/particle_gate_audit/`, excluded from the
main project's importer. Its original host is independently frozen before this
candidate; its extension libraries are separate from production.

- 12,293 direct typed/Variant checks across 1,024 numerical/shape cases.
- 104 full-host assertions over five sequential deltas, all output row bytes,
  complete patch state, bounds, ordered callbacks/events and retained outputs.
  Reentrant callbacks mutate later flags/data, counts and Dictionary arrays.
- A structural check proves that removing only the helper field and gate from
  the candidate reproduces the complete frozen reference host body.
- Independent audit: the same 1,367,007-check pure-core suite passes separately
  at `-O1` and `-O3` under ASan/UBSan. It includes 1,248,384 arithmetic/flag
  cases, exact-sized/poisoned allocations and short-circuit access checks.
- Independent Godot audit reruns the 12,293-check contract, then four clean
  engine lifecycles with eight concurrent readers each: 65,652 additional ABI
  checks and 8,196 instance lifetimes.
- All three candidate binaries have the intended architecture, no imported
  runtime dependencies, and only `source_water_library_init` exported. Android
  LOAD segments have 16 KiB alignment and matching file/address congruence.

Full independent report, commands and exact artifact hashes:
`tests/fixtures/particle_gate_audit/audit/README.md` and its `summary.json`.
The later core-header edit clarifies comments only; no gate expression changed.
Preparation now asserts every injection anchor and records generated-source
provenance. Existing binary hashes are explicitly marked observations, not a
claim that preparation itself performed a rebuild.

## Actual APIC snapshot replay

The native capture archived frames 1, 9, 21, 39 and 59, each retaining three
13,806-particle domains. Its SHA-256 is
`8a343bf31a6be133520693066757831ceb563380c9db898734e14010735e091a`.
The capture's own archival allocations/I/O are not a performance benchmark.

The guarded production-shaped host passes full replay against the frozen
reference at five deltas (0, .003, fixed delta, .05 and NaN). Complete rows,
patch state, bounds, ordered callbacks and events match. The capture fixture's
surface/depth callback constants are replayed from its metadata. Earlier
reentrant/adversarial callback tests remain separate evidence.

A parent-reserved quiet CPU window finished at 22:20:56 UTC. For each snapshot,
two warmups preceded nine alternating reference/candidate calls. Snapshot
cloning, serialization and comparison stayed outside the timer; every timed
result was also compared. New host instances make the measured candidate
include lazy capability detection and helper construction, not just its inner
scan. Cloud scheduling noise remains visible in raw sample ranges.

| Actual frame | Visible rows | Original median ms | Guarded median ms |
| --- | ---: | ---: | ---: |
| 1 | 2,757 | 16.538 | 16.577 |
| 9 | 4,233 | 17.587 | 17.208 |
| 21 | 448 | 14.734 | 14.396 |
| 39 | 0 | 8.501 | 4.983 |
| 59 | 0 | 6.845 | 0.379 |

No meaningful active-state speedup is claimed from the first three rows. Frame
39 still has eligible particles in two domains: those complete original loops
remain intact, and only the third inert domain is skipped. Frame 59 proves all
three domains inert. Thus zero rendered rows alone is explicitly **not** a
license to skip host work. The late-frame median reductions are 41.4% and 94.5%
in this CPU replay, not whole-game/GPU/device frame-rate gains.

Evidence: `docs/verification/eight-hour/water/source_particle_gate_integrated_replay.json`
and `source-particle-gate-integrated-replay-isolated.log`.

## Guard and remaining release gates

The staged production host probes the class/method lazily when domains exist.
`--no-native-water-particle-gate`, an older/missing helper, or a negative native
result keeps the original loop. Runtime disable is immediate; helper lifetime
ends at disposal. Its `nativeParticleGate` diagnostics separate availability,
requested/enabled state, prefix calls, skipped domains/particles, fallbacks and
scan milliseconds. The unchanged active inner body is structurally checked.

The integration lifecycle contract passes 15 assertions both enabled and
explicitly disabled. The full-host 104-check contract also passes against the
actual older production helper, which does not provide the new method.

The production batch is installed. All three rebuilt binaries are byte-identical
to the independently audited candidate binaries. Actual shipped-helper checks:

- Readback: 72,823 numerical assertions and 1,000 typed calls.
- Masks: 1,001 typed calls, plus 13 integration checks in each enabled,
  explicitly disabled and missing-helper mode.
- Gate: 12,293 direct/Variant checks; 104 full-host and 15 lifecycle assertions
  in each enabled, explicitly disabled and missing-helper mode.
- Actual snapshot replay: all five real states and five deltas match again
  using the shipped binary and the actual promoted source.
- All three artifacts retain zero runtime imports and the single init export;
  Android LOAD alignment remains 16 KiB. Readback/mask core files are unchanged.

`tests/fixtures/particle_gate_audit/run_production_tests.sh` regenerates its
isolated test project from the actual production host/binary, rather than
quietly testing the old staged candidate. Previous production binaries are
archived separately for reproducible older-helper evidence.

Binary/source hashes: `native/source_water/verification/binaries.json` and
`docs/verification/eight-hour/water/exact-water-bundle-source-hashes.json`.
Reports: `native/source_water/verification/particle-gate-*.json` and
`docs/verification/eight-hour/water/source_particle_gate_production_replay-parity.json`.

Remaining release gates are the full native splash regression and refreshed
Windows/Android package inclusion checks. No further production changes are
planned before the next actual room-render checkpoint.

Only Linux CPU/headless execution has been validated so far. Windows/Android
binary inspection is not runtime execution or device performance. ASan/UBSan
cover the standalone core, not the prebuilt Godot engine/extension. LeakSanitizer
is unavailable under executor ptrace and was disabled explicitly. Concurrent
read-only use is covered; concurrent array mutation, hot reload, custom rounding
modes and custom double-precision engines are not claimed tested.
