extends RefCounted
## First continuous two-hall slice. Source builders and static caches stay intact.
const G = preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const Catalog = preload("res://scripts/dreamcore/dream_catalog.gd")
const Hand = preload("res://scripts/dreamcore/scenes/hanging_hand.gd")
const Aquarium = preload("res://scripts/dreamcore/scenes/aquarium_atrium.gd")
const ROOM := 32.0
const AQUARIUM_OFFSET := Vector2i(3,0)
const PORTAL_Z := -10.0
const PORTAL_WIDTH := 2.4
const FLOOR_Y := .4
const PORTAL_TOP := 3.1
var _items: Dictionary = {}
var _corridor: Array = []

static func definition() -> Dictionary:
	return {"id":"unified_hand_aquarium","title":"连续设施 · 双厅切片","subtitle":"悬手浅池 / 检修廊 / 水族中庭","spawn":Vector3(-9,.42,26),"look_at":Vector3(0,7,-4),"bounds":Rect2i(-2,-2,8,5),"fog":.0007,"fog_color":"#aebdbb"}

static func sectors() -> Array:
	return [{"id":"hanging_hand","builder":Hand,"chunk_offset":Vector2i.ZERO}, {"id":"aquarium_atrium","builder":Aquarium,"chunk_offset":AQUARIUM_OFFSET}]

static func contributors(coord: Vector2i) -> Array:
	var result: Array = []
	for sector: Dictionary in sectors():
		var local: Vector2i = coord-sector.chunk_offset
		if sector.builder.definition().bounds.has_point(local):
			var row: Dictionary = sector.duplicate()
			row.local_coord = local
			result.append(row)
	return result

func geometry(id: String) -> Array:
	if _items.has(id): return _items[id]
	assert(id in ["hanging_hand","aquarium_atrium"])
	var source: Array = Hand.geometry() if id == "hanging_hand" else Aquarium.geometry()
	var center := Vector3(32.5,19,0) if id == "hanging_hand" else Vector3(-35.5,14,0)
	var size := Vector3(1,38,74) if id == "hanging_hand" else Vector3(1,28,38)
	var result: Array = []
	var matches := 0
	for item: Dictionary in source:
		var mesh: Mesh = item.mesh
		var transform: Transform3D = item.transform
		if mesh is BoxMesh and mesh.size == size and transform.origin == center and transform.basis == Basis.IDENTITY and bool(item.collision):
			matches += 1
			result.append_array(_split_portal(center,size,str(item.material)))
		else:
			# Dictionary copy prevents adapter metadata mutation of source cache.
			result.append(item.duplicate())
	assert(matches == 1, "Authored wall precondition changed; do not cut a guessed wall")
	_items[id] = result
	return result

static func _split_portal(center: Vector3, size: Vector3, material: String) -> Array:
	var result: Array = []
	var low_z := center.z-size.z*.5
	var high_z := center.z+size.z*.5
	var door_low := PORTAL_Z-PORTAL_WIDTH*.5
	var door_high := PORTAL_Z+PORTAL_WIDTH*.5
	for extent: Vector2 in [Vector2(low_z,door_low),Vector2(door_high,high_z)]:
		result.append(G.box(Vector3(center.x,center.y,(extent.x+extent.y)*.5),Vector3(size.x,size.y,extent.y-extent.x),material))
	result.append(G.box(Vector3(center.x,(PORTAL_TOP+size.y)*.5,PORTAL_Z),Vector3(size.x,size.y-PORTAL_TOP,PORTAL_WIDTH),material))
	# The original below-floor wall becomes a flush threshold, not an obstacle.
	result.append(G.box(Vector3(center.x,FLOOR_Y*.5,PORTAL_Z),Vector3(size.x,FLOOR_Y,PORTAL_WIDTH),material))
	return result

func corridor_geometry() -> Array:
	if not _corridor.is_empty(): return _corridor
	# Thresholds occupy x32..33 and x60..61. This deck fills the intervening 27m.
	# All three visible top surfaces meet at y=.4, with no coplanar overlap.
	_corridor.append(G.box(Vector3(46.5,.15,PORTAL_Z),Vector3(27,.5,3),"tile"))
	for z in [PORTAL_Z-1.35,PORTAL_Z+1.35]:
		_corridor.append(G.box(Vector3(46.5,1.9,z),Vector3(27,3,.3),"ivory"))
	_corridor.append(G.box(Vector3(46.5,3.25,PORTAL_Z),Vector3(27,.3,3),"ivory"))
	# Fixed, warm maintenance practicals. No flashing, progress lock or surprise trigger.
	for x in [37.5,46.5,55.5]:
		_corridor.append(G.box(Vector3(x,3.06,PORTAL_Z),Vector3(.7,.08,.28),"metal",false))
		_corridor.append(G.box(Vector3(x,3.012,PORTAL_Z),Vector3(.58,.016,.20),"glow",false))
	return _corridor

