extends SceneTree
## Actual production dependency compilation and cold, unconfigured adapter state.
## No configure(), world creation, solver step, GPU resource setup, or imports.
const Runtime = preload("res://scripts/reference_wing/reference_water_runtime.gd")

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or RenderingServer.get_rendering_device() != null:
		push_error("Headless dummy renderer required."); quit(2); return
	var water := Runtime.new()
	var solver_before: RefCounted = water.solver
	var caustics_before: RefCounted = water.caustics
	var source_settings: Dictionary = water.settings.duplicate(true)
	var wind_target: Dictionary = water.wind_waves.target.duplicate(true)
	var material := ShaderMaterial.new(); material.shader = Runtime.Surface
	material.set_shader_parameter("waveHeight", 1.37)
	water._materials[Vector2i.ZERO] = material
	water.set_reference_wave_settings({"referenceWaves": true, "referenceWaveStrength": 0.7})
	var enabled_ok := material.shader == Runtime.ReferenceSurface
	water._process(0.1) # Original base returns immediately because unconfigured.
	water.set_reference_wave_settings({"referenceWaves": false})
	var checks := {
		"actual_adapter_and_dependency_scripts_compile": is_instance_valid(water) and water.get_script() == Runtime,
		"actual_enable_changes_only_known_surface": enabled_ok,
		"actual_off_restores_original_shader_and_uniform": material.shader == Runtime.Surface and material.get_shader_parameter("waveHeight") == 1.37,
		"actual_unconfigured_base_never_advances": water._time == 0.0 and water.reference_waves.elapsed == 0.0,
		"actual_original_solver_caustics_instances_unchanged": water.solver == solver_before and water.caustics == caustics_before,
		"actual_source_and_wind_settings_unchanged": water.settings == source_settings and water.wind_waves.target == wind_target,
		"actual_source_not_configured": not water._configured and not water.solver.is_ready and not water.caustics._initialized,
	}
	var passed := true
	for value: bool in checks.values(): passed = passed and value
	water.free()
	print("REFERENCE_PRODUCTION_PARSE ", JSON.stringify({"passed": passed, "checks": checks, "engine": Engine.get_version_info().string, "gpu_run": false,
		"scope": "Actual production adapter dependency compilation and unconfigured CPU state only. No solver configure/step, graph import, GPU shader compilation, or visual test."}))
	quit(0 if passed else 1)
