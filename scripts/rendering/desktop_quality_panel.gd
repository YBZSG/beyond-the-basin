extends Node
## Desktop-only, live graphics controls. Android retains its independent runtime.
## The preset is the starting point; every override is saved independently.
const NRControls = preload("res://scripts/rendering/nr_control_settings.gd")
const RTMaterialRefresh = preload("res://scripts/rendering/rt_material_refresh.gd")
const PCShadowProfile = preload("res://scripts/rendering/pc_indoor_shadow_candidate.gd")
const SETTINGS_PATH := "user://desktop_quality.cfg"
const PRESET_NAMES := ["Low", "Medium", "High", "Ultra"]
const SHADOW_SIZES := [1024, 2048, 4096, 8192]
const REFLECTION_SIZES := [256, 384, 512, 768, 1024, 1536, 2048]
const REFLECTION_INTERVALS := [0, 1, 2, 3, 5]
const CAUSTIC_INTERVALS := [0, 1, 2, 3, 4, 5, 6]
const DLSS_SCALES := {"Quality":2.0 / 3.0, "Balanced":0.58, "Performance":0.5, "DLAA":1.0}
const PRESETS := {
	"Low": {"caustic_interval":2, "scale":0.75, "msaa":0, "taa":false, "shadows":false, "shadow_size":1024, "reflection_size":256, "reflection_interval":3, "water":"Low", "caustics":false, "gi":false, "ssao":false, "ssil":false, "glow":false},
	"Medium": {"caustic_interval":1, "scale":0.9, "msaa":1, "taa":false, "shadows":true, "shadow_size":2048, "reflection_size":512, "reflection_interval":1, "water":"Medium", "caustics":true, "gi":false, "ssao":true, "ssil":false, "glow":true},
	"High": {"caustic_interval":0, "scale":1.0, "msaa":2, "taa":true, "shadows":true, "shadow_size":4096, "reflection_size":1024, "reflection_interval":0, "water":"High", "caustics":true, "gi":true, "ssao":true, "ssil":true, "glow":true},
	"Ultra": {"caustic_interval":0, "scale":1.25, "msaa":3, "taa":true, "shadows":true, "shadow_size":8192, "reflection_size":2048, "reflection_interval":0, "water":"Ultra", "caustics":true, "gi":true, "ssao":true, "ssil":true, "glow":true},
}
var main: Node
var preset := "High"
var settings: Dictionary = preset_settings("High")
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
var _pc_shadow_profile := PCShadowProfile.new()
var pc_shadow_status: Dictionary = {}
var dlss_status: Dictionary = {}
var frame_generation_status: Dictionary = {}
var raytracing_status: Dictionary = {}
var _rt_material_refresh_pending := false
var _rt_material_router := RTMaterialRefresh.new()
var _nr_controls := NRControls.new()
var nr_status: Dictionary = {}
var _nr_sliders: Dictionary = {}
var _nr_labels: Dictionary = {}
var _nr_status_poll := 0.0

static func dlss_support() -> Dictionary:
	# Query the optional NVIDIA API dynamically so stock Godot still loads this script.
	if not is_desktop_session() or DisplayServer.get_name() == "headless":
		return {"available":false, "reason":"需要桌面图形设备"}
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return {"available":false, "reason":"需要 Forward+ 渲染器"}
	if not Engine.has_singleton("Streamline") or not ClassDB.class_has_integer_constant("Viewport", "SCALING_3D_MODE_DLSS"):
		return {"available":false, "reason":"当前引擎未集成 DLSS"}
	var streamline := Engine.get_singleton("Streamline")
	if not streamline.has_method("get_capability") or not ClassDB.class_has_integer_constant("Streamline", "STREAMLINE_CAPABILITY_DLSS"):
		return {"available":false, "reason":"当前引擎缺少 DLSS 能力检测"}
	var capability := ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_CAPABILITY_DLSS")
	if not bool(streamline.call("get_capability", capability)):
		return {"available":false, "reason":"显卡、驱动或 DLSS 运行库不可用"}
	return {"available":true, "reason":"", "mode":ClassDB.class_get_integer_constant("Viewport", "SCALING_3D_MODE_DLSS")}

