extends Node
## Desktop-only, live graphics controls. Android retains its independent runtime.
## The preset is the starting point; every override is saved independently.
const SETTINGS_PATH := "user://desktop_quality.cfg"
const PRESET_NAMES := ["Low", "Medium", "High", "Ultra"]
const SHADOW_SIZES := [1024, 2048, 4096, 8192]
const REFLECTION_SIZES := [256, 384, 512, 768, 1024, 1536, 2048]
const REFLECTION_INTERVALS := [0, 1, 2, 3, 5]
const CAUSTIC_INTERVALS := [0, 1, 2, 3, 4, 5, 6]
const PRESETS := {
	"Low": {"caustic_interval":2, "scale":0.75, "msaa":0, "taa":false, "shadows":false, "shadow_size":1024, "reflection_size":256, "reflection_interval":3, "water":"Low", "caustics":false, "gi":false, "ssao":false, "ssil":false, "glow":false},
	"Medium": {"caustic_interval":1, "scale":0.9, "msaa":1, "taa":false, "shadows":true, "shadow_size":2048, "reflection_size":512, "reflection_interval":1, "water":"Medium", "caustics":true, "gi":false, "ssao":true, "ssil":false, "glow":true},
	"High": {"caustic_interval":0, "scale":1.0, "msaa":2, "taa":true, "shadows":true, "shadow_size":4096, "reflection_size":1024, "reflection_interval":0, "water":"High", "caustics":true, "gi":true, "ssao":true, "ssil":true, "glow":true},
	"Ultra": {"caustic_interval":0, "scale":1.25, "msaa":3, "taa":true, "shadows":true, "shadow_size":8192, "reflection_size":2048, "reflection_interval":0, "water":"Ultra", "caustics":true, "gi":true, "ssao":true, "ssil":true, "glow":true},
}
var main: Node
var preset := "High"
var settings: Dictionary = PRESETS.High.duplicate()
var settings_path := SETTINGS_PATH
var _water: Node
var _water_applied_quality := ""
var _environment: Environment
var _panel: PanelContainer
var _open_button: Button
var _preset_selector: OptionButton
var _scale: HSlider
var _scale_label: Label
var _summary: Label
var _notes: Label
var _status: Label
var _options: Dictionary = {}
var _checks: Dictionary = {}
var _scroll: ScrollContainer
var _applied: Dictionary = {}
var apply_counts: Dictionary = {}

static func is_desktop_session() -> bool:
	return not (OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args())

static func install(host: Node, path: String = SETTINGS_PATH) -> Node:
	if not is_desktop_session(): return null
	var existing := host.get_node_or_null("DesktopQuality")
	if existing: return existing
	var runtime := load("res://scripts/rendering/desktop_quality_panel.gd").new() as Node
	runtime.name = "DesktopQuality"
	host.add_child(runtime)
	runtime.configure(host, path)
	return runtime

static func supported_features(renderer: String) -> Dictionary:
	var forward := renderer == "forward_plus"
	return {"taa":forward, "gi":forward, "ssao":forward, "ssil":forward, "glow":renderer in ["forward_plus", "mobile"]}

func configure(host: Node, path: String = SETTINGS_PATH) -> void:
	main = host
	settings_path = path
	# Keep an existing Ultra choice when migrating; never auto-select a lower tier.
	var previous := str(main.get("_quality"))
	preset = previous if previous in PRESET_NAMES else "High"
	settings = PRESETS[preset].duplicate()
	settings.gi = bool(main.get("_gi_on"))
	settings.caustics = bool(main.get("_caustics_on"))
	# Preserve an explicitly saved source advanced-water cadence on first migration.
	var old_water:Variant=main.get("_water_settings")
	if old_water is Dictionary and old_water.has("causticsRefresh"):
		settings.caustic_interval=clampi(int(old_water.causticsRefresh),0,6)
	load_settings()
	get_tree().node_added.connect(_node_added)
	_build_panel()
	apply_settings()

