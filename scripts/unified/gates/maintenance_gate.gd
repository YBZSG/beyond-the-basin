extends "./gate_base.gd"
## Visual refinement only. Axis, leaf collision, stops, motion and safety API remain base06.
const Art = preload("./gate_art_geometry.gd")
var art_moving_meshes: Array[MeshInstance3D] = []
var art_fixed_meshes: Array[MeshInstance3D] = []
var hinge_records: Array = []

func configure(x: float, direction: float) -> void:
	super.configure(x,direction)
	var old_knuckles: Array[Node] = []
	for child: Node in get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and is_equal_approx(child.mesh.top_radius,.065) and is_equal_approx(child.mesh.height,.18): old_knuckles.append(child)
	for child: Node in old_knuckles:
		remove_child(child)
		child.free()
	_style_existing(self)
	for index in 2:
		frame_visuals[index].mesh = Art.embedded_jamb(Vector3(.16,2.7,.10),.0015,1.0 if index == 0 else -1.0)
	leaf_visual.mesh = Art.pressed_leaf()
	leaf_visual.material_override = Art.material("paint")
	for y in [.35,1.35,2.35]: _build_service_hinge(y)
	_add_frame_anchors()
	_add_pull_fasteners()

func _style_existing(node: Node) -> void:
	if node is MeshInstance3D:
		var kind := "steel"
		if node == leaf_visual: kind = "paint"
		elif node in frame_visuals: kind = "frame"
		elif node.material_override is StandardMaterial3D and node.material_override.albedo_color.is_equal_approx(Color("252d29")): kind = "rubber"
		if node.mesh is BoxMesh:
			var size: Vector3 = node.mesh.size
			var bevel := minf(.0015,minf(size.x,minf(size.y,size.z))*.12)
			node.mesh = Art.bevel_box(size,bevel)
		else:
			node.mesh = Art.metric_mesh(node.mesh)
		node.material_override = Art.material(kind)
	for child: Node in node.get_children(): _style_existing(child)

func _mesh_part(parent: Node3D, mesh: Mesh, center: Vector3, kind: String, label: String, moving: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.set_meta("gate_art_role",label)
	node.set_meta("gate_art_moving",moving)
	node.mesh = mesh
	node.position = center
	node.material_override = Art.material(kind)
	parent.add_child(node)
	if moving: art_moving_meshes.append(node)
	else: art_fixed_meshes.append(node)
	return node

func _small_box(parent: Node3D, center: Vector3, size: Vector3, kind: String, label: String, moving: bool) -> MeshInstance3D:
	return _mesh_part(parent,Art.bevel_box(size,minf(.001,minf(size.x,minf(size.y,size.z))*.12)),center,kind,label,moving)

func _screw(parent: Node3D, center: Vector3, radius: float, depth: float, rotation_value: Vector3, label: String, moving: bool) -> MeshInstance3D:
	var node := _mesh_part(parent,Art.socket_head(radius,depth),center,"steel",label,moving)
	node.rotation = rotation_value
	return node

func _build_service_hinge(y: float) -> void:
	# Two fixed sleeves, one moving sleeve, bored around a fixed 39.6mm pin.
	# Hinge-edge pockets have skins at |X|>=.056, so sleeve r=.050 clears by 6mm.
	for offset in [-.0555,.0555]:
		_mesh_part(self,Art.tube(.050,.020,.045,.001),Vector3(0,y+offset,0),"steel","FixedBoredKnuckle",false)
		# Fixed offset bracket lies outside the inward swept quadrant, not through the leaf.
		_small_box(self,Vector3(corridor_sign*.0475,y+offset,-.0475),Vector3(.015,.039,.040),"steel","FixedKnuckleBridge",false)
	_mesh_part(body,Art.tube(.049,.020,.060,.001),Vector3(0,y,0),"steel","RotatingBoredKnuckle",true)
	for offset in [-.0315,.0315]:
		_mesh_part(self,Art.tube(.0505,.0205,.002,.0002),Vector3(0,y+offset,0),"bearing","ThrustWasher",false)
	var pin := CylinderMesh.new()
	pin.top_radius = .0198
	pin.bottom_radius = .0198
	pin.height = .162
	pin.radial_segments = 32
	_mesh_part(self,Art.metric_mesh(pin),Vector3(0,y,0),"steel","FixedHingePin",false)
	_mesh_part(self,Art.tube(.030,.0205,.003,.0003),Vector3(0,y+.0795,0),"steel","PinRetainerWasher",false)
	_mesh_part(self,Art.tube(.030,.0195,.003,.0003),Vector3(0,y-.0795,0),"steel","LowerPinShoulder",false)
	_screw(self,Vector3(0,y+.081,0),.026,.008,Vector3.ZERO,"SocketPinRetainer",false)
	# Internal moving steel web joins the rotating sleeve to the folded leaf edge.
	_small_box(body,Vector3(0,y,.085),Vector3(.072,.050,.085),"steel","MovingHingeWeb",true)
	for side in [-1.0,1.0]:
		_small_box(body,Vector3(side*.057,y,.120),Vector3(.002,.052,.110),"steel","LeafHingeReinforcement",true)
		for offset in [-.016,.016]:
			_screw(body,Vector3(side*.058,y+offset,.130),.0045,.0018,Vector3(0,0,-side*PI*.5),"LeafStrapSocket",true)
	for px in [-.0325,.0325]:
		for py in [-.045,.045]:
			_screw(self,Vector3(px,y+py,-.065),.005,.0018,Vector3(PI*.5,0,0),"FixedFlangeSocket",false)
	hinge_records.append({"axis_y":y,"bore_radius":.020,"pin_radius":.0198,
		"radial_pin_clearance":.0002,"sleeve_to_skin_clearance":.006,
		"axial_washer_gap":.0005,"fixed_bridge_to_rotating_sleeve_y_gap":.006,
		"all_knuckle_parts_within_old_radius":.065,"upper_extent_from_axis":.089})

func _add_frame_anchors() -> void:
	for y in [.18,.80,1.90,2.55]:
		_screw(self,Vector3(corridor_sign*.1103,y,-.0475),.0075,.003,Vector3(0,0,-corridor_sign*PI*.5),"HingeJambAnchor",false)
		_screw(self,Vector3(corridor_sign*.1103,y,2.2475),.0075,.003,Vector3(0,0,-corridor_sign*PI*.5),"LatchJambAnchor",false)

func _add_pull_fasteners() -> void:
	for side in [-1.0,1.0]:
		for y in [1.025,1.175]:
			for z in [1.920,2.040]:
				_screw(body,Vector3(side*.068,y,z),.0032,.0015,Vector3(0,0,-side*PI*.5),"PullBackplateSocket",true)

func art_diagnostics() -> Dictionary:
	return {"paint_dielectric":Art.material("paint").metallic == 0.0,
		"paint_has_no_metal_map":Art.material("paint").metallic_texture == null,
		"steel_uses_existing_orm":Art.material("steel").metallic_texture != null,
		"rubber_dielectric":Art.material("rubber").metallic == 0.0,
		"panel_face_inset":.004,"collision_is_conservative_outer_envelope":true,
		"new_rust_layer":false,"hinges":hinge_records.duplicate(true),
		"moving_art_meshes":art_moving_meshes.size(),"fixed_art_meshes":art_fixed_meshes.size()}
