extends RefCounted
## Deterministic desktop action telemetry. Values are gameplay tuning in metres
## and seconds, not claimed hydrodynamics. No node, camera, bone or GPU writes.
const ENTER_DEPTH: float = 1.25
const EXIT_DEPTH: float = 1.10
const ENTER_IMMERSION: float = 1.20
const EXIT_IMMERSION: float = 0.95
const ENTER_DWELL: float = 0.12
const EXIT_DWELL: float = 0.16
const FLOAT_EYE_CLEARANCE: float = 0.12
# A support-only dead band absorbs +/-5 cm crests around neck depth.
# Standing enters at <=5 cm eye clearance; swimmers exit with >=17 cm clearance.
const SUPPORTED_ENTER_IMMERSION: float = 1.55
const SUPPORTED_EXIT_IMMERSION: float = 1.43
const FLOAT_FREQUENCY: float = 5.0
const SWIM_UP_SPEED: float = 0.65
const LAND_SECONDS: float = 0.18
const RELEASE_SECONDS: float = 0.25
const RECOVER_SECONDS: float = 0.60
# Measured native swim feet reach 1.32 m behind the eye; a 1.40 m ray gives
# a small visual skin. This is a pose guard, never a collision-body substitute.
const STROKE_PROBE_RANGE: float = 1.40
const STROKE_NEAR_DISTANCE: float = 0.72
const STROKE_FULL_DISTANCE: float = 1.35
const STROKE_SAFETY_FULL_DISTANCE: float = 1.10
const STROKE_REDUCE_SECONDS: float = 0.06
const STROKE_RESTORE_SECONDS: float = 0.18

var swimming: bool = false
var terrain_deep: bool = false
var enter_age: float = 0.0
var exit_age: float = 0.0
var float_velocity: float = 0.0
var stroke_phase: float = 0.0
var jump_phase: String = "grounded"
var jump_age: float = 0.0
var airborne_age: float = 0.0
var landing_impulse: float = 0.0
var landing_age: float = -1.0
var throw_phase: String = "none"
var release_age: float = -1.0
var release_charge: float = 0.0
var release_serial: int = 0
var last_release_kind: String = "none"
var last_release_speed: float = 0.0
var stroke_clearance: float = 1.0
var stroke_wall_distance: float = STROKE_PROBE_RANGE
var clearance_queries: int = 0
var clearance_query_total: int = 0
var _clearance_valid: bool = false

func reset() -> void:
	swimming = false
	terrain_deep = false
	enter_age = 0.0
	exit_age = 0.0
	float_velocity = 0.0
	stroke_phase = 0.0
	jump_phase = "grounded"
	jump_age = 0.0
	airborne_age = 0.0
	landing_impulse = 0.0
	landing_age = -1.0
	throw_phase = "none"
	release_age = -1.0
	release_charge = 0.0
	last_release_kind = "none"
	last_release_speed = 0.0
	stroke_clearance = 1.0
	stroke_wall_distance = STROKE_PROBE_RANGE
	clearance_queries = 0
	_clearance_valid = false
	# Release serial is monotonic across warps; epoch marks discontinuities.

func sample_water(dt: float, wet: bool, depth: float, immersion: float, grounded: bool, vertical: float) -> void:
	terrain_deep = wet and (depth > EXIT_DEPTH if terrain_deep else depth >= ENTER_DEPTH)
	var supported_limit: float = SUPPORTED_EXIT_IMMERSION if swimming else SUPPORTED_ENTER_IMMERSION
	if grounded and (not wet or immersion <= supported_limit):
		# Supported shallow water wins; a submerged floor must allow surfacing.
		swimming = false
		enter_age = 0.0
		exit_age = 0.0
		float_velocity = 0.0
		return
	if swimming:
		var leaving: bool = not wet or not terrain_deep or immersion < EXIT_IMMERSION
		exit_age = exit_age + dt if leaving else 0.0
		if exit_age >= EXIT_DWELL:
			swimming = false
			enter_age = 0.0
			exit_age = 0.0
	else:
		var entering: bool = wet and terrain_deep and immersion >= ENTER_IMMERSION
		enter_age = enter_age + dt if entering else 0.0
		if enter_age + 0.000001 >= ENTER_DWELL:
			swimming = true
			float_velocity = vertical
			exit_age = 0.0


