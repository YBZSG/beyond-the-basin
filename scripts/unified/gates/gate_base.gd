extends Node3D
## Visible supported hinged gate. No invisible blocker or teleport.
const LEAF_SIZE := Vector3(.12,2.55,2.20)
const LEAF_CENTER := Vector3(0,1.295,1.10)
const ANGULAR_SPEED := .8 # rad/s; about 1.96 s for the 90-degree heavy leaf.
var ramp_visual: MeshInstance3D
var ramp_collision: CollisionShape3D
var operating_hardware: Array[MeshInstance3D] = []
var stops := StaticBody3D.new()
var stop_pairs: Array = []
var frame_visuals: Array[MeshInstance3D] = []
var frame_pairs: Array = []
var corridor_sign := 1.0
var leaf_visual: MeshInstance3D
var header_visual: MeshInstance3D
var hinge := Node3D.new()
var body := StaticBody3D.new()
var leaf_shape := CollisionShape3D.new()
var angle := 0.0
var open_angle := 0.0
var goal := 0.0
var state := "CLOSED"
var last_motion_frame := -1
var sweep := AABB()
var blocked_count := 0
var motion_seconds := 0.0
var motion_wall_seconds := 0.0
var _motion_started_usec := 0
var _closed_transform := Transform3D.IDENTITY
var _authored_transform := Transform3D.IDENTITY

func configure(x: float, direction: float) -> void:
	position = Vector3(x,.4,-11.10)
	open_angle = direction*PI*.5
	corridor_sign = -direction
	# Steel jambs connect real deck to ceiling; hinge knuckles meet leaf/jamb.
	for z in [-.15,2.35]: frame_visuals.append(_box(self,Vector3(0,1.35,z),Vector3(.16,2.7,.10),Color("656e69")))
	header_visual = _box(self,Vector3(0,2.64,1.10),Vector3(.16,.12,2.6),Color("656e69"))
	frame_visuals.append(header_visual)
	add_child(hinge)
	hinge.add_child(body)
	body.collision_layer = 1
	body.collision_mask = 4 | 2
	leaf_shape.shape = BoxShape3D.new()
	leaf_shape.shape.size = LEAF_SIZE
	leaf_shape.position = LEAF_CENTER
	body.add_child(leaf_shape)
	leaf_visual = _box(body,leaf_shape.position,leaf_shape.shape.size,Color("50645b"))
	for y in [.35,1.35,2.35]:
		# Fixed hinge plate reaches jamb and knuckle; 5mm clear of rotating leaf.
		_box(self,Vector3(0,y,-.1075),Vector3(.11,.14,.085),Color("717b74"))
		var knuckle := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = .065
		cylinder.bottom_radius = .065
		cylinder.height = .18
		knuckle.mesh = cylinder
		knuckle.position = Vector3(0,y,0)
		add_child(knuckle)
	_build_two_sided_operating_hardware()
	_build_perimeter_stops()
	_closed_transform = hinge.transform
	_authored_transform = transform
	# Conservative entire 90 degree sweep, plus body clearance on either side.
	var min_x := x-2.65 if direction < 0 else x-.3
	sweep = AABB(Vector3(min_x,.25,-11.5),Vector3(2.95,3.05,3.0))

func _build_two_sided_operating_hardware() -> void:
	# Low-profile folding-ring pulls on BOTH faces. Their folded envelope clears the side wall.
	# Ring manipulation/hand animation is not implemented by this structure harness.
	for side in [-1.0,1.0]:
		var plate := _box(body,Vector3(side*.064,1.10,1.98),Vector3(.008,.21,.18),Color("89918b"))
		plate.name = "OperatingBackplate_%s" % ("Negative" if side < 0 else "Positive")
		operating_hardware.append(plate)
		var pivot := _box(body,Vector3(side*.078,1.18,1.98),Vector3(.026,.025,.075),Color("89918b"))
		operating_hardware.append(pivot)
		var ring := MeshInstance3D.new()
		ring.name = "FoldedRingPull_%s" % ("Negative" if side < 0 else "Positive")
		var torus := TorusMesh.new()
		torus.inner_radius = .052
		torus.outer_radius = .076
		torus.rings = 32
		torus.ring_segments = 12
		ring.mesh = torus
		ring.position = Vector3(side*.080,1.10,1.98)
		ring.rotation.z = PI*.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("89918b")
		material.roughness = .45
		material.metallic = .75
		ring.material_override = material
		body.add_child(ring)
		operating_hardware.append(ring)

