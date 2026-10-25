extends "res://scripts/player/avatar_hand_ik.gd"
## Uses the proven visual-only solver, with an independent rig and palm adapter.
const Rig = preload("res://scripts/player/ithappy_rig.gd")
var _rig_reason: String = "not_set_up"

func setup(skeleton: Skeleton3D) -> void:
	_rig_reason = Rig.validate(skeleton)
	if _rig_reason != "ready":
		super.setup(null)
		return
	super.setup(skeleton)
	for arm: Dictionary in _arms:
		var side: String = "L" if int(arm.side) == 1 else "R"
		var geometry: Dictionary = Rig.palm_geometry(skeleton, side)
		var rest: Transform3D = geometry.hand
		var normal: Vector3 = geometry.normal
		var longitudinal: Vector3 = geometry.long
		# BVH raycast on this source body's rest mesh: origin at 68% of
		# wrist→Middle1, inward ray surface distance 28.987 mm (L).
		# These are this asset's bone-local measured anchors, never original-rig
		# wrist constants. See source_provenance/ithappy/ for export provenance.
		var local := Vector3(-0.0194578264, 0.0762481764, 0.0029789258) if side == "L" else Vector3(0.0194578264, 0.0762481764, 0.0029789258)
		arm.palm_local = local
		arm.palm_offset = local.length()
		arm.palm_frame = _frame(rest.basis.inverse() * longitudinal, rest.basis.inverse() * normal)

func apply(held: RigidBody3D, avatar_basis: Basis, weight: float, delta: float) -> Dictionary:
	var result: Dictionary = super.apply(held, avatar_basis, weight, delta)
	result["rig_profile"] = "ithappy_44"
	result["rig_reason"] = _rig_reason
	return result

func _target(arm: Dictionary, basis: Basis, center: Vector3, radius: float) -> Dictionary:
	var result: Dictionary = super._target(arm, basis, center, radius)
	# The short stylized forearms otherwise meet a horizontal palm with a ~73°
	# bend in the near carry pose. Tilt fingers upward along the contact tangent;
	# the actual prop support point and inward surface normal are unchanged.
	var normal: Vector3 = (result.hand_basis as Basis) * (arm.palm_frame as Basis).z
	var forward_up: Vector3 = -basis.z + basis.y * 0.8
	var tangent: Vector3 = (forward_up - normal * forward_up.dot(normal)).normalized()
	var hand_basis: Basis = _frame(tangent, normal) * (arm.palm_frame as Basis).inverse()
	result.hand_basis = hand_basis
	result.wrist = (result.palm as Vector3) - hand_basis * (arm.palm_local as Vector3)
	return result
