extends "res://tests/poolrooms_wing/movement_contract.gd"
## Extends, never relaxes, the previous production route acceptance suite.
## Extra tests derive contact expectations from final Blender-export metadata.
const WaterField = preload("res://scripts/water/water_field.gd")
const SourceSolver = preload("res://scripts/water/source_port/source_wave_solver.gd")
const InputBridge = preload("res://tests/architecture_contact/contact_input_bridge.gd")
const ContactDriver = preload("res://tests/architecture_contact/contact_walk_driver.gd")
var output_dir := "res://output/contact-walk/contracts"
var mesh_cache: Dictionary = {}
var snapshot_colliders: Array = []
var field: RefCounted
var source_grids: Dictionary = {}

func bounds_record(record: Dictionary) -> AABB:
	return AABB(v(record.position), v(record.size))

func close_box(a: AABB, b: AABB, tolerance: float = .001) -> bool:
	return a.position.distance_to(b.position) < tolerance and a.size.distance_to(b.size) < tolerance

func mesh_named(room: Node3D, name_value: String, expected: AABB = AABB()) -> MeshInstance3D:
	# Blender export batches visible surfaces by role; Godot sanitizes decimal
	# points and gives repeated proxy names a numeric suffix. Preserve exact
	# geometry matching rather than assuming editable-source names survive.
	var imported_name:=name_value.replace(".","_")
	for mesh: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
		var actual_name:=String(mesh.name)
		if actual_name==imported_name or (expected.size!=Vector3.ZERO and actual_name.begins_with(imported_name+"_")):
			if expected.size==Vector3.ZERO or close_box(local_bounds(room,mesh),expected):return mesh
	if name_value.begins_with("COLLISION_"):
		if expected.size!=Vector3.ZERO:
			for mesh:MeshInstance3D in room.find_children("*","MeshInstance3D",true,false):
				if String(mesh.name).begins_with("COLLISION_") and close_box(local_bounds(room,mesh),expected):return mesh
		return null
	var role:=""
	if "SubmergedFooting" in name_value or "BasinBottom" in name_value:role="art_pass_tile_blue"
	elif "CenjiLaneRib" in name_value or "CommonEntryStep" in name_value:role="art_pass_tile_pearl"
	elif "PortalJamb" in name_value:role="art_pass_coping_ivory"
	if not role.is_empty():
		for mesh:MeshInstance3D in room.find_children("*","MeshInstance3D",true,false):
			if String(mesh.name)=="IntegratedRoom_"+role:return mesh
	return null

func local_bounds(room: Node3D, mesh: MeshInstance3D) -> AABB:
	return (room.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()

func mesh_ray(room: Node3D, mesh: MeshInstance3D, from: Vector3, to: Vector3) -> Variant:
	if mesh == null: return null
	var key := str(mesh.get_instance_id())
	if not mesh_cache.has(key):
		var transform := room.global_transform.affine_inverse() * mesh.global_transform
		var vertices: PackedVector3Array = mesh.mesh.get_faces()
		for i: int in vertices.size(): vertices[i] = transform * vertices[i]
		mesh_cache[key] = vertices
	var faces: PackedVector3Array = mesh_cache[key]
	var nearest: Variant = null
	var distance := INF
	for i: int in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, faces[i], faces[i+1], faces[i+2])
		if hit != null and from.distance_to(hit) < distance:
			nearest = hit
			distance = from.distance_to(hit)
	return nearest

func actual_shape_bounds(room: Node3D) -> Array:
	var boxes: Array = []
	for shape: CollisionShape3D in room.find_children("*", "CollisionShape3D", true, false):
		if not shape.shape is BoxShape3D: continue
		var transform := room.global_transform.affine_inverse() * shape.global_transform
		var box: AABB = transform * AABB(-shape.shape.size*.5, shape.shape.size)
		boxes.append(box)
	return boxes

