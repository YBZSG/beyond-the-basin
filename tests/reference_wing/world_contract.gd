extends SceneTree
const Catalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const World=preload("res://scripts/reference_wing/reference_world.gd")
var checks: Array=[]
var host:Node3D
var world:Node3D
var seam_diagnostics:Array=[]
func check(name:String,condition:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":condition,"detail":detail})
	if not condition:push_error(name+": "+str(detail))
func _initialize()->void:call_deferred("run")
func ray(from:Vector3,to:Vector3)->Dictionary:
	return host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
func closed_seam_geometry(point:Vector3,forward:Vector3)->Dictionary:
	var axis:=0 if absf(forward.x)>.5 else 2
	var crossing:=point[axis]
	var before_end:=-INF
	var after_start:=INF
	var before_top:=0.0
	var after_top:=0.0
	for node:Node in host.find_children("*","CollisionShape3D",true,false):
		if not node.shape is BoxShape3D:continue
		var shape:BoxShape3D=node.shape
		var bounds:AABB=node.global_transform*AABB(-shape.size*.5,shape.size)
		if absf(bounds.end.y-.52)>.00001:continue
		var other:=2 if axis==0 else 0
		if point[other]<bounds.position[other] or point[other]>bounds.end[other]:continue
		if bounds.position[axis]<crossing-.001 and absf(bounds.end[axis]-crossing)<.01:
			before_end=maxf(before_end,bounds.end[axis]);before_top=bounds.end.y
		if bounds.end[axis]>crossing+.001 and absf(bounds.position[axis]-crossing)<.01:
			after_start=minf(after_start,bounds.position[axis]);after_top=bounds.end.y
	var found:=is_finite(before_end) and is_finite(after_start)
	return {"matched_boxes":found,"gap_metres":after_start-before_end if found else -999.0,
		"top_delta_metres":after_top-before_top,"closed":found and absf(after_start-before_end)<.00001 and absf(after_top-before_top)<.00001}

func run()->void:
	if DirAccess.make_dir_recursive_absolute("res://output/reference_wing/integration") != OK:
		push_error("Cannot create reference test evidence directory")
		quit(2);return
	for id:String in Catalog.IDS:
		if not load(Catalog.ROOT+id+".glb") is PackedScene:
			push_error("Reference test aborted: missing or stale imported room "+id)
			quit(2);return
	host=Node3D.new();root.add_child(host)
	world=World.new();host.add_child(world);world.expanded_mode=true
	world.initialize(250821,null);world.complete_pending_streaming()
	await physics_frame;await physics_frame
	check("five_complete_resident_rooms",world.resident_rooms.size()==5)
	var total_proxies:=0
	var total_triangles:=0
	for index in Catalog.COORDS.size():
		var coord:Vector2i=Catalog.COORDS[index]
		var layout:Dictionary=world.get_layout(coord)
		var room:Node3D=world.resident_rooms[coord]
		var statistics:Dictionary=room.get_meta("reference_geometry_stats")
		total_proxies+=int(statistics.proxies);total_triangles+=int(statistics.triangles)
		check(layout.reference_id+"_complete",world.is_room_ready(coord))
		var spawn:Vector3=world.get_spawn_position(coord)
		var floor_hit:=ray(spawn+Vector3.UP*.2,spawn-Vector3.UP*1.0)
		check(layout.reference_id+"_spawn_supported",not floor_hit.is_empty(),str(spawn))
		if not floor_hit.is_empty():check(layout.reference_id+"_spawn_gap",absf(spawn.y-floor_hit.position.y)<.13,{"spawn_y":spawn.y,"floor_y":floor_hit.position.y})
		var offset:=Vector3(coord.x*32,0,coord.y*32)
		for portal:Dictionary in layout.geometry_contract.get("portal_contracts",[]):
			if not portal.get("open",true):continue
			var direction:Vector2i={"north":Vector2i.UP,"south":Vector2i.DOWN,"east":Vector2i.RIGHT,"west":Vector2i.LEFT}[portal.side]
			var neighbor:Vector2i=coord+direction
			check(layout.reference_id+"_"+portal.side+"_has_neighbor",neighbor in Catalog.COORDS)
			var center:=Catalog.vec3(portal.center)+offset
			var forward:=Vector3(direction.x,0,direction.y)
			var right:=Vector3(-forward.z,0,forward.x)
			for lateral in [-1.1,0.0,1.1]:
				for height in [.3,1.6,2.5]:
					var p:Vector3=center+right*lateral+Vector3.UP*height
					var hit:=ray(p-forward*.8,p+forward*.8)
					check(layout.reference_id+"_"+portal.side+"_clear_"+str(lateral)+"_"+str(height),hit.is_empty(),str(hit.get("position",Vector3.ZERO)))
			for distance in [-.6,.0,.6]:
				var p:Vector3=center+forward*distance
				var hit:=ray(p+Vector3.UP*.2,p-Vector3.UP*.2)
				var floor_ok:=not hit.is_empty() and absf(hit.position.y-.52)<.002
				if not floor_ok and distance==0.0:
					# Jolt's zero-width ray can miss the exact coincident edge of two
					# closed boxes. Keep the raw result and inspect BOTH sides at0.1mm;
					# physical continuous crossing is separately tested with the capsule.
					var left:=ray(p-forward*.0001+Vector3.UP*.2,p-forward*.0001-Vector3.UP*.2)
					var right_hit:=ray(p+forward*.0001+Vector3.UP*.2,p+forward*.0001-Vector3.UP*.2)
					var detail:={"room":layout.reference_id,"side":portal.side,"point":str(p),"exact_ray":str(hit),"minus_0_1mm":str(left),"plus_0_1mm":str(right_hit)}
					detail["shape_joint"]=closed_seam_geometry(p,forward)
					seam_diagnostics.append(detail)
					floor_ok=bool(detail.shape_joint.closed) and not left.is_empty() and not right_hit.is_empty() and absf(left.position.y-.52)<.002 and absf(right_hit.position.y-.52)<.002
				check(layout.reference_id+"_"+portal.side+"_floor_"+str(distance),floor_ok)
		var view:=Catalog.camera(index)
		check(layout.reference_id+"_camera_finite",view.position.is_finite() and view.target.is_finite() and view.fov>20 and view.fov<130)
		world.update_player_position(spawn)
		check(layout.reference_id+"_position_selects_room",world.current_room==coord)
	check("finite_world_no_unrelated_generation",world.resident_rooms.size()==5)
	var failures:=checks.filter(func(v):return not v.ok)
	var result:={"engine":Engine.get_version_info().string,"scope":"Godot headless physics/resources only, no target RT/NR visual acceptance","checks":checks,"failures":failures.size(),"triangles":total_triangles,"proxies":total_proxies,"exact_edge_ray_diagnostics":seam_diagnostics}
	var file:=FileAccess.open("res://output/reference_wing/integration/world-contract.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("REFERENCE_WORLD_CONTRACT ",checks.size()," checks / ",failures.size()," failures / ",total_triangles," triangles / ",total_proxies," proxies")
	host.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
