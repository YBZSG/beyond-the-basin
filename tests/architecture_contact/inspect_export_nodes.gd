extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var packed:PackedScene=load("res://assets/models/poolrooms_wing/vaulted_lanes.glb")
	var room:Node3D=packed.instantiate();root.add_child(room)
	for mesh:MeshInstance3D in room.find_children("*","MeshInstance3D",true,false):
		if "CenjiLaneRib" in String(mesh.name) or "PortalJamb" in String(mesh.name) or "BasinBottom" in String(mesh.name) or "Bench" in String(mesh.name): print(mesh.name," ",mesh.global_transform*mesh.mesh.get_aabb())
	room.free();quit()
