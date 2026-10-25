extends SceneTree
## Isolated CPU/Canvas geometry contract. It never constructs the actual game,
## source solver, RenderingDevice, compositor, or native engine extension.
const Settings = preload("res://scripts/reference_wing/reference_look_settings.gd")
const Waves = preload("res://scripts/reference_wing/reference_wave_controller.gd")
var checks := {}
var errors: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(label: String, condition: bool) -> void:
	checks[label] = condition
	if not condition: errors.append(label)

func _settle(controller: RefCounted, seconds := 20.0) -> void:
	for frame in ceili(seconds * 60.0): controller.advance(1.0 / 60.0)

func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("CPU-only contract requires headless dummy renderer."); quit(2); return
	_test_settings()
	_test_waves()
	await _test_camera_and_layout()
	print("REFERENCE_LOOK_CONTRACT ", JSON.stringify({"passed": errors.is_empty(), "checks": checks,
		"errors": errors, "engine": Engine.get_version_info().string, "gpu_run": false,
		"scope": "Isolated module math, state, material parameter ownership and Canvas geometry only. Not GPU shader compilation, production UI integration, target performance, or visual acceptance."}))
	quit(0 if errors.is_empty() else 1)

func _test_settings() -> void:
	var defaults := Settings.sanitize({})
	_check("both_additions_default_off", not defaults.referenceWaves and not defaults.referenceLook)
	for invalid: Variant in [null, "bad", [], 7]:
		_check("invalid_container_" + str(invalid), Settings.sanitize(invalid) == defaults)
	var source := {"referenceWaves": true, "referenceWaveStrength": 9.0,
		"referenceWaveDirection": -90.0, "referenceWaveScale": 0.0,
		"referenceLook": "false", "referenceFringePx": 20.0,
		"referenceGrain": NAN, "referenceVignette": INF, "windStrength": 0.73}
	var before := source.duplicate(true)
	var clean := Settings.sanitize(source)
	_check("sanitize_does_not_change_input", source.hash() == before.hash())
	_check("numerics_are_bounded", clean.referenceWaveStrength == 1.0 and clean.referenceWaveDirection == 270.0 and clean.referenceWaveScale == 0.6 and clean.referenceFringePx == 8.0)
	_check("bad_bool_and_nonfinite_default", not clean.referenceLook and clean.referenceGrain == defaults.referenceGrain and clean.referenceVignette == defaults.referenceVignette)
	_check("no_wind_or_solver_setting_ownership", not clean.has("windStrength") and clean.size() == Settings.DEFAULT.size())
	var camera_only := defaults.duplicate(); camera_only.referenceLook = true
	var wave_only := defaults.duplicate(); wave_only.referenceWaves = true
	_check("wave_switch_cannot_enable_post", not Settings.camera_visible(wave_only, 0))
	_check("camera_switch_cannot_enable_wave", not camera_only.referenceWaves and Settings.camera_visible(camera_only, 0))
	_check("off_bypasses_post_and_preserves_legacy", not Settings.camera_visible(defaults, 0) and Settings.camera_visible(defaults, 2))
	var zero := Settings.sanitize({"referenceLook": true, "referenceFringePx": 0.0, "referenceGrain": 0.0, "referenceVignette": 0.0})
	_check("zero_camera_effect_is_exact_hidden_pass_identity", not Settings.camera_visible(zero, 0) and Settings.camera_visible(zero, 2))
	var save := ConfigFile.new()
	save.set_value("reference", "settings", camera_only)
	save.set_value("water", "settings", {"windWaves": true, "windStrength": 0.73, "waveHeight": 1.4})
	var restored := ConfigFile.new()
	_check("isolated_config_roundtrip", restored.parse(save.encode_to_text()) == OK and Settings.sanitize(restored.get_value("reference", "settings")) == camera_only)
	_check("separate_config_keeps_legacy_water", restored.get_value("water", "settings") == {"windWaves": true, "windStrength": 0.73, "waveHeight": 1.4})

