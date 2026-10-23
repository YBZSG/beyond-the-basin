class_name AvatarCarryContactCandidate
extends RefCounted
## Isolated candidate, not enabled by production code.
## Carry presentation is a target orientation, not a teleported body rotation.
## PoolPropBody's existing exponential quaternion servo supplies the transition.
## Free buoyancy, throw behavior, hold distance, prop geometry and arm IK stay intact.

static func rotation_offset(kind: String, picked_relative_basis: Basis) -> Basis:
	# The native duck faces -Z. Present its broad body/wing sides to the palms,
	# rather than occasionally asking the far hand to reach its head or beak.
	# Symmetric balls and intentionally tilted eggs retain their pickup orientation.
	return Basis.IDENTITY if kind == "duck" else picked_relative_basis

static func facing_yaw(authored_yaw: float, carry_weight: float) -> float:
	# Optional SECOND-stage candidate, evaluated separately from orientation-only.
	# Face the carried object with the torso instead of retaining a prior strafe
	# twist. This rotates the whole visual body; it never translates shoulders,
	# stretches bones, changes the camera, or overrides the authored arm solve.
	return lerp_angle(authored_yaw, 0.0, clampf(carry_weight, 0.0, 1.0))
