extends Node3D
## Unified-preview-only host. Owns real eye targeting, never story/station state.
const Session = preload("res://scripts/unified/interactions/environment_session.gd")
const Lamp = preload("res://scripts/unified/interactions/inspection_lamp.gd")
const LAMP_ID := "maintenance/north_inspection"
const MAX_DISTANCE := 2.2
const AIM_DOT := 0.965925826 # 15 degrees
var session := Session.new()
var lamp: Node3D
var _playable := false
var _down := false
var _disposed := false
var _operations := 0

func install(materials: RefCounted) -> void:
	assert(lamp == null and not _disposed)
	var registered: bool = session.register_item(LAMP_ID,"lamp")
	assert(registered)
	if not registered: return
	lamp = Lamp.new()
	lamp.name = "WallInspectionLamp"
	lamp.interaction_id = LAMP_ID
	lamp.hardware_material = materials.get_material("metal")
	lamp.wall_mount_positive_z = true
	# Backplate touches north wall inner face (-11.2), hardware projects into room.
	lamp.position = Vector3(46.5,0.4,-11.165)
	add_child(lamp)
	_apply_snapshot()
	set_playable(false)

func set_playable(value: bool) -> void:
	value = value and not _disposed
	_playable = value
	if not value: _down = false
	session.set_playable(value)
	if is_instance_valid(lamp): lamp.set_playable(value)

func advance(delta: float, playable: bool) -> void:
	set_playable(playable)
	session.advance(delta)

func target_point() -> Vector3:
	return lamp.to_global(Vector3(0,1.135,.075))

func target_visible(camera: Camera3D, excluded: Array[RID] = []) -> bool:
	if _disposed or not is_instance_valid(lamp) or not is_instance_valid(camera): return false
	if not is_inside_tree() or not camera.is_inside_tree(): return false
	var start := camera.global_position
	var target := target_point()
	var offset := target-start
	var distance := offset.length()
	if distance < .05 or distance > MAX_DISTANCE: return false
	if (-camera.global_basis.z).normalized().dot(offset/distance) < AIM_DOT: return false
	# Target is a noncolliding lever in free air. Any actual solid/prop before it blocks.
	var query := PhysicsRayQueryParameters3D.create(start,target,1 | 2,excluded)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func handle_event(event: InputEvent, camera: Camera3D, excluded: Array[RID] = []) -> bool:
	if event.is_action_released("interact"):
		_down = false
		return false
	if not _playable or not event.is_action_pressed("interact"): return false
	if event is InputEventKey and event.echo: return false
	if not target_visible(camera,excluded): return false
	# Consume the valid hardware press even during cooldown; never also grab/tap.
	if not _down:
		_down = true
		if session.operate(LAMP_ID):
			_operations += 1
			_apply_snapshot()
	return true

func hint(camera: Camera3D, excluded: Array[RID] = []) -> String:
	if not _playable or not target_visible(camera,excluded): return ""
	return "E 检修灯：关 / 左照 / 右照（不影响通行）"

func _apply_snapshot() -> void:
	if is_instance_valid(lamp): lamp.apply_state(session.values(),session.observation_values(),true)

func export_session() -> Dictionary:
	return session.export_session()

func restore_session(data: Dictionary) -> bool:
	# Always remain paused after restore, including rejected snapshots.
	set_playable(false)
	var accepted := session.import_session(data)
	if accepted: _apply_snapshot()
	return accepted

func diagnostics() -> Dictionary:
	return {"playable":_playable,"disposed":_disposed,"operations":_operations,
		"session":session.diagnostics(),"lamp":lamp.diagnostics() if is_instance_valid(lamp) else {},
		"presence_actor_count":0,"file_writes":0}

func dispose() -> void:
	if _disposed: return
	set_playable(false)
	_disposed = true
	if is_instance_valid(lamp):
		remove_child(lamp)
		lamp.queue_free()
	lamp = null

func _exit_tree() -> void:
	dispose()