func _test_waves() -> void:
	var controller := Waves.new()
	var initial: Dictionary = controller.describe()
	_check("initial_optical_zero", not controller.active() and controller.sample(Vector2(3, 2)) == Vector3.ZERO)
	_check("explicit_approximation", initial.optical_only and initial.solver_readbacks == 0 and initial.mode_count == 3)
	_check("longer_than_existing_fine_wind", Waves.WAVELENGTHS[0] > 0.48 and Waves.WAVELENGTHS[1] > 0.48 and Waves.WAVELENGTHS[2] > 0.48)
	controller.set_target({"referenceWaves": true, "referenceWaveStrength": 1.0, "referenceWaveScale": 0.6})
	_check("setting_target_never_resets_modes", controller.modes == initial.modes)
	controller.advance(1.0 / 60.0)
	_check("gradual_enable", controller.active() and controller.strength > 0.0 and controller.strength < 0.04)
	_settle(controller)
	_check("12mm_equivalent_relief_bound", controller.describe().peak_equivalent_relief_bound_m <= 0.012 and controller.describe().peak_equivalent_relief_bound_m > 0.01199)
	var max_derivative_error := 0.0
	var bounded := true
	for z in range(-8, 9):
		for x in range(-8, 9):
			var point := Vector2(x * 0.16, z * 0.13)
			var sample: Vector3 = controller.sample(point)
			bounded = bounded and sample.is_finite() and absf(sample.x) <= 0.012 and Vector2(sample.y, sample.z).length() < 0.12
			var epsilon := 0.0001
			var dx: float = (controller.sample(point + Vector2(epsilon, 0)).x - controller.sample(point - Vector2(epsilon, 0)).x) / (2.0 * epsilon)
			var dz: float = (controller.sample(point + Vector2(0, epsilon)).x - controller.sample(point - Vector2(0, epsilon)).x) / (2.0 * epsilon)
			max_derivative_error = maxf(max_derivative_error, maxf(absf(dx - sample.y), absf(dz - sample.z)))
	_check("finite_bounded_height_and_slope", bounded)
	_check("analytic_gradient_matches_height", max_derivative_error < 0.0003)
	checks["gradient_max_error"] = max_derivative_error
	_check("dry_and_subpixel_exact_zero", controller.sample(Vector2(3, 2), 0.0, 0.0) == Vector3.ZERO and controller.sample(Vector2(3, 2), 2.0) == Vector3.ZERO)
	var old_modes: PackedVector4Array = controller.modes.duplicate()
	var point := Vector2(100, -50)
	controller.set_target({"referenceWaveDirection": 180.0, "referenceWaveScale": 1.6})
	controller.advance(1.0 / 60.0)
	var continuity := true
	for index in 3:
		var next: Vector4 = controller.modes[index]
		var change := wrapf(next.w - old_modes[index].w, -PI, PI)
		continuity = continuity and change < 0.0 and change > -0.08
	_check("direction_scale_edit_preserves_fixed_world_phase", continuity)
	_check("coordinate_space_is_fixed_world_not_camera", controller.describe().coordinate_space == "fixed_world_xz")
	var settings_before: Dictionary = controller.target.duplicate()
	var phases_before: PackedFloat64Array = controller.phases.duplicate()
	controller.set_target({"referenceWaves": false})
	_check("off_is_immediate_exact_zero_not_fade", not controller.active() and controller.sample(point) == Vector3.ZERO and controller.strength > 0.0)
	_check("off_preserves_phase_strength_direction_scale", controller.phases == phases_before and controller.target.referenceWaveStrength == settings_before.referenceWaveStrength and controller.target.referenceWaveDirection == settings_before.referenceWaveDirection and controller.target.referenceWaveScale == settings_before.referenceWaveScale)
	controller.advance(0.1)
	_check("off_never_restarts_phase", controller.phases != phases_before)
	controller.set_target({"referenceWaves": true})
	_check("re_enable_retains_values", controller.target.referenceWaveStrength == 1.0 and controller.target.referenceWaveScale == 1.6)
	controller.set_target({"referenceWaveStrength": 0.0})
	_check("zero_strength_also_immediate", not controller.active() and controller.sample(point) == Vector3.ZERO)
	var target_before: Dictionary = controller.target.duplicate()
	controller.set_target({"referenceWaves": "false", "referenceWaveStrength": NAN, "referenceWaveDirection": INF, "referenceWaveScale": "bad"})
	_check("invalid_partial_edits_keep_last_valid_target", target_before == controller.target)
	var state_before: Dictionary = controller.describe()
	controller.advance(NAN); controller.advance(INF); controller.advance(-1.0); controller.advance(0.0)
	_check("invalid_delta_never_changes_state", controller.describe() == state_before)
	var slow := Waves.new(); var fast := Waves.new()
	for step in 15 * 10: slow.advance(1.0 / 15.0)
	for step in 60 * 10: fast.advance(1.0 / 60.0)
	var phase_error := 0.0
	for index in 3: phase_error = maxf(phase_error, absf(angle_difference(slow.phases[index], fast.phases[index])))
	_check("constant_speed_15_60hz_phase_invariance", phase_error < 0.000001)
	checks["constant_phase_error_15_60hz"] = phase_error
	var travel := Waves.new()
	var before_mode: Vector4 = travel.modes[0]
	travel.advance(0.1)
	var after_mode: Vector4 = travel.modes[0]
	var k := Vector2(before_mode.x, before_mode.y)
	var travel_delta := k.normalized() * Waves.TRAVEL_SPEEDS_M_S[0] * 0.1
	_check("crest_advects_in_selected_direction", absf(angle_difference(before_mode.w, k.dot(travel_delta) + after_mode.w)) < 0.000001)
	var stub := Shader.new()
	stub.code = "shader_type spatial; uniform vec4 referenceWaveModes[3]; uniform float referenceWavesActive=0.0; void fragment(){ALBEDO=vec3(0.0);}"
	var material := ShaderMaterial.new(); material.shader = stub
	controller.set_target({"referenceWaves": true, "referenceWaveStrength": 0.7})
	_settle(controller); controller.apply_to(material)
	var published: PackedVector4Array = material.get_shader_parameter("referenceWaveModes").duplicate()
	controller.advance(0.1)
	_check("published_uniform_array_is_immutable", material.get_shader_parameter("referenceWaveModes") == published and controller.modes != published)
	controller.set_target({"referenceWaves": false}); controller.apply_to(material)
	_check("material_off_gate_is_exact_zero", material.get_shader_parameter("referenceWavesActive") == 0.0)
	for step in 6000: controller.advance(1.0 / 60.0)
	var phase_bounded := true
	for phase: float in controller.phases: phase_bounded = phase_bounded and is_finite(phase) and phase >= -PI and phase <= PI
	_check("long_run_phases_stay_bounded", phase_bounded)

