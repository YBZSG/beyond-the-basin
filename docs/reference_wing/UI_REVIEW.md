# Reference Wing UI and persistence review

Reviewed 2026-10-24 against base `351fcd6f8f2bb5fe21851482e2526dfa262ef406` plus the current Reference Wing changes.

## Result

**PASS: 171 checks in the primary process and 5 fresh-process reload checks.** Engine: official Godot 4.6.3, headless dummy renderer. No engine errors or warnings. Machine-readable results and exact reviewed source hashes are in `tests/reference_wing/ui_contract_report.json`.

The sole initial defect was missing `reference_resolution` in the lounge's two camera records. Its generator and JSON contract explicitly say **1000 × 680**, matching the saved source. A later reference-photo audit corrected the stair camera from portrait to square, the bath from square to 4:5, and the cyan corridor to 700:688; previous A/B frames remain unchanged. Final camera metadata is checked against the table below.

## Reproduce safely

From the project root:

```sh
python tests/reference_wing/ui_run_contract.py --report tests/reference_wing/ui_contract_report.json
```

The runner copies only necessary scripts, the camera shader source and geometry JSON into a temporary `/tmp` project. HOME, XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME all point to newly created writable temporary directories. It launches no editor/import, source-water solver, native extension, main scene or GPU renderer, and never arms an operating-system restart. It removes the launcher contract from the isolated environment. A second Godot process uses the same temporary user directory to verify genuine disk reload, then the temporary directory is removed.

The runner extracts exact current `main.gd` methods into an inert host rather than independently rewriting the settings logic. Full main-game creation is intentionally excluded. The report lists every extracted method and fingerprints the actual sources. World regeneration and preview-switch hooks are recording doubles. The successful restart UI test uses a recording request double, but executes the real host save callback, real `world_restart.save_config_atomic`, and the exact production desktop settings-save method. Pure `build_plan` validation and refusal without a launcher contract execute directly against the production restart script.

## Verified behavior

- Existing four world indices remain 0–3; Reference Wing is appended at 4. All five actual selection callbacks preserve the entered seed. Busy switching and invalid seed input are rejected; leaving the experimental mainhall preview can target Reference Wing.
- Both additions default off when settings are absent or predate this feature. Real ordinary and atomic disk saves reload all reference values, wrap directions, bound numerical values and discard unsupported reference keys.
- Water/wind/solver overrides and unrelated config sections survive reference changes. The separately owned `desktop_quality.cfg` remains byte-identical during main settings edits. The actual restart UI save callback retains RT, NR including their real control keys, DLSS, frame generation, AA, render scale, water and shadow preferences in the isolated file. This verifies preference ownership, not native RT/NR execution.
- Reference filter and optical ripples are independent. Clean plus reference-off hides the entire camera pass; enabled reference filter with all strengths zero also hides it. Disabling the reference filter restores whichever legacy Clean/CCD/VHS/Cold mode was selected. Wave-only changes cannot turn on the camera pass. Legacy CCD remains session-only while reference opt-ins persist.
- All eight reference controls bind to their correct keys. Both switches, six slider bounds and their numeric labels work. Wind reset does not change reference settings. Keyboard arrow input changes the actual setting; focusability and Tab order match the visual sequence.
- Actual full water-panel nodes were constructed with the host's dimensions, margins, theme and font fallbacks. At 1024×768, 1280×720, 1920×1080 and 3440×1440, the panel stays inside the viewport and all reference controls are initially visible, horizontally contained and have a 249-pixel slider width. These are node-layout checks, not rendered typography or visual approval.
- Desktop keyboard-focus scrolling is now verified at all four viewport sizes: focusing the final legacy OptionButton scrolls it fully into view; actual Tab moves to the visible Back button; reverse Tab returns to the visible legacy control; focusing the first reference switch scrolls back toward the top (vertical offset 1485 → 135). Reference/water dictionaries and on-disk settings remain unchanged by this navigation. The production assignment is explicitly desktop-guarded.
- The desktop post-process layer remains below the default HUD/menu layer and ignores mouse input. Its visibility and material parameters were tested without executing the GPU shader.
- Exact launcher argument plans remove old world-selection flags including `--reference-wing`, retain unrelated flags/GPU choice/separators, pin the actual renderer/driver if omitted, and reject unsupported headless/editor/script/import invocations and mismatched launch identities. The queued-autosave guard cannot overwrite a committed restart selection.
- All five fixed-camera positions/targets include the correct room offset and use finite explicit vertical FOV values. Each camera now supplies its authored reference resolution.

