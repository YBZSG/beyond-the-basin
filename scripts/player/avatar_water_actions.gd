class_name AvatarWaterActions
extends RefCounted
## Physics-authored action time; render sampling never advances an action clock.
## Visual weights only. This class cannot move the player or a held rigid body.

const ACTION_CLIPS: Array[String] = ["SwimIdle", "JumpRise", "JumpAir", "Land", "ThrowCharge", "ThrowRelease", "ThrowRecover"]
var state: Dictionary = {}
var epoch: int = -1
var swim_forward: float = 0.0
var air_weight: float = 0.0
var landing_weight: float = 0.0
var throw_weight: float = 0.0
var throw_kind: String = "none"
var throw_time: float = 0.0
var last_release_serial: int = 0
var accepted_release_events: int = 0

func reset(value: int) -> void:
	epoch = value
	swim_forward = 0.0
	air_weight = 0.0
	landing_weight = 0.0
	throw_weight = 0.0
	throw_kind = "none"
	throw_time = 0.0
	last_release_serial = 0
	state.clear()

func integrate(sample: Dictionary, delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta): return
	var next_epoch: int = int(sample.get("epoch", 0))
	if next_epoch != epoch:
		reset(next_epoch)
		# A warp/pause carries the controller serial, not a fresh release event.
		last_release_serial = int(sample.get("throw_release_serial", 0))
	state = sample.duplicate()
	var enabled: bool = bool(sample.get("enabled", true))
	var swimming: bool = bool(sample.get("swimming", false))
	var grounded: bool = bool(sample.get("grounded", true))
	var holding: bool = bool(sample.get("held", false))
	var input: Vector2 = sample.get("move_input", Vector2.ZERO)
	var speed: float = maxf(0.0, float(sample.get("move_speed", 0.0)))
	# Reverse/side motion and carrying use upright sculling, not backward breaststroke.
	var forward_intent: float = clampf(-input.y, 0.0, 1.0)
	var stroke_goal: float = smoothstep(0.12, 0.95, speed) * forward_intent if swimming and not holding else 0.0
	var clearance: float = clampf(float(sample.get("swim_stroke_clearance", 1.0)), 0.0, 1.0)
	stroke_goal *= clearance
	# A voluntary stop eases from the glide into tread rather than snapping
	# extended arms upright. A nearby wall retains the faster protective fold.
	var stroke_rate: float = 8.0 if clearance < 0.99 else (4.0 if stroke_goal < swim_forward else 6.0)
	var response: float = 1.0 - exp(-stroke_rate * delta)
	swim_forward = lerpf(swim_forward, stroke_goal if enabled else swim_forward, response)
	var climbing: bool = str(sample.get("mode", "")) in ["climb", "ladder"]
	var air_goal: float = 1.0 if enabled and not swimming and not grounded and not climbing else 0.0
	air_weight = lerpf(air_weight, air_goal, 1.0 - exp(-18.0 * delta))
	var landing_age: float = float(sample.get("landing_age", 99.0))
	var impact: float = maxf(0.0, float(sample.get("landing_impulse", 0.0)))
	landing_weight = clampf(impact / 4.0, 0.0, 1.0) * (1.0 - smoothstep(0.20, 0.30, landing_age)) if grounded and not swimming and landing_age >= 0.0 and landing_age < 0.30 else 0.0
	throw_kind = str(sample.get("throw_phase", "none"))
	var release_age: float = maxf(0.0, float(sample.get("throw_release_age", 99.0)))
	var serial: int = int(sample.get("throw_release_serial", 0))
	if serial > last_release_serial:
		accepted_release_events += 1
		last_release_serial = serial
	var goal: float = 0.0
	match throw_kind:
		"charging":
			throw_time = clampf(float(sample.get("throw_charge", 0.0)), 0.0, 1.0) * 0.45
			goal = 1.0 if holding else 0.0
		"release":
			throw_time = clampf(release_age, 0.0, 0.25)
			goal = 1.0
		"recover":
			throw_time = clampf(release_age - 0.25, 0.0, 0.35)
			goal = 1.0 - smoothstep(0.15, 0.35, throw_time)
		_:
			throw_time = 0.0
	# No pre-release delay. Existing physical release remains authoritative.
	throw_weight = lerpf(throw_weight, goal, 1.0 - exp(-24.0 * delta))
	if not enabled: return # Sampled state may freeze, but no event ages are fabricated.

func sample_times() -> Dictionary:
	var age: float = maxf(0.0, float(state.get("airborne_age", 0.0)))
	var rise: float = 1.0 - smoothstep(0.16, 0.25, age)
	return {
		"swim_phase": fposmod(float(state.get("stroke_phase", 0.0)), 1.0),
		"swim_forward": swim_forward,
		"air_weight": air_weight,
		"air_rise": rise,
		"jump_rise_time": minf(age, 0.25),
		"jump_air_phase": fposmod(age / 0.60, 1.0),
		"landing_time": clampf(float(state.get("landing_age", 0.0)), 0.0, 0.30),
		"landing_weight": landing_weight,
		"throw_kind": throw_kind,
		"throw_time": throw_time,
		"throw_weight": throw_weight,
		"release_serial": last_release_serial,
		"release_events": accepted_release_events,
		"physics_time": float(state.get("time", 0.0)),
		"render_clock_advances": 0,
	}
