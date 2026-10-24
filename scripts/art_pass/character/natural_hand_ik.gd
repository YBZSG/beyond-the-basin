extends "res://scripts/player/avatar_hand_ik.gd"
## Arm lengths, contact timing, solver and reach limits remain the shipped
## implementation. Only measured bone-local palm geometry changes with the skin.
var model_contract: Dictionary = {}

func setup(skeleton: Skeleton3D) -> void:
	super.setup(skeleton)
	if not _valid: return
	var contacts: Dictionary = model_contract.get("hand_contact", {})
	for arm: Dictionary in _arms:
		var side: String = "L" if int(arm.side) == 1 else "R"
		var row: Dictionary = contacts.get(side, {})
		if row.is_empty():
			_valid = false
			return
		var p: Array = row.palm_local_godot
		var a: Array = row.long_local_godot
		var n: Array = row.inward_local_godot
		var palm := Vector3(float(p[0]),float(p[1]),float(p[2]))
		arm.palm_local = palm
		arm.palm_offset = palm.length()
		arm.palm_frame = _frame(Vector3(float(a[0]),float(a[1]),float(a[2])),Vector3(float(n[0]),float(n[1]),float(n[2])))
