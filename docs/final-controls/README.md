# Current PC controls and local-save boundary

Status: PASS, executed on 2026-10-22 at 22:19 UTC after the parent granted the serial engine slot. All five runtime processes exited normally with code 0; the slot was explicitly released at 22:19:41 UTC. No production fix was needed.

The source-only audit passes all 17 current wiring checks. The new runtime suite passes 135 checks across three fresh processes (64 write, 49 reload/restore, 22 second reload). The existing menu-readiness regression passes all 8 checks and the release preflight passes. All production source and asset hashes remained unchanged. See `summary.json`, `latest-execution.json` and `regressions-receipt.json`.

## Gap targeted

Existing suites already deeply exercise device mechanics and weak source-water inputs (`tests/facility_devices/runtime_contract.gd`), notebook validation/atomic saves/corruption recovery (`tests/exploration_notes_native.gd`), spawn regeneration (`tests/source_spawn_selection_contract.gd`), independent graphics controls (`tests/desktop_quality_contract.gd`), and menu readiness (`tests/water_feel_menu_readiness.gd`). This suite does not copy their exhaustive matrices.

The new `settings_integration.gd` instead tests the cross-feature boundary:

- The unchanged Main interface is constructed and its real CheckButton signals invoke current production callbacks. Cloth finish, quiet valves, depth response and avatar visibility are changed together; spawn mode and quality are saved with them.
- Actual metric-cloth GLB and finish helper are loaded. Both cloth material uniforms must track the control. Avatar visibility and process mode must track the control.
- Actual desktop quality panel chooses presets and independent resolution/water overrides. Main's same-tier apply must preserve those overrides.
- Three separate engine processes share only a new isolated save directory. First saves all four toggles off / expanded / Medium with custom overrides; second verifies disk reload then saves toggles on / formal / Ultra with different overrides; third verifies the second reload.
- Main's actual quiet-valve handler attaches both authored devices from the delivered GLBs. A genuine camera/physics LOS opens the side valve. Main off must remove hints, interaction dispatch, visibility and collision; genuine ray queries verify disabled collision disappears. Main on must restore two stations, old bodies must retire, and the new actual handle must retain its open quarter-turn.
- Main's physics callback observes real PoolWorld coordinate/catalogue methods against controlled ready-room nodes and actual player positions. It must not count preloaded rooms or an announced destination before the player's position moves. Menu open must commit the exact four seed/mode records; both fresh processes must recover exactly those coordinates.
- Current Main menu reopen refreshes readiness immediately without awaiting a frame. A world switch must still block resume.

## Safety and limits

The runner requires `--serial-slot-granted`, refuses a concurrent known Godot/Blender process, and creates new HOME plus XDG data/config/cache directories for every invocation. Existing user settings and notes are never read, moved, backed up, or overwritten. Execution logs and receipts remain in a timestamped run directory under this folder. Production sources and delivered assets are hashed before and after each process.

This is a CPU/Jolt controls/state integration test. Main's startup is suppressed; the fixture creates a lightweight world, a controlled player/water interface, and the actual UI/assets explicitly. It does not claim full-game startup, world regeneration, movement, source-water/fluid behavior, native GI, screenshots, render quality, target-PC FPS, Windows hardware acceptance or Android work. The existing deeper fixtures remain relevant for those separate contracts. Valve selection is retained within a running world and through off/on reattachment; it is not claimed to persist across a game restart because production does not serialize mechanical valve state.

## Reproduction

Source-only preparation:

    PYTHONDONTWRITEBYTECODE=1 python tests/final_controls/static_contract.py

Only after the parent explicitly grants the serial engine slot:

    PYTHONDONTWRITEBYTECODE=1 python tests/final_controls/run.py --serial-slot-granted --parse-only
    PYTHONDONTWRITEBYTECODE=1 python tests/final_controls/run.py --serial-slot-granted

No production files or existing tests are modified by this work.

## Executed evidence

- New three-process run: `run-20261022T221851-769352Z/execution.json`; each phase has a detailed receipt and stdout/stderr. The suite took 3.535 seconds in total measured child elapsed time, not a game-performance measurement.
- Initial syntax-only check: `run-20261022T221844-713480Z/execution.json`.
- Existing regressions: `regressions-wkzqc087/receipt.json`, including exact commands and separate logs.
- No script errors, runtime errors, timeouts or failed assertions occurred. Each new phase emitted the expected headless Compatibility warning that TAA requires Forward+. Saved graphics preferences remain tested, but the renderer is intentionally not certified.
- The first source audit used a fixture expectation that startup called the avatar setter; inspection showed current Main correctly applies the saved visibility/process mode directly. Only the new audit was corrected to inspect those actual assignments before any engine run. This was not a production defect.

To reproduce the two requested existing regressions after a new serial-slot grant:

    PYTHONDONTWRITEBYTECODE=1 python tests/final_controls/run_regressions.py --serial-slot-granted