func occupied_coords() -> Array[Vector2i]:
	var occupied: Dictionary = {}
	for sector: Dictionary in sectors():
		var offset: Vector2i = sector.chunk_offset
		for item: Dictionary in geometry(str(sector.id)):
			var bounds: AABB = item.transform*item.mesh.get_aabb()
			_add_bounds_coords(occupied,bounds,offset)
		# Real point-owner locations from unchanged build_detail(), not light ranges.
		var lamps: Array = [Vector3(-14,24,8),Vector3(14,24,8),Vector3(0,29,-20)] if sector.id == "hanging_hand" else [Vector3(-22,9,-21),Vector3(-6,9,-21),Vector3(10,9,-21),Vector3(0,26,0)]
		for point: Vector3 in lamps:
			occupied[Vector2i(floori((point.x+16)/32),floori((point.z+16)/32))+offset] = true
		var declared: Rect2i = sector.builder.definition().bounds
		for z in range(declared.position.y,declared.end.y):
			for x in range(declared.position.x,declared.end.x):
				if not sector.builder.layout(Vector2i(x,z)).get("water_rects",[]).is_empty(): occupied[Vector2i(x,z)+offset] = true
	for item: Dictionary in corridor_geometry(): _add_bounds_coords(occupied,item.transform*item.mesh.get_aabb(),Vector2i.ZERO)
	var result: Array[Vector2i] = []
	for coord: Vector2i in occupied: result.append(coord)
	result.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	return result

static func _add_bounds_coords(result: Dictionary, bounds: AABB, offset: Vector2i) -> void:
	for z in range(floori((bounds.position.z+16)/32),floori((bounds.end.z+16)/32)+1):
		for x in range(floori((bounds.position.x+16)/32),floori((bounds.end.x+16)/32)+1):
			# Only discard zero-area boundary contact, never a nonempty geometry slice.
			var overlap := Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).intersection(Rect2(x*32-16,z*32-16,32,32))
			if overlap.has_area(): result[Vector2i(x,z)+offset] = true

func layout(coord: Vector2i, seed_value: int) -> Dictionary:
	var data: Dictionary = Catalog.base_layout(coord,definition())
	data.seed = seed_value
	data.unified_preview = true
	data.unified_owners = []
	data.water_enabled = false
	data.name = "检修连廊"
	data.subtitle = "两座大厅之间的真实步行连接"
	for sector: Dictionary in contributors(coord):
		var local: Dictionary = sector.builder.layout(sector.local_coord)
		data.unified_owners.append(str(sector.id))
		for field: String in ["water_rects","water_steps","water_exclusions","water_closed_edges"]:
			data[field].append_array(local.get(field,[]))
		if not local.get("water_rects",[]).is_empty():
			assert(not data.water_enabled,"Two wet sector owners overlap one chunk; explicit merge required")
			data.water_enabled = true
			data.water_floor_y = local.get("water_floor_y",.12)
			data.dream_id = str(sector.id)
	if coord.x <= 1:
		data.name = "悬手浅池"
	elif coord.x >= 2:
		data.name = "水族中庭"
	data.spawn_local = definition().spawn-Vector3(coord.x*ROOM,0,coord.y*ROOM)
	return data

func build_shell(room: Node3D, data: Dictionary, _materials: RefCounted) -> void:
	for sector: Dictionary in contributors(data.coord):
		var child := Node3D.new()
		child.name = str(sector.id)
		child.set_meta("unified_sector",str(sector.id))
		child.set_meta("source_chunk",sector.local_coord)
		room.add_child(child)
		var local: Dictionary = {"coord":sector.local_coord,"solids":[]}
		G.build(child,local,geometry(str(sector.id)),true)
		# Solids are already chunk-local. Global parent position adds sector offset.
		data.solids.append_array(local.solids)
	var corridor_root := Node3D.new()
	corridor_root.name = "MaintenanceLink"
	room.add_child(corridor_root)
	G.build(corridor_root,data,corridor_geometry(),true)

func build_detail(room: Node3D, data: Dictionary, materials: RefCounted) -> void:
	for sector: Dictionary in contributors(data.coord):
		var child: Node3D = room.get_node(str(sector.id))
		var local: Dictionary = {"coord":sector.local_coord,"solids":[]}
		# Only collision=true wall pieces changed. Original detail and lamps stay exact.
		sector.builder.build_detail(child,local,materials)
	var corridor_root: Node3D = room.get_node("MaintenanceLink")
	G.build(corridor_root,data,corridor_geometry(),false)
	for x in [37.5,46.5,55.5]:
		G.lamp(corridor_root,data,Vector3(x,2.94,PORTAL_Z),Color("ffe7bb"),.75,5.)

func transformed_anchor(sector_id: String, point: Vector3) -> Vector3:
	assert(sector_id in ["hanging_hand","aquarium_atrium"])
	return point + (Vector3(96,0,0) if sector_id == "aquarium_atrium" else Vector3.ZERO)
