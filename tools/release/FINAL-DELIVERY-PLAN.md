# Final delivery groups

This is a plan, not an export or acceptance record. Freeze authorization and
current native visual decisions remain mandatory before final packaging.
The 01:02 UTC decision keeps all baked GI quarantined after both full-game bake
attempts were externally SIGKILLed without a candidate image. No production
bake assets or installer are allowed in this release.

## Three primary groups

1. **PC playable**: `PoolCore-Windows-Play.zip`, containing
   `PoolCore-Source-Water.exe`, exactly one `PoolCore-Source-Water.pck`,
   `Launch-PoolCore.cmd`, the external Windows DLL at its declared relative path,
   native C/build sources, licenses, diagnostics and package manifest.
   Default launch uses the bundled engine. Dragging an explicitly chosen official
   Godot 4.6/4.7 main EXE onto the launcher instead uses that engine. No second
   full PCK-only upload is needed. Exact 4.6.3 is the tested baseline; 4.7 is
   permitted with an unverified-version warning.
2. **Android**: a freshly exported
   `PoolCore-Source-Water-Android-Test.apk`, never the retained baseline APK.
   It includes the current ARM64 helper and is pinned to the approved retained
   debug certificate's public SHA-256. The key stays outside all packages.
3. **Complete editable sources**: `PoolCore-Source-Final-<freeze>-NN-<group>.zip`.
   All ordinary ZIPs are required, extracted into the same folder. Includes the
   six Blender files, generators, models, raw scripts/shaders, runtime caches,
   native implementation/build/license and regression harnesses. No host imports,
   key, SDK, toolchain or executable engine is included.

Optional lab/evidence is clearly separate, not a fourth playable version. Preserve
lab scenes and tiny validated fixtures, with documented regeneration for omitted
rejected large bakes. `make_lab_archives.py` supports ordinary bounded lab ZIPs
that restore directly into the editable source root, without binary rebuilding.

## Attachment transport

Oversized PC ZIP and APK are losslessly split using `make_binary_parts.py`, with
14,000,000-byte raw parts and each ordinary transport ZIP below 16,000,000 bytes.
Users extract every matching transport ZIP, double-click the included CMD, then
extract the reconstructed PC ZIP or decide whether to install the reconstructed
APK. Reconstruction never launches or installs anything. The inline PowerShell
uses `-NoProfile -Command`, environment-only base-path data, exact SHA-256 checks,
and refuses destructive overwrite. It never bypasses execution policy. A Python
alternative is retained. Actual Windows execution is not implied by static review.

Do not present editable source ZIPs as binary reconstruction parts. Their complete
union directly restores the source tree, including every prepared terrain file.
Attach only the current completed parts; historical checkpoints remain separate
recovery records rather than a mandatory dependency of the final source delivery.

## Measured planning estimate at 00:50 UTC, before export

Decimal MB, rounded. These are not final artifact sizes or acceptance claims.

| Item | Estimate | Expected transport |
|---|---:|---|
| Current PCK, uncompressed Godot pack | 121 MB | Inside the single PC ZIP |
| Self-contained Windows ZIP | 87–92 MB | About 7 transport ZIPs |
| New ARM64 test APK | 79–85 MB | About 6–7 transport ZIPs |
| Complete clean editable source | 59 MB compressed | About 6 ordinary ZIPs |
| Optional lab as currently retained | 20.5 MB compressed | About 2 ordinary ZIPs |

The official Windows EXE is 104,659,456 bytes and its official ZIP entry is
35,916,343 bytes. Runtime import/payload selection was measured read-only without
export or snapshot. Existing APK non-asset compressed content is about 27.7 MB;
platform-specific imports and signing alignment can change the new total.
For historical size planning only, the mainhall candidate texture would add
about 18.9 MB raw or 5.3 MB compressed plus scene/data overhead. The later final
decision excludes it from production, so that addition is not planned.
Exact files, sizes, hashes and part counts will be measured
after the explicit final freeze and actual successful exports. No quality is
reduced to fit an attachment limit.

## Final acceptance and disclosures

- Require actual exporter exit 0 and unchanged frozen inputs, not file existence.
- Actual PCK must load the helper from its isolated package host, verified by
  process mapping and SHA-256. Separately omit the helper and prove fallback starts.
- Check PE imports, Android ELF dependencies/16-KiB alignment, raw script/resource
  dependency closure, exact terrain identities, APK signature and package policy.
- Retain parent-owned serial native graphical proof separately. Linux headless
  and cloud llvmpipe are not Windows GPU or physical-phone execution evidence.
- Reconcile historical CREDITS wording only after new EXE/APK exports succeed.
  Do not mutate the private frozen build or its manifest to hide source changes.