func contains_box(boxes: Array, expected: AABB) -> bool:
	for actual: AABB in boxes:
		if close_box(actual, expected): return true
	return false

func source_grid_depth(local: Vector3, resolution: int) -> float:
	var cell := 96.0 / resolution
	var x := floori((local.x+48.0)/cell)
	var z := floori((local.z+48.0)/cell)
	return source_grids[resolution][x+z*resolution]

func contact_geometry() -> void:
	field = WaterField.new()
	for coord: Vector2i in Wing.ANCHORS:
		var room: Node3D = world.resident_rooms[coord]
		var room_name: String = Wing.FILES[Wing.ANCHORS[coord]]
		var contract: Dictionary = geometry.rooms[room_name]
		var boxes := actual_shape_bounds(room)
		var mismatches: Array = []
		var unmatched_shapes:Array=boxes.duplicate()
		var unmatched_meshes:Array=[]
		for mesh:MeshInstance3D in room.find_children("*","MeshInstance3D",true,false):
			if String(mesh.name).begins_with("COLLISION_"):unmatched_meshes.append(mesh)
		var mapping:Array=[]
		for record: Dictionary in contract.collision_boxes:
			var expected := bounds_record(record)
			var mesh_index:=-1
			var shape_index:=-1
			for i:int in unmatched_meshes.size():
				if close_box(local_bounds(room,unmatched_meshes[i]),expected):mesh_index=i;break
			for i:int in unmatched_shapes.size():
				if close_box(unmatched_shapes[i],expected):shape_index=i;break
			if mesh_index<0 or shape_index<0:mismatches.append(record.name)
			if mesh_index>=0:
				mapping.append({"authored_name":record.name,"imported_name":String(unmatched_meshes[mesh_index].name),"position":vec(expected.position),"size":vec(expected.size)})
				unmatched_meshes.remove_at(mesh_index)
			if shape_index>=0:unmatched_shapes.remove_at(shape_index)
		add(room_name+"_all_exported_proxy_meshes_match_actual_box_shapes",mismatches.is_empty() and unmatched_shapes.is_empty() and unmatched_meshes.is_empty(), {"exported_proxy_count":contract.collision_boxes.size(),"actual_box_count":boxes.size(),"mismatches":mismatches,"unmatched_shapes":unmatched_shapes.size(),"unmatched_meshes":unmatched_meshes.size(),"exact_bounds_multiset_mapping":mapping,"matching":"Consume one actual exported proxy mesh and one actual production collision shape per metadata AABB; duplicate source names never overwrite keys.","tolerance_metres":.001})
		var jamb_failures:Array=[]
		var jamb_checks:Array=[]
		for bearing:Dictionary in contract.get("portal_jamb_bearings",[]):
			var probe:=v(bearing.tread_contact_probe)
			var jamb_mesh:=mesh_named(room,bearing.object)
			var underside:Variant=mesh_ray(room,jamb_mesh,probe-Vector3.UP*.2,probe+Vector3.UP*.2)
			var receiver:Variant=null
			for step_record:Dictionary in contract.collision_boxes:
				if "CommonEntryStep" not in step_record.name:continue
				var step_mesh:=mesh_named(room,String(step_record.name).trim_prefix("COLLISION_"))
				var hit:Variant=mesh_ray(room,step_mesh,probe+Vector3.UP*.2,probe-Vector3.UP*.2)
				if hit!=null:receiver=hit;break
			var joined:bool=underside!=null and receiver!=null
			if joined:joined=absf(underside.y-receiver.y)<.001 and absf(underside.y-float(bearing.bottom_y))<.001
			if not joined:jamb_failures.append(bearing.object)
			jamb_checks.append({"object":bearing.object,"jamb_bottom":vec(underside) if underside!=null else [],"tread_top":vec(receiver) if receiver!=null else [],"pass":joined})
		add(room_name+"_eight_actual_portal_jamb_lips_seat_on_entry_tread",jamb_failures.is_empty() and jamb_checks.size()==8,{"checks":jamb_checks,"failures":jamb_failures})
		if coord != Vector2i.UP: continue
		var layout: Dictionary = room.get_meta("layout")
		snapshot_colliders = []
		for box: AABB in boxes: snapshot_colliders.append({"center":box.get_center(),"half":box.size*.5})
		for resolution: int in [384,768]: source_grids[resolution]=SourceSolver.build_depth_data(snapshot_colliders,resolution,96.0)
		var obstacles: Dictionary = {}
		for obstacle: Dictionary in contract.water_obstacles: obstacles[obstacle.collision]=obstacle
		var checked := 0
		for bearing: Dictionary in contract.architecture_bearings:
			var shaft: Dictionary = obstacles[bearing.pier_collision]
			var footing: Dictionary = obstacles["COLLISION_"+bearing.receiving_surface]
			var shaft_box := bounds_record(shaft)
			var foot_box := bounds_record(footing)
			var shaft_mesh := mesh_named(room,bearing.object)
			var foot_mesh := mesh_named(room,bearing.receiving_surface)
			var label: String = bearing.object+"_"+str(bearing.side)
			var centre := shaft_box.get_center()
			var underside: Variant = mesh_ray(room,shaft_mesh,Vector3(centre.x,-.6,centre.z),Vector3(centre.x,.4,centre.z))
			var footing_top: Variant = mesh_ray(room,foot_mesh,Vector3(centre.x,.2,centre.z),Vector3(centre.x,-.5,centre.z))
			var footing_bottom: Variant = mesh_ray(room,foot_mesh,Vector3(centre.x,-.6,centre.z),Vector3(centre.x,-.1,centre.z))
			var actual_floor: Variant = null
			for floor_record: Dictionary in contract.collision_boxes:
				if "BasinBottom" not in floor_record.name: continue
				var floor_mesh := mesh_named(room,String(floor_record.name).trim_prefix("COLLISION_"))
				var hit: Variant = mesh_ray(room,floor_mesh,Vector3(centre.x,-.1,centre.z),Vector3(centre.x,-.6,centre.z))
				if hit != null: actual_floor=hit
			var supported: bool = underside!=null and footing_top!=null and footing_bottom!=null and actual_floor!=null
			if supported:
				supported = absf(underside.y-footing_top.y)<.001 and footing_bottom.y<actual_floor.y-.05 and actual_floor.y<footing_top.y and absf(actual_floor.y-float(contract.basin_floor_y))<.001
			add(label+"_visible_triangle_floor_footing_shaft_contact",supported,{"visible_shaft_bottom":vec(underside) if underside!=null else [],"visible_footing_top":vec(footing_top) if footing_top!=null else [],"visible_footing_bottom":vec(footing_bottom) if footing_bottom!=null else [],"visible_floor_top":vec(actual_floor) if actual_floor!=null else [],"tolerance_metres":.001})
			# Side face correspondence is tested below the old .52m floating tip.
			var outer_side: float = float(bearing.side)
			var side_from := Vector3(centre.x+outer_side*1.5,.08,centre.z)
			var side_to := Vector3(centre.x,.08,centre.z)
			var side_hit: Variant=mesh_ray(room,shaft_mesh,side_from,side_to)
			var expected_side: float=shaft_box.end.x if outer_side>0 else shaft_box.position.x
			var foot_side_hit:Variant=mesh_ray(room,foot_mesh,Vector3((foot_box.end.x if outer_side>0 else foot_box.position.x)+outer_side*.04,-.1,centre.z),Vector3(centre.x,-.1,centre.z))
			var expected_foot_side:float=foot_box.end.x if outer_side>0 else foot_box.position.x
			add(label+"_submerged_visible_shaft_matches_solid",side_hit!=null and absf(side_hit.x-expected_side)<.001 and foot_side_hit!=null and absf(foot_side_hit.x-expected_foot_side)<.001 and contains_box(boxes,shaft_box) and contains_box(boxes,foot_box),{"visible_side_hit":vec(side_hit) if side_hit!=null else [],"collision_side_x":expected_side,"visible_footing_side":vec(foot_side_hit) if foot_side_hit!=null else [],"collision_footing_side_x":expected_foot_side})
			var shaft_point := Vector2(centre.x,centre.z)
			# Sample the actual outer exposed footing lip, not the solid shaft.
			var lip_x: float = (foot_box.end.x+shaft_box.end.x)*.5 if outer_side>0 else (foot_box.position.x+shaft_box.position.x)*.5
			var lip := Vector2(lip_x,centre.z)
			var adjacent := Vector2(foot_box.end.x+.2 if outer_side>0 else foot_box.position.x-.2,centre.z+1.0 if centre.z<0 else centre.z-1.0)
			var grid_report: Array=[]
			var source_mask_ok:=true
			for resolution: int in [384,768]:
				var shaft_depth:=source_grid_depth(centre,resolution)
				source_mask_ok=source_mask_ok and is_zero_approx(shaft_depth)
				grid_report.append({"resolution":resolution,"cell_metres":96.0/resolution,"shaft_depth":shaft_depth,"sampled_lip_depth":source_grid_depth(Vector3(lip.x,0,lip.y),resolution),"note":"The .14 m lip is smaller than a Medium .25 m cell; the sampled grid lip can be omitted or quantized to the neighbouring solid. Continuous authored depth is tested separately."})
			var continuous_ok: bool=is_zero_approx(field._rest_depth(shaft_point,layout)) and absf(field._rest_depth(lip,layout)-(.32-foot_box.end.y))<.001 and absf(field._rest_depth(adjacent,layout)-float(contract.basin_depth_metres))<.001
			add(label+"_water_exclusion_and_submerged_footing_depth",continuous_ok and source_mask_ok,{"shaft_depth":field._rest_depth(shaft_point,layout),"exposed_lip_depth":field._rest_depth(lip,layout),"adjacent_basin_depth":field._rest_depth(adjacent,layout),"source_solver_depth_from_actual_shapes":grid_report})
			checked+=1
		add("all_eight_repaired_submerged_piers_tested",checked==8,{"count":checked})

