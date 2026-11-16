extends RigidBody3D
## Real dry-pit ball. Deliberately independent of source water/prop active sets.
var radius := 0.16
var prop_kind := "ball"
var display_name := "彩色小球"
var held := false
var promoted := false
var hold_target := Vector3.ZERO
var ball_id := 0
var last_push_msec := -1000
var player: CharacterBody3D
var _shape: SphereShape3D

func configure(id: int, ball_radius: float, shared_mesh: Mesh, material: Material) -> void:
	ball_id = id; radius = ball_radius
	mass = 0.35
	collision_layer = 2; collision_mask = 1 | 2 | 4
	can_sleep = true
	linear_damp = 0.8; angular_damp = 0.8
	var surface := PhysicsMaterial.new()
	surface.friction = 0.45; surface.bounce = 0.12
	physics_material_override = surface
	_shape = SphereShape3D.new(); _shape.radius = radius
	var collider := CollisionShape3D.new(); collider.shape = _shape; add_child(collider)
	var visual := MeshInstance3D.new(); visual.mesh = shared_mesh
	visual.material_override = material
	visual.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	add_to_group("pool_interactable")
	add_to_group("dream_physical_ball")

func _ready() -> void:
	set_physics_process(held)

func set_held(value: bool) -> void:
	held = value; promoted = promoted or value
	set_physics_process(value)
	gravity_scale = 0.0 if value else 1.0
	continuous_cd = value or linear_velocity.length() > 3.0
	sleeping = false
	if value:
		hold_target = global_position
		linear_velocity = Vector3.ZERO; angular_velocity = Vector3.ZERO

func set_hold_target(target: Vector3) -> void:
	if target.is_finite(): hold_target = target

func launch(direction: Vector3, speed: float) -> void:
	set_held(false)
	continuous_cd = true
	linear_velocity = direction.normalized() * clampf(speed, 0.0, 14.0) + Vector3.UP * 0.6

func _physics_process(delta: float) -> void:
	# Only the single held ball runs script physics. All unheld balls use the
	# native solver with no per-body GDScript integration callback.
	if not held: return
	var displacement := hold_target - global_position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape; query.transform = global_transform
	query.collision_mask = 1 | 2
	query.exclude = [get_rid()]
	query.margin = 0.001
	var space := get_world_3d().direct_space_state
	# Casts ignore initial overlap: explicitly refuse to servo out through a wall.
	var inner := SphereShape3D.new(); inner.radius = maxf(0.05, radius-0.02)
	query.shape = inner; query.collision_mask = 1
	if not space.intersect_shape(query, 1).is_empty():
		apply_central_force(-linear_velocity * mass / maxf(delta,0.001))
		return
	# A3 experimental geometry guard. Native casts ignore initial contacts.
	# Preserve the architecture-inner query; enumerate ALL initial ball contacts.
	var contacts: Dictionary = _initial_contacts(space, query)
	if not contacts.ok:
		displacement = Vector3.ZERO
	else:
		query.shape = _shape; query.collision_mask = 1 | 2
		query.motion = displacement
		var fraction := space.cast_motion(query)
		if fraction.size() == 2:
			var requested: Vector3 = displacement
			displacement *= maxf(0.0, fraction[0] - 0.01)
			# Certify the actual clipped direct command, even when native safe=1.
			var direct_safe: bool = _segment_allowed(contacts.rows, displacement, false, query.margin)
			if not direct_safe: displacement = Vector3.ZERO
			var lateral := Vector2(requested.x,requested.z)
			if (fraction[0] < 1.0 or not direct_safe) and requested.y > 0.0 and lateral.length_squared() > query.margin*query.margin:
				query.collision_mask = 1
				var architecture := space.cast_motion(query)
				# New dynamic recovery requires wholly clear architecture. Keep old
				# architecture-leading recovery only for an actually blocked cast.
				if architecture.size() == 2 and (architecture[0] == 1.0 or (fraction[0] < 1.0 and architecture[0] < 1.0 and architecture[0] <= fraction[0])):
					query.shape = _shape; query.transform = global_transform
					query.collision_mask = 1 | 2
					query.motion = Vector3.UP * minf(requested.y,radius*2.0)
					var upward := space.cast_motion(query)
					if upward.size() == 2 and upward[0] == 1.0:
						var lift: Vector3 = query.motion * maxf(0.0,upward[0]-0.01)
						# Whole native leg AND analytic segment must clear; actual .99
						# endpoint must leave every initially reported sphere contact.
						if _segment_allowed(contacts.rows, query.motion, true, query.margin) and lift.y > displacement.y:
							displacement = lift
		else:
			# Missing native result is not evidence of a safe path.
			displacement = Vector3.ZERO
	var desired_velocity := (displacement * 12.0).limit_length(6.0)
	apply_central_force((desired_velocity-linear_velocity).limit_length(12.0)*mass/maxf(delta,0.001))
	angular_velocity *= 0.8

func _exit_tree() -> void:
	# Children leave before the pit parent; release while this transform is valid.
	if is_instance_valid(player) and player.get("held") == self:
		player.release_prop()

# Trial policy values, NOT claims about Jolt's contact tolerance.
const CONTACT_DEPTH_TRIAL := 0.002
const CONTACT_EPSILON := 0.00001
const RIGID_BASIS_EPSILON := 0.00001
const CONTACT_LIMIT := 16

