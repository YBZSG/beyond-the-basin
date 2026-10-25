extends "res://scripts/art_pass/character/natural_finger_poses.gd"
## Preserve the new authored finger opening/recovery before contact curls the
## grip. Existing contact geometry and the final wrist-support solve stay final.
var supplemental_sample: Callable
func apply(delta: float, held_body: RigidBody3D, contact_weight: float, action_state: Variant={}) -> Dictionary:
	var state: Dictionary=action_state.duplicate() if action_state is Dictionary else {"state":str(action_state)}
	var extra: Dictionary=supplemental_sample.call() if supplemental_sample.is_valid() else {}
	if float(extra.get("pickup_weight",0.0))>0.0001: state.state="Pickup"
	elif float(extra.get("setdown_weight",0.0))>0.0001: state.state="SetDown"
	return super.apply(delta,held_body,contact_weight,state)
