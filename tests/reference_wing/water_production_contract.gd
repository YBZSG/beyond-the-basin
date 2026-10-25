extends SceneTree
## Actual production inheritance and cold CPU state; no configure or GPU dispatch.
const Runtime = preload("res://scripts/reference_wing/reference_scene_water_runtime.gd")

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("Headless dummy renderer required."); quit(2); return
	var water := Runtime.new()
	var solver: RefCounted = water.solver
	var caustics: RefCounted = water.caustics
	var base_settings: Dictionary = water.settings.duplicate(true)
	var original_wind: Dictionary = water.wind_waves.target.duplicate(true)
	var material := ShaderMaterial.new(); material.shader = Runtime.Surface
	material.set_shader_parameter("waveHeight", 1.37)
	water._materials[Vector2i.ZERO] = material
	water.set_reference_wave_settings({"referenceWaves": true})
	var reference_enabled := material.shader == Runtime.ReferenceSurface
	water._process(0.1)
	water.set_reference_wave_settings({"referenceWaves": false})
	water.set_quality(water.quality)
	water.set_quality("NotAQuality")
	var checks := {
		"actual_new_scene_runtime_compiles": water.get_script() == Runtime,
		"actual_wave_enable_still_works": reference_enabled,
		"actual_wave_off_restores_original_shader": material.shader == Runtime.Surface and material.get_shader_parameter("waveHeight") == 1.37,
		"actual_cold_source_state_untouched": not water._configured and water._time == 0.0 and not water.solver.is_ready and not water.caustics._initialized,
		"actual_source_instances_and_parameters_unchanged": water.solver == solver and water.caustics == caustics and water.settings == base_settings and water.wind_waves.target == original_wind,
		"actual_cold_state_has_no_pending_geometry_job": not water.preparation_pending() and water._reference_depth_thread == null and water._reference_depth_jobs.is_empty(),
		"actual_same_invalid_quality_never_configures_source": water._initialization_stats.solver_configure_calls == 0,
	}
	var passed := true
	for value: bool in checks.values(): passed = passed and value
	water.free()
	print("REFERENCE_WATER_PRODUCTION ", JSON.stringify({"passed": passed, "checks": checks, "gpu_run": false,
		"scope": "Actual production scene-water subclass with real base dependencies, left unconfigured. Not a GPU solver, thread scheduler integration or visual test."}))
	quit(0 if passed else 1)
