extends SceneTree
## CPU-only fixture generation for independent exact-mask native parity tests.
const Runtime = preload("res://scripts/water/source_water_runtime.gd")
const World = preload("res://scripts/world/pool_world.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Lighting = preload("res://scripts/rendering/pool_lighting.gd")
const Caustics = preload("res://scripts/water/source_port/source_caustics.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var runtime:=Runtime.new();root.add_child(runtime);runtime.set_process(false)
	var world:=World.new();root.add_child(world);world.set_process(false)
	var lighting:=Lighting.new()
	world.room_loaded.connect(func(room:Node3D,coord:Vector2i,layout:Dictionary):
		lighting.add_room_lights(room,int(layout.variant));runtime._rooms[coord]=weakref(room);runtime._layouts[coord]=layout)
	world.initialize(250821,Materials.new());world.complete_pending_streaming()
	var colliders:Array=[];var solids:Array=[];var triangles:=PackedVector3Array()
	var triangles_by_room:Dictionary={}
	for coord:Vector2i in runtime._rooms:
		var room_triangles:=PackedVector3Array()
		runtime._collect(runtime._rooms[coord].get_ref(),colliders,solids,room_triangles)
		triangles_by_room[coord]=room_triangles;triangles.append_array(room_triangles)
	var optical_file:=FileAccess.open("res://tests/fixtures/source_optical_triangles_real.bvhfixture",FileAccess.WRITE)
	optical_file.store_var({"seed":250821,"engine":Engine.get_version_info().hash,"geometry_origin":Vector2.ZERO,"triangles_by_room":triangles_by_room});optical_file.close()
	var fixtures:Array=[]
	for coord:Vector2i in runtime._rooms:
		var translated:Array=[];var origin:=Vector2(coord)*32.0;var shift:=Vector3(-origin.x,0,-origin.y)
		for box:AABB in solids:translated.append(AABB(box.position+shift,box.size))
		fixtures.append({"coord":coord,"variant":runtime._layouts[coord].variant,"solids":Caustics.filter_occlusion_solids(translated),"lamps":runtime._effective_lamps(coord)})
	var path:="res://tests/fixtures/source_incoming_masks_real.maskfixture"
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var({"seed":250821,"engine":Engine.get_version_info().hash,"fixtures":fixtures});file.close()
	print("SOURCE_MASK_FIXTURES ",JSON.stringify({"path":path,"count":fixtures.size(),"sha256":FileAccess.get_sha256(path)}))
	runtime.dispose();runtime.free();world.free();quit()
