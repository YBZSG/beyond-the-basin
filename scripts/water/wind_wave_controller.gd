extends RefCounted
## Bounded analytic optical wind ripples. This is not a wind-force fluid solver.
## No GPU reads, textures, queues, physical depth edits or solver dependencies.
const DEFAULT := {"windWaves":true,"windStrength":0.18,"windDirection":35.0,"windDensity":1.0}
const WAVELENGTHS := [0.48, 0.23, 0.115]
const DIRECTION_OFFSETS := [-0.14, 0.27, -0.43]
const WEIGHTS := [0.62, 0.26, 0.12]
const MAX_RELIEF_M := 0.006
const STRENGTH_EXPONENT := 1.23 # ~0.73mm at default; stronger response only toward high end.
const GRAVITY := 9.81
const CAPILLARY := 0.0000728
const PHASE_RATE := 0.45 # Art-directed slow indoor motion, not a physical wind prediction.
var target: Dictionary = DEFAULT.duplicate()
var strength := 0.18
var direction := deg_to_rad(35.0)
var density := 1.0
var elapsed := 0.0
var phases := PackedFloat64Array([0.0, 1.7, -2.183185307179586])
var modes := PackedVector4Array()
var _last_anchor := Vector2.ZERO

func _init() -> void:
	_build_modes()

func set_target(values: Dictionary) -> void:
	for key: String in DEFAULT:
		if not values.has(key): continue
		var value: Variant = values[key]
		if key == "windWaves":
			if value is bool: target[key] = value
		elif (value is int or value is float) and is_finite(float(value)):
			match key:
				"windStrength": target[key] = clampf(float(value), 0.0, 1.0)
				"windDirection": target[key] = fposmod(float(value), 360.0)
				"windDensity": target[key] = clampf(float(value), 0.5, 2.0)

func advance(delta: float, world_anchor: Vector2 = Vector2.ZERO) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	if not world_anchor.is_finite(): world_anchor = _last_anchor
	var previous_strength := strength
	var previous_density := density
	var previous_direction := direction
	var desired_strength: float = float(target.windStrength) if bool(target.windWaves) else 0.0
	strength = lerpf(strength, desired_strength, 1.0 - exp(-delta / 0.45))
	density = lerpf(density, float(target.windDensity), 1.0 - exp(-delta / 1.2))
	direction = lerp_angle(direction, deg_to_rad(float(target.windDirection)), 1.0 - exp(-delta / 1.4))
	if desired_strength == 0.0 and strength < 0.00001: strength = 0.0
	for i: int in 3:
		var old_k := _wave_vector(i, previous_direction, previous_density)
		var new_k := _wave_vector(i, direction, density)
		# A parameter edit morphs wave vectors continuously around the player.
		# Compensating the phase keeps that anchor continuous; it never resets time.
		var omega := 0.5 * (_omega(old_k.length(), previous_strength) + _omega(new_k.length(), strength))
		phases[i] = wrapf(phases[i] - omega * delta - (new_k - old_k).dot(world_anchor), -PI, PI)
	elapsed += delta
	_last_anchor = world_anchor
	_build_modes()

func _wave_vector(index: int, angle: float, scale: float) -> Vector2:
	return Vector2.from_angle(angle + float(DIRECTION_OFFSETS[index])) * (TAU * scale / float(WAVELENGTHS[index]))

func _omega(k: float, force: float) -> float:
	return sqrt(GRAVITY * k + CAPILLARY * k * k * k) * PHASE_RATE * (0.72 + 0.28 * force)

func _build_modes() -> void:
	# Godot retains PackedArray references in material parameters. Publish a
	# fresh bounded 3-mode snapshot; never mutate a previously submitted uniform.
	var next_modes := PackedVector4Array()
	next_modes.resize(3)
	for i: int in 3:
		var k := _wave_vector(i, direction, density)
		var amplitude := MAX_RELIEF_M * pow(maxf(strength, 0.0), STRENGTH_EXPONENT) * float(WEIGHTS[i])
		next_modes[i] = Vector4(k.x, k.y, amplitude, phases[i])
	modes = next_modes

func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("windModes", modes)
	material.set_shader_parameter("windOpticsActive", 1.0 if strength > 0.0 else 0.0)

func sample(world_point: Vector2, footprint: float = 0.0, depth: float = 0.44) -> Vector3:
	# CPU oracle for tests only. Runtime rendering uses the identical GLSL function.
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
	return {"target":target.duplicate(),"strength":strength,"direction_degrees":fposmod(rad_to_deg(direction),360.0),"density":density,"elapsed":elapsed,"modes":modes,"peak_relief_bound_m":MAX_RELIEF_M * pow(maxf(strength,0.0),STRENGTH_EXPONENT),"optical_only":true,"solver_readbacks":0,"anchor":_last_anchor}