static func nvidia_feature_support(capability_name: String) -> Dictionary:
	var base := dlss_support()
	if not base.available: return base
	if not ClassDB.class_has_integer_constant("Streamline", capability_name):
		return {"available":false, "reason":"引擎缺少此功能"}
	var capability := ClassDB.class_get_integer_constant("Streamline", capability_name)
	if not bool(Engine.get_singleton("Streamline").call("get_capability", capability)):
		return {"available":false, "reason":"显卡、驱动或运行库不支持"}
	return {"available":true, "reason":""}

static func raytracing_support() -> Dictionary:
	var support := nvidia_feature_support("STREAMLINE_CAPABILITY_DLSS_RR")
	if not support.available: return support
	if not ClassDB.class_has_method("Environment", "set_pathtracing_enabled") or not ClassDB.class_has_integer_constant("RenderingDevice", "SUPPORTS_RAYTRACING_PIPELINE"):
		return {"available":false, "reason":"当前引擎不支持硬件路径追踪"}
	var device := RenderingServer.get_rendering_device()
	if device == null or not device.has_feature(ClassDB.class_get_integer_constant("RenderingDevice", "SUPPORTS_RAYTRACING_PIPELINE")):
		return {"available":false, "reason":"当前图形设备不支持硬件光追"}
	return {"available":true, "reason":""}

static func preset_settings(value: String) -> Dictionary:
	var result: Dictionary = PRESETS[value].duplicate()
	result.dlss = "Quality"
	result.merge(NRControls.DEFAULTS, true)
	result.nr = OS.get_environment("POOLCORE_DLSS_NR") == "1"
	result.frame_generation = not result.nr
	result.raytracing = false
	return result

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
	_rt_material_router.configure(host)
	settings_path = path
	# Keep an existing Ultra choice when migrating; never auto-select a lower tier.
	var previous := str(main.get("_quality"))
	preset = previous if previous in PRESET_NAMES else "High"
	settings = preset_settings(preset)
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
	settings = preset_settings(preset)
	for key: String in settings:
		settings[key] = _validated(key, config.get_value("graphics", key, settings[key]), settings[key])
	NRControls.normalize(settings)

func save_settings(path: String = "") -> Error:
	var config := ConfigFile.new()
	config.set_value("graphics", "preset", preset)
	for key: String in settings: config.set_value("graphics", key, settings[key])
	var result := config.save(settings_path if path.is_empty() else path)
	if is_instance_valid(_status):
		_status.text = "已自动保存 / SAVED" if result == OK else "已应用，保存失败 / SAVE FAILED (%s)" % error_string(result)
	return result

func _validated(key: String, value: Variant, fallback: Variant) -> Variant:
	if key in NRControls.DEFAULTS: return NRControls.validate(key, value, fallback)
	match key:
		"dlss":
			if value is String and (value == "Off" or DLSS_SCALES.has(value)): return value
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
	var keep_nr := bool(settings.get("nr", false))
	var keep_nr_controls: Dictionary = {}
	for key: String in NRControls.DEFAULTS: keep_nr_controls[key] = settings[key]
	settings = preset_settings(value)
	settings.merge(keep_nr_controls, true)
	settings.nr = keep_nr
	if keep_nr: settings.frame_generation = false
	apply_settings()
	save_settings()

func set_option(key: String, value: Variant) -> void:
	if not settings.has(key): return
	settings[key] = _validated(key, value, settings[key])
	if key == "nr" and bool(settings[key]): settings.frame_generation = false
	if key == "frame_generation" and bool(settings[key]): settings.nr = false
	apply_settings()
	save_settings()

