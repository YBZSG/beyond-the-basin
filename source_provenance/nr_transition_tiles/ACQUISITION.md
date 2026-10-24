# NR / room transition / tile source update

User supplied `PoolCore-NR-Transition-Tiles-20261024 (1).zip` on 2026-10-25.

- Archive SHA256: `1ac1cf67e373a3375cf0cd2c0b38d3f4fc77c11b1a9f7dbca0233b67b26b939a`
- Exact upstream baseline: `4876a68adab536d0d41dd147e93566a4f534ecf8`.
- Applied the 32 manifest payload files after matching their hashes and the clean baseline (Windows newline differences normalized for comparison).
- `provider_evidence/` contains the package author's results, not new local verification.
- No tests, engine compilation, GPU runs or packaged executable updates were performed during this intake, as requested by the user.
- Room-shell staging remains a test-only opt-in patch; production `pool_world.gd` was not replaced.
- Adjustable/multilayer NR requires rebuilding the custom engine. Existing executables retain the previous single-layer implementation.