func load_settings(path: String = "") -> void:
	var config := ConfigFile.new()
	if config.load(settings_path if path.is_empty() else path) != OK: return
	var saved_preset := str(config.get_value("graphics", "preset", "High"))
	preset = saved_preset if saved_preset in PRESET_NAMES else "High"
	settings = PRESETS[preset].duplicate()
	for key: String in settings:
		settings[key] = _validated(key, config.get_value("graphics", key, settings[key]), settings[key])

func save_settings(path: String = "") -> Error:
	var config := ConfigFile.new()
	config.set_value("graphics", "preset", preset)
	for key: String in settings: config.set_value("graphics", key, settings[key])
	var result := config.save(settings_path if path.is_empty() else path)
	if is_instance_valid(_status):
		_status.text = "已自动保存 / SAVED" if result == OK else "已应用，保存失败 / SAVE FAILED (%s)" % error_string(result)
	return result

func _validated(key: String, value: Variant, fallback: Variant) -> Variant:
	match key:
		"scale":
			if (value is float or value is int) and is_finite(float(value)):
				return clampf(float(value), 0.5, 1.5)
		"msaa":
			if value is int: return clampi(value, 0, 3)
		"shadow_size":
			if value is int and value in SHADOW_SIZES: return value
		"reflection_size":
			if value is int and value in REFLECTION_SIZES: return value
		"reflection_interval":
			if value is int and value in REFLECTION_INTERVALS: return value
		"caustic_interval":
			if value is int and value in CAUSTIC_INTERVALS: return value
		"water":
			if value is String and value in PRESET_NAMES: return value
		_:
			if value is bool: return value
	return fallback

func select_preset(value: String) -> void:
	if value not in PRESET_NAMES: return
	preset = value
	settings = PRESETS[value].duplicate()
	apply_settings()
	save_settings()

func set_option(key: String, value: Variant) -> void:
	if not settings.has(key): return
	settings[key] = _validated(key, value, settings[key])
	apply_settings()
	save_settings()

func _changed(group: String, signature: Array) -> bool:
	if _applied.get(group, []) == signature: return false
	_applied[group] = signature.duplicate()
	apply_counts[group] = int(apply_counts.get(group, 0)) + 1
	return true

