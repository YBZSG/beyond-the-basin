extends SceneTree
const Kit = preload("res://scripts/campaign/campaign_interactables.gd")
const KINDS := [["breaker","breaker","breaker","breaker","breaker","breaker","breaker","breaker"],["valve","valve","valve","pressure_panel"],["flow_selector","flow_selector","outlet"],["memory_tile","memory_tile","memory_tile","memory_tile","memory_tile"],["damper","vent","motor"],["shutter","mirror","drain","mirror","egress"]]
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var total_meshes := 0
	for chapter in 6:
		for index in KINDS[chapter].size():
			var spec := {"kind":KINDS[chapter][index],"index":index,"chapter":chapter,"id":"%d_%d"%[chapter,index]}
			var n: Node3D = Kit.build_station(spec); root.add_child(n)
			var meshes := n.find_children("*","MeshInstance3D",true,false)
			total_meshes += meshes.size()
			check(meshes.size()<=85,"mesh budget "+spec.id+": "+str(meshes.size()))
			check(n.find_children("*","CollisionShape3D",true,false).size()==3,"coarse collision "+spec.id)
			check(n.find_children("*","Light3D",true,false).is_empty(),"no per-station light")
			check(n.find_children("*","RigidBody3D",true,false).is_empty(),"no dynamic physics")
			check(n.find_children("*","Label3D",true,false).size()>=1,"embedded mechanical plates")
			var lamp0: Material=n.get_node("ArrivalLamp0").material_override
			var lamp1: Material=n.get_node("ArrivalLamp1").material_override
			check(lamp0!=lamp1 and lamp0!=Kit._mat("ceramic"),"private arrival materials")
			check(is_zero_approx(lamp0.emission_energy_multiplier),"neutral arrival lamp")
			check(lamp0.albedo_color.is_equal_approx(Color("344345")),"smoked neutral gives visible courtesy activation")
			var before := _transforms(n)
			var view := {"value":1,"active":true,"solved":false}
			Kit.update_station(n,spec,view)
			var after := _transforms(n)
			check(before!=after,"visible mechanical response "+spec.id)
			for i in 100: Kit.update_station(n,spec,view)
			check(after==_transforms(n),"repeatable update "+spec.id)
			check(meshes.size()==n.find_children("*","MeshInstance3D",true,false).size(),"no resource growth "+spec.id)
			check(n.find_children("*","CollisionShape3D",true,false).size()==3,"no duplicate collider after updates "+spec.id)
			Kit.update_station(n,spec,{"value":0,"active":false,"solved":false})
			check(before==_transforms(n),"recovery restores pose "+spec.id)
			for mesh: MeshInstance3D in meshes:
				var aabb := (n.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
				check(aabb.size.is_finite(),"finite geometry")
				check(aabb.position.x>=-.65-.001 and aabb.end.x<=.65+.001 and aabb.position.y>=-.001 and aabb.end.y<=1.8+.001 and aabb.position.z>=-.4-.001 and aabb.end.z<=.4+.001,"declared bounds "+spec.id+" "+str(aabb))
			n.free()
	for kind in ["repair","departure","bell","locker"]:
		var n: Node3D = Kit.build_station({"kind":kind});root.add_child(n)
		check(n.find_children("*","MeshInstance3D",true,false).size()<50,"optional budget "+kind)
		n.free()
	var panel: Node3D=Kit.build_station({"kind":"pressure_panel"}); root.add_child(panel)
	Kit.update_station(panel,{"kind":"pressure_panel"},{"readings":[3,4,5]})
	check(panel.get_node("Gauge0").rotation.z>panel.get_node("Gauge1").rotation.z and panel.get_node("Gauge1").rotation.z>panel.get_node("Gauge2").rotation.z,"coupled pressure readout ordering")
	panel.free()
	var light: Node3D=Kit.build_station({"kind":"shutter"});root.add_child(light)
	Kit.update_station(light,{"kind":"shutter"},{"stable":12.0})
	check(is_equal_approx(light.get_node("Needle").rotation.z,-2.2),"fully charged needle")
	light.free()
	var pulse: Node3D=Kit.build_station({"kind":"bell"});root.add_child(pulse)
	for i in 20: Kit.pulse_station(pulse)
	await process_frame
	var running := 0
	for tween in get_processed_tweens():
		if tween.is_running(): running+=1
	check(running<=1,"repeated action replaces feedback tween")
	await create_timer(.5).timeout
	check(pulse.get_node("Status").scale.is_equal_approx(Vector3.ONE),"interaction pulse settles without blink")
	pulse.free()
	var success: Color=Kit._mat("ready").albedo_color
	check(success.r>success.g and success.g>success.b,"success warm white not corruption green")
	print("CAMPAIGN_STATIONS ",JSON.stringify({"checks":checks,"failures":failures,"meshes_all_28":total_meshes,"shared_materials":Kit._materials.size()}))
	quit(0 if failures.is_empty() else 1)
func _transforms(n: Node3D) -> String:
	var data := []
	for child in n.find_children("*","Node3D",true,false): data.append(str(child.transform))
	return str(data)
