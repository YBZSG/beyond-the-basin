class_name ExpandedFacilityModel
extends RefCounted
## Reusable standalone facility GLBs with hidden proxies and simple solid collision.
## Example: room.add_child(ExpandedFacilityModel.instantiate("facility_bench", materials))
const NAMES := ["facility_bench","facility_shower","facility_drain","facility_rail","facility_portal","facility_wayfinding","facility_service_door"]

static func instantiate(asset_name: String, materials: RefCounted=null) -> Node3D:
	assert(asset_name in NAMES,"Unknown original facility model: "+asset_name)
	var packed: PackedScene=load("res://assets/models/expansion/"+asset_name+".glb")
	assert(packed!=null,"Facility model must be imported")
	var result:=Node3D.new();result.name=asset_name.to_pascal_case()
	var geometry:Node3D=packed.instantiate();result.add_child(geometry)
	var body:=StaticBody3D.new();body.name="FacilityCollision";body.collision_layer=1;body.collision_mask=0;result.add_child(body)
	_visit(geometry,Transform3D.IDENTITY,body,materials)
	return result

static func _visit(node: Node, parent_transform: Transform3D, body: StaticBody3D, materials: RefCounted) -> void:
	var transform: Transform3D=parent_transform*node.transform if node is Node3D else parent_transform
	if node is MeshInstance3D and node.mesh!=null:
		if String(node.name).begins_with("COLLISION_"):
			var bounds:AABB=node.mesh.get_aabb()
			var shape:=BoxShape3D.new();shape.size=bounds.size
			var collision:=CollisionShape3D.new();collision.shape=shape
			collision.transform=Transform3D(transform.basis,transform*bounds.get_center())
			body.add_child(collision);node.hide();node.set_meta("source_exclude_optics",true)
		else:
			node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
			for surface in node.mesh.get_surface_count():
				var original:Material=node.get_active_material(surface)
				if materials!=null and original!=null:node.set_surface_override_material(surface,materials.get_material(original.resource_name))
	for child in node.get_children():_visit(child,transform,body,materials)