func _changed(group: String, signature: Array) -> bool:
	if _applied.get(group, []) == signature: return false
	_applied[group] = signature.duplicate()
	apply_counts[group] = int(apply_counts.get(group, 0)) + 1
	return true

func apply_settings() -> void:
	NRControls.normalize(settings)
	_nr_controls.publish(settings)
	nr_status = _nr_controls.read_status()
	if not is_instance_valid(main): return
	var viewport := main.get_viewport()
	var support := supported_features(RenderingServer.get_current_rendering_method())
	dlss_status = dlss_support()
	dlss_status.requested = str(settings.get("dlss", "Quality"))
	dlss_status.active = bool(dlss_status.available) and DLSS_SCALES.has(dlss_status.requested)
	var desired_mode := int(dlss_status.mode) if dlss_status.active else int(Viewport.SCALING_3D_MODE_BILINEAR)
	var desired_scale := float(DLSS_SCALES[dlss_status.requested]) if dlss_status.active else float(settings.scale)
	var desired_msaa := int(Viewport.MSAA_DISABLED) if dlss_status.active else int(settings.msaa)
	var desired_taa := bool(settings.taa) and bool(support.taa) and not bool(dlss_status.active)
	var viewport_changed := _changed("viewport", [viewport.get_instance_id(), desired_mode, desired_scale, desired_msaa, desired_taa])
	# World regeneration keeps this Viewport but the host reapplies legacy AA.
	# A cached settings signature alone cannot prove the actual state still matches.
	# Reconcile only this group; keep every saved override and all other caches.
	var viewport_drifted := int(viewport.scaling_3d_mode) != desired_mode or not is_equal_approx(viewport.scaling_3d_scale, desired_scale) or viewport.msaa_3d != desired_msaa or viewport.use_taa != desired_taa
	if viewport_changed or viewport_drifted:
		if not viewport_changed: apply_counts["viewport"] = int(apply_counts.get("viewport", 0)) + 1
		# Set compatible intermediate values; each setter reconfigures the renderer.
		# In particular, do not briefly enable DLSS with legacy TAA or 125% scale.
		viewport.use_taa = false
		if int(viewport.scaling_3d_mode) != desired_mode:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.set("msaa_3d", desired_msaa)
		viewport.scaling_3d_scale = desired_scale
		viewport.set("scaling_3d_mode", desired_mode)
		viewport.use_taa = desired_taa
	dlss_status.scale = desired_scale
	OS.set_environment("POOLCORE_DLSS_NR", "1" if bool(settings.get("nr", false)) else "0")
	frame_generation_status = nvidia_feature_support("STREAMLINE_CAPABILITY_DLSS_G")
	var reflex := nvidia_feature_support("STREAMLINE_CAPABILITY_REFLEX")
	frame_generation_status.available = bool(frame_generation_status.available) and bool(reflex.available)
	if not reflex.available: frame_generation_status.reason = "Reflex 不可用：" + str(reflex.reason)
	frame_generation_status.requested = bool(settings.frame_generation)
	frame_generation_status.active = bool(frame_generation_status.available) and bool(dlss_status.active) and bool(settings.frame_generation)
	if ClassDB.class_has_method("Viewport", "set_frame_generation"):
		# Reflex stays on with DLSS, including during a frame-generation shutdown.
		if bool(reflex.available):
			var parameter := ClassDB.class_get_integer_constant("Streamline", "STREAMLINE_PARAM_REFLEX_MODE")
			Engine.get_singleton("Streamline").call("set_parameter", parameter, 1)
		viewport.set("frame_generation", bool(frame_generation_status.active))
	raytracing_status = raytracing_support()
	raytracing_status.requested = bool(settings.raytracing)
	raytracing_status.active = bool(raytracing_status.available) and bool(dlss_status.active) and bool(settings.raytracing)
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
		if _changed("raster_water_rt_context", [water_id, raytracing_status.active]) and _water.has_method("set_raster_water_rt_context"):
			_water.call("set_raster_water_rt_context", bool(raytracing_status.active))
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
		if _changed("raytracing", [_environment.get_instance_id(), raytracing_status.active, water_replaced]):
			_set_rt_materials(bool(raytracing_status.active))
			if _environment.has_method("set_pathtracing_enabled"):
				_environment.set("pathtracing_samples_per_pixel", 1)
				_environment.set("pathtracing_max_bounces", 3)
				_environment.set("pathtracing_denoiser", 1)
				_environment.set("pathtracing_enabled", bool(raytracing_status.active))
		lighting_changed = _changed("environment", [_environment.get_instance_id(), settings.gi, settings.ssao, settings.ssil, settings.glow, support])
		if lighting_changed:
			_environment.sdfgi_enabled = (bool(main.call("effective_gi_requested",bool(settings.gi))) if main.has_method("effective_gi_requested") else bool(settings.gi)) and support.gi
			_environment.ssao_enabled = bool(settings.ssao) and support.ssao
			_environment.ssil_enabled = bool(settings.ssil) and support.ssil
			_environment.glow_enabled = bool(settings.glow) and support.glow
	var shadows_changed := _changed("light_overrides", [main.get_instance_id(), settings.shadows])
	if shadows_changed:
		for node in main.find_children("*", "Light3D", true, false): _apply_light(node)
	var pc_shadow_changed := _apply_pc_shadow_profile(environment_node)
	if (lighting_changed or shadows_changed or atlas_changed or water_replaced or pc_shadow_changed) and is_instance_valid(_water) and _water.has_method("refresh_capture_lighting"):
		if main.has_method("_capture_lighting_changed"): main.call("_capture_lighting_changed")
		else: _water.call("refresh_capture_lighting")
	_refresh_interface()

