extends Node
## Exact source nearby predicate; native Jolt contacts stay native.
## Runs after body-state synchronization, before the existing player callback.
const SOURCE_RADIUS_SQUARED := 576.0
var owns_callbacks := false
var enabled := true
var camera: Camera3D
var bodies: Array[RigidBody3D] = []
var _entries: Dictionary = {}
var selected: Array[RigidBody3D] = []
var last_force_calls := 0
var force_calls := 0
var last_error := ""

static func source_selected(point: Vector3, eye: Vector3, held: bool) -> bool:
	# Three.Vector3.distanceToSquared uses ordered binary64 scalar arithmetic.
	# Vector3 subtraction/dot would introduce binary32 intermediate rounding.
	var dx: float = float(point.x) - float(eye.x)
	var dy: float = float(point.y) - float(eye.y)
	var dz: float = float(point.z) - float(eye.z)
	return dx * dx + dy * dy + dz * dz < SOURCE_RADIUS_SQUARED or held

func configure(source_bodies: Array[RigidBody3D], view_camera: Camera3D, running: bool) -> bool:
	process_physics_priority = -1000
	if not is_instance_valid(view_camera):
		last_error = "No actual eye camera; existing callbacks retained."
		return false
	for body in source_bodies:
		if is_instance_valid(body) and (not body.has_method("source_bind_activity") or not body.has_method("source_integrate_active")):
			last_error = "Body does not implement source activity API; existing callbacks retained."
			return false
	if owns_callbacks:
		_release_all()
	bodies = source_bodies
	camera = view_camera
	enabled = running
	owns_callbacks = true
	for body in bodies:
		if is_instance_valid(body): track(body)
	return true

func track(body: RigidBody3D) -> void:
	if not owns_callbacks or not is_instance_valid(body) or _entries.has(body.get_instance_id()): return
	if not body.has_method("source_bind_activity") or not body.has_method("source_integrate_active"):
		last_error = "New body lacks source activity API."
		_release_all()
		return
	_entries[body.get_instance_id()] = {"body":weakref(body),"layer":body.collision_layer,"mask":body.collision_mask,"freeze_mode":body.freeze_mode,"inactive":false,"inactive_frame":-1,"ever_callback":int(body.source_activity_callback_frame)>=0}
	var exit_callback := _on_body_exiting.bind(body.get_instance_id())
	_entries[body.get_instance_id()]["exit_callback"] = exit_callback
	body.tree_exiting.connect(exit_callback)
	body.source_bind_activity(self)
	_set_active(body, enabled and source_selected(body.global_position,camera.global_position,bool(body.held)))

func set_enabled(value: bool) -> void:
	enabled = value
	if not owns_callbacks: return
	for body in bodies:
		if is_instance_valid(body) and _entries.has(body.get_instance_id()):
			_set_active(body, value and is_instance_valid(camera) and source_selected(body.global_position,camera.global_position,bool(body.held)))

func _set_active(body: RigidBody3D, active: bool) -> void:
	var entry: Dictionary = _entries[body.get_instance_id()]
	if active == not bool(entry.inactive): return
	# Restore explicitly after mode changes. In Jolt, static velocity is a
	# surface velocity; it must never participate in contacts while inactive.
	var linear := body.linear_velocity
	var angular := body.angular_velocity
	if active:
		body.freeze = false
		body.linear_velocity = linear
		body.angular_velocity = angular
		body.collision_layer = int(entry.layer)
		body.collision_mask = int(entry.mask)
		entry.inactive = false
	else:
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.linear_velocity = linear
		body.angular_velocity = angular
		entry.inactive = true
		entry.inactive_frame = Engine.get_physics_frames()

func _physics_process(_delta: float) -> void:
	if not owns_callbacks: return
	if not is_instance_valid(camera):
		last_error = "Eye camera was removed; existing callbacks restored."
		_release_all(true)
		return
	selected.clear()
	last_force_calls = 0
	var eye := camera.global_position
	var frame := Engine.get_physics_frames()
	for body in bodies:
		if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion(): continue
		if not _entries.has(body.get_instance_id()): track(body)
		if not owns_callbacks: return
		var entry: Dictionary = _entries[body.get_instance_id()]
		entry.ever_callback = bool(entry.ever_callback) or int(body.source_activity_callback_frame)>=0 or (bool(entry.inactive) and int(entry.inactive_frame)<frame)
		var active := enabled and source_selected(body.global_position,eye,bool(body.held))
		_set_active(body,active)
		if active and bool(entry.ever_callback): selected.append(body)
	for body in selected:
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state == null:
			last_error = "Direct state unavailable; existing callbacks restored."
			_release_all()
			return
		_invoke(body,state)

func _invoke(body: RigidBody3D, state: PhysicsDirectBodyState3D) -> void:
	body.source_activity_force_frame = Engine.get_physics_frames()
	body.source_integrate_active(state)
	# Mirror the normal post-callback transform/velocity synchronization. The
	# unchanged force routine does not set sleeping or inertia properties.
	body.set_ignore_transform_notification(true)
	body.global_transform = state.transform
	body.set_ignore_transform_notification(false)
	body.linear_velocity = state.linear_velocity
	body.angular_velocity = state.angular_velocity
	last_force_calls += 1
	force_calls += 1

func _on_body_exiting(id: int) -> void:
	# Held props are normally reparented from streamed room to collection.
	# Do not drop collision/velocity state during that temporary tree exit.
	_retire_detached.call_deferred(id)

func _retire_detached(id: int) -> void:
	if not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	var body: RigidBody3D = entry.body.get_ref()
	if is_instance_valid(body):
		if body.is_inside_tree(): return
		var linear := body.linear_velocity
		var angular := body.angular_velocity
		if body.tree_exiting.is_connected(entry.exit_callback): body.tree_exiting.disconnect(entry.exit_callback)
		body.source_bind_activity(null)
		body.freeze = not enabled
		body.freeze_mode = int(entry.freeze_mode)
		body.linear_velocity = linear
		body.angular_velocity = angular
		body.collision_layer = int(entry.layer)
		body.collision_mask = int(entry.mask)
	_entries.erase(id)

func _release_all(integrate_missing: bool = false) -> void:
	owns_callbacks = false
	var fallback_bodies: Array[RigidBody3D] = []
	var frame := Engine.get_physics_frames()
	for entry: Dictionary in _entries.values():
		var body: RigidBody3D = entry.body.get_ref()
		if not is_instance_valid(body): continue
		var linear := body.linear_velocity
		var angular := body.angular_velocity
		if body.tree_exiting.is_connected(entry.exit_callback): body.tree_exiting.disconnect(entry.exit_callback)
		body.source_bind_activity(null)
		body.freeze = not enabled
		body.freeze_mode = int(entry.freeze_mode)
		body.linear_velocity = linear
		body.angular_velocity = angular
		body.collision_layer = int(entry.layer)
		body.collision_mask = int(entry.mask)
		# On a lost camera, a body that was frozen has no queued Jolt callback.
		# Complete this tick exactly once before returning to original callbacks.
		if integrate_missing and enabled and int(body.source_activity_force_frame)!=frame and (bool(entry.ever_callback) or (bool(entry.inactive) and int(entry.inactive_frame)<frame)):
			fallback_bodies.append(body)
	_entries.clear()
	selected.clear()
	for body in fallback_bodies:
		if not body.is_inside_tree() or body.is_queued_for_deletion(): continue
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state != null: _invoke(body,state)

func _exit_tree() -> void:
	_release_all()
