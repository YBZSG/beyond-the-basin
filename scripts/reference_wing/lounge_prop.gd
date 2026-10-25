extends "res://scripts/player/pool_prop_body.gd"
## Existing carry/throw contract, with bounded sleeping physics for the dry lounge.
var simulating := false
var soft := false

func wake() -> void:
	simulating = true
	freeze = false
	sleeping = false

func set_held(value: bool) -> void:
	super.set_held(value)
	if value: wake()
	_physics_material.bounce = 0.0 if value else (0.06 if soft else 0.38)

func launch(direction: Vector3, speed: float) -> void:
	wake()
	super.launch(direction, minf(speed, 7.0) if soft else speed)

func source_integrate_active(state: PhysicsDirectBodyState3D) -> void:
	super.source_integrate_active(state)
	if not held:
		state.angular_velocity *= exp(-state.step * (3.0 if soft else 1.2))
		state.linear_velocity *= exp(-state.step * (0.35 if soft else 0.12))
