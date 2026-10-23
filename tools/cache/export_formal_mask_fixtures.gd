extends SceneTree
## Archive old-kernel prepared masks before a native acceleration cache rebake.
const Store=preload("res://scripts/water/source_terrain_disk_cache.gd")
const Formal=preload("res://scripts/world/formal_rooms.gd")
const Lighting=preload("res://scripts/rendering/pool_lighting.gd")
const Runtime=preload("res://scripts/water/source_water_runtime.gd")
func _initialize()->void:
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/verification/eight-hour/transition/formal-terrain-bake.json"))
	var runtime:=Runtime.new();var fixtures:Array=[]
	var lighting:=Lighting.new()
	for coord:Vector2i in Formal.COORDS:
		var layout:=Formal.layout(coord,1337);var room:=Node3D.new()
		lighting.add_formal_lights(room,layout);runtime._layouts[coord]=layout;room.free()
	for entry:Dictionary in report.rooms:
		var payload:=Store.read_value(entry.path,entry.key,entry.algorithm)
		if payload.is_empty():push_error("Old exact payload is unavailable");quit(1);return
		fixtures.append({"coord":payload.coord,"solids":payload.filtered_solids,"lamps":runtime._effective_lamps(payload.coord),"expected_masks":payload.masks,"reference_algorithm":entry.algorithm})
	var path:="res://tests/fixtures/formal_incoming_masks_real.maskfixture"
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var({"engine":Engine.get_version_info().hash,"fixtures":fixtures});file.close()
	print("FORMAL_MASK_FIXTURES ",JSON.stringify({"path":path,"count":fixtures.size(),"sha256":FileAccess.get_sha256(path)}))
	runtime.dispose();runtime.free();quit()
