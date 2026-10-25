# Independent compact-delivery safety review

Reviewed on 2026-10-24. Scope: `compact_source_update.py`,
`build_compact_source_update.py`, their integration with the unchanged installer,
and the outer-package launchers. This was a read-only code review plus memory-only
adversarial probes. No final package was built, no real project was updated, and
Godot, Blender, network operations, and Windows execution were not used.

## Result

No remaining release-blocking issue was identified within the reviewed wrapper
scope and its stated trust/concurrency assumptions. This is not approval of a
future final payload, visual output, Windows execution, or package provenance.

The original installer remains byte-for-byte unchanged. SHA256:

`eee346a3052c9b025c86d709af6537647d02b9403947bcbd67b963dcf4c34aba`

## Findings resolved during review

- Replaced TarFile member iteration with explicit 512-byte USTAR header parsing.
  PAX/GNU metadata is rejected before any extended-header body is interpreted.
  The descriptor binds the exact padded tar length to the complete file-size
  table, in addition to manifest and compressed-archive hashes.
- The wrapper now rejects equal, ancestor, and descendant package/project roots
  before preparation. Consequently, `check` cannot put preparation artifacts
  inside the selected project through an overlapping package location.
- Builder file/total byte limits are checked before output creation or
  compression. Actual compressed-file size is checked before archive hashing;
  `inspect_archive` performs one hash pass rather than two.

## Independent probes

All 51 memory-only probes behaved as expected:

- 30 archive/XZ cases: a valid ordinary USTAR file was accepted; symlink,
  hardlink, directory, character/block device, FIFO, PAX, GNU long-name/link and
  sparse headers were rejected. Traversal, absolute paths, backslashes, ADS,
  unexpected/duplicate/missing files, wrong content/size/checksum, nonzero file
  or tail padding, excess/truncated tar output, truncated/concatenated/trailing
  XZ input, and an insufficient decoder memory limit were also rejected.
- 16 descriptor cases: a valid descriptor was accepted; invalid format, archive
  name, archive hash, manifest binding, bool/nonpositive/oversized compressed
  lengths, inexact tar length, incomplete/duplicate/unsafe size entries, and
  bool/negative/oversized file lengths were rejected.
- Five final control-flow checks: all three package/project overlap forms were
  refused before preparation or installer dispatch; rollback forwarded directly
  to the original core without archive preparation; mismatched actual archive
  size was refused before any archive hash I/O.

The memory-only harness supplied archive bytes and metadata through mocked file
reads with `destination=None`. It did not replace the separate synthetic
filesystem/CLI regression suite or exercise final production assets.

## Security properties and limits

Extraction uses explicitly validated paths, exclusive new-file creation, known
file sizes, per-file SHA256, an XZ decoder memory cap, a decompressed-byte cap,
unique staging, and complete-tree verification before publication. Reusing an
existing payload verifies its exact files/directories and hashes rather than
overwriting it. Rollback/status are independent of compressed-payload recovery.

The package-local lock excludes cooperating preparers, not external editors or
malicious concurrent filesystem changes. External concurrent directory edits
are explicitly unsupported. In particular, portable `os.rename` plus a prior
existence check is not an adversarial no-replace primitive on POSIX: a separately
created empty destination directory can race the check. No stronger guarantee
should be claimed.

SHA256 provides integrity/version matching, not publisher authentication. Run
only trusted package scripts/manifests. USTAR-only encoding intentionally rejects
paths that cannot be represented; it does not silently enable extended headers.
Windows CMD, junction/reparse handling, Windows file locking, crash/power-loss
durability, and the eventual real frozen package still need their designated
platform/final-delivery validation.

## Required-baseline closure extension

The subsequent scoped addition, `baseline_prerequisites.py` and the wrapper's
required-base check, was reviewed against actual 351f runtime patterns. No
remaining source-review blocker was found for the currently scoped Reference
Wing update. This supplements, rather than changes, the archive review above.

Fourteen additional independent memory-only prerequisite-validation probes
passed, bringing this review's independent probe count to 65. They cover a
valid prerequisite list, wrong document format/commit/manifest binding, an empty
list or absent project anchor, duplicate/case-alias entries, payload overlap,
unsafe paths, invalid hashes, missing/modified required assets, and a mismatched
prerequisite-document SHA256. The wrapper validates prerequisites before package
preparation and rechecks before core dispatch; rollback/status bypass these
checks so missing prerequisites cannot prevent recovery.

The following actual dependency cases identified in review are now handled:

- `PoolFixtureFlicker.new()` is a globally registered GDScript class reference,
  not a literal resource preload. Class-name expansion now covers it.
- Four original art-pass GLBs contain 63 relative external image URIs, including
  legitimate `../../materials/...` paths. Resolution normalizes them inside the
  project namespace and rejects external/escaping URI forms.
- Shader directory expansion includes raw `.vert`, `.frag`, `.glslinc`, and
  `whitewater_dfg.rg16f` inputs, not only conventional shader suffixes.
- Auto-discovered `.gdextension` descriptors add their platform binaries.
- The compressed `.scn` and binary `.lmbake` use explicit dependency-query
  results supplied by the integration owner. Both mappings are bound to the
  exact queried SHA256; unknown or changed binary resources require fresh
  explicit verification. This reviewer did not run Godot to reproduce the query.
- Known optional terrain caches, stale optional hand-contract defaults, and
  authoring/provenance paths are explicitly distinguished from required inputs.
  A missing compact descriptor cannot silently downgrade to expanded staging;
  that mode is explicit and refuses remaining compact archive/prerequisite files.
- GLB JSON allocation is bounded to 64 MiB and remaining declared bytes;
  malformed headers, JSON shapes, and URI types fail before compact output.

The archive-derived inventory has 1,018 unique paths, independently checked to
exactly match `git ls-tree` for 351f. Six critical hashes were independently
compared to immutable Git blob bytes: project.godot, PoolFixtureFlicker, both
binary Godot resources, the native extension descriptor, and the raw DFG input.
The recorded real-tree preview reports 234 required immutable base files and
185 baseline metadata exclusions. Baseline `.import`/`.uid` files are traversed
for discovery but intentionally not hash-gated on the recipient, per the
editor-regeneration requirement; newly shipped payload metadata remains strict.

Closure remains scoped to the reviewed runtime patterns, explicit dynamic seeds,
and byte-bound binary mappings. It is not a proof about arbitrary future
GDScript path construction. Final source changes require refreshed closure and
aggregate test evidence. During freeze review, a stale failing compact-test log
was flagged to the integration owner for refresh after its fixture repair;
aggregate pass counts should be reported from the final successful logs, not
inferred from this independent review. The installer core fingerprint is still
the unchanged value recorded above. No final package was created by this review.

Final log refresh (2026-10-24 21:49 UTC): `compact_tests.log` now records 30
passing compact tests, `all_delivery_tests.log` records 46 passing independent
and compact tests, and `existing_synthetic_tests.log` records 38 passing original
tests. The stale fixture-error log has been replaced; the total is 84 passing
unit tests. This does not change the untested final-package/Windows scope.