func _rigid_basis(b: Basis) -> bool:
	if not b.is_finite(): return false
	return absf(b.x.length_squared()-1.0) <= RIGID_BASIS_EPSILON and absf(b.y.length_squared()-1.0) <= RIGID_BASIS_EPSILON and absf(b.z.length_squared()-1.0) <= RIGID_BASIS_EPSILON and absf(b.x.dot(b.y)) <= RIGID_BASIS_EPSILON and absf(b.x.dot(b.z)) <= RIGID_BASIS_EPSILON and absf(b.y.dot(b.z)) <= RIGID_BASIS_EPSILON and absf(b.determinant()-1.0) <= RIGID_BASIS_EPSILON

func _sphere_record(body: Object, hit_index: int) -> Dictionary:
	# One actual active sphere only. Unknown/multiple/scaled/sheared shapes fail.
	if not is_instance_valid(body) or not body is RigidBody3D:
		return {"ok":false,"reason":"not_rigid_sphere","reads":0}
	var collider := body as RigidBody3D
	var owners: PackedInt32Array = collider.get_shape_owners()
	if owners.size() != 1: return {"ok":false,"reason":"owner_count","reads":1}
	var owner: int = owners[0]
	if collider.is_shape_owner_disabled(owner): return {"ok":false,"reason":"disabled","reads":2}
	if collider.shape_owner_get_shape_count(owner) != 1: return {"ok":false,"reason":"shape_count","reads":3}
	var shape: Shape3D = collider.shape_owner_get_shape(owner,0)
	if not shape is SphereShape3D: return {"ok":false,"reason":"unknown_shape","reads":4}
	var shape_index: int = collider.shape_owner_get_shape_index(owner,0)
	if hit_index >= 0 and shape_index != hit_index: return {"ok":false,"reason":"shape_index","reads":5}
	var local: Transform3D = collider.shape_owner_get_transform(owner)
	var body_transform: Transform3D = collider.global_transform
	var world: Transform3D = body_transform * local
	var actual_radius: float = (shape as SphereShape3D).radius
	if not world.is_finite() or not _rigid_basis(body_transform.basis) or not _rigid_basis(local.basis) or not _rigid_basis(world.basis) or not is_finite(actual_radius) or actual_radius <= 0.0:
		return {"ok":false,"reason":"invalid_rigid_transform_or_radius","reads":8}
	# Our existing native queries use the configured shape at body transform.
	# Do not silently support a modified held collider with different geometry.
	if collider == self and (shape != _shape or local != Transform3D.IDENTITY):
		return {"ok":false,"reason":"held_shape_binding","reads":8}
	return {"ok":true,"center":world.origin,"radius":actual_radius,"shape_index":shape_index,"reads":8}

func _initial_contacts(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var own: Dictionary = _sphere_record(self,-1)
	if not own.ok: return {"ok":false,"reason":own.reason,"rows":[]}
	query.shape = _shape; query.collision_mask = 2; query.motion = Vector3.ZERO
	# An extra sentinel makes any saturated/truncated collection a refusal.
	var hits: Array[Dictionary] = space.intersect_shape(query, CONTACT_LIMIT+1)
	if hits.size() > CONTACT_LIMIT: return {"ok":false,"reason":"contact_capacity","rows":[]}
	var rows: Array[Dictionary] = []
	for hit: Dictionary in hits:
		if not hit.has("collider") or not hit.has("shape") or int(hit.shape) < 0:
			return {"ok":false,"reason":"invalid_hit_metadata","rows":rows}
		var other: Dictionary = _sphere_record(hit.get("collider"),int(hit.get("shape",-1)))
		if not other.ok: return {"ok":false,"reason":other.reason,"rows":rows}
		var q: Vector3 = own.center - other.center
		var x: float = q.x; var y: float = q.y; var z: float = q.z
		var d0: float = sqrt(x*x+y*y+z*z)
		var combined_radius: float = float(own.radius) + float(other.radius)
		rows.append({"q":q,"distance":d0,"radius_sum":combined_radius,"center":other.center,"radius":other.radius})
		if combined_radius-d0 > CONTACT_DEPTH_TRIAL+CONTACT_EPSILON:
			return {"ok":false,"reason":"deep_contact","rows":rows}
	return {"ok":true,"reason":"complete","rows":rows}

func _segment_allowed(rows: Array, motion: Vector3, require_exit: bool, margin: float) -> bool:
	if not motion.is_finite(): return false
	var ux: float = motion.x; var uy: float = motion.y; var uz: float = motion.z
	var length_squared: float = ux*ux+uy*uy+uz*uz
	for row: Dictionary in rows:
		var q: Vector3 = row.q
		var x: float = q.x; var y: float = q.y; var z: float = q.z
		var t: float = clampf(-(x*ux+y*uy+z*uz)/length_squared,0.0,1.0) if length_squared > 0.0 else 0.0
		var mx: float = x+t*ux; var my: float = y+t*uy; var mz: float = z+t*uz
		if sqrt(mx*mx+my*my+mz*mz) < float(row.distance)-CONTACT_EPSILON: return false
		if require_exit:
			var ex: float = x+ux*.99; var ey: float = y+uy*.99; var ez: float = z+uz*.99
			if sqrt(ex*ex+ey*ey+ez*ez) < float(row.radius_sum)+margin+CONTACT_EPSILON: return false
	return true