func apply_settings() -> void:
	if not is_instance_valid(main): return
	var viewport := main.get_viewport()
	var support := supported_features(RenderingServer.get_current_rendering_method())
	var desired_taa := bool(settings.taa) and bool(support.taa)
	var viewport_changed := _changed("viewport", [viewport.get_instance_id(), settings.scale, settings.msaa, settings.taa, support.taa])
	# World regeneration keeps this Viewport but the host reapplies legacy AA.
	# A cached settings signature alone cannot prove the actual state still matches.
	# Reconcile only this group; keep every saved override and all other caches.
	var viewport_drifted := viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR or not is_equal_approx(viewport.scaling_3d_scale, float(settings.scale)) or viewport.msaa_3d != int(settings.msaa) or viewport.use_taa != desired_taa
	if viewport_changed or viewport_drifted:
		if not viewport_changed: apply_counts["viewport"] = int(apply_counts.get("viewport", 0)) + 1
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = float(settings.scale)
		viewport.msaa_3d = int(settings.msaa)
		viewport.use_taa = desired_taa
	var atlas_changed := _changed("shadow_atlas", [viewport.get_instance_id(), settings.shadow_size])
	if atlas_changed:
		viewport.positional_shadow_atlas_size = int(settings.shadow_size)
		RenderingServer.directional_shadow_atlas_set_size(int(settings.shadow_size), true)
	main.set("_quality", preset)
	# Apply environment first, then notify captures once with its final state.
	# Calling host._set_gi for every unrelated slider used to invalidate all room
	# cubemaps even when GI did not change, followed by a second invalidation below.
	main.set("_gi_on", bool(settings.gi))
	main.set("_caustics_on", bool(settings.caustics))
	var water := main.get("water") as Node
	var water_replaced := water != _water
	if water_replaced:
		_water = water
		_water_applied_quality = ""
	if is_instance_valid(_water):
		var water_id := _water.get_instance_id()
		var quality_changed := _water_applied_quality != str(settings.water)
		if quality_changed:
			_water.call("set_quality", str(settings.water))
			_water_applied_quality = str(settings.water)
		if _changed("caustics", [water_id, settings.caustics]):
			_water.call("set_caustics", bool(settings.caustics))
		var cadence_changed := _changed("caustic_cadence", [water_id, settings.caustic_interval])
		if (quality_changed or cadence_changed) and _water.has_method("set_tuning"):
			_water.call("set_tuning", "causticsRefresh", int(settings.caustic_interval))
		var planar := _water.get("planar") as Node
		if is_instance_valid(planar):
			var planar_changed := _changed("planar", [planar.get_instance_id(), settings.reflection_size, settings.reflection_interval])
			if quality_changed or planar_changed:
				planar.call("set_quality", int(settings.reflection_size), int(settings.reflection_interval))
	var environment_node := main.get("environment") as WorldEnvironment
	_environment = environment_node.environment if is_instance_valid(environment_node) else null
	var lighting_changed := false
	if _environment:
		lighting_changed = _changed("environment", [_environment.get_instance_id(), settings.gi, settings.ssao, settings.ssil, settings.glow, support])
		if lighting_changed:
			_environment.sdfgi_enabled = (bool(main.call("effective_gi_requested",bool(settings.gi))) if main.has_method("effective_gi_requested") else bool(settings.gi)) and support.gi
			_environment.ssao_enabled = bool(settings.ssao) and support.ssao
			_environment.ssil_enabled = bool(settings.ssil) and support.ssil
			_environment.glow_enabled = bool(settings.glow) and support.glow
	var shadows_changed := _changed("light_overrides", [main.get_instance_id(), settings.shadows])
	if shadows_changed:
		for node in main.find_children("*", "Light3D", true, false): _apply_light(node)
	if (lighting_changed or shadows_changed or atlas_changed or water_replaced) and is_instance_valid(_water) and _water.has_method("refresh_capture_lighting"):
		if main.has_method("_capture_lighting_changed"): main.call("_capture_lighting_changed")
		else: _water.call("refresh_capture_lighting")
	_refresh_interface()

func _node_added(node: Node) -> void:
	# Lighting is configured around add_child(), so read the authored state only
	# after construction. Also covers newly streamed rooms and reseeding.
	if node is Light3D: call_deferred("_apply_new_light", weakref(node))

func _apply_new_light(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node): _apply_light(node)

func _apply_light(node: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(main) or not main.is_ancestor_of(node): return
	var light := node as Light3D
	if not light: return
	if light.has_meta("source_shadow_managed"):
		light.set_meta("source_shadows_allowed",bool(settings.shadows));return
	if not light.has_meta("desktop_authored_shadow"):
		light.set_meta("desktop_authored_shadow", light.shadow_enabled)
	light.shadow_enabled = bool(settings.shadows) and bool(light.get_meta("desktop_authored_shadow"))

func _process(_delta: float) -> void:
	if not is_instance_valid(main): return
	if not bool(main.get("_booted")):
		set_process(false)
		return
	var environment_node := main.get("environment") as WorldEnvironment
	var current_environment := environment_node.environment if is_instance_valid(environment_node) else null
	if main.get("water") != _water or current_environment != _environment:
		apply_settings()
	# Preserve the existing menu and V/C hotkeys as equal entry points.
	var changed := false
	for pair in [["gi", "_gi_on"], ["caustics", "_caustics_on"]]:
		var value := bool(main.get(pair[1]))
		if settings[pair[0]] != value:
			settings[pair[0]] = value
			changed = true
	if is_instance_valid(_water) and _water.get("settings") is Dictionary:
		var live:Dictionary=_water.get("settings")
		var cadence:=clampi(roundi(float(live.get("causticsRefresh",settings.caustic_interval))),0,6)
		if cadence!=settings.caustic_interval:
			settings.caustic_interval=cadence;changed=true
	if changed:
		save_settings()
		_refresh_interface()
	if is_instance_valid(_panel) and _panel.visible:
		if not bool(main.get("menu_open")) or (main.get("_menu") as Control).visible:
			_panel.hide()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_panel) and _panel.visible and event.is_action_pressed("pause"):
		close_panel()
		get_viewport().set_input_as_handled()

