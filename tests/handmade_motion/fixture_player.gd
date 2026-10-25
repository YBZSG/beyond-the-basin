extends CharacterBody3D
signal locomotion_step(displacement: Vector3, delta: float)
var enabled := true
var held: RigidBody3D
var climbing: Node3D
var _swimming := false
var _in_water := false
var locomotion_epoch := 1
var locomotion_time := 0.0
var locomotion_distance := 0.0
var snapshot := {"epoch":1,"enabled":true,"mode":"ground","grounded":true,"held":false,"throw_phase":"none","release_kind":"none","move_speed":0.0,"move_input":Vector2.ZERO,"landing_age":99.0,"airborne_age":0.0,"throw_release_age":99.0,"throw_release_serial":0}
func get_action_state()->Dictionary:
	snapshot.epoch=locomotion_epoch;snapshot.time=locomotion_time;snapshot.enabled=enabled;snapshot.held=is_instance_valid(held)
	snapshot.swimming=_swimming;snapshot.in_water=_in_water
	snapshot.mode="swim" if _swimming else ("wade" if _in_water else "ground")
	return snapshot
func _water_depth(_pos:Vector3)->float:return .42 if _in_water else 0.0
func tick(delta:float,displacement:=Vector3.ZERO)->void:
	locomotion_time+=delta;locomotion_distance+=displacement.length()
	locomotion_step.emit(displacement,delta)
