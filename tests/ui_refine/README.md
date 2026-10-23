# PC menu regression checks

This integration adapts the supplied Water Motion presentation to the current PC renderer. It preserves existing controls and handlers, including DLSS, frame generation and experimental path tracing. The Light/Original splash settings and their UI are intentionally excluded.

Use the matching Godot editor and an isolated project copy. On Windows, set APPDATA to a fresh directory whose name includes poolcore-ui-contract-. On Linux use an isolated XDG_DATA_HOME with the same marker. Never point the tests at a normal player profile.

- presentation_contract.gd: run headless; checks the actual production menus, node identities, 720p/1080p layout, 150% scaling, focus/back navigation, guarded callbacks, settings persistence and preservation of unknown keys. In Godot 4.8, hidden PopupMenu search fields are excluded from visible page bounds checks.
- mobile_bypass_contract.gd: run headless with -- --mobile-preview; checks that the desktop presentation does not install.
- ui_preview.gd: graphical --stage=after --output=<isolated directory> captures actual menus. A headless geometry-only run requires --layout-only. This fixture does not load the game world.

Validate both the JSON result and engine log. A zero exit code alone does not prove that every GDScript test ran; missing dependencies can abort individual test functions without stopping the whole SceneTree.

Local results for 0.6.9 are recorded in docs/pc-water-motion-integration-20261024.md and output/motion-integration/. Upstream reports describe their own 4.6.3 fixture and are not current Windows or whole-game acceptance.