func open_panel() -> void:
	(main.get("_menu") as Control).hide()
	_refresh_interface()
	_fit_panel()
	_panel.show()
	_preset_selector.grab_focus()

func close_panel() -> void:
	if is_instance_valid(_panel): _panel.hide()
	if is_instance_valid(main) and bool(main.get("menu_open")):
		(main.get("_menu") as Control).show()
		if is_instance_valid(_open_button): _open_button.grab_focus()

func _build_panel() -> void:
	var menu := main.get("_menu") as PanelContainer
	var ui := menu.get_parent() as Control
	_panel = PanelContainer.new()
	_panel.name = "DesktopQualityPanel"
	_panel.add_theme_stylebox_override("panel", menu.get_theme_stylebox("panel"))
	ui.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	_scroll.add_child(column)
	var title := Label.new()
	title.text = "桌面画质 / PC GRAPHICS"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", Color("a7cfca"))
	column.add_child(_summary)
	_preset_selector = OptionButton.new()
	_preset_selector.name = "DesktopPreset"
	for title_text in ["Low · 低", "Medium · 中", "High · 高（默认）", "Ultra · 极致"]:
		_preset_selector.add_item(title_text)
	_preset_selector.custom_minimum_size.y = 38
	_preset_selector.item_selected.connect(func(index: int): select_preset(PRESET_NAMES[index]))
	column.add_child(_preset_selector)
	_scale_label = Label.new()
	column.add_child(_scale_label)
	_scale = HSlider.new()
	_scale.name = "DesktopResolutionScale"
	_scale.min_value = 50
	_scale.max_value = 150
	_scale.step = 5
	_scale.custom_minimum_size.y = 28
	_scale.value_changed.connect(func(value: float): set_option("scale", value / 100.0))
	_scale.tooltip_text = "只缩放 3D，不降低菜单清晰度；100% 为原生分辨率，超过 100% 为超采样。"
	column.add_child(_scale)
	_add_option(column, "多重采样 / MSAA", "msaa", ["关闭 / Off", "2×", "4×", "8×"], [0, 1, 2, 3])
	_add_check(column, "时间抗锯齿 / TAA", "taa")
	_add_section(column, "光照与阴影 / LIGHTING")
	_add_check(column, "真实光源阴影 / SHADOWS", "shadows")
	_add_option(column, "阴影图集 / SHADOW ATLAS", "shadow_size", ["1024", "2048", "4096", "8192"], SHADOW_SIZES)
	_add_check(column, "间接光 / SDFGI", "gi")
	_add_check(column, "环境遮蔽 / SSAO", "ssao")
	_add_check(column, "屏幕空间间接光 / SSIL", "ssil")
	_add_check(column, "高光辉光 / GLOW", "glow")
	_add_section(column, "水面与反射 / WATER")
	_add_option(column, "水体模拟精度 / WATER", "water", PRESET_NAMES, PRESET_NAMES)
	_add_option(column, "平面反射宽度 / MIRROR", "reflection_size", ["256 px", "384 px", "512 px", "768 px", "1024 px", "1536 px", "2048 px"], REFLECTION_SIZES)
	_add_option(column, "反射更新 / REFRESH", "reflection_interval", ["每帧 / Every frame", "每 2 帧", "每 3 帧", "每 4 帧", "每 6 帧"], REFLECTION_INTERVALS)
	_add_check(column, "水下焦散 / CAUSTICS", "caustics")
	_add_option(column, "焦散更新 / PHOTON REFRESH", "caustic_interval", ["每帧 / Every frame", "每 2 帧", "每 3 帧（原设置）", "每 4 帧", "每 5 帧", "每 6 帧", "每 7 帧"], CAUSTIC_INTERVALS)
	_notes = Label.new()
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.add_theme_font_size_override("font_size", 13)
	_notes.add_theme_color_override("font_color", Color("a7b9b6"))
	column.add_child(_notes)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	column.add_child(_status)
	var back := Button.new()
	back.text = "返回 / BACK"
	back.custom_minimum_size.y = 38
	back.pressed.connect(close_panel)
	column.add_child(back)
	_panel.hide()
	var menu_columns := menu.find_children("*", "VBoxContainer", true, false)
	if not menu_columns.is_empty():
		var menu_column := menu_columns[0] as VBoxContainer
		_open_button = Button.new()
		_open_button.name = "DesktopQualityButton"
		_open_button.text = "桌面画质 / PC GRAPHICS"
		_open_button.custom_minimum_size.y = 38
		_open_button.pressed.connect(open_panel)
		menu_column.add_child(_open_button)
		menu_column.move_child(_open_button, mini(5, menu_column.get_child_count() - 1))
	ui.resized.connect(_fit_panel)
	_fit_panel()

