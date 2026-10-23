# Frozen-source release packaging

Staging/audit tools never install an engine, download an SDK, generate a signing key,
sign a new APK, publish, or execute a Windows/phone build. They stage and audit
artifacts after the source owner declares the source and imported geometry frozen.
The separate explicitly invoked `acquire_windows_templates.py` downloads only
the two official release-template entries and never executes them.
The existing authorized Android signing route remains `tools/android/export-test-apk.sh`.

## Read-only preflight and exact inclusion contract

Run `python3 tools/release/preflight_release.py --source . --report /absolute/preflight.json`
without importing or exporting. This inventories the live tree only; it is not a
snapshot or a guarantee about files changed afterward. Staging still waits for
the release owner's explicit coherent freeze.

- Editable game source requires all six formal `.blend` files, their generator
  and floor-plan source, six formal GLBs, four Quiet Wing GLBs, original room
  generation and water code, desktop/mobile quality controls and gait audio code.
  Numbered Blender backups (`.blend1`, `.blend2`, `.blend3`, etc.), interrupted
  `.blend@` saves, `blendcache_*` directories and `.bphys` caches are excluded;
  authored `.blend` sources, source `.gdignore` and generator inputs remain.
- A shipped PCK is not complete without its platform helper beside it at the
  descriptor's relative path. Windows staging also includes the helper's C/header
  sources, vendor interface, build recipe, license and atomic-build provenance.
- PCK/APK audits follow exported `.import` remaps for models, audio, textures,
  mobile icons and compiled compute shaders, and compare actual imported payload
  bytes to frozen source imports. Raw shader text, raw GDScript and prepared
  terrain remain separately verified.
- Historical terrain, lab/quarantine data, tests, tools, output and source audit
  documents cannot enter playable exports. Imported rejected EXR payloads are
  checked too. Source recovery retains prepared runtime terrain, not editor caches.
- Repeated generated test-run workspaces, sanitizer binaries, fixture build/cache
  directories and duplicate engine-API snapshots are omitted from source. Small
  top-level JSON result/input manifests, audit harnesses and golden fixtures remain.
- No staged distributable contains a signing key, private credentials, SDK, compiler,
  `.git`, or host import cache. Editable source and PCK-only packages omit the engine;
  the self-contained Windows package deliberately includes the official release
  template executable and its license notices. The sole permitted `.godot` source
  entry is the portable native startup registry.

The optional lab is deliberately separate for final editable delivery:

Final decision at 01:02 UTC on 2026-10-22: all baked GI remains quarantined.
The hot and pre-first-draw cold full-game attempts ended by external SIGKILL,
without a baked full-game candidate image. Genuine native finite/UV/optical
proofs do not establish visual acceptance. Read-only preflight and actual PCK/APK
audits now fail closed if `assets/lighting_runtime`, `scenes/formal_baked` or
`scripts/rendering/formal_baked_lighting.gd` appears in the release source/runtime.
No export preset was weakened to hide or silently promote a bake.
The evidence binding is retained at
`docs/verification/eight-hour/material-lighting/baked-gi-quarantine-decision.json`.

```
python3 tools/release/stage_release.py lab --source . \
  --output /absolute/release/PoolCore-Optional-Lighting-Lab \
  --zip /absolute/release/PoolCore-Optional-Lighting-Lab.zip
```

It preserves lab scene sources and small fixtures without the rejected full-hall
EXR/bake. `LAB-RESTORE.txt` explains which retained tests require it and provides
exact regeneration commands and safeguards. Its prefixed `LAB-PACKAGE-MANIFEST`
and `LAB-SHA256SUMS` cannot overwrite the gameplay source manifests on restoration.
Each fixture keeps its own validation scope. No lab data is thereby promoted to
gameplay lighting. Development recovery staging defaults to retaining laboratory
work so unfinished experiments are not lost.

