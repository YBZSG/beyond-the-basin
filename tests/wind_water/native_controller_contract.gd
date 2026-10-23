extends SceneTree
## CPU-only independent numeric/API checks. Never starts an RD or the game.
const Controller = preload("res://scripts/water/wind_wave_controller.gd")
var checks := {}
var errors: Array[String] = []
var output := "res://output/wind-water/cpu-contract.json"

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, value: bool) -> void:
	checks[name] = value
	if not value: errors.append(name)

func _settle(controller: RefCounted, seconds := 10.0, anchor := Vector2.ZERO) -> void:
	for index in ceili(seconds * 60.0): controller.advance(1.0 / 60.0, anchor)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	_check("cpu_only_no_rendering_device", DisplayServer.get_name() == "headless" and RenderingServer.get_rendering_device() == null)
	var c := Controller.new()
	var initial: Dictionary = c.describe()
	_check("default_values", is_equal_approx(initial.strength, .18) and is_equal_approx(initial.direction_degrees, 35.0) and is_equal_approx(initial.density, 1.0) and initial.target.windWaves)
	_check("explicit_optical_only_and_zero_readbacks", initial.optical_only and initial.solver_readbacks == 0)
	_check("three_analytic_modes", initial.modes.size() == 3)
	c.set_target({"windStrength": 9.0, "windDirection": 725.0, "windDensity": -4.0})
	_check("input_clamping_and_direction_wrapping", c.describe().target.windStrength == 1.0 and c.describe().target.windDirection == 5.0 and c.describe().target.windDensity == .5)
	var valid_target: Dictionary = c.describe().target
	c.set_target({"windStrength": NAN, "windDirection": INF, "windDensity": "bad", "windWaves": "false"})
	_check("malformed_values_ignored", c.describe().target == valid_target)
	var untouched: Dictionary = c.describe()
	c.advance(NAN); c.advance(INF); c.advance(-1.0); c.advance(0.0)
	_check("invalid_time_does_not_mutate_state", c.describe() == untouched)
	c = Controller.new()
	var old_modes: PackedVector4Array = c.describe().modes.duplicate()
	c.set_target({"windStrength": 1.0, "windDirection": 125.0, "windDensity": 2.0})
	_check("setting_target_does_not_jump_current_modes", c.describe().modes == old_modes)
	c.advance(1.0 / 60.0)
	var first: Dictionary = c.describe()
	_check("smooth_first_strength_step", first.strength > .18 and first.strength < .25)
	_check("smooth_first_direction_step", first.direction_degrees > 35.0 and first.direction_degrees < 40.0)
	_check("smooth_first_density_step", first.density > 1.0 and first.density < 1.03)
	var strength_previous: float = first.strength
	var monotone := true
	for index in 900:
		c.advance(1.0 / 60.0)
		var current: float = c.describe().strength
		monotone = monotone and current >= strength_previous and current <= 1.0
		strength_previous = current
	_check("strength_monotone_bounded_convergence", monotone and absf(c.describe().strength - 1.0) < .00001)
	_check("density_converges", absf(c.describe().density - 2.0) < .00001)
	_check("direction_converges", absf(c.describe().direction_degrees - 125.0) < .01)
	_check("maximum_relief_bound_6mm", c.describe().peak_relief_bound_m <= .006 + .000000001 and c.describe().peak_relief_bound_m > .005999)
	var bound_valid := true; var finite_valid := true; var derivative_error := 0.0
	for z in range(-4, 5):
		for x in range(-4, 5):
			var point := Vector2(float(x) * .071, float(z) * .053)
			var value: Vector3 = c.sample(point)
			bound_valid = bound_valid and absf(value.x) <= c.describe().peak_relief_bound_m + .00000001
			finite_valid = finite_valid and value.is_finite()
			var epsilon := .0001
			var dx: float = (c.sample(point + Vector2(epsilon, 0)).x - c.sample(point - Vector2(epsilon, 0)).x) / (2.0 * epsilon)
			var dz: float = (c.sample(point + Vector2(0, epsilon)).x - c.sample(point - Vector2(0, epsilon)).x) / (2.0 * epsilon)
			derivative_error = maxf(derivative_error, maxf(absf(dx - value.y), absf(dz - value.z)))
	_check("sampled_relief_inside_bound", bound_valid)
	_check("sampled_values_finite", finite_valid)
	_check("analytic_gradient_matches_finite_difference", derivative_error < .0002)
	checks["max_gradient_absolute_error"] = derivative_error
	_check("dry_boundary_exact_zero", c.sample(Vector2(.2, .3), 0.0, 0.0) == Vector3.ZERO)
	_check("large_footprint_fully_filtered", c.sample(Vector2(.2, .3), 1.0, .44) == Vector3.ZERO)
	var a: Vector3 = c.sample(Vector2(.2, .3)); c.advance(.15); var b: Vector3 = c.sample(Vector2(.2, .3))
	_check("time_advances_actual_analytic_wave", a.distance_to(b) > .00001)
	c.set_target({"windDirection": 350.0}); _settle(c, 20.0)
	c.set_target({"windDirection": 10.0}); c.advance(1.0 / 60.0)
	_check("direction_takes_short_wrap_path", c.describe().direction_degrees > 350.0 and c.describe().direction_degrees < 352.0)
	var t_before: float = c.describe().elapsed
	var anchor := Vector2(100.0, -50.0)
	old_modes = c.describe().modes.duplicate()
	c.set_target({"windDirection": 180.0, "windDensity": .5}); c.advance(1.0 / 60.0, anchor)
	var new_modes: PackedVector4Array = c.describe().modes
	var phase_continuity := true
	for index in 3:
		var old_k := Vector2(old_modes[index].x, old_modes[index].y)
		var new_k := Vector2(new_modes[index].x, new_modes[index].y)
		var phase_change := wrapf(new_k.dot(anchor) + new_modes[index].w - old_k.dot(anchor) - old_modes[index].w, -PI, PI)
		# At this bound every physical phase advance is small and negative; a reset
		# would give an arbitrary phase jump unrelated to the actual elapsed frame.
		phase_continuity = phase_continuity and phase_change < 0.0 and phase_change > -.5
	_check("edited_wave_vectors_preserve_anchor_phase", phase_continuity)
	_check("parameter_edits_do_not_reset_time", c.describe().elapsed > t_before)
	c.advance(1.0 / 60.0, Vector2(NAN, INF))
	_check("invalid_anchor_cannot_poison_modes", c.describe().anchor.is_finite() and c.sample(Vector2(.2, .3)).is_finite())
	var material := ShaderMaterial.new()
	var shader := Shader.new(); shader.code = "shader_type spatial; uniform vec4 windModes[3]; uniform float windOpticsActive = 0.0; void fragment(){ALBEDO=vec3(0.0);}"
	material.shader = shader; c.apply_to(material)
	_check("material_api_binds_modes_and_active", material.get_shader_parameter("windModes") == c.describe().modes and material.get_shader_parameter("windOpticsActive") == 1.0)
	var immutable_uniform_modes: PackedVector4Array = material.get_shader_parameter("windModes").duplicate()
	c.advance(.1)
	_check("later_controller_advance_cannot_mutate_bound_uniform_payload", material.get_shader_parameter("windModes") == immutable_uniform_modes)
	c.apply_to(material)
	_check("explicit_rebind_updates_uniform_payload", material.get_shader_parameter("windModes") == c.describe().modes and material.get_shader_parameter("windModes") != immutable_uniform_modes)
	c.set_target({"windWaves": false}); _settle(c)
	c.apply_to(material)
	_check("toggle_off_reaches_exact_zero", c.describe().strength == 0.0 and c.sample(Vector2(.2, .3)) == Vector3.ZERO and material.get_shader_parameter("windOpticsActive") == 0.0)
	c.set_target({"windWaves": true, "windStrength": 0.0}); _settle(c)
	_check("zero_strength_reaches_exact_zero", c.describe().strength == 0.0 and c.sample(Vector2(.2, .3)) == Vector3.ZERO)
	c.set_target({"windWaves": true, "windStrength": 1.0}); _settle(c)
	var phases_finite := true
	for index in 6000: c.advance(1.0 / 60.0, Vector2(-32.0, -32.0))
	for mode: Vector4 in c.describe().modes: phases_finite = phases_finite and mode.is_finite() and absf(mode.w) <= PI + .000001
	_check("long_run_phases_bounded_finite", phases_finite)
	_check("no_solver_readbacks_after_long_run", c.describe().solver_readbacks == 0)
	var result := {"pass": errors.is_empty(), "checks": checks, "errors": errors, "native_optical_execution": false, "scope": "Independent CPU/API/numeric controller contract; no shader render, physical wind simulation, gameplay or performance claim."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result, "  ") + "\n")
	print("WIND_CONTROLLER_CPU ", JSON.stringify(result)); quit(0 if result.pass else 1)
