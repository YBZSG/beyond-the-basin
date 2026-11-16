extends RefCounted
## Pure scene-query support; allocates no player/world/orphan Nodes.
func _objects(node: Node) -> Array[CollisionObject3D]:
	var result: Array[CollisionObject3D] = []
	if node is CollisionObject3D: result.append(node)
	for child: Node in node.get_children(): result.append_array(_objects(child))
	return result

func _body_bounds(body: CollisionObject3D, physics_delta: float) -> Dictionary:
	if not body.global_transform.is_finite(): return {"ok":false,"reason":"unknown_transform"}
	if body is RigidBody3D and (not body.angular_velocity.is_finite() or not body.angular_velocity.is_zero_approx()): return {"ok":false,"reason":"angular_motion_requires_conservative_support"}
	var bounds := AABB()
	var first := true
	for owner_id: int in body.get_shape_owners():
		if not body.shape_owner_get_transform(owner_id).is_finite(): return {"ok":false,"reason":"unknown_shape_transform"}
		for index in body.shape_owner_get_shape_count(owner_id):
			var shape: Shape3D = body.shape_owner_get_shape(owner_id,index)
			var size := Vector3.ZERO
			if shape is BoxShape3D: size = shape.size
			elif shape is CapsuleShape3D: size = Vector3(shape.radius*2,shape.height,shape.radius*2)
			elif shape is SphereShape3D: size = Vector3.ONE*shape.radius*2
			elif shape is CylinderShape3D: size = Vector3(shape.radius*2,shape.height,shape.radius*2)
			else: return {"ok":false,"reason":"unknown_shape"}
			if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0: return {"ok":false,"reason":"invalid_shape"}
			# Include disabled/layer-zero shapes: held objects must not disappear from safety.
			var b: AABB = body.global_transform*body.shape_owner_get_transform(owner_id)*AABB(-size*.5,size)
			if not b.position.is_finite() or not b.size.is_finite(): return {"ok":false,"reason":"unknown_bounds"}
			bounds = b if first else bounds.merge(b)
			first = false
	if first: return {"ok":false,"reason":"missing_shape"}
	var motion := Vector3.ZERO
	if body is CharacterBody3D: motion = body.velocity
	elif body is RigidBody3D: motion = body.linear_velocity
	if not motion.is_finite(): return {"ok":false,"reason":"unknown_velocity"}
	# Conservative two-frame forecast. Full sweep prevents door crossing an actor.
	var future := bounds
	future.position += motion*maxf(2.0/Engine.physics_ticks_per_second,2.0*physics_delta)
	var predicted := bounds.merge(future).grow(.05)
	if not predicted.position.is_finite() or not predicted.size.is_finite(): return {"ok":false,"reason":"unknown_predicted_bounds"}
	return {"ok":true,"bounds":predicted}