func _build_perimeter_stops() -> void:
	# Corridor-side rebated stop; leaf opens the other way, so no swing overlap.
	stops.name = "VisibleRebatedFrameAndThreshold"
	stops.collision_layer = 1
	add_child(stops)
	for visual: MeshInstance3D in frame_visuals:
		var frame_shape := CollisionShape3D.new()
		frame_shape.shape = BoxShape3D.new()
		frame_shape.shape.size = visual.mesh.size
		frame_shape.transform = visual.transform
		stops.add_child(frame_shape)
		frame_pairs.append([visual,frame_shape])
	var bars: Array = [
		[Vector3(0,1.35,-.0475),Vector3(.04,2.7,.125)],
		[Vector3(0,1.35,2.2475),Vector3(.04,2.7,.125)],
		[Vector3(0,2.6275,1.10),Vector3(.04,.145,2.42)],
		[Vector3(0,.0175,1.10),Vector3(.04,.035,2.42)]]
	for bar: Array in bars:
		var center: Vector3 = bar[0]
		var size: Vector3 = bar[1]
		center.x = corridor_sign*.09
		var visual := _box(stops,center,size,Color("717b74"))
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		collision.shape.size = size
		collision.position = center
		stops.add_child(collision)
		stop_pairs.append([visual,collision])
		# Opaque visible rubber meets the closed leaf face at x=+/-0.06 exactly.
		center.x = corridor_sign*.065
		var gasket := _box(stops,center,Vector3(.01,size.y,size.z),Color("252d29"))
		gasket.material_override.metallic = 0.0
		gasket.material_override.roughness = .92
	# Actual shallow bevel away from the stop: only 3.5cm rise, backed by permanent deck.
	var points := PackedVector3Array([
		Vector3(corridor_sign*.11,0,-.11),Vector3(corridor_sign*.41,0,-.11),Vector3(corridor_sign*.11,.035,-.11),
		Vector3(corridor_sign*.11,0,2.31),Vector3(corridor_sign*.41,0,2.31),Vector3(corridor_sign*.11,.035,2.31)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # Hard prism edges; generated normals follow each actual front face.
	# Do not render a bottom cap coplanar with the permanent floor. Convex physics stays closed.
	# Godot triangle front faces use clockwise winding, hence reverse the +X construction.
	for tri: Array in [[0,2,1],[3,4,5],[0,3,5],[0,5,2],[2,5,4],[2,4,1]]:
		if corridor_sign > 0: tri.reverse()
		for index: int in tri: st.add_vertex(points[index])
	st.generate_normals()
	ramp_visual = MeshInstance3D.new()
	ramp_visual.name = "ClockwiseFrontFacingThresholdRamp"
	ramp_visual.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("717b74")
	material.roughness = .72
	material.metallic = .5
	material.cull_mode = BaseMaterial3D.CULL_BACK
	ramp_visual.material_override = material
	stops.add_child(ramp_visual)
	ramp_collision = CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	ramp_collision.shape = convex
	stops.add_child(ramp_collision)

func perimeter_geometry() -> Dictionary:
	var matching := true
	for pair: Array in stop_pairs+frame_pairs:
		var mesh: MeshInstance3D = pair[0]
		var shape: CollisionShape3D = pair[1]
		var visual: AABB = mesh.global_transform*mesh.mesh.get_aabb()
		var size: Vector3 = shape.shape.size
		var collision: AABB = shape.global_transform*AABB(-size*.5,size)
		matching = matching and visual.is_equal_approx(collision)
	return {"visible_collision_stop_boxes_match":matching,"stop_count":stop_pairs.size(),"matching_frame_count":frame_pairs.size(),
		"threshold_height":.035,"threshold_ramp_run":.30,"gasket_leaf_face_contact_x":.06}

func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = center
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .68
	material.metallic = .5
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func closed_clearances() -> Dictionary:
	var visual: AABB = leaf_visual.global_transform*leaf_visual.mesh.get_aabb()
	var frame: AABB = header_visual.global_transform*header_visual.mesh.get_aabb()
	var size: Vector3 = leaf_shape.shape.size
	var collision: AABB = leaf_shape.global_transform*AABB(-size*.5,size)
	return {"top_gap":frame.position.y-visual.end.y,"bottom_gap":visual.position.y-.4,
		"visual_collision_match":visual.is_equal_approx(collision)}

func request(open: bool) -> void:
	if not open and state == "CLOSED" and is_zero_approx(angle): return
	motion_seconds = 0.0
	motion_wall_seconds = 0.0
	_motion_started_usec = Time.get_ticks_usec()
	goal = open_angle if open else 0.0
	state = "OPENING" if open else "CLOSING"

func advance(delta: float, obstruction: String) -> void:
	if state not in ["OPENING","CLOSING","BLOCKED"]: return
	if not obstruction.is_empty():
		if state != "BLOCKED": blocked_count += 1
		state = "BLOCKED"
		goal = open_angle # Reopen only after complete reverse sweep becomes clear.
		return
	if state == "BLOCKED": state = "OPENING"
	var next_angle := move_toward(angle,goal,ANGULAR_SPEED*delta)
	if next_angle != angle:
		motion_seconds += delta
		angle = next_angle
		hinge.rotation.y = angle
		last_motion_frame = Engine.get_physics_frames()
	if is_equal_approx(angle,goal):
		state = "CLOSED" if is_zero_approx(goal) else "OPEN"
		motion_wall_seconds = float(Time.get_ticks_usec()-_motion_started_usec)/1000000.0

func physically_closed() -> bool:
	return transform.is_equal_approx(_authored_transform) and body.transform.is_equal_approx(Transform3D.IDENTITY) and leaf_shape.shape is BoxShape3D and leaf_shape.shape.size == LEAF_SIZE and leaf_shape.position == LEAF_CENTER and state == "CLOSED" and absf(angle) < .00001 and hinge.transform.is_equal_approx(_closed_transform) and not leaf_shape.disabled and body.collision_layer == 1 and Engine.get_physics_frames() > last_motion_frame+1