func _add_section(parent: Node, text: String) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("a7cfca"))
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)

func _add_option(parent: Node, text: String, key: String, labels: Array, values: Array) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(180, 32)
	for index in labels.size():
		option.add_item(str(labels[index]))
		option.set_item_metadata(index, values[index])
	option.item_selected.connect(func(index: int): set_option(key, option.get_item_metadata(index)))
	_options[key] = option
	row.add_child(option)
	parent.add_child(row)

func _add_check(parent: Node, text: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = text
	check.custom_minimum_size.y = 32
	check.toggled.connect(func(value: bool): set_option(key, value))
	_checks[key] = check
	parent.add_child(check)

func _refresh_interface() -> void:
	if not is_instance_valid(_preset_selector): return
	_preset_selector.select(PRESET_NAMES.find(preset))
	var custom: bool = settings != PRESETS[preset]
	_summary.text = "%s%s · 立即生效 / LIVE" % [preset, " + 自定义 / CUSTOM" if custom else ""]
	_scale.set_value_no_signal(float(settings.scale) * 100.0)
	_scale_label.text = "3D 渲染比例 / RESOLUTION SCALE: %d%%" % roundi(float(settings.scale) * 100.0)
	for key: String in _options:
		var option := _options[key] as OptionButton
		for index in option.item_count:
			if option.get_item_metadata(index) == settings[key]: option.select(index)
	var renderer := RenderingServer.get_current_rendering_method()
	var support := supported_features(renderer)
	for key: String in _checks:
		var check := _checks[key] as CheckButton
		check.disabled = not bool(support.get(key, true))
		check.set_pressed_no_signal(bool(settings[key]) and not check.disabled)
		check.tooltip_text = "当前渲染器不支持；保存的选择会在兼容的渲染器下启用。" if check.disabled else ""
	_notes.text = "移动视角时反射始终逐帧更新；更新间隔仅用于静止视角。当前渲染器：%s。High 默认保持原生高画质；Ultra 启用 125%% 超采样、8× MSAA 和更高精度。选择预设会重置下面的单项设置，修改会自动保存。" % renderer
	_notes.text += "\n水体精度改变模拟、细波纹和水面网格；反射宽度与刷新频率独立可调。关闭阴影不会开启原本不投影的灯光。High / Ultra 默认逐帧计算焦散；这提高动画连续性，也增加 GPU 负担，不改变光子数量或波浪公式。"
	if renderer != "forward_plus":
		_notes.text += "\nTAA、SDFGI、SSAO 和 SSIL 仅支持 Forward+，不可用选项已禁用；本页不会假装即时更换渲染器。"

func _fit_panel() -> void:
	if not is_instance_valid(_panel): return
	var ui := _panel.get_parent() as Control
	var available := ui.size
	if available.x < 1 or available.y < 1: available = main.get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(720, maxf(360, available.x - 40)), minf(640, maxf(300, available.y - 40)))
	_panel.position = (available - dimensions) * 0.5
	_panel.size = dimensions
	_scroll.custom_minimum_size = Vector2.ZERO

func _exit_tree() -> void:
	if is_instance_valid(_panel): _panel.queue_free()
	if is_instance_valid(_open_button): _open_button.queue_free()