func shared_wall_neighbor_support() -> void:
	for coord:Vector2i in Wing.ANCHORS:
		for offset:Vector2i in [Vector2i.UP,Vector2i.LEFT]:world.ensure_room_ready(coord+offset)
	await tick(3)
	for coord:Vector2i in Wing.ANCHORS:
		var room:Node3D=world.resident_rooms[coord]
		var room_name:String=Wing.FILES[Wing.ANCHORS[coord]]
		var excluded:Array[RID]=[]
		for body:StaticBody3D in room.find_children("*","StaticBody3D",true,false):excluded.append(body.get_rid())
		for wall:Dictionary in geometry.rooms[room_name].collision_boxes:
			if not ("OuterNorth_" in wall.name or "OuterWest_" in wall.name):continue
			var north:bool="OuterNorth_" in wall.name
			var box:=bounds_record(wall)
			var neighbor:Vector2i=coord+(Vector2i.UP if north else Vector2i.LEFT)
			var p:=box.get_center()
			if north:p.z=-16.15
			else:p.x=-16.15
			p+=origin(coord)
			var from:=Vector3(p.x,.62,p.z)
			var to:=Vector3(p.x,box.position.y-.2,p.z)
			var query:=PhysicsRayQueryParameters3D.create(from,to,1,excluded)
			var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
			var floor_box:=AABB()
			var actual_neighbor:=Vector2i(9999,9999)
			if not hit.is_empty():
				var collider:CollisionObject3D=hit.collider
				var parent_room:Node=collider.get_parent()
				if parent_room.has_meta("coord"):actual_neighbor=parent_room.get_meta("coord")
				var owner_id:int=collider.shape_find_owner(hit.shape)
				var shape:CollisionShape3D=collider.shape_owner_get_owner(owner_id)
				if shape.shape is BoxShape3D:floor_box=shape.global_transform*AABB(-shape.shape.size*.5,shape.shape.size)
			var passed:bool=not hit.is_empty() and actual_neighbor==neighbor and floor_box.position.y<=box.position.y+.001 and floor_box.end.y>=box.position.y-.001
			add(room_name+"_"+wall.name+"_actual_neighbor_floor_bears_outboard_wall",passed,{"actual_neighbor":str(actual_neighbor),"expected_neighbor":str(neighbor),"room_ready":world.is_room_ready(neighbor),"ray_from":vec(from),"ray_to":vec(to),"neighbor_floor_hit":vec(hit.position) if not hit.is_empty() else [],"wall_base_y":box.position.y,"floor_shape_bottom_y":floor_box.position.y,"floor_shape_top_y":floor_box.end.y,"query":"Production-built adjoining room physics, architecture mask 1; current room excluded; no water or synthetic translated mesh."})

