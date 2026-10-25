extends SceneTree
## Runs the actual adapter against an isolated lifecycle double, not a GPU solver.
const Runtime = preload("res://scripts/reference_wing/reference_water_runtime.gd")
var checks := {}
var errors: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _check(label: String, condition: bool) -> void:
	checks[label] = condition
	if not condition: errors.append(label)

func _material(shader: Shader) -> ShaderMaterial:
	var value := ShaderMaterial.new(); value.shader = shader
	value.render_priority = 3
	value.set_shader_parameter("waveHeight", 1.37)
	value.set_shader_parameter("refractionStrength", 0.77)
	value.set_shader_parameter("windOpticsActive", 1.0)
	value.set_shader_parameter("windModes", PackedVector4Array([Vector4(1, 2, 0.003, 0.4), Vector4(3, 4, 0.002, 1.2), Vector4(5, 6, 0.001, -0.5)]))
	return value

func _run() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("CPU-only adapter contract requires dummy renderer."); quit(2); return
	var water := Runtime.new()
	var first := _material(Runtime.Surface)
	var second := _material(Runtime.Surface)
	var diagnostic_shader := Shader.new()
	diagnostic_shader.code = "shader_type spatial; uniform float poolTime=0.0; uniform float sentinel=0.0; void fragment(){ALBEDO=vec3(sentinel);}"
	var diagnostic := ShaderMaterial.new(); diagnostic.shader = diagnostic_shader
	diagnostic.set_shader_parameter("sentinel", 0.61)
	water._materials = {Vector2i.ZERO: first, Vector2i(1, 0): second, Vector2i(2, 0): diagnostic}
	var wind_before: PackedVector4Array = first.get_shader_parameter("windModes").duplicate()
	_check("default_original_shader_exact_resource", first.shader == Runtime.Surface and not water.reference_wave_status().requested)
	water.set_reference_wave_settings({"referenceWaves": true, "referenceWaveStrength": 0.7, "referenceWaveDirection": 125.0})
	_check("enable_switches_only_known_resources", first.shader == Runtime.ReferenceSurface and second.shader == Runtime.ReferenceSurface and diagnostic.shader == diagnostic_shader)
	_check("settings_do_not_rebind_source_or_caustics", water.source_surface_bind_calls == 0 and water.source_caustic_bind_calls == 0 and water.source_step_calls == 0 and water._time == 0.0)
	_check("shader_swap_preserves_original_uniform_overrides", first.get_shader_parameter("waveHeight") == 1.37 and first.get_shader_parameter("refractionStrength") == 0.77 and first.get_shader_parameter("windModes") == wind_before and first.get_shader_parameter("windOpticsActive") == 1.0 and first.render_priority == 3)
	_check("diagnostic_shader_and_values_untouched", diagnostic.shader == diagnostic_shader and diagnostic.get_shader_parameter("sentinel") == 0.61 and diagnostic.get_shader_parameter("referenceWavesActive") == null)
	water._process(0.1)
	_check("unconfigured_source_does_not_advance_reference", water.reference_wave_status().elapsed == 0.0 and water.source_process_calls == 1)
	water._configured = true
	water._process(0.1)
	_check("not_ready_source_does_not_advance_reference", water.reference_wave_status().elapsed == 0.0 and water.source_step_calls == 0)
	water.pump_completes_ready = true
	water._process(0.1)
	_check("ready_during_base_pump_advances_same_frame", is_equal_approx(water.reference_wave_status().elapsed, 0.1) and water.source_step_calls == 1)
	_check("three_materials_advance_phase_once", water.reference_wave_status().clock_updates == 1 and water.source_surface_bind_calls == 3)
	_check("both_surfaces_publish_identical_current_phase", first.get_shader_parameter("referenceWaveModes") == water.reference_waves.modes and second.get_shader_parameter("referenceWaveModes") == water.reference_waves.modes and first.get_shader_parameter("referenceWavesActive") == 1.0)
	for frame in 10: water._process(1.0 / 60.0)
	_check("original_loop_called_once_per_process", water.source_process_calls == 13 and water.source_step_calls == 11)
	_check("phase_tracks_source_without_duplicate_time", is_equal_approx(water.reference_wave_status().elapsed, water._time) and is_equal_approx(water.wind_elapsed, water._time) and water.reference_wave_status().clock_updates == 11)
	var elapsed_before: float = water.reference_wave_status().elapsed
	var clock_before: int = water.reference_wave_status().clock_updates
	for publication in 5: water._apply_surface(first)
	_check("quality_or_repeated_surface_publication_does_not_tick", water.reference_wave_status().elapsed == elapsed_before and water.reference_wave_status().clock_updates == clock_before)
	water._terrain_paused = true
	water._process(0.5)
	_check("paused_source_does_not_tick", water.reference_wave_status().elapsed == elapsed_before)
	var phase_before: PackedFloat64Array = water.reference_waves.phases.duplicate()
	var binds_before: int = water.source_surface_bind_calls
	water.set_reference_wave_settings({"referenceWaves": false})
	_check("off_while_paused_restores_exact_original_resources", first.shader == Runtime.Surface and second.shader == Runtime.Surface)
	_check("off_retains_phases_and_numeric_preferences", water.reference_waves.phases == phase_before and water.reference_waves.target.referenceWaveStrength == 0.7 and water.reference_waves.target.referenceWaveDirection == 125.0)
	_check("off_never_rebinds_base_or_caustics", water.source_surface_bind_calls == binds_before and water.source_caustic_bind_calls == 0)
	_check("off_original_water_and_wind_values_exact", first.get_shader_parameter("waveHeight") == 1.37 and first.get_shader_parameter("refractionStrength") == 0.77 and first.get_shader_parameter("windModes") == wind_before and first.render_priority == 3)
	water._terrain_paused = false; water.enabled = false
	water._process(0.5)
	_check("disabled_water_does_not_tick", water.reference_wave_status().elapsed == elapsed_before)
	water.enabled = true; water._terrain_ready = false; water.pump_completes_ready = false
	water._process(0.5)
	_check("later_not_ready_water_does_not_tick", water.reference_wave_status().elapsed == elapsed_before)
	water._terrain_ready = true
	water._process(0.1)
	_check("off_keeps_phase_running_without_shader_effect", water.reference_waves.phases != phase_before and first.shader == Runtime.Surface)
	water.set_reference_wave_settings({"referenceWaves": true})
	var streamed := _material(Runtime.Surface)
	water._materials[Vector2i(3, 0)] = streamed
	clock_before = water.reference_wave_status().clock_updates
	water._apply_surface(streamed)
	_check("streamed_surface_gets_current_reference_settings", streamed.shader == Runtime.ReferenceSurface and streamed.get_shader_parameter("referenceWaveModes") == water.reference_waves.modes)
	_check("new_room_publication_does_not_advance_time", water.reference_wave_status().clock_updates == clock_before)
	water.set_reference_wave_settings({"referenceWaveStrength": 0.0})
	_check("zero_strength_restores_original_shader", first.shader == Runtime.Surface and streamed.shader == Runtime.Surface)
	water.set_reference_wave_settings({"referenceWaveStrength": 0.7})
	water.mobile_optimized = true
	elapsed_before = water.reference_wave_status().elapsed
	water._process(0.1)
	_check("mobile_guard_restores_original_and_never_ticks", first.shader == Runtime.Surface and water.reference_wave_status().elapsed == elapsed_before)
	water.mobile_optimized = false
	water._process(0.1)
	_check("mobile_interval_is_not_replayed_on_desktop", is_equal_approx(water.reference_wave_status().elapsed, elapsed_before + 0.1))
	water._materials.clear()
	elapsed_before = water.reference_wave_status().elapsed
	clock_before = water.reference_wave_status().clock_updates
	water._process(0.1)
	_check("zero_material_source_frame_still_advances_once", is_equal_approx(water.reference_wave_status().elapsed, elapsed_before + 0.1) and water.reference_wave_status().clock_updates == clock_before + 1)
	water._materials[Vector2i.ZERO] = first
	water._disposed = true
	water.set_reference_wave_settings({"referenceWaves": true})
	_check("disposed_adapter_cannot_reactivate_optional_shader", first.shader == Runtime.Surface)
	water.free()
	print("REFERENCE_ADAPTER_CONTRACT ", JSON.stringify({"passed": errors.is_empty(), "checks": checks, "errors": errors,
		"engine": Engine.get_version_info().string, "gpu_run": false,
		"scope": "Actual adapter and ShaderMaterial state against an isolated lifecycle double. Static guards protect the production source/runtime order. Not a source solver run or GPU/visual acceptance."}))
	quit(0 if errors.is_empty() else 1)