func _set_rt_materials(enabled: bool) -> void:
	_rt_material_router.refresh_all(enabled)

func rt_material_refresh_stats() -> Dictionary:
	return _rt_material_router.get_stats()

func _apply_pc_shadow_profile(environment_node: WorldEnvironment) -> bool:
	var sun := environment_node.get_node_or_null("ApertureSun") as DirectionalLight3D if is_instance_valid(environment_node) else null
	var enabled := bool(settings.shadows) and "--original-shadow-sampling" not in OS.get_cmdline_user_args()
	var sun_id := sun.get_instance_id() if is_instance_valid(sun) else 0
	if not _changed("pc_shadow_sampling", [sun_id, preset, enabled]): return false
	# Keep the original120m fade/cutoff and atlas size. Only near allocation and
	# supported desktop filtering change; mobile never installs this owner.
	pc_shadow_status = _pc_shadow_profile.configure(sun, preset, enabled, "preserve120")
	return is_instance_valid(sun)

func _node_added(node: Node) -> void:
	# Lighting is configured around add_child(), so read the authored state only
	# after construction. Also covers newly streamed rooms and reseeding.
	if node is Light3D: call_deferred("_apply_new_light", weakref(node))
	if node is GeometryInstance3D and bool(raytracing_status.get("active", false)):
		_rt_material_router.queue_node(node)
		if not _rt_material_refresh_pending:
			_rt_material_refresh_pending = true
			call_deferred("_refresh_streamed_rt_materials")

func _refresh_streamed_rt_materials() -> void:
	_rt_material_refresh_pending = false
	if is_instance_valid(main): _rt_material_router.refresh_pending(bool(raytracing_status.get("active", false)))