func pier_approaches() -> void:
	var coord := Vector2i.UP
	var contract: Dictionary=geometry.rooms.vaulted_lanes
	var obstacles: Dictionary={}
	for obstacle: Dictionary in contract.water_obstacles: obstacles[obstacle.collision]=obstacle
	for bearing: Dictionary in contract.architecture_bearings:
		var shaft:=bounds_record(obstacles[bearing.pier_collision])
		var centre:=shaft.get_center()
		var side:float=bearing.side
		# Outer-side approach starts in genuine water away from deck and stairs.
		var start:=point(coord,centre.x+side*1.5,0.0,centre.z)
		start.y=.32-sampler.depth_at(start)+.02
		await warp(start)
		var first:=player.position
		trace=[]
		var blocked:Dictionary=await travel(point(coord,centre.x,-.22,centre.z),4.0)
		var edge:float=shaft.end.x if side>0 else shaft.position.x
		var separation:float=(player.position.x-origin(coord).x-edge)*side
		var state:Dictionary=player.get_action_state()
		var contact_ok:bool=not blocked.reached and blocked.wall_ticks>0 and separation>=Player.BODY_RADIUS-.025 and separation<Player.BODY_RADIUS+.075 and player.position.distance_to(first)>.5 and player.is_on_floor() and state.in_water and not state.swimming and player.position.y>=-.25 and player.position.y<.12
		var retreat:Dictionary=await travel(start,6.0)
		add(bearing.object+"_"+str(bearing.side)+"_physical_water_approach_block_and_return",contact_ok and retreat.reached,{"approach":blocked,"capsule_to_visible_side_metres":separation,"retreat":retreat,"trace":trace})

