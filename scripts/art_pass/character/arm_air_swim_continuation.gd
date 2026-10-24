extends RefCounted
## Finite eight-arm Air->Swim continuation only. No gameplay or source-clock writes.
## Same tested formula and event policy; graph placement supplies action authority.
const BONES: Array[String] = ["Shoulder_L", "Shoulder_R", "UpperArm_L", "UpperArm_R", "Forearm_L", "Forearm_R", "Hand_L", "Hand_R"]
# Three original 9/s swim-blend time constants; ends with the graph 95% settled.
const DURATION: float = 1.0 / 3.0
# Reuse the source AirBlend response to decay outgoing angular velocity.
const AIR_RESPONSE: float = 18.0
var _epoch: int = -1
var _previous_state: Dictionary = {}
var _last_pose: Dictionary = {}
var _earlier_pose: Dictionary = {}
var _last_time: float = -1.0
var _earlier_time: float = -1.0
var _pending_time: float = -1.0
var _event_time: float = -1.0
var _origin_time: float = -1.0
var _origin_pose: Dictionary = {}
var _origin_velocity: Dictionary = {}
var debug: Dictionary = {"active":false,"events":0,"cancelled_for_authority":0}

func observe(state: Dictionary) -> void:
	var epoch: int = int(state.get("epoch", 0))
	if epoch != _epoch:
		_epoch = epoch
		_previous_state.clear()
		_last_pose.clear(); _earlier_pose.clear()
		_last_time = -1.0; _earlier_time = -1.0
		_pending_time = -1.0; _event_time = -1.0
		_origin_pose.clear(); _origin_velocity.clear()
	if not _previous_state.is_empty():
		var was_air: bool = not bool(_previous_state.get("swimming", false)) and not bool(_previous_state.get("grounded", true)) and not str(_previous_state.get("mode", "")) in ["climb", "ladder"]
		if was_air and bool(state.get("swimming", false)) and bool(state.get("enabled", true)):
			_pending_time = float(state.get("time", 0.0))
	_previous_state = state.duplicate()

func _rotation_vector(value: Quaternion) -> Vector3:
	var q: Quaternion = value.normalized()
	if q.w < 0.0: q = -q
	var axis := Vector3(q.x, q.y, q.z)
	var length: float = axis.length()
	return axis * (2.0 * atan2(length, maxf(0.0, q.w)) / length) if length > 0.0000001 else axis * 2.0

func _rotation_exp(value: Vector3) -> Quaternion:
	var angle: float = value.length()
	return Quaternion(value / angle, angle) if angle > 0.0000001 else Quaternion(value.x * 0.5, value.y * 0.5, value.z * 0.5, 1.0).normalized()

func prepare(state: Dictionary, hold_weight: float, throw_weight: float) -> Dictionary:
	debug.active = false
	var now: float = float(state.get("time", 0.0))
	var eligible_start: bool = bool(state.get("enabled", true)) and not bool(state.get("held", false)) and str(state.get("throw_phase", "none")) == "none" and hold_weight < 0.01 and throw_weight < 0.01 and not str(state.get("mode", "")) in ["climb", "ladder"]
	if _pending_time >= 0.0:
		if eligible_start and not _last_pose.is_empty():
			_event_time = _pending_time
			_origin_time = _last_time
			_origin_pose = _last_pose.duplicate()
			_origin_velocity.clear()
			var interval: float = _last_time - _earlier_time
			for name: String in _origin_pose:
				var velocity := Vector3.ZERO
				if interval > 0.000001 and _earlier_pose.has(name): velocity = _rotation_vector(_last_pose[name] * _earlier_pose[name].inverse()) / interval
				_origin_velocity[name] = velocity
			debug.events = int(debug.events) + 1
		_pending_time = -1.0
	if _event_time < 0.0: return {"weight":0.0,"rotations":{}}
	var age: float = maxf(0.0,now-_event_time)
	if age >= DURATION:
		_event_time = -1.0
		return {"weight":0.0,"rotations":{}}
	var u: float = age/DURATION
	var target_weight: float = u*u*u*(10.0+u*(-15.0+6.0*u))
	var extrapolation: float = maxf(0.0,_event_time-_origin_time)+(1.0-exp(-AIR_RESPONSE*age))/AIR_RESPONSE
	var rotations: Dictionary = {}
	for name: String in _origin_pose: rotations[name] = (_rotation_exp(_origin_velocity[name]*extrapolation)*_origin_pose[name]).normalized()
	debug.active = true
	debug.age = age
	debug.target_weight = target_weight
	debug.authority = "original Climb/Hold/Throw graph, then original release transition and IK"
	return {"weight":1.0-target_weight,"rotations":rotations}

func capture(skeleton: Skeleton3D, state: Dictionary) -> void:
	var now: float = float(state.get("time", 0.0))
	if now < _last_time: return
	if now > _last_time + 0.000001:
		_earlier_pose = _last_pose
		_earlier_time = _last_time
	_last_pose = {}
	_last_time = now
	for name: String in BONES:
		var bone: int = skeleton.find_bone(name)
		if bone >= 0: _last_pose[name] = skeleton.get_bone_pose_rotation(bone)
