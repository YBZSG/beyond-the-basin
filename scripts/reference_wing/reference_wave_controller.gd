extends RefCounted
## Three crossing, slowly traveling ripples, added to the source water optical normal.
## The equivalent relief below is an analytic equivalent, NOT mesh displacement,
## a fluid solver, a caustic source, or a collision/buoyancy height change.
const Settings = preload("res://scripts/reference_wing/reference_look_settings.gd")
const WAVELENGTHS := [1.35, 0.83, 0.47]
const DIRECTION_OFFSETS := [-0.20, 0.95, -0.85]
const WEIGHTS := [0.46, 0.34, 0.20]
const TRAVEL_SPEEDS_M_S := [0.24, 0.21, 0.17]
const MAX_RELIEF_M := 0.075
const STRENGTH_EXPONENT := 1.15
var target: Dictionary = {}
var strength := 0.0
var direction := deg_to_rad(35.0)
var wavelength_scale := 1.0
var elapsed := 0.0
var phases := PackedFloat64Array([0.4, 2.1, -1.3])
var modes := PackedVector4Array()

func _init() -> void:
	for key: String in Settings.WAVE_KEYS: target[key] = Settings.DEFAULT[key]
	_build_modes()

func set_target(values: Dictionary) -> void:
	var proposed := target.duplicate()
	# Reject invalid partial edits instead of replacing them with defaults.
	for key: String in Settings.WAVE_KEYS:
		if not values.has(key): continue
		var value: Variant = values[key]
		if key == "referenceWaves":
			if value is bool: proposed[key] = value
		elif (value is int or value is float) and is_finite(float(value)):
			proposed[key] = value
	var clean := Settings.sanitize(proposed)
	for key: String in Settings.WAVE_KEYS: target[key] = clean[key]
	# Output is immediately gated by target.referenceWaves. Do not reset the
	# saved strength/scale/direction, accumulated phases, wind, or source fields.

func active() -> bool:
	return bool(target.referenceWaves) and float(target.referenceWaveStrength) > 0.0 and strength > 0.0

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var old_direction := direction
	var old_scale := wavelength_scale
	var desired: float = float(target.referenceWaveStrength) if bool(target.referenceWaves) else 0.0
	strength = lerpf(strength, desired, 1.0 - exp(-delta / 0.6))
	wavelength_scale = lerpf(wavelength_scale, float(target.referenceWaveScale), 1.0 - exp(-delta / 1.2))
	direction = lerp_angle(direction, deg_to_rad(float(target.referenceWaveDirection)), 1.0 - exp(-delta / 1.4))
	if desired == 0.0 and strength < 0.00001: strength = 0.0
	for index: int in 3:
		var old_k := _wave_vector(index, old_direction, old_scale)
		var new_k := _wave_vector(index, direction, wavelength_scale)
		var omega := 0.5 * (old_k.length() + new_k.length()) * float(TRAVEL_SPEEDS_M_S[index])
		# Phase is integrated at the fixed world origin, never at the camera.
		# Changing direction/scale interpolates the field in world coordinates;
		# walking or a solver-domain rebase cannot drag or restart these ripples.
		phases[index] = wrapf(phases[index] - omega * delta, -PI, PI)
	elapsed += delta
	_build_modes()

func _wave_vector(index: int, angle: float, scale: float) -> Vector2:
	return Vector2.from_angle(angle + float(DIRECTION_OFFSETS[index])) * (TAU / (float(WAVELENGTHS[index]) * scale))

func _build_modes() -> void:
	# Publish an immutable bounded snapshot, just as the existing wind does.
	var next_modes := PackedVector4Array()
	next_modes.resize(3)
	for index: int in 3:
		var k := _wave_vector(index, direction, wavelength_scale)
		var amplitude := MAX_RELIEF_M * pow(maxf(strength, 0.0), STRENGTH_EXPONENT) * float(WEIGHTS[index])
		next_modes[index] = Vector4(k.x, k.y, amplitude, phases[index])
	modes = next_modes

func apply_to(material: ShaderMaterial) -> void:
	if material == null: return
	material.set_shader_parameter("referenceWaveModes", modes)
	material.set_shader_parameter("referenceWavesActive", 1.0 if active() else 0.0)

func sample(world_point: Vector2, footprint: float = 0.0, depth: float = 0.44) -> Vector3:
	# CPU oracle for tests only. Gameplay never reads the GPU or samples this.
	if not active(): return Vector3.ZERO
	var height := 0.0
	var slope := Vector2.ZERO
	var shore := smoothstep(0.015, 0.12, depth)
	for mode: Vector4 in modes:
		var k := Vector2(mode.x, mode.y)
		var fade := 1.0 - smoothstep(0.7, 2.4, maxf(footprint, 0.0) * k.length())
		var amplitude := mode.z * fade * shore
		var phase := k.dot(world_point) + mode.w
		height += amplitude * sin(phase)
		slope += k * amplitude * cos(phase)
	return Vector3(height, slope.x, slope.y)

func describe() -> Dictionary:
	return {"target": target.duplicate(), "active": active(), "strength": strength,
		"direction_degrees": fposmod(rad_to_deg(direction), 360.0), "wavelength_scale": wavelength_scale,
		"elapsed": elapsed, "modes": modes, "coordinate_space": "fixed_world_xz",
		"peak_equivalent_relief_bound_m": MAX_RELIEF_M * pow(maxf(strength, 0.0), STRENGTH_EXPONENT),
		"optical_only": true, "solver_readbacks": 0, "mode_count": 3}