func continuous_route() -> void:
	await warp(point(Vector2i.UP,-4,.54,-10))
	player.set_physics_process(true)
	var driver=ContactDriver.new()
	driver.player=player
	driver.room_origin=origin(Vector2i.UP)
	root.add_child(driver)
	driver.start()
	while not driver.completed: await physics_frame
	player.set_physics_process(false)
	add("native_fixture_route_continuous_actual_controller",driver.errors.is_empty(),driver.result())
	driver.queue_free()
	await process_frame

func manual_input_path() -> void:
	var bridge:=InputBridge.new();bridge.player=player;root.add_child(bridge)
	var old_yaw:float=player.rotation.y
	var old_pitch:float=player.camera.rotation.x
	player.enabled=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var capture_supported:bool=Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
	var mouse:=InputEventMouseMotion.new();mouse.relative=Vector2(10,5)
	Input.parse_input_event(mouse)
	await process_frame
	var looked:bool=absf(player.rotation.y-old_yaw)>.005 and absf(player.camera.rotation.x-old_pitch)>.002
	var event:=InputEventKey.new();event.physical_keycode=KEY_SPACE;event.keycode=KEY_SPACE;event.pressed=true
	if InputMap.action_get_events("jump").is_empty():InputMap.action_add_event("jump",event)
	Input.parse_input_event(event)
	await process_frame
	var jumped:bool=player._jump_buffer>0.0
	event=InputEventKey.new();event.physical_keycode=KEY_ESCAPE;event.keycode=KEY_ESCAPE;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	var released:bool=not player.enabled and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	Input.parse_input_event(click)
	await process_frame
	var resumed:bool=player.enabled
	add("interactive_root_input_bridge_delivers_mouse_jump_escape_resume",(looked or not capture_supported) and jumped and released and resumed and bridge.delivered_events>=4,{"mouse_look":looked,"captured_mouse_supported":capture_supported,"mouse_look_scope":"Actual captured mouse required only when display backend supports capture; headless bridge event delivery still checked","jump_buffer":jumped,"escape_releases":released,"click_resumes":resumed,"events_delivered":bridge.delivered_events})
	bridge.queue_free();Input.action_release("jump");player._jump_buffer=0.0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await process_frame

