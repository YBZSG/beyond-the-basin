extends SceneTree
## Read-only release preflight. Never extracts mesh faces or builds fallback data.
## May run as an external --script with --main-pack to inspect exported resources.
const Runtime = preload("res://scripts/water/source_water_runtime.gd")
const World = preload("res://scripts/world/pool_world.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Lighting = preload("res://scripts/rendering/pool_lighting.gd")
const RoomCache = preload("res://scripts/water/source_formal_snapshot_cache.gd")
const Store = preload("res://scripts/water/source_terrain_disk_cache.gd")
const Identity = preload("res://scripts/water/source_terrain_identity.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var seed_value := 250821
	var sizes: Array[int] = [768]
	var report_path := ""
	var require_pck := false
	var early_room: Variant = null
	for argument in OS.get_cmdline_user_args():
		if argument == "--all-quality": sizes = [384,768,1152]
		elif argument == "--require-pck": require_pck = true
		elif argument.begins_with("--seed="): seed_value = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--early-room="):
			var pair := argument.trim_prefix("--early-room=").split(",")
			if pair.size()==2: early_room = Vector2i(pair[0].to_int(),pair[1].to_int())
	var errors: Array[String] = []
	var signatures: Dictionary = {}
	for script: GDScript in Store.loaded_algorithms() + RoomCache.BUILDERS:
		if script.source_code.is_empty(): errors.append("Source unavailable for cache identity: " + script.resource_path)
		signatures[script.resource_path] = Identity.digest(script.source_code)
	var arguments := OS.get_cmdline_args()
	var main_pack := ""
	for index in arguments.size():
		if arguments[index] == "--main-pack" and index + 1 < arguments.size(): main_pack = arguments[index+1]
	if require_pck and main_pack.is_empty(): errors.append("--require-pck needs explicit --main-pack")
	var water := Runtime.new(); root.add_child(water); water.set_process(false)
	var world := World.new(); world.formal_mode = true; root.add_child(world); world.set_process(false)
	var lighting := Lighting.new()
	var origin := Vector2(world.Formal.COORDS[0]) * 32.0
	water._terrain_geometry_origin = origin; water.domain_origin = origin
	world.room_loaded.connect(func(room: Node3D, coord: Vector2i, layout: Dictionary):
		lighting.add_formal_lights(room,layout)
		water._rooms[coord] = weakref(room); water._layouts[coord] = layout)
	world.initialize(seed_value, Materials.new())
	# Match main's early travel before normal queued room completion. This catches
	# publication-order cache misses that a catalog-only bake cannot reveal.
	if early_room != null:
		if early_room not in World.Formal.COORDS: errors.append("Early room is not in the authored catalog: " + str(early_room))
		else: world.teleport_to_room(early_room)
	while not world._queue.is_empty(): world._process(1.0/60.0)
	var reader := RoomCache.new()
	reader.spec = RoomCache.specification(water._layouts,water._rooms.keys(),origin)
	reader.build()
	var entries: Array = []
	var algorithm := Store.algorithm_signature()
	if reader.result.is_empty(): errors.append(reader.miss_reason)
	else:
		for size in sizes:
			for coord: Vector2i in water._rooms:
				var identity := Identity.components(coord,size,origin,reader.result,water._layouts,water._effective_lamps(coord),0)
				var path := Store.BUNDLED_DIR + Store.file_name(identity.key)
				var payload := Store.read(path,identity.key,algorithm,{"size":size,"coord":coord,"origin":Vector2(coord)*32.0,"domain":96.0})
				if payload.is_empty(): errors.append("Missing or rejected exact terrain: " + path)
				entries.append({"coord":coord,"size":size,"path":path,"key":identity.key,
					"valid":not payload.is_empty(),"sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""})
	var report := {"pass":errors.is_empty(),"errors":errors,"seed":seed_value,"sizes":sizes,
		"scope":"Read-only exact authored asset validation; no fallback generation or GPU",
		"snapshot":reader.diagnostic,"snapshot_load_ms":reader.elapsed_ms,"terrain":entries,
		"algorithm":algorithm,"source_signatures":signatures,"main_pack":main_pack,
		"early_room":early_room,"publication_order":water._rooms.keys(),
		"standalone":OS.has_feature("standalone"),"godot":Engine.get_version_info().string}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report,"\t")+"\n")
		else: errors.append("Could not write requested report: " + report_path); report.pass = false
	water.dispose(); water.free(); world.free()
	print("SOURCE_FORMAL_CACHE_VALIDATE_", "PASS" if report.pass else "FAIL", " ",JSON.stringify(report))
	quit(0 if report.pass else 1)
