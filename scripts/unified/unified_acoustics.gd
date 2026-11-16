extends Node
## Optional single-writer lease over an existing footsteps reverb.
## Host calls update_at from a pausable process; never call set_room during lease.
const OWNER_KEY := &"unified_acoustics_owner"
const KEYS := [&"room_size", &"wet"]
var _effect: AudioEffectReverb
var _bus: StringName
var _original := Vector2.ZERO
var _last := Vector2.ZERO
var status := "inactive"

static func target_at(point: Vector3) -> Vector2:
	# First/second threshold centers; 4 m blend on each side of a door.
	var entry := smoothstep(28.5, 36.5, point.x)
	var exit_weight := smoothstep(56.5, 64.5, point.x)
	return Vector2(0.60, 0.090).lerp(Vector2(0.36, 0.060), entry).lerp(Vector2(0.58, 0.085), exit_weight)

func acquire(bus_name: StringName = &"Footsteps") -> bool:
	release()
	if not is_inside_tree():
		status = "host_not_in_tree"
		return false
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0 or AudioServer.get_bus_effect_count(index) == 0:
		status = "missing_bus_or_effect"
		return false
	var candidate := AudioServer.get_bus_effect(index, 0) as AudioEffectReverb
	if candidate == null or not AudioServer.is_bus_effect_enabled(index, 0) or AudioServer.is_bus_bypassing_effects(index):
		status = "unavailable_effect"
		return false
	if candidate.has_meta(OWNER_KEY):
		status = "already_owned"
		return false
	_effect = candidate
	_bus = bus_name
	_original = Vector2(_effect.room_size, _effect.wet)
	_last = _original
	_effect.set_meta(OWNER_KEY, get_instance_id())
	status = "active"
	return true

func update_at(point: Vector3, delta: float, paused: bool = false) -> void:
	if _effect == null: return
	if not _lease_valid():
		release()
		status = "yielded_external_change"
		return
	if paused or (is_inside_tree() and get_tree().paused): return
	if not point.is_finite() or not is_finite(delta) or delta <= 0.0: return
	# No catch-up jump after a stalled frame or pause; no timers/accumulator.
	var weight := 1.0 - exp(-minf(delta, 0.1) / 0.35)
	_last = _last.lerp(target_at(point), weight)
	_effect.room_size = _last.x
	_effect.wet = _last.y

func _lease_valid() -> bool:
	if _effect.get_meta(OWNER_KEY, 0) != get_instance_id(): return false
	var index := AudioServer.get_bus_index(_bus)
	if index < 0 or AudioServer.get_bus_effect_count(index) == 0: return false
	if AudioServer.get_bus_effect(index, 0) != _effect: return false
	if not AudioServer.is_bus_effect_enabled(index, 0) or AudioServer.is_bus_bypassing_effects(index): return false
	return is_equal_approx(_effect.room_size, _last.x) and is_equal_approx(_effect.wet, _last.y)

func release() -> void:
	if _effect != null and _effect.get_meta(OWNER_KEY, 0) == get_instance_id():
		# Restore only values still ours, never clobber a newer external writer.
		if is_equal_approx(_effect.room_size, _last.x): _effect.room_size = _original.x
		if is_equal_approx(_effect.wet, _last.y): _effect.wet = _original.y
		_effect.remove_meta(OWNER_KEY)
	_effect = null
	status = "inactive"

func _exit_tree() -> void:
	release()
