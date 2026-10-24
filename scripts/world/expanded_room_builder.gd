class_name ExpandedPoolRoomBuilder
extends RefCounted
## Compact imported facility architecture. No full-room trimesh collision.
const Expansion := preload("res://scripts/world/expanded_room_catalog.gd")
const ArtPassMaterials := preload("res://scripts/art_pass/art_pass_materials.gd")
static var scene_cache: Dictionary={}
static var proxy_cache: Dictionary={}
var host: WeakRef
var room: Node3D
var layout: Dictionary
var library: RefCounted
var body: StaticBody3D
var geometry: Node3D
var triangle_count: int=0
var proxy_count: int=0
var shower_dry_material: ShaderMaterial
var local_wet_materials: Dictionary = {}
var art_pass_materials: RefCounted
# Native water-level A/B showed only a local edge highlight, not an accepted
# wet-atmosphere improvement. Keep this material experiment OFF by default.
var local_wet_finish_requested: bool = "--pc-local-wet-finish" in OS.get_cmdline_user_args()

func _init(owner_builder: RefCounted) -> void:
	host=weakref(owner_builder);room=owner_builder.room;layout=owner_builder.layout;library=owner_builder.library;body=owner_builder.physics_body

func build_shell() -> void:
	var path: String=layout.geometry_path
	if not scene_cache.has(path): scene_cache[path]=load(path)
	var packed: PackedScene=scene_cache[path]
	assert(packed!=null,"Missing expanded facility GLB: "+path)
	geometry=packed.instantiate()
	geometry.name="ExpandedFacilityArchitecture"
	room.add_child(geometry)
	_visit(geometry)
	layout.solids=host.get_ref().solids
	layout.water_exclusions=[]
	for solid: AABB in host.get_ref().solids:
		if solid.position.y<=Expansion.WATER_LEVEL and solid.end.y>=Expansion.WATER_LEVEL:
			layout.water_exclusions.append(solid)
	room.set_meta("expanded_geometry_stats",{"triangles":triangle_count,"proxies":proxy_count,"geometry_path":path})

func _visit(node: Node) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var instance:=node as MeshInstance3D
		if String(node.name).begins_with("COLLISION_"):
			# These authored proxies are all axis-aligned boxes after export, so
			# retain exact simple boxes rather than generating a scene trimesh.
			var bounds: AABB=instance.mesh.get_aabb()
			var transform: Transform3D=room.global_transform.affine_inverse()*instance.global_transform
			var key: String=str(bounds.size)
			if not proxy_cache.has(key):
				var shape:=BoxShape3D.new();shape.size=bounds.size;proxy_cache[key]=shape
			transform.origin=transform*bounds.get_center()
			host.get_ref().add_shape(proxy_cache[key],transform)
			host.get_ref().solids.append(transform*AABB(-bounds.size*.5,bounds.size))
			proxy_count+=1
			instance.hide()
			instance.set_meta("source_exclude_optics",true)
		else:
			instance.gi_mode=GeometryInstance3D.GI_MODE_STATIC
			instance.layers=1
			triangle_count+=instance.mesh.get_faces().size()/3
			for surface in instance.mesh.get_surface_count():
				var original: Material=instance.get_active_material(surface)
				if original==null: continue
				var role: String=original.resource_name
				if library!=null: instance.set_surface_override_material(surface,_material_for(role))
				if role=="lamp": instance.set_meta("source_exclude_optics",true)
				if role=="formal_glazing":
					instance.set_meta("source_transmissive",true)
					instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					instance.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children(): _visit(child)

func _material_for(role:String)->Material:
	if role.begins_with("art_pass_"):
		if art_pass_materials == null: art_pass_materials = ArtPassMaterials.new()
		var authored: ShaderMaterial = art_pass_materials.resolve(role, library)
		if authored != null: return authored
	var source:Material=library.get_material(role)
	# Keep the shower's local ceramic instance and its glazed tile finish.
	if role=="formal_dry_deck" and layout.get("expanded_module","")=="shower_changing" and source is ShaderMaterial:
		if shower_dry_material==null:
			shower_dry_material=source.duplicate(false) as ShaderMaterial
			shower_dry_material.resource_name="Expanded / shower dry ceramic without clearcoat"
			shower_dry_material.set_shader_parameter("coat_strength",0.18)
			library.register_local_receiver(shower_dry_material, source as ShaderMaterial)
		return shower_dry_material
	# Explicit experimental opt-in: low-arched bath only. Shower and all other rooms,
	# shared dry/formal/source resources, basin floor and plaster stay unchanged.
	if local_wet_finish_requested and layout.get("expanded_module", "") == "low_arched_bath" and role in ["formal_dry_deck", "formal_wainscot"] and source is ShaderMaterial:
		if not local_wet_materials.has(role):
			var wet_material := source.duplicate(false) as ShaderMaterial
			wet_material.resource_name = "Expanded / local thin-film approximation / " + role
			wet_material.set_shader_parameter("local_wet_finish_enabled", true)
			wet_material.set_shader_parameter("local_wet_room_origin", Vector2(room.global_position.x, room.global_position.z))
			wet_material.set_shader_parameter("local_wet_deck_y", room.global_position.y + Expansion.DECK_TOP)
			wet_material.set_shader_parameter("local_wet_water_y", room.global_position.y + Expansion.WATER_LEVEL)
			wet_material.set_shader_parameter("local_wet_basin_range", Vector2(3.0, 10.0))
			library.register_local_receiver(wet_material, source as ShaderMaterial)
			local_wet_materials[role] = wet_material
		return local_wet_materials[role] as Material
	return source

func build_interior() -> void:
	for index in range(4):
		var angle: float=float(index)*PI*.5
		var root:=Node3D.new();root.name="FacilityWayfinding";root.rotation.y=angle;room.add_child(root)
		var label:=Label3D.new();label.name="RoomLabel"
		label.text="%02d  %s" % [int(layout.variant)-10,layout.name]
		label.font_size=25;label.pixel_size=.0023;label.outline_size=0
		label.position=Vector3(3.15,2.43,-11.305)
		label.modulate=Color("e5eeeb");label.shaded=true
		root.add_child(label)
	room.set_meta("layout",layout)
	room.set_meta("complete",true)