If the optional lab exceeds 16 MB, stage it without `--zip` and run
`make_lab_archives.py --staged-lab /absolute/release/PoolCore-Optional-Lighting-Lab
--output /absolute/release/lab-parts --label PoolCore-Optional-Lab-YYYYMMDD-HHMM`.
These are ordinary file-boundary ZIPs, not binary parts. Extract ALL of them
directly into the editable project root. The exact union and every hash are
checked against the separate LAB manifest; gameplay paths and the rejected large
study payloads are refused. Retained tiny fixtures do not require regeneration.

## Verified dependency findings (Godot 4.6.3 official)

1. `--export-pack` creates only the PCK. It **does not copy shared libraries**.
   The PCK contains `native/source_water/source_water.gdextension` and
   `.godot/extension_list.cfg`, but no runtime DLL/SO. Explicit staging is required.
2. Keep the Windows DLL at
   `native/source_water/bin/source_water.windows.x86_64.dll`, relative to the
   package root. Do not flatten the directory tree.
3. With an engine in another directory, `--main-pack /full/game.pck` alone did
   not load an external helper from next to that PCK. `--path /package/root`
   together with `--main-pack` did. `Launch-PoolCore.cmd` always supplies both.
4. A Linux CPU launch loaded the same helper after relocating the package into
   a directory containing spaces, Chinese characters, and `!`. This is a Linux
   execution result, **not a Windows CMD execution claim**.
5. The Android exporter places the helper in
   `lib/arm64-v8a/libsource_water.android.arm64.so`. The descriptor remains an
   asset and its original resource path remains unchanged. The official Android
   loader resolves the basename when the resource path is not an ordinary file;
   the tested standard template sets `extractNativeLibs=true`. The APK audit
   checks the real native ZIP entry, not only the descriptor.
6. The editor scan normally generates `.godot/extension_list.cfg`, but Godot
   4.6.3 has a first-discovery headless documentation shutdown race. The source
   package includes only this portable one-line bootstrap, not generated import
   caches. Every final source/PCK/APK audit requires startup registration.
   `Prepare-Editor.cmd` restores the known entry before opening the editor, and
   preserves unrelated extension entries.

