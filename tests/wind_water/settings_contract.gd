extends SceneTree
## CPU-only integration: actual main callbacks, ConfigFile storage, and UI layout.
const Settings = preload("res://scripts/water/source_port/source_water_settings.gd")
const DesktopQuality = preload("res://scripts/rendering/desktop_quality_panel.gd")

class Host extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class WaterSpy extends Node3D:
	var writes: Array = []
	var quality := "High"
	var planar: Node
	func set_caustics(_enabled: bool) -> void: pass
	func set_tuning(key: String, value: Variant) -> void: writes.append([key, value])
	func set_quality(value: String) -> void: quality = value

var errors: Array[String] = []
var checks := 0
func _initialize() -> void: _run.call_deferred()
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: errors.append(label)
func _check_defaults(values: Dictionary, label: String) -> void:
	for key: String in Settings.WIND_KEYS:
		_check(values.get(key) == Settings.DEFAULT[key], label + ": " + key)
func _load_saved() -> ConfigFile:
	var config := ConfigFile.new()
	_check(config.load("user://settings.cfg") == OK, "Actual settings.cfg loads")
	return config
func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("This contract is CPU-only; no GPU launch is allowed."); quit(2); return
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/poolcore-wind-settings-") or not OS.get_user_data_dir().begins_with(isolated):
		push_error("Run with settings_run.py to isolate all saved preferences."); quit(2); return
	_test_validation()
	var host := Host.new()
	host.set_process(false)
	root.add_child(host)
	_check_defaults(host._water_settings, "First-launch defaults")
	var config := ConfigFile.new()
	config.set_value("game", "seed", 123456)
	config.set_value("game", "spawn_mode", "expanded")
	config.set_value("game", "depth_wading_response", false)
	config.set_value("display", "quality", "Ultra")
	config.set_value("display", "avatar_fabric", false)
	config.set_value("display", "gi", false)
	config.set_value("water", "settings", {"micro_strength": 0.73, "foam": false, "impact": 1.4, "futureWaterOption": {"kept": true}})
	_check(config.save("user://settings.cfg") == OK, "Old-config fixture saved")
	host._load_settings()
	_check_defaults(host._water_settings, "Old config migrates missing wind keys")
	_check(host._quality == "Ultra" and host._spawn_mode == "expanded" and host.world_seed == 123456, "Load preserves quality, world, seed")
	_check(not host._depth_wading_enabled and not host._avatar_fabric_enabled and not host._gi_on, "Load preserves wading, fabric, GI choices")
	var spy := WaterSpy.new()
	host.add_child(spy); host.water = spy
	var ui := Control.new()
	ui.size = Vector2(1280, 720)
	host.add_child(ui)
	host._menu = PanelContainer.new(); ui.add_child(host._menu)
	host._build_water_panel(ui)
	host._advanced.show()
	await process_frame
	await process_frame
	_test_ui(host, spy)
	# A saved wind change must not replace independent desktop graphics prefs.
	var desktop_sentinel := ConfigFile.new()
	desktop_sentinel.set_value("graphics", "shadow_size", 8192)
	desktop_sentinel.set_value("graphics", "water", "Medium")
	_check(desktop_sentinel.save("user://desktop_quality.cfg") == OK, "Desktop sentinel saved")
	var sentinel_hash := FileAccess.get_sha256("user://desktop_quality.cfg")
	var before_quality: Dictionary = host._water_settings.duplicate(true)
	for tier: String in ["Low", "Medium", "High", "Ultra"]:
		host._apply_quality(tier)
		_check(host._water_settings == before_quality and spy.quality == tier, "Quality switch retains exact wind settings: " + tier)
	host._save_settings()
	_check(FileAccess.get_sha256("user://desktop_quality.cfg") == sentinel_hash, "Main save never touches desktop shadow/water quality config")
	var reloaded := Host.new()
	reloaded._load_settings()
	_check(reloaded._water_settings == host._water_settings, "Complete water override dictionary survives actual save/reload")
	_check(not reloaded._depth_wading_enabled and not reloaded._avatar_fabric_enabled and not reloaded._gi_on, "Wind autosave preserves interaction/material/GI choices")
	_check(reloaded._water_settings.futureWaterOption == {"kept": true} and reloaded._water_settings.micro_strength == 0.73 and not reloaded._water_settings.foam, "Unrelated and legacy water settings survive")
	# Exercise the installed-desktop branch with the actual graphics owner. It
	# writes only its isolated test config and never constructs a world or GPU.
	var desktop := DesktopQuality.new()
	desktop.name = "DesktopQuality"
	host.add_child(desktop)
	desktop.main = host
	desktop.settings_path = "user://wind-test-desktop.cfg"
	desktop.set_process(false)
	for tier: String in ["Low", "Medium", "High", "Ultra"]:
		host._apply_quality(tier)
		_check(host._water_settings == before_quality and spy.quality == tier, "Actual desktop preset retains wind settings: " + tier)
	desktop.settings.shadow_size = 2048
	desktop.settings.water = "Low"
	host._apply_quality("Ultra")
	_check(host._water_settings == before_quality and desktop.settings.shadow_size == 2048 and desktop.settings.water == "Low", "Same-tier reapply preserves custom shadow, water tier and wind overrides")
	_check(FileAccess.get_sha256("user://desktop_quality.cfg") == sentinel_hash, "Desktop branch test did not touch existing user graphics file")
	desktop.free()
	host._gi_on = false
	host._caustics_on = true
	var reset_button: Button = host._advanced.find_child("ResetWind", true, false)
	spy.writes.clear()
	reset_button.pressed.emit()
	_check_defaults(host._water_settings, "Wind-only reset defaults")
	_check(spy.writes.size() == 4, "Wind reset writes exactly four live parameters")
	for entry: Array in spy.writes: _check(entry[0] in Settings.WIND_KEYS, "Reset does not write unrelated runtime setting")
	_check(host._water_settings.impact == 1.4 and host._water_settings.micro_strength == 0.73 and not host._water_settings.foam, "Reset leaves interaction and material-related water overrides unchanged")
	for key: String in Settings.WIND_KEYS:
		var control: Control = host._wind_controls[key]
		_check(control.button_pressed == Settings.DEFAULT[key] if control is CheckButton else is_equal_approx(control.value, Settings.DEFAULT[key]), "Reset updates actual UI control: " + key)
		if control is HSlider:
			_check(control.get_parent().get_node("NumericValue").text == host._water_value_text(Settings.DEFAULT[key], control.step), "Reset updates number text: " + key)
	reloaded._load_settings()
	_check_defaults(reloaded._water_settings, "Reset persists after reload")
	# World-retirement clicks retain intent without calling a retired water instance.
	host._retiring_world = true
	spy.writes.clear()
	host._wind_controls.windStrength.value = 0.66
	_check(spy.writes.is_empty() and is_equal_approx(host._water_settings.windStrength, 0.66), "During world retirement UI saves intent without stale runtime calls")
	reloaded._load_settings()
	_check(is_equal_approx(reloaded._water_settings.windStrength, 0.66), "Retirement-safe change persists for replacement world")
	# Confirm bad serialized values cannot reach newly constructed runtime tuning.
	config = _load_saved()
	config.set_value("water", "settings", {"windWaves": "false", "windStrength": NAN, "windDirection": -700, "windDensity": 99.0, "impact": 1.6})
	_check(config.save("user://settings.cfg") == OK, "Invalid saved fixture writes")
	reloaded._load_settings()
	_check(reloaded._water_settings.windWaves and is_equal_approx(reloaded._water_settings.windStrength, 0.18) and reloaded._water_settings.windDirection == 0.0 and reloaded._water_settings.windDensity == 2.0, "Saved invalid values sanitize before use")
	_check(reloaded._water_settings.impact == 1.6, "Sanitization leaves unrelated override untouched")
	config.set_value("water", "settings", ["invalid", "container"])
	_check(config.save("user://settings.cfg") == OK, "Invalid settings container fixture writes")
	reloaded._load_settings()
	_check_defaults(reloaded._water_settings, "Non-dictionary saved value is safely migrated")
	reloaded.free(); host.free()
	var report := {"passed": errors.is_empty(), "checks": checks, "errors": errors, "renderer": DisplayServer.get_name(), "engine_version": Engine.get_version_info().string, "gpu_run": false, "scope": "Actual settings, callbacks, save/reload, reset, quality retention and headless UI geometry; not pixel-level or wind shader visual acceptance"}
	print("WIND_SETTINGS_CONTRACT ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)

func _test_validation() -> void:
	_check_defaults(Settings.sanitize_wind_settings({}), "Empty config defaults")
	for invalid: Variant in [null, "not a dictionary", [], 42]:
		_check_defaults(Settings.sanitize_wind_settings(invalid), "Invalid container defaults")
	var original := {"windWaves": false, "windStrength": 0.72, "windDirection": 275.0, "windDensity": 1.65, "impact": 2.2, "nested": {"value": 3}}
	var snapshot: Dictionary = original.duplicate(true)
	var clean := Settings.sanitize_wind_settings(original)
	_check(clean == original and original == snapshot, "Valid settings and input dictionary stay unchanged")
	clean.nested.value = 9
	_check(original.nested.value == 3, "Sanitized dictionary does not alias nested source data")
	for invalid: Variant in [NAN, INF, -INF, "0.8", true, null, [], {}]:
		var invalid_row := {"windStrength": invalid, "windDirection": invalid, "windDensity": invalid, "windWaves": invalid}
		var validated := Settings.sanitize_wind_settings(invalid_row)
		_check_defaults(validated, "Invalid scalar defaults: " + str(invalid))
	var clamped := Settings.sanitize_wind_settings({"windStrength": 5, "windDirection": 999, "windDensity": -8, "windWaves": false})
	_check(clamped.windStrength == 1.0 and clamped.windDirection == 360.0 and clamped.windDensity == 0.5 and not clamped.windWaves, "Finite scalars clamp and strict boolean false survives")
	clamped = Settings.sanitize_wind_settings({"windStrength": -2.0, "windDirection": -1.0, "windDensity": 9.0})
	_check(clamped.windStrength == 0.0 and clamped.windDirection == 0.0 and clamped.windDensity == 2.0, "Opposite range boundaries clamp")
	var found := {}
	for row: Dictionary in Settings.SLIDERS:
		_check(not found.has(row.key), "Each slider key occurs exactly once: " + row.key)
		found[row.key] = true
		if row.key in Settings.WIND_KEYS:
			_check(Settings.DEFAULT[row.key] == row.defval and row.min <= row.defval and row.defval <= row.max, "Wind slider default matches runtime schema: " + row.key)
	_check(Settings.LAYERS.has("windWaves"), "Wind toggle is part of source layer schema")

func _test_ui(host: Node, spy: Node) -> void:
	_check(host._wind_controls.size() == 4, "Wind group contains toggle and exactly three sliders")
	var scroll: ScrollContainer = host._advanced.get_child(0)
	var viewport_rect := scroll.get_global_rect()
	for key: String in Settings.WIND_KEYS:
		var control: Control = host._wind_controls[key]
		_check(control.is_visible_in_tree() and viewport_rect.encloses(control.get_global_rect()), "Wind control visible at top without scrolling: " + key)
		_check(not control.tooltip_text.is_empty(), "Chinese tooltip exists: " + key)
		if control is HSlider: _check(control.size.x >= 120.0, "Slider has useful interactive width: " + key)
	var note: Label = host._advanced.find_child("WindOpticsNote", true, false)
	_check(note.text.contains("光学近似") and note.text.contains("涉水"), "Visible note distinguishes visual wind from physics and retained interactions")
	host._wind_controls.windStrength.value = 0.72
	host._wind_controls.windDirection.value = 275
	host._wind_controls.windDensity.value = 1.65
	host._wind_controls.windWaves.button_pressed = false
	_check(spy.writes.size() == 4, "Each UI change invokes live tuning exactly once")
	_check(is_equal_approx(host._water_settings.windStrength, 0.72) and host._water_settings.windDirection == 275 and is_equal_approx(host._water_settings.windDensity, 1.65) and not host._water_settings.windWaves, "Slider/toggle callbacks store requested values")
	var saved: Dictionary = _load_saved().get_value("water", "settings")
	_check(saved == host._water_settings, "Every UI change autosaves current requested values")
	_check(host._wind_controls.windStrength.get_parent().get_node("NumericValue").text == "0.72", "Live slider number tracks value")
	# Turning off retains values; editing while off can prepare a future enabled state.
	host._wind_controls.windWaves.button_pressed = true
	host._wind_controls.windWaves.button_pressed = false
	_check(host._water_settings.windDirection == 275 and is_equal_approx(host._water_settings.windStrength, 0.72), "Repeated off/on does not reset selected direction or strength")
	var back: Button
	for button: Button in host._advanced.find_children("*", "Button", true, false):
		if button.text == "返回 / BACK": back = button
	_check(is_instance_valid(back), "Existing Back control is retained")
	if is_instance_valid(back):
		back.pressed.emit()
		_check(not host._advanced.visible and host._menu.visible, "Back closes water settings and returns to menu")
		host._menu.hide(); host._advanced.show()
		_check(not host._wind_controls.windWaves.button_pressed and host._wind_controls.windDirection.value == 275, "Reopening retains toggle and direction without stale reset")