func sample_clearance(dt: float, distance: float, eligible: bool, queries: int = 0) -> void:
	clearance_queries = queries
	clearance_query_total += queries
	stroke_wall_distance = clampf(distance, 0.0, STROKE_PROBE_RANGE)
	if not eligible:
		stroke_clearance = 1.0
		_clearance_valid = false
		return
	var target: float = smoothstep(STROKE_NEAR_DISTANCE, STROKE_FULL_DISTANCE, stroke_wall_distance)
	# First eligible sample is measured immediately, especially after a warp.
	# A near-wall zero is exact, so smoothing cannot retain an unsafe stroke.
	if not _clearance_valid or stroke_wall_distance <= STROKE_NEAR_DISTANCE:
		stroke_clearance = target
	else:
		var tau: float = STROKE_REDUCE_SECONDS if target < stroke_clearance else STROKE_RESTORE_SECONDS
		stroke_clearance = lerpf(stroke_clearance, target, 1.0 - exp(-maxf(dt, 0.0) / tau))
	# A second smooth spatial cap removes the exponential tail continuously
	# before the near-wall zero, rather than snapping a residual weight away.
	var spatial_cap: float = smoothstep(STROKE_NEAR_DISTANCE, STROKE_SAFETY_FULL_DISTANCE, stroke_wall_distance)
	stroke_clearance = clampf(minf(stroke_clearance, spatial_cap), 0.0, 1.0)
	_clearance_valid = true

func float_step(root_y: float, target_y: float, dt: float) -> float:
	# Exact critically damped solution. Return the step-average velocity so that
	# move_and_slide lands at the integrated endpoint, independent of tick rate.
	if dt <= 0.0: return 0.0
	var error: float = root_y - target_y
	var c: float = float_velocity + FLOAT_FREQUENCY * error
	var decay: float = exp(-FLOAT_FREQUENCY * dt)
	var next_error: float = (error + c * dt) * decay
	float_velocity = (float_velocity - FLOAT_FREQUENCY * c * dt) * decay
	return (next_error - error) / dt

func advance(dt: float, charging: bool, move_amount: float) -> void:
	if swimming:
		stroke_phase = fposmod(stroke_phase + dt * lerpf(0.42, 0.58, clampf(move_amount, 0.0, 1.0)), 1.0)
	if landing_age >= 0.0: landing_age += dt
	if release_age >= 0.0: release_age += dt
	if charging:
		throw_phase = "charging"
	elif release_age >= 0.0 and last_release_kind == "throw" and release_age < RELEASE_SECONDS:
		throw_phase = "release"
	elif release_age >= 0.0 and last_release_kind == "throw" and release_age < RECOVER_SECONDS:
		throw_phase = "recover"
	else:
		throw_phase = "none"

func sample_jump(dt: float, was_grounded: bool, grounded: bool, vertical_before_collision: float, vertical_after: float, did_jump: bool) -> String:
	var event: String = ""
	var next_phase: String
	if swimming:
		next_phase = "swim"
		airborne_age = 0.0
	elif grounded:
		if not was_grounded and airborne_age > 0.0:
			landing_impulse = maxf(0.0, -vertical_before_collision)
			landing_age = 0.0
			event = "land"
		airborne_age = 0.0
		next_phase = "land" if landing_age >= 0.0 and landing_age < LAND_SECONDS else "grounded"
	else:
		airborne_age += dt
		if did_jump:
			next_phase = "takeoff"
			event = "jump"
		elif vertical_after > 0.15:
			next_phase = "rise"
		elif vertical_after < -0.15:
			next_phase = "fall"
		else:
			next_phase = "apex"
	jump_age = jump_age + dt if next_phase == jump_phase else 0.0
	jump_phase = next_phase
	return event

func released(charge: float, speed: float, thrown: bool) -> void:
	release_serial += 1
	release_age = 0.0
	release_charge = clampf(charge, 0.0, 1.0)
	last_release_speed = speed if thrown else 0.0
	last_release_kind = "throw" if thrown else "drop"
	throw_phase = "release" if thrown else "none"
