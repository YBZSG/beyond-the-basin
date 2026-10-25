extends "res://scripts/player/pool_player.gd"
## Reference-wing-only adapter. Do not replace the source controller
## for ordinary worlds. This preserves the source path before a guarded fallback.
var lounge_interactions: Node

func pick_prop() -> RigidBody3D:
	if is_instance_valid(lounge_interactions) and camera != null:
		var body: RigidBody3D = lounge_interactions.pick_prop(camera, get_rid(), PICK_DISTANCE)
		if body != null: return body
	return super.pick_prop()

func grab_prop(body: RigidBody3D) -> void:
	super.grab_prop(body)
	if is_instance_valid(held) and str(held.prop_kind) == "cushion": held_distance = 1.1

func _try_step(delta: float, was_grounded: bool) -> bool:
	if super._try_step(delta, was_grounded):
		return true
	if not was_grounded or velocity.y > 0.1:
		return false
	var travel := Vector3(velocity.x, 0.0, velocity.z) * delta
	if travel.length_squared() < 0.0000001:
		return false
	var wall_hit := KinematicCollision3D.new()
	# move_and_slide can block on a recovery-only stair-corner contact which the
	# source's ordinary horizontal test does not report. Match the body's margin
	# and expose recovery contacts, only after the original step attempt failed.
	if not test_move(global_transform, travel, wall_hit, safe_margin, true):
		return false
	if wall_hit.get_normal().y > 0.5:
		return false
	var probe: Vector3 = global_position + travel.normalized() * (BODY_RADIUS + travel.length() + 0.03)
	var query := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * (STEP_HEIGHT + 0.02), probe + Vector3.DOWN * 0.02, 1, [get_rid()])
	var landing: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if landing.is_empty() or (landing["normal"] as Vector3).y < cos(floor_max_angle):
		return false
	var elevation: float = (landing["position"] as Vector3).y - global_position.y + safe_margin
	if elevation < 0.005 or elevation > STEP_HEIGHT + 0.005:
		return false
	var raised: Transform3D = global_transform
	if test_move(raised, Vector3.UP * elevation):
		return false
	raised.origin.y += elevation
	if test_move(raised, travel):
		return false
	raised.origin += travel
	_step_eye_offset -= elevation
	_step_snap_pause = 0.16
	global_position = raised.origin
	return true