func _apply_new_light(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		_apply_light(node)
		if node is DirectionalLight3D and node.name == "ApertureSun": apply_settings()

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
	_nr_status_poll += _delta
	if _nr_status_poll >= 0.5:
		_nr_status_poll = 0.0
		nr_status = _nr_controls.read_status()
		if is_instance_valid(_panel) and _panel.visible: _refresh_interface()
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
	_add_option(column, "NVIDIA DLSS / DLAA", "dlss", ["关闭 / Off", "质量 / Quality", "平衡 / Balanced", "性能 / Performance", "原生抗锯齿 / DLAA"], ["Off", "Quality", "Balanced", "Performance", "DLAA"])
	_add_check(column, "NVIDIA 帧生成 2× + Reflex", "frame_generation")
	_add_check(column, "原生神经渲染 NR（与帧生成互斥）", "nr")
	_add_option(column, "NR 叠加层数 / EXPERIMENTAL", "nr_layers", ["1 层 · 默认", "2 层 · 实验", "3 层 · 高开销", "4 层 · 很高开销"], [1,2,3,4])
	_add_nr_slider(column, "NR 混合强度 / INTENSITY", "nr_intensity")
	_add_nr_slider(column, "NR 局部色调 / TONE", "nr_tone")
	_add_nr_slider(column, "NR 结构细节 / STRUCTURE", "nr_structure")
	_add_check(column, "全场景硬件光追 + 光线重建（水面保留光栅）", "raytracing")
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

func _add_nr_slider(parent: Node, text: String, key: String) -> void:
	var label := Label.new()
	label.set_meta("caption", text)
	parent.add_child(label)
	_nr_labels[key] = label
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size.y = 28
	slider.value_changed.connect(func(value: float): set_option(key, value))
	parent.add_child(slider)
	_nr_sliders[key] = slider

func _nr_controls_available() -> bool:
	return bool(nr_status.get("acknowledged", false)) and bool(nr_status.get("fresh", false)) and bool(nr_status.get("supported", false)) and nr_status.get("capability", "unknown") == "available" and bool(dlss_status.get("active", false)) and bool(settings.nr)

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
	var custom: bool = settings != preset_settings(preset)
	_summary.text = "%s%s · 立即生效 / LIVE" % [preset, " + 自定义 / CUSTOM" if custom else ""]
	_scale.set_value_no_signal(float(settings.scale) * 100.0)
	_scale_label.text = "3D 渲染比例 / RESOLUTION SCALE: %d%%" % roundi(float(settings.scale) * 100.0)
	var dlss_active := bool(dlss_status.get("active", false))
	var nr_controls_available := _nr_controls_available()
	for key: String in _nr_sliders:
		var slider: HSlider = _nr_sliders[key]
		slider.set_value_no_signal(float(settings[key]))
		slider.editable = nr_controls_available
		slider.tooltip_text = "实验 NR 参数，不增加场景真实光照；高层数增加耗时和显存，可能破坏水面或手部细节。" if nr_controls_available else "需要新版 NR 引擎确认能力，并先开启 NR；旧引擎不伪装支持新参数。"
		_nr_labels[key].text = "%s: %.2f" % [_nr_labels[key].get_meta("caption"), float(settings[key])]
	_scale.editable = not dlss_active
	if dlss_active:
		_scale_label.text = "DLSS %s · 内部渲染 %d%% · 菜单保持原生清晰度" % [settings.dlss, roundi(float(dlss_status.scale) * 100.0)]
	for key: String in _options:
		var option := _options[key] as OptionButton
		option.disabled = (key == "dlss" and not bool(dlss_status.get("available", false))) or (key == "msaa" and dlss_active) or (key == "nr_layers" and not nr_controls_available)
		for index in option.item_count:
			if option.get_item_metadata(index) == settings[key]: option.select(index)
	var renderer := RenderingServer.get_current_rendering_method()
	var support := supported_features(renderer)
	for key: String in _checks:
		var check := _checks[key] as CheckButton
		check.disabled = not bool(support.get(key, true)) or (key == "taa" and dlss_active)
		if key == "frame_generation": check.disabled = not bool(frame_generation_status.get("available", false)) or not dlss_active
		if key == "nr": check.disabled = not dlss_active or not FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("nvngx_dlssnr.dll"))
		if key == "raytracing": check.disabled = not bool(raytracing_status.get("available", false)) or not dlss_active
		if key in ["gi", "ssao", "ssil"] and bool(raytracing_status.get("active", false)): check.disabled = true
		check.set_pressed_no_signal(bool(settings[key]) and not check.disabled)
		check.tooltip_text = "DLSS 已负责时间抗锯齿；关闭 DLSS 后恢复保存的选择。" if key == "taa" and dlss_active else ("当前渲染器不支持；保存的选择会在兼容的渲染器下启用。" if check.disabled else "")
	_notes.text = "DLSS 默认 Quality；DLAA 使用原生分辨率。启用时由 DLSS 负责抗锯齿和渲染比例，关闭后恢复原有比例、MSAA 与 TAA。水体模拟、反射精度和菜单分辨率独立保留。"
	var nr_note := "NR：关闭。NR 与帧生成不是同一功能，二者互斥。"
	if bool(settings.get("nr", false)):
		if not bool(nr_status.get("acknowledged", false)):
			nr_note = "NR：旧引擎单层请求；未确认新参数接口。叠加与强度设置需重新编译新版引擎，当前不声称生效。"
		elif bool(nr_status.get("current_request_applied", false)):
			nr_note = "NR：原生已执行 %d 层（请求 %d 层）；强度 %.2f / 色调 %.2f / 结构 %.2f。" % [int(nr_status.applied_layers), int(settings.nr_layers), float(settings.nr_intensity), float(settings.nr_tone), float(settings.nr_structure)]
		else:
			nr_note = "NR：请求 %d 层，未确认当前参数执行。%s" % [int(settings.nr_layers), str(nr_status.get("reason", nr_status.get("state", "等待原生状态")))]
		if bool(frame_generation_status.get("active", false)): nr_note = "NR：被帧生成旁路，请关闭 FG。"
		elif not dlss_active: nr_note = "NR：被 DLSS 关闭状态旁路。"
	nr_note += "\n叠加是独立历史的串联 NR 实验，默认 1 层；2–4 层增加 GPU 工作和显存，不保证更好，不用于掩盖切房间卡顿。"
	_notes.text += "\n" + nr_note
	_notes.text += "\n帧生成增加显示帧，操作响应仍取决于基础帧率；需要 DLSS / DLAA 和支持帧生成的 RTX 显卡。"
	_notes.text += "\n实验光追用于建筑和人物。水面使用光栅倒影；开启场景光追时，水下折射也采用独立光栅画面，避免池底光追亮点闪烁。波浪和焦散保留；关闭光追后恢复所选倒影质量。"
	if not bool(frame_generation_status.get("available", false)): _notes.text += "\n帧生成不可用：" + str(frame_generation_status.get("reason", "Reflex 不可用"))
	if not bool(raytracing_status.get("available", false)): _notes.text += "\n光追不可用：" + str(raytracing_status.get("reason", ""))
	if not bool(dlss_status.get("available", false)):
		_notes.text += "\nDLSS 不可用：%s。当前使用保存的常规渲染设置。" % str(dlss_status.get("reason", ""))
	_notes.text += "\n移动视角时反射始终逐帧更新；更新间隔仅用于静止视角。当前渲染器：%s。关闭 DLSS 时 High 默认原生分辨率，Ultra 默认 125%% 超采样与 8× MSAA。选择预设会重置单项设置，修改自动保存。" % renderer
	_notes.text += "\n水体精度改变模拟、细波纹和水面网格；反射宽度与刷新频率独立可调。关闭阴影不会开启原本不投影的灯光。High / Ultra 默认逐帧计算焦散；这提高动画连续性，也增加 GPU 负担，不改变光子数量或波浪公式。"
	_notes.text += "\nPC 近景阴影采用 5/14/60/120 米分配，保留原最远覆盖；High/Ultra 增加软阴影采样。更高滤波可能增加 GPU 负担，不会改变角色轮廓。"
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
	_pc_shadow_profile.restore()
	if is_instance_valid(_panel): _panel.queue_free()
	if is_instance_valid(_open_button): _open_button.queue_free()