## Fixed-camera capture guidance for the user's target engine

These are **instructions for the user's own target-engine checks, not captures performed in this review**. Keep the existing verified NVIDIA/custom-4.8 launcher and renderer settings. Add the relevant user arguments after its existing `--` separator; do not substitute the cloud's official 4.6.3 engine for visual acceptance.

Use exactly one starting-world selection: do not retain `--original-world`, `--legacy-world`, other world-selection flags or `--pc-mainhall-lightmap-preview` in the same capture invocation. The explicit original/preview overrides take precedence over Reference Wing.

Common diagnostic arguments:

```text
--reference-wing --qa --qa-user-water --qa-wait-ready --qa-frames=120
```

Use one room and its matching output aspect:

| Room | Additional user arguments | Vertical FOV |
| --- | --- | ---: |
| Stair gallery | `--qa-room=stair_gallery --qa-capture-resolution=750x750` | 78.578814° |
| Colonnade | `--qa-room=colonnade --qa-capture-resolution=700x700` | 76.094090° |
| Cyan corridor | `--qa-room=cyan_corridor --qa-capture-resolution=700x688` | 77.609411° |
| Octagonal bath | `--qa-room=octagonal_bath --qa-capture-resolution=700x875` | 102.680383° |
| Ball lounge | `--qa-room=ball_lounge --qa-capture-resolution=1000x680` | 59.305920° |

The lounge uses the authored1000×680 approximation to the supplied400×270 photo, not an exact aspect match. The other camera corrections preserve their fixed poses and intended angular framing; they do not change the normal gameplay viewport.

Supply a distinct writable absolute `--qa-out=...png` path per capture. The QA run selects the authored position, target and vertical FOV, but **does not automatically adopt the stored reference aspect**. Omitting `--qa-capture-resolution` leaves the normal viewport shape, so a default 1280×720 screenshot cannot be called a matching reference composition. No silent production aspect change is proposed.

For an off/on comparison, first set reference filter and reference ripples independently through the water panel and use the same saved wind, material, graphics and camera state. `--qa-user-water` retains saved water overrides; without it, the existing QA startup intentionally clears those overrides for that session. The existing QA path also forces water visible and GI requested unless `--qa-no-gi` is supplied, so log those facts when comparing with gameplay. Avoid legacy `--qa-traverse` and other camera-changing QA modes for fixed-camera comparisons. These diagnostic runs exit after capture and are not normal play sessions.

## Limits and existing observations

- No target image quality, shader execution/compilation on NVIDIA, custom-engine RT/NR behavior, performance, display-color correctness or actual process relaunch is established here. The user owns those native visual checks. The cloud graphics access denial was not retried or bypassed.
- The previously observed desktop focus-follow limitation is resolved by the integration owner’s desktop-only `follow_focus` change. The review tests the actual production panel and native focus signals, including injected forward/reverse Tab actions, rather than calling a scroll-to-control helper in the test. Android was not launched, modified or validated by this review.
- Layout below the tested desktop sizes, font rasterization on Windows, controller navigation and visual contrast need native review if required. The authored-world physics/geometry and water solver are covered by separate reviews, not this UI fixture.
- Review-owned files are only `tests/reference_wing/ui_*` and this document. No Android, PC-access, production source, shared import or push operation was performed.