Our fresh-discovery crash, clean no-extension control, and clean startup-prelisted
control match the upstream reports [#111048](https://github.com/godotengine/godot/issues/111048)
and [#111645](https://github.com/godotengine/godot/issues/111645). The helper binary
was not changed to mask this engine/editor race. All successful export probes
record the bootstrap explicitly; a failed exporter exit is never accepted.

Primary implementation references:
- [Godot PCK reader](https://github.com/godotengine/godot/blob/4.6.3-stable/core/io/file_access_pack.cpp)
- [Godot Android dynamic-library loader](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/os_android.cpp)
- [Godot Android exporter](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/export/export_plugin.cpp)

Windows and Android binaries have the audited target architecture, no added
runtime dependencies, and the expected entry point. The Android helper's ELF
segments have 16 KiB alignment. Static correctness and Linux execution do not
replace a Windows GPU or physical-phone run.

## Final release order

Run from the frozen source root. Quote all paths. Use the matching official
Godot 4.6.3 executable and existing export templates. Do not run an import or
bake while another worker is changing geometry, materials, lights, or algorithms.

1. Before first headless import/export, bootstrap the known startup registration:
   `python3 tools/release/prepare_extension_registry.py --project .`
   This preserves existing extension entries. Then finish the source editor
   import. Treat any abort as failure, even if a PCK was written. This explicit
   startup prelist avoids the verified upstream first-discovery editor race.
2. Both final presets must use `script_export_mode=0` and include
   `*.glslinc,*.vert,*.frag,*.rg16f,*.terrain`. Source text is intentional: exact
   authored-cache identities depend on the loaded source-code bytes. Encrypted
   or bytecode-only exports are not accepted by this release gate.
   Keep `terrain-cache-history/*,scenes/lighting_lab/*,assets/lighting/*` excluded from playable PC/APK
   exports. The first native lightmap study contained non-finite radiance; its
   files may remain clearly labeled in editable source, not as release GI.
3. Rebuild prepared authored assets **after the final source/GLB import changes**:
   `godot --headless --path . --fixed-fps 120 --script tools/cache/bake_formal_terrain.gd -- --all-quality`
4. Validate actual startup seed 250821 without building fallback replacements:
   `godot --headless --path . --fixed-fps 120 --script tools/cache/validate_formal_terrain.gd -- --all-quality --seed=250821 --report=/absolute/release-source-cache.json`
5. Export the actual PCK:
   `godot --headless --path . --export-pack "Windows Desktop" /absolute/frozen/PoolCore-Source-Water.pck`
   Require process exit 0. Do not rely on file existence alone.
6. Stage into a NEW directory outside the source project:
   `python3 tools/release/stage_release.py windows --source . --pck /absolute/frozen/PoolCore-Source-Water.pck --output /absolute/release/PoolCore-Windows`
7. Validate the actual PCK's exact cache hits using a separate, Linux-headless
   host probe. The PC package itself retains only the Windows DLL:
   `python3 tools/release/validate_frozen_release.py --source . --pck /absolute/release/PoolCore-Windows/PoolCore-Source-Water.pck --package-root /absolute/release/PoolCore-Windows --report-dir /absolute/release/frozen-gate --all-quality --all-early-rooms --seed 250821`
   This runs the cache validator both against frozen source and against the
   exported PCK, requires every expected hit, and compares source and terrain
   signatures. The early-room sweep additionally verifies all five initial
   teleport targets, strict catalog publication order, and complete five-room
   coverage for every requested quality. It initializes no GPU water rendering
   and does not bake caches. Use another new report directory for seed 1337 if
   validating the second supported seed.
8. The release owner performs the separate, serial native-GPU PCK smoke and
   visual check. Do not call the static/CPU gate a GPU/phone performance pass.
9. Export Android using the existing authorized key and existing script. Then
   extend its historical verifier with this native-aware audit:
   `python3 tools/release/audit_packages.py --report /absolute/release/apk-native-audit.json apk /absolute/release/game.apk --source . --build-tools /absolute/android-sdk/build-tools/36.0.0 --require-signature --expected-signer-sha256 b37b9b79f772a8a88df696a41190b3b8ce2f655788503a220160b7ef74e2cf11`
10. Stage editable source only after the final gate passes:
    `python3 tools/release/stage_release.py source --source . --source-profile final --output /absolute/release/PoolCore-Source --zip /absolute/release/PoolCore-Source.zip`
    The source package includes all three native targets, source, notices,
    authored assets, and release tools. It excludes signing material, SDKs,
    native build intermediates, generated `.godot` cache (except the portable
    extension-list bootstrap), output, and credentials. `Prepare-Editor.cmd` and
    `SOURCE-OPEN.txt` are placed beside project.godot.

Use the staging tool's `--zip /new/archive.zip` to create a deterministic ZIP.
An existing output/archive is deliberately rejected. A failed partial staging
folder is not a release. Do not zip it by hand and treat the failure as success.
`PACKAGE-MANIFEST.json` and `SHA256SUMS.txt` record staged bytes. No file-count,
source-code, or cache result alone establishes correct final GPU rendering.

## Development recovery checkpoints

A recovery checkpoint is not a final release. First stage source as above, then
split that staged tree with:

```
python3 tools/release/make_checkpoint_archives.py \
  --staged-source /absolute/checkpoint/source-staging \
  --output /absolute/checkpoint/new-archives \
  --label PoolCore-Development-YYYYMMDD-HHMM \
  --snapshot-utc YYYY-MM-DDTHH:MM:SSZ
```

The default bound is **16,000,000 bytes per ZIP**. Source, runtime assets,
runtime models, editable Blender files, and prepared terrain are split at file
boundaries. Each is a normal independently extractable ZIP, not a multipart
volume. Extract **all** ZIPs into the same parent directory to recover the whole
project; the source ZIP alone is deliberately not a playable game. Every staged
file occurs exactly once across the archive set. CRC, SHA-256, duplicate/omitted
paths, archive sizes, native build identities, and privacy exclusions are checked.
`CHECKPOINT-ARCHIVES.json` records archive hashes and exact limits. No import,
export, signing, installation, or upload is performed by these Python tools.

Staged manifests are checked before and after archive creation so changed,
extra or missing files fail closed. Once the current all-quality CPU validators
have produced all five early-room reports, bind the staged bytes to those reports:

```
python3 tools/release/verify_checkpoint_identity.py \
  --staged-source /absolute/checkpoint/source-staging \
  --cache-reports /absolute/frozen-reports/formal-cache-early*.json \
  --report /absolute/checkpoint/RECOVERY-IDENTITY-AUDIT.json
```

This verifies the engine's serialized-string source signatures, 15 exact terrain
hits per early room, source/snapshot identity agreement, stored container integrity
and the exact 16-file prepared-cache set. It does not rerun the engine, decompress
and revalidate terrain here, or turn CPU evidence into graphical/device acceptance.

## Final PC and Android attachment transport

Keep canonical validated outputs named `PoolCore-Source-Water.pck`,
`PoolCore-Windows-Play.zip`, and `PoolCore-Source-Water-Android-Test.apk` in the
new timestamped delivery directory. Never replace the retained baseline files.
The Windows ZIP contains the PCK, correct external native DLL, diagnostics,
sources/licenses and instructions. The APK already contains its ARM64 helper.

If a complete PC ZIP or APK exceeds the attachment bound, split that immutable
artifact, not its unvalidated live source:

```
python3 tools/release/make_binary_parts.py \
  --input /absolute/release/PoolCore-Windows-Play.zip \
  --output /absolute/release/pc-delivery \
  --label PoolCore-PC-YYYYMMDD-HHMM
python3 tools/release/make_binary_parts.py \
  --input /absolute/release/PoolCore-Source-Water-Android-Test.apk \
  --output /absolute/release/android-delivery \
  --label PoolCore-Android-Test-YYYYMMDD-HHMM
```

The tool creates normal independently extractable ZIPs named
`<label>-Part01-of-NN.zip`, each below 16,000,000 bytes. Unlike editable source
checkpoint parts, the embedded binary parts MUST be reconstructed before use.
Extract all matching parts together and run `Rebuild-PC-Package.cmd` or
`Rebuild-APK.cmd`; Python 3 alternatives are included. Every part, manifest and
final artifact is SHA-256 checked, and different existing targets are never
overwritten. PC reconstruction produces a complete ZIP which still must be
extracted before launch. Android reconstruction produces the original signed APK.
The double-click CMD runs the reviewed inline PowerShell via `-NoProfile
-Command`, not `-File` or a `.ps1`-only route. The base directory is passed in
`POOLCORE_REBUILD_BASE` and consumed as environment data, so Chinese, spaces and
`!` never become PowerShell source. No execution-policy bypass is used. The
scripts do not install, download, upload, execute a game or change execution
policy. The PowerShell/Windows paths are statically audited, not Windows-executed.
Python reconstruction is tested under spaces, Chinese characters and `!`.

Use `audit_packages.py apk ... --require-signature` for the final APK. The older
`tools/android/verify-apk.py` requires bytecode `.gdc` and is incompatible with the
deliberate source-text export policy; do not weaken current exports to satisfy it.
The current audit requires the test/debuggable manifest, ARM64-only runtime and
helper, no added permissions, v2/v3 signatures and 16 KiB ZIP/ELF alignment. It
pins the public certificate fingerprint to the retained authorized test APK when `--expected-signer-sha256` is supplied. That public digest is not secret signing material. The audit never reads or packages the existing authorized signing key, and does not claim
physical-phone installation, graphics correctness, heat or frame rate.

## Native probe and CPU tests

`python3 tools/release/test_release_tools.py` runs offline, standard-library
checks of PCK v2/v3 parsing, all-entry hashes, malformed archives, privacy
filtering, source symlinks, reproducible ZIPs, native ABI headers, launcher
quoting, preserving/idempotent registry bootstraps, experimental-lightmap
exclusion, complete cache coverage, and early-publication-order rejection.
Windows CMD is statically inspected, not run.

`probe_native_exports.py` creates a tiny isolated project, exports Windows and
Linux PCKs, tests missing-library fallback and separated/relocated engine paths,
and optionally exports an **unsigned** arm64 APK. It startup-prelists the
extension by default; `--discover-extension` is only for reproducing the upstream
engine issue, not for accepting a failed export. Its output must be empty and
separate from the source. Example:

```
python3 tools/release/probe_native_exports.py \
  --source . --output output/export-probe/final \
  --existing-debug-keystore /absolute/existing-authorized-debug.keystore \
  --android-template /absolute/templates/4.6.3.stable/android_debug.apk \
  --android-sdk /absolute/android-sdk \
  --java-home /absolute/java-home \
  --build-tools /absolute/android-sdk/build-tools/36.0.0
```

The existing key path prevents the Godot editor's default-key auto-generation.
The probe does not read key contents or invoke signing. Do not omit that guard
and assume an unsigned export cannot create a default key as an editor side
effect. No credential is copied into the fixture, output, or source package.

## Portable Windows use

Ship `Launch-PoolCore.cmd` and `README-RUN.txt` from this directory, not the older
launcher under `tools/windows`. The new launcher explicitly binds the package
root for native dependencies. It resolves relative engine arguments before
changing directories, disables delayed expansion (preserving `!`), quotes
paths, accepts a 4.6.x or 4.7.x version regardless of filename, writes local diagnostics,
and pauses on failure. Any version other than the tested 4.6.3 baseline receives a clear unverified-version warning, not a forced downgrade. Engine-bound exact terrain caches may rebuild under another engine version, increasing first-run preparation time. It never downloads, installs, uploads, resets saves, or
changes security settings. The PCK-only edition does not bundle an engine. The
self-contained edition includes `PoolCore-Source-Water.exe`, which the launcher
prefers unless an explicit engine path is supplied.

The GDScript helper fallback remains an intentional runtime behavior. The
release audit still rejects a missing required shipped DLL; fallback is not an
excuse to ship an incomplete package. If a user loses/removes that optional
helper, normal script execution can continue, with expected load diagnostics
and higher CPU parsing cost.

The full main Godot Windows EXE may be renamed. The small official console
wrapper is not standalone: preserve its companion main EXE and matching names.
This distinction is enforced by the [official 4.6.3 wrapper source](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/console_wrapper_windows.cpp).
The launcher prefers the full 4.6.3 engine and retains redirected logs; Godot
[preserves Windows redirected stdout/stderr handles](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/os_windows.cpp).

When executing an older checkpoint’s Python tools from its immutable staging tree, use `python3 -B` (or `PYTHONDONTWRITEBYTECODE=1`) so imported helpers do not create unmanifested `__pycache__` files. Current CLI entry points disable bytecode writes themselves.

Generated XDG user/cache/config trees and Godot/Mesa shader caches under old evidence folders are excluded from source staging. Small reports and screenshots remain; prepared gameplay `assets/cache/*.terrain` files and `tools/cache` generators are retained. This also avoids irrelevant cache paths exceeding common Windows extraction limits.

## Private final-build freeze

Only after the release owner signals a stable production/source/import freeze:

```
python3 -B tools/release/freeze_build_inputs.py create \
  --source /absolute/stable/project --output /absolute/new-release/build-project
```

This verified copy retains `.godot/imported`, the script-class/UID registries and
native startup registration, but never copies export credentials, editor
preferences, keys, SDKs or toolchains. It is private build staging, NOT the
editable ZIP and NOT an upload artifact. All copied source/imported bytes are
hashed and the live selected set must remain unchanged through the copy. Once
that copy passes, source editing outside the build tree can resume. Keep export
outputs and Android signing/export HOME outside the build tree.

After each import/export, and again before staging final deliverables:

```
python3 -B tools/release/freeze_build_inputs.py verify \
  --source /absolute/new-release/build-project
```

Generated engine metadata/new cache files may appear, but a changed or missing
original source/imported payload is rejected. Do not rewrite the old manifest to
hide a change. Diagnose it and create a newly identified freeze, rebuilding and
revalidating terrain when its inputs changed. Run all actual PCK/APK gates
against this same build tree, then use `stage_release.py source --source-profile
final` to produce the cache-free editable delivery and the separate optional
laboratory package.

For the final cache-free editable source, ordinary bounded source parts remain
preferable to a binary-split source ZIP. Stage the `final` profile without
`--zip`, then run:

```
python3 -B tools/release/make_checkpoint_archives.py \
  --kind editable-source --staged-source /absolute/release/PoolCore-Source \
  --output /absolute/release/source-parts --label PoolCore-Source-YYYYMMDD-HHMM \
  --snapshot-utc YYYY-MM-DDTHH:MM:SSZ
```

This rejects a development/lab-containing staging profile, omits the stale root
recovery-status document, and writes fresh editable-source scope/restore notes.
The archives remain ordinary ZIPs to extract together in any order. Their exact
manifest is `EDITABLE-SOURCE-ARCHIVES.json`; archive integrity alone does not
assert final graphical/device acceptance.

## Self-contained Windows release

The primary self-contained package includes the PCK + diagnostic launcher route,
so there is no need to deliver a second copy of the full PCK. Its filenames are deliberately paired:
`PoolCore-Source-Water.exe`, `PoolCore-Source-Water.pck`, and the unchanged external
`native/source_water/bin/source_water.windows.x86_64.dll` tree. The full Windows
release template is sufficient; the optional console wrapper need not be bundled.
The diagnostic launcher records redirected output and prefers the bundled EXE,
while still accepting an explicit arbitrary-name Godot 4.6/4.7 EXE path.

Availability checked 2026-10-21 23:18 UTC: Android templates were extracted locally;
Windows templates were not. `templates-index.tpz` was only a sparse ZIP directory
index, not a complete downloaded archive. Its official 4.6.3 index lists the x86_64
release EXE as 104,659,456 bytes, compressed to 35,916,343 bytes. Do not mistake that
index for an installed executable, or silently package the GUI editor instead.
Obtain only the needed official matching template payload if still absent, verify
its archive CRC and record a SHA-256/origin receipt. The missing payloads were then acquired at 23:22 UTC using only the official
GitHub release and bounded ZIP ranges. See
`docs/verification/release/20261021-2322-windows-template-acquisition.json` for
source URL, archive metadata digest, actual per-entry CRC/SHA-256 and result hashes.
Only entries were downloaded, so the full-archive metadata digest is recorded but
not claimed as verified. Both templates now exist beside the Android templates.
No new download is performed by staging. Keep official Godot MIT and third-party copyright notices alongside
any bundled engine.

After the explicit final freeze, with matching templates and an isolated export
HOME already configured to the existing authorized Android test-key path (so an
editor initialization cannot create a replacement key), export the real Windows
executable from the private frozen build tree:

```
godot --headless --path /absolute/new-release/build-project \
  --export-release "Windows Desktop" /absolute/new-release/exports/PoolCore-Source-Water.exe
```

Require exit 0, `binary_format/embed_pck=false`, `codesign/enable=false`, and
`application/modify_resources=false`. Verify frozen inputs again. Audit the PCK
produced by THIS export; do not reuse a historical pack. Stage both files:

```
python3 -B tools/release/stage_release.py windows \
  --source /absolute/new-release/build-project \
  --pck /absolute/new-release/exports/PoolCore-Source-Water.pck \
  --windows-exe /absolute/new-release/exports/PoolCore-Source-Water.exe \
  --windows-template /absolute/templates/4.6.3.stable/windows_release_x86_64.exe \
  --output /absolute/new-release/PoolCore-Windows-SelfContained \
  --zip /absolute/new-release/PoolCore-Windows-SelfContained.zip
```

The EXE must be byte-identical to the supplied official release template. PE32+
x86_64 main-image checks reject an ARM64 binary, DLL or wrongly selected wrapper;
exported resource modifications or appended PCK bytes fail closed. The known official 4.6.3 release template SHA-256 is pinned to the retained
acquisition receipt; origin is not inferred merely from PE headers. No Windows execution is claimed by these static checks.

Run the actual PCK CPU/native/fallback/cache gates and the owner's separate
native graphical smoke. The same package supports the user's existing engine:
drag that main EXE onto `Launch-PoolCore.cmd`; its explicit path takes priority
over the bundled EXE. If a smaller alternative is separately needed, a PCK-only
staging directory can be made from the same PCK by omitting the two EXE arguments,
but do not upload duplicate full PCKs in both primary delivery groups.
Use `make_binary_parts.py` for the larger
self-contained ZIP, with label `PoolCore-Windows-SelfContained-YYYYMMDD-HHMM`.
The engine alone exceeds one attachment, so expect multiple lossless parts. Do
not reduce assets, bake precision, textures, water quality or editable sources
to meet an attachment limit. The existing reconstruction scripts verify every
part and final ZIP before use; final part count is measured after packaging.

After final source staging, bind the authored-source reproduction proof to its
actual package manifest (write the report OUTSIDE the immutable staged tree):

```
python3 -B /absolute/release/PoolCore-Source/tests/formal_source_packaging_contract.py \
  --root /absolute/release/PoolCore-Source \
  --report /absolute/release/formal-source-package-audit.json
```

This checks all six editable Blender files and six matching GLBs, the generator's
complete input closure, the model manifest, clean generator/source round-trip
proof, and hashes in `PACKAGE-MANIFEST.json`. It does not invoke Blender or change
geometry. Historical pre-fitting comparison tests intentionally require the
separately retained old checkpoint; the current clean-rebuild route is standalone.

The final actual-PCK native/fallback probe also reads Linux process mappings.
It requires the mapped helper path and SHA-256 to match the independent probe
host's external library, not a development-project library. Its separate
missing-helper process must show no source-water native mapping and must publish
the same valid data via the production GDScript parser. A source-only rehearsal
with Chinese/spaces/! paths is recorded in
`docs/verification/release/20261022-0004-native-library-mapping.json`; the final
PCK must pass independently. Linux mapping proof is not Windows DLL execution.

## Incremental development recovery

`make_incremental_recovery.py` compares two independently verified source stages,
records the exact six-archive base Library IDs/hashes and both complete file
inventories, and packages changed/new files plus every current prepared-terrain
container. The explicit deletion delta is non-destructive: `Restore-Recovery.py`
builds a NEW target tree from a verified base plus delta. It never deletes or
modifies the base. Extract all matching ordinary delta ZIPs together before
running restoration; they are not a standalone project and not binary volumes.

Restoration validates the pinned delta manifest, every required base/payload
SHA-256 and the exact resulting file set. Missing parts, wrong bases and tampered
payloads fail closed. Package integrity is still not graphical acceptance.
On Unix, invoke retained shell test wrappers with `bash path/to/test.sh` if the
ZIP extractor did not preserve executable permissions. Windows source opening
uses `Prepare-Editor.cmd` and does not depend on Unix executable mode bits.