func _run() -> void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_dir=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	geometry=JSON.parse_string(FileAccess.get_file_as_string("res://source_provenance/poolrooms_wing/geometry.json"))
	for action:String in ["move_left","move_right","move_forward","move_back","sprint","jump","throw_prop","grab_prop","interact","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		Input.action_release(action)
	world=World.new();world.poolrooms_mode=true;world.expanded_mode=true;world.stream_radius=0
	root.add_child(world);world.initialize(250821,null);world.set_process(false)
	for coord:Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.LEFT]:world.ensure_room_ready(coord)
	sampler=AuthoredDepthSampler.new();sampler.world=world;root.add_child(sampler)
	player=Player.new();root.add_child(player);player.set_physics_process(false);player.set_water(sampler)
	player.enabled=true;player.water_motion_actions_enabled=true;player.depth_wading_response_enabled=true
	tall_capsule=CapsuleShape3D.new();tall_capsule.radius=.32;tall_capsule.height=2.0
	await tick(3)
	contact_geometry()
	await shared_wall_neighbor_support()
	await pier_approaches()
	await continuous_route()
	# Re-run the existing complete three-room perimeter, four portals per room,
	# basin stairs, circular gateway and all four between-room threshold routes.
	for coord:Vector2i in Wing.ANCHORS: await room_routes(coord)
	await gateway_routes();await threshold_routes()
	await manual_input_path()
	var hashes:Dictionary={}
	for name:String in Wing.FILES:hashes[name+".glb"]=FileAccess.get_sha256("res://assets/models/poolrooms_wing/"+name+".glb")
	for path:String in ["scripts/player/pool_player.gd","scripts/world/room_builder.gd","scripts/world/expanded_room_builder.gd","scripts/poolrooms_wing/geometry_contract.gd","source_provenance/poolrooms_wing/geometry.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	var report:Dictionary={"pass":errors.is_empty(),"errors":errors,"checks":reports,"engine":Engine.get_version_info(),"physics_hz":120,"source_sha256":hashes,"scope":"Actual final exported visible mesh triangles, hidden BOX proxy meshes, production BoxShape3D physics, production source solver CPU depth preparation, unchanged real PoolPlayer controller. Existing route thresholds unchanged. Controlled authored water sampler for locomotion only; not GPU water/render/performance acceptance.","routes":"All three authored room regressions plus eight submerged pier approaches and one continuous no-warp native-fixture route."}
	FileAccess.open(output_dir.path_join("contact-contract.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ARCHITECTURE_CONTACT_RESULT ",JSON.stringify({"pass":errors.is_empty(),"cases":reports.size(),"errors":errors}))
	player.free();sampler.free();world.free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
