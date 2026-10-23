extends SceneTree
## CPU-only exact authored snapshot + complete source terrain asset bake.
## Never initializes water renderers or changes scene quality/geometry.
const Runtime = preload("res://scripts/water/source_water_runtime.gd")
const World = preload("res://scripts/world/pool_world.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
const Lighting = preload("res://scripts/rendering/pool_lighting.gd")
const RoomCache = preload("res://scripts/water/source_formal_snapshot_cache.gd")
const Store = preload("res://scripts/water/source_terrain_disk_cache.gd")
const Prepare = preload("res://scripts/water/source_port/source_terrain_prepare.gd")
const Identity = preload("res://scripts/water/source_terrain_identity.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var water := Runtime.new(); root.add_child(water); water.set_process(false)
	var world := World.new(); world.formal_mode = true; root.add_child(world); world.set_process(false)
	var lighting := Lighting.new()
	var origin := Vector2(world.Formal.COORDS[0]) * 32.0
	water.domain_origin = origin; water._terrain_geometry_origin = origin
	world.room_loaded.connect(func(room: Node3D, coord: Vector2i, layout: Dictionary):
		lighting.add_formal_lights(room,layout)
		water._rooms[coord] = weakref(room); water._layouts[coord] = layout; water._invalidate_terrain(coord))
	world.initialize(1337, Materials.new()); world.complete_pending_streaming()
	var started := Time.get_ticks_usec()
	while water._terrain_room_snapshots.size() != water._rooms.size():
		water._pump_room_snapshots()
		await process_frame
		OS.delay_msec(1)
	var spec := RoomCache.specification(water._layouts,water._rooms.keys(),origin)
	var bundle := RoomCache.write_bundle(spec,water._terrain_room_snapshots)
	if not bundle.success: push_error("Failed to bake exact authored snapshot"); quit(1); return
	var ordered: Dictionary = {}; var colliders: Array = []; var solids: Array = []; var triangles := PackedVector3Array(); var per_room: Dictionary = {}
	for coord: Vector2i in water._rooms:
		var value: Dictionary = water._terrain_room_snapshots[coord]
		ordered[coord] = value; colliders.append_array(value.colliders); solids.append_array(value.solids)
		triangles.append_array(value.triangles); per_room[coord] = value.triangles
	var base := {"colliders":colliders,"solids":solids,"triangles":triangles,"triangles_by_room":per_room,
		"geometry_origin":origin,"layouts":water._layouts.duplicate(true),"domain":96.0,"revision":water._terrain_revision}
	var reports: Array = []; var success: bool = bundle.success
	var sizes: Array[int] = [768]
	for argument in OS.get_cmdline_user_args():
		if argument == "--all-quality": sizes = [384,768,1152]
	var optics_by_coord: Dictionary = {}
	for size in sizes:
		for coord: Vector2i in water._rooms:
			var lamps: Array = water._effective_lamps(coord)
			var identity := Identity.components(coord,size,origin,ordered,water._layouts,lamps,0)
			var snapshot := base.duplicate(false)
			snapshot.merge({"size":size,"coord":coord,"origin":Vector2(coord)*32.0,"lamps":lamps})
			var prior: Dictionary = optics_by_coord.get(coord,{})
			if prior.get("bvh_key","")==identity.bvh_key: snapshot.prepared_bvh=prior.packed_bvh
			if prior.get("mask_key","")==identity.mask_key: snapshot.prepared_occlusion=prior.occlusion
			var worker := Thread.new(); worker.start(Prepare.build.bind(snapshot),Thread.PRIORITY_LOW)
			while worker.is_alive(): await process_frame; OS.delay_msec(2)
			var payload: Dictionary = worker.wait_to_finish()
			optics_by_coord[coord]={"bvh_key":identity.bvh_key,"mask_key":identity.mask_key,"packed_bvh":payload.packed_bvh,
				"occlusion":{"masks":payload.masks,"filtered_solids":payload.filtered_solids}}
			var path := Store.BUNDLED_DIR + Store.file_name(identity.key)
			var algorithm := Store.algorithm_signature()
			var written := Store.write(path,identity.key,algorithm,payload)
			var verified := Store.read(path,identity.key,algorithm,snapshot)
			var exact := not verified.is_empty() and var_to_bytes(payload)==var_to_bytes(verified)
			success = success and written and exact
			var report := {"coord":coord,"size":size,"path":path,"bytes":FileAccess.get_file_as_bytes(path).size(),
				"written":written,"byte_exact_reload":exact,"timing_ms":payload.timing_ms,"key":identity.key,"algorithm":algorithm}
			reports.append(report); print("SOURCE_FORMAL_BAKE_ROOM ",JSON.stringify(report))
	var report := {"pass":success,"scope":"Exact CPU-prepared immutable authored terrain; not GPU pixels or target-device performance",
		"snapshot":bundle,"rooms":reports,"elapsed_ms":float(Time.get_ticks_usec()-started)/1000.0,
		"godot":Engine.get_version_info().string}
	var file := FileAccess.open("res://docs/verification/eight-hour/transition/formal-terrain-bake.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")+"\n")
	water.dispose(); water.free(); world.free()
	print("SOURCE_FORMAL_BAKE_", "PASS" if success else "FAIL", " ",JSON.stringify(report))
	quit(0 if success else 1)
