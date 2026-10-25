# Export quarantine and source preflight — 2026-10-25

Windows now excludes `scenes/lighting_lab/*` and `assets/lighting/*`, matching the existing broad laboratory quarantine. Android already excluded them. No source asset was deleted and no bake was promoted into normal gameplay.

The optional mainhall preview now checks all three scene/data/HDR resources before accepting its launch flag, enabling its UI, or loading a candidate. An unavailable preview request returns before leaving campaign mode. Normal lighting stays selected when laboratory resources are absent.

The release audit exempts exactly three constant declarations in this one reviewed consumer, pinned to its SHA-256; every other literal dependency still receives normal validation. Changed consumer bytes (including removed guards or added preload), these paths in another consumer, and a missing required mainhall model all fail closed. Any consumer edit requires reviewing and renewing the pinned contract, not merely updating a hash to silence failure.

The next source-preflight failure exposed an older stale default in `natural_pool_avatar.gd`: `assets/character_refinement/model_contract.json` does not exist. Its default now uses the existing accepted `natural_hand_finish/model_contract.json`, exactly matching the character-selection override. The actual selected model and original fallback behavior remain unchanged.

## Observed verification

Evidence is retained in `release-evidence/`.

- `python3 tools/release/preflight_release.py --source .`: **PASS**. This is a read-only source inventory, not an exported-package audit.
- `python3 -m unittest discover -s tools/release -p test_release_tools.py`: **67 passed**, including optional-preview positive/negative guards and accepted-contract default.
- `python3 -m unittest discover -s tools/release -p test_pc_expansion_release.py`: **14 passed**.
- Broad `test*.py` discovery: **not fully passing**. Its earlier run executed 80 tests successfully but one module could not import: tracked `test_validate_pc_expansion_pack.py` depends on absent `validate_pc_expansion_pack.py`. No implementation was found in this workspace. Parent verification also received HTTP 404 when fetching it from `YBZSG/beyond-the-basin` at pinned baseline `351fcd6f8f2bb5fe21851482e2526dfa262ef406`; no authoritative restoration was available. The test was not deleted, skipped, or replaced with a fabricated validator.
- Official Godot 4.6.3 Linux headless, isolated minimal project containing only the preview consumer and `tests/release/optional_preview_absent.gd`: **PASS**. Missing assets reject the flag and preserve original architecture and 254 collision children. This is an actual missing-resource CPU test, not a GPU bake test.
- Handmade motion regressions: state **24**, rig **457**, real controller **7** checks passed; missing-animation-library fallback passed. The fallback test deliberately emits its missing-library warning.
- Accepted-character policy: **8 checks passed**, including original-model rollback and accepted natural contract.
- `git diff --check`: passed.

The first isolated Godot launch lacked writable host user-data/cache paths and crashed before running tests. It was rerun successfully with HOME and XDG paths in `/tmp`; the successful log is retained. No permissions were escalated.

## Remaining release boundaries

This source checkpoint is **not an export-certified Windows release**. A matching custom Windows NR runtime/export template is unavailable; official 4.6.3 templates are not a substitute for this branch. No actual Windows PCK/EXE/APK export or package audit was performed here. The missing expansion-pack validator must be restored from its authoritative source before claiming full release-tool discovery success.

NR/RT/water, campaign progression and handmade actions were preserved. Target NVIDIA GPU visuals, motion/contact acceptance, water interaction and performance remain user-owned target-runtime acceptance work. CPU tests and source preflight do not establish them.
