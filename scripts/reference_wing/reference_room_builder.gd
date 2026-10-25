extends RefCounted
## Complete authored GLB, exact simplified physics, no new procedural decoration.
const ReferenceMaterialsScript = preload("res://scripts/reference_wing/reference_materials.gd")
const Catalog = preload("res://scripts/reference_wing/reference_catalog.gd")
const JointSeals = preload("res://scripts/reference_wing/reference_joint_seals.gd")
var room: Node3D
var layout: Dictionary
var library: RefCounted
var reference_materials: RefCounted
var _triangles := 0
var _proxy_count := 0

func _init(parent: Node3D, contract: Dictionary, materials: RefCounted) -> void:
	room=parent; layout=contract; library=materials
	reference_materials=ReferenceMaterialsScript.new()
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--reference-material="):
			reference_materials.set_diagnostic_variant(argument.trim_prefix("--reference-material="))

func build_shell() -> void:
	var packed := load(str(layout.geometry_path)) as PackedScene
	assert(packed != null,"Missing complete reference room: "+str(layout.geometry_path))
	var architecture := packed.instantiate() as Node3D
	architecture.name="ReferenceAuthoredArchitecture"
	room.add_child(architecture)
	_visit(architecture)
	var backing := JointSeals.build(layout.geometry_contract.collision_proxies)
	if backing != null:
		room.add_child(backing)
		_triangles += backing.mesh.get_faces().size() / 3
	var body:=StaticBody3D.new();body.name="ReferenceSolidStructure";body.collision_layer=1;body.collision_mask=0
	room.add_child(body)
	for proxy: Dictionary in layout.geometry_contract.collision_proxies:
		var shape_node:=CollisionShape3D.new();shape_node.name=str(proxy.name)
		if str(proxy.type)=="BOX":
			var shape:=BoxShape3D.new();shape.size=Catalog.vec3(proxy.size)
			shape_node.shape=shape;shape_node.position=Catalog.vec3(proxy.center)
			layout.solids.append(AABB(shape_node.position-shape.size*.5,shape.size))
		elif str(proxy.type)=="CONVEX":
			var shape:=ConvexPolygonShape3D.new()
			var points:=PackedVector3Array()
			for value: Array in proxy.vertices: points.append(Catalog.vec3(value))
			shape.points=points;shape_node.shape=shape
		else:
			assert(false,"Unsupported authored proxy kind: "+str(proxy.type));continue
		body.add_child(shape_node);_proxy_count+=1
	room.set_meta("reference_geometry_stats",{"triangles":_triangles,"proxies":_proxy_count,"id":layout.reference_id})

func _visit(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		if str(node.name).begins_with("COLLISION_"):
			node.hide();node.set_meta("source_exclude_optics",true)
		else:
			node.layers=1;node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
			_triangles+=node.mesh.get_faces().size()/3
			for index in node.mesh.get_surface_count():
				var previous: Material=node.get_active_material(index)
				if previous==null:continue
				var replacement: Material=reference_materials.resolve(previous.resource_name,library)
				# Untiled architecture, upholstery, balls and fixture emission retain
				# their authored nonmetal PBR values, not a generic blue tile override.
				if replacement!=null:node.set_surface_override_material(index,replacement)
	for child in node.get_children():_visit(child)

func build_interior() -> void:
	room.set_meta("layout",layout)
	room.set_meta("complete",true)