func _test_camera_and_layout() -> void:
	var shader := load("res://shaders/reference_wing/reference_camera_look.gdshader") as Shader
	_check("camera_shader_resource_loads", shader != null)
	var material := ShaderMaterial.new(); material.shader = shader
	var state := Settings.sanitize({"referenceLook": true, "referenceFringePx": 1.1})
	Settings.apply_camera(material, state, 2)
	_check("camera_uniforms_and_legacy_mode_bound", material.get_shader_parameter("reference_look_enabled") == true and material.get_shader_parameter("reference_fringe_px") == 1.1 and material.get_shader_parameter("look_mode") == 2)
	state.referenceLook = false
	Settings.apply_camera(material, state, 2)
	_check("camera_off_does_not_clear_saved_intensity_or_legacy", material.get_shader_parameter("reference_look_enabled") == false and material.get_shader_parameter("reference_fringe_px") == 1.1 and material.get_shader_parameter("look_mode") == 2)
	# Headless layout fixture, not a claim about production main.gd integration.
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280, 720); root.add_child(viewport)
	var layer := CanvasLayer.new(); layer.layer = 0; viewport.add_child(layer)
	var rect := ColorRect.new(); rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect); rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); rect.material = material
	var hud := CanvasLayer.new(); hud.layer = 1; viewport.add_child(hud)
	var menu := Panel.new(); hud.add_child(menu)
	await process_frame
	_check("post_below_clean_hud_menu", layer.layer < hud.layer and rect.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(720, 1280), Vector2i(3440, 1440)]:
		viewport.size = size
		await process_frame
		_check("post_resizes_" + str(size), rect.size.is_equal_approx(Vector2(size)))
	var frozen := state.duplicate()
	for quality: String in ["Low", "Medium", "High", "Ultra"]:
		menu.visible = not menu.visible
		Settings.apply_camera(material, state, 0)
		rect.visible = Settings.camera_visible(state, 0)
		_check("quality_agnostic_settings_and_clean_bypass_" + quality, state == frozen and not rect.visible)
	viewport.free()
