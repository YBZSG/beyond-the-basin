extends SceneTree
## CPU-only production catalogue, restart-plan, save and notebook contracts.
## Main is instantiated outside the scene tree: the GPU game is never started.
const Catalog = preload("res://scripts/world/room_catalog.gd")
const Baseline = preload("res://tests/poolrooms_wing/fixtures/room_catalog.gd")
const Wing = preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd")
const World = preload("res://scripts/world/pool_world.gd")
const Notes = preload("res://scripts/gameplay/exploration_notes.gd")
const Restart = preload("res://scripts/app/world_restart.gd")
const Main = preload("res://scripts/main.gd")
const SEEDS = [0, 1, -1, 1337, 250821, 2147483647, -2147483648, 91357, 8675309, 777]
var checks: Array = []
var errors: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool, data: Dictionary = {}) -> void:
	data.merge({"name":label, "pass":passed})
	checks.append(data)
	if not passed: errors.append(label)
	print("POOLROOMS_MODE_CASE ", label, " ", passed)

func same(a: Variant, b: Variant) -> bool:
	# Semantic deep equality, independent of Dictionary insertion order and an
	# Array's optional type annotation. Values and nested collection sizes match.
	return a == b

func _catalogue() -> void:
	var original_mismatches: Array = []
	var expanded_mismatches: Array = []
	var outside_mismatches: Array = []
	var compared := 0
	for seed_value: int in SEEDS:
		var world := World.new()
		world.poolrooms_mode = true
		world.expanded_mode = true
		world.seed_value = seed_value
		for x: int in range(-5,6):
			for z: int in range(-5,6):
				var coord := Vector2i(x,z)
				compared += 1
				if not same(Catalog.room_layout(coord,seed_value,false),Baseline.room_layout(coord,seed_value,false)):
					original_mismatches.append([seed_value,x,z])
				if not same(Catalog.room_layout(coord,seed_value,true),Baseline.room_layout(coord,seed_value,true)):
					expanded_mismatches.append([seed_value,x,z])
				if not Wing.ANCHORS.has(coord):
					var world_layout: Dictionary=world.get_layout(coord).duplicate(true)
					var has_mode_marker: bool=world_layout.get("poolrooms_mode",false)==true
					world_layout.erase("poolrooms_mode")
					if not has_mode_marker or not same(world_layout,Baseline.room_layout(coord,seed_value,true)):
						outside_mismatches.append([seed_value,x,z])
		world.free()
	check("original_catalogue_matches_pre_wing_baseline",original_mismatches.is_empty(),{"samples":compared,"mismatches":original_mismatches})
	check("expanded_catalogue_matches_pre_wing_baseline",expanded_mismatches.is_empty(),{"samples":compared,"mismatches":expanded_mismatches})
	check("poolrooms_outside_three_anchors_matches_expanded",outside_mismatches.is_empty(),{"samples":compared-SEEDS.size()*3,"mismatches":outside_mismatches,"allowed_difference":"Exactly one required poolrooms_mode=true metadata field; every other layout field must match."})
	check("exact_three_anchors",same(Wing.ANCHORS,{Vector2i.ZERO:0,Vector2i.UP:1,Vector2i.RIGHT:2}))
	var issues: Array = []
	var water_samples := 0
	for seed_value: int in SEEDS:
		for coord: Vector2i in Wing.ANCHORS:
			var index: int = Wing.ANCHORS[coord]
			var layout: Dictionary = Wing.room_layout(coord,seed_value)
			if not same(layout,Wing.room_layout(coord,seed_value)): issues.append([seed_value,str(coord),"not deterministic"])
			if layout.variant != 15+index or not layout.poolrooms_wing or not layout.expanded_mode or not layout.expanded: issues.append([seed_value,str(coord),"identity"])
			if not same(layout.connections,[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]) or layout.portal_width != 8.0: issues.append([seed_value,str(coord),"portals"])
			var spawn: Vector3 = layout.spawn_local
			if absf(spawn.x)>11.5 or absf(spawn.z)>11.5 or not is_equal_approx(spawn.y,.6): issues.append([seed_value,str(coord),"spawn bounds"])
			for rect: Rect2 in layout.water_rects:
				water_samples += 1
				if rect.position.x < -16 or rect.position.y < -16 or rect.end.x > 16 or rect.end.y > 16 or rect.size.x<=0 or rect.size.y<=0: issues.append([seed_value,str(coord),"water bounds"])
				if rect.has_point(Vector2(spawn.x,spawn.z)): issues.append([seed_value,str(coord),"wet spawn"])
			for basin: Rect2 in Wing.BASINS[index]:
				var found := false
				for step: AABB in layout.water_steps:
					if is_equal_approx(step.position.x,basin.position.x) and is_equal_approx(step.position.z,basin.position.y) and is_equal_approx(step.size.x,basin.size.x) and is_equal_approx(step.size.z,basin.size.y) and is_equal_approx(step.end.y,-.22): found=true
				if not found: issues.append([seed_value,str(coord),"central basin depth is not .54 m"])
	check("anchor_determinism_identity_water_bounds_dry_spawn",issues.is_empty(),{"seeds":SEEDS,"water_rectangles":water_samples,"issues":issues})
	var default_world := World.new()
	check("default_world_has_no_poolrooms_opt_in",not default_world.poolrooms_mode and not default_world.expanded_mode and same(default_world.get_layout(Vector2i.ZERO),Catalog.room_layout(Vector2i.ZERO,1337,false)))
	default_world.free()
	var geometry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://source_provenance/poolrooms_wing/geometry.json"))
	var sync_issues:Array=[]
	var checked_steps:=0
	for coord:Vector2i in Wing.ANCHORS:
		var layout:Dictionary=Wing.room_layout(coord,250821)
		var contract:Dictionary=geometry.rooms[Wing.FILES[Wing.ANCHORS[coord]]]
		if layout.water_steps.size()!=contract.water_steps.size():sync_issues.append([str(coord),"water step count"])
		for i:int in mini(layout.water_steps.size(),contract.water_steps.size()):
			var expected:Dictionary=contract.water_steps[i]
			var pos:=Vector3(expected.position[0],expected.position[1],expected.position[2])
			var size:=Vector3(expected.size[0],expected.size[1],expected.size[2])
			var step:AABB=layout.water_steps[i]
			checked_steps+=1
			if not step.position.is_equal_approx(pos) or not step.size.is_equal_approx(size):sync_issues.append([str(coord),"water step",i])
		var spawn:Vector3=layout.spawn_local
		if not spawn.is_equal_approx(Vector3(contract.spawn_local[0],contract.spawn_local[1],contract.spawn_local[2])):sync_issues.append([str(coord),"spawn"])
		if not is_equal_approx(layout.interior_ceiling,contract.interior_ceiling):sync_issues.append([str(coord),"interior ceiling"])
	check("catalogue_exactly_syncs_final_geometry_water_steps_spawn_ceiling",sync_issues.is_empty(),{"water_step_boxes":checked_steps,"issues":sync_issues})

func _restart_and_settings() -> void:
	check("runtime_mode_enumerations_include_poolrooms",Main.SPAWN_MODES == ["original","formal","expanded","poolrooms"] and "poolrooms" in Restart.MODES and "--poolrooms-wing" in Restart.WORLD_FLAGS)
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("cli_and_world_wiring_source_contract",'if "--poolrooms-wing" in OS.get_cmdline_user_args(): _spawn_mode="poolrooms"' in main_source and 'world.expanded_mode = _spawn_mode in ["expanded", "poolrooms"]' in main_source and 'world.poolrooms_mode = _spawn_mode == "poolrooms"' in main_source,{"scope":"Source wiring only, not a full-game CLI launch."})
	var plan_issues: Array = []
	for separator: String in ["--","++"]:
		var engine_args: Array = ["--rendering-method","gl_compatibility","--rendering-driver","opengl3","--gpu-index","2"]
		var users: Array = ["--expanded-world","--poolrooms-wing","--original-world","--custom-preserved=hello"]
		var contract := {"version":1,"executable":"/tmp/Poolcore","pack":"/tmp/Poolcore.pck","args":engine_args+[separator]+users}
		var plan: Dictionary = Restart.build_plan(contract,"/tmp/Poolcore",PackedStringArray(users),"Linux","gl_compatibility","opengl3")
		var expected := PackedStringArray(engine_args+[separator,"--custom-preserved=hello"])
		if not plan.ok or plan.get("args") != expected: plan_issues.append({"separator":separator,"plan":plan})
		contract.args=engine_args+[separator,"--poolrooms-wing","--qa"]
		if Restart.build_plan(contract,"/tmp/Poolcore",PackedStringArray(["--poolrooms-wing","--qa"]),"Linux","gl_compatibility","opengl3").ok: plan_issues.append({"error":"QA launch allowed"})
	check("restart_strips_mode_flags_preserves_exact_nonworld_arguments",plan_issues.is_empty(),{"issues":plan_issues})
	var forbidden: Array = []
	for flag: String in ["--headless","--script","--editor","--check-only"]:
		var contract := {"version":1,"executable":"/tmp/Poolcore","pack":"/tmp/Poolcore.pck","args":[flag,"--","--poolrooms-wing"]}
		if Restart.build_plan(contract,"/tmp/Poolcore",PackedStringArray(["--poolrooms-wing"]),"Linux","gl_compatibility","opengl3").ok: forbidden.append(flag)
	check("restart_refuses_test_editor_launches",forbidden.is_empty(),{"unexpected_allowed":forbidden})
	var main := Main.new()
	var cfg := ConfigFile.new()
	cfg.set_value("unrelated","sentinel","preserve me")
	cfg.set_value("game","spawn_mode","poolrooms")
	cfg.set_value("game","seed",91357)
	var initial_saved := cfg.save("user://settings.cfg")
	main._load_settings()
	check("poolrooms_selection_loads_without_restart",initial_saved==OK and main._spawn_mode=="poolrooms" and main.world_seed==91357 and not OS.is_restart_on_exit_set() and not main._world_restart._requested)
	var saved: Error = main._save_settings("poolrooms",-12345,true)
	var reloaded := ConfigFile.new()
	var loaded := reloaded.load("user://settings.cfg")
	check("atomic_poolrooms_selection_save_preserves_unrelated_settings",saved==OK and loaded==OK and reloaded.get_value("game","spawn_mode","")=="poolrooms" and reloaded.get_value("game","seed",0)==-12345 and reloaded.get_value("unrelated","sentinel","")=="preserve me")
	main._load_settings()
	check("saved_selection_round_trips_without_auto_restart",main._spawn_mode=="poolrooms" and main.world_seed==-12345 and not OS.is_restart_on_exit_set())
	reloaded.set_value("game","spawn_mode","not_a_mode")
	reloaded.save("user://settings.cfg")
	main._load_settings()
	check("invalid_saved_mode_falls_back_to_original",main._spawn_mode=="original")
	var calls := {"save":0,"quit":0}
	var save_callback := func(_mode:String,_seed:int)->Error: calls.save+=1;return OK
	var quit_callback := func()->void: calls.quit+=1
	var restart := Restart.new()
	var busy: Dictionary = restart.request("poolrooms",1337,true,save_callback,quit_callback)
	var invalid: Dictionary = restart.request("bogus",1337,false,save_callback,quit_callback)
	var unsupported: Dictionary = restart.request("poolrooms",1337,false,save_callback,quit_callback)
	check("rejected_restart_never_saves_quits_or_arms_loop",not busy.ok and not invalid.ok and not unsupported.ok and calls.save==0 and calls.quit==0 and not restart._requested and not OS.is_restart_on_exit_set())
	main.free()

func _notebook() -> void:
	var path := "user://poolrooms-contract-notes-"+str(OS.get_process_id())+".json"
	var note := Notes.new()
	var initialized := note.initialize_store(true,path)
	var began := note.begin_world(250821,"poolrooms")
	var world := World.new()
	world.seed_value=250821
	world.poolrooms_mode=true
	world.expanded_mode=true
	var observations: Array = []
	var coords: Array[Vector2i] = [Vector2i.ZERO,Vector2i.UP,Vector2i.RIGHT,Vector2i.LEFT,Vector2i(2,2)]
	for coord: Vector2i in coords:
		world.current_room=coord
		var room := Node3D.new()
		room.set_meta("complete",true)
		world.resident_rooms[coord]=room
		world.add_child(room)
		observations.append(note.observe_player_room(world,Vector3(coord.x*32,0,coord.y*32)))
	var summary: Dictionary=note.get_summary()
	check("notebook_records_poolrooms_and_expanded_fallback_in_own_world",initialized==OK and began==OK and not false in observations and summary.mode=="poolrooms" and summary.recorded_coordinates==5 and summary.archetypes.size()>=4,{"summary":summary})
	var document: Dictionary=note.get_snapshot()
	check("notebook_poolrooms_document_valid",Notes.validate_document(document).is_empty())
	var saved: Error=note.flush()
	var second:=Notes.new()
	var second_loaded:=second.initialize_store(true,path)
	second.begin_world(250821,"poolrooms")
	# Compare canonical JSON because schema_version is an int in the live schema
	# and a float when parsed from JSON; that is not a persisted-data change.
	check("notebook_round_trip_matches_snapshot",saved==OK and second_loaded==OK and JSON.stringify(second.get_snapshot())==JSON.stringify(document),{"save_error":saved,"load_error":second_loaded})
	var isolated:=second.begin_world(250821,"expanded")
	check("same_seed_other_mode_has_separate_record",isolated==OK and second.get_summary().recorded_coordinates==0 and Notes.world_key(250821,"poolrooms")!="expanded:250821")
	var wrong_mode:=second.observe_player_room(world,Vector3(64,0,64))
	check("notebook_rejects_active_world_mode_mismatch",not wrong_mode and second.get_summary().recorded_coordinates==0)
	var malformed: Array=[]
	var wrong: Dictionary=document.duplicate(true)
	wrong.worlds[0].mode="expanded"
	malformed.append(Notes.validate_document(wrong))
	wrong=document.duplicate(true);wrong.worlds[0].archetypes[0].id="poolrooms:not_a_room";malformed.append(Notes.validate_document(wrong))
	wrong=document.duplicate(true);wrong.worlds[0].coords.append("0,0");malformed.append(Notes.validate_document(wrong))
	wrong=document.duplicate(true);wrong.worlds[0].mode="unknown";malformed.append(Notes.validate_document(wrong))
	check("notebook_rejects_cross_mode_unknown_duplicate_documents",not "" in malformed,{"validation_messages":malformed})
	var corrupted := path+"-corrupt"
	var corrupt_text := JSON.stringify(wrong)
	FileAccess.open(corrupted,FileAccess.WRITE).store_string(corrupt_text)
	var blocked:=Notes.new()
	var rejected:=blocked.initialize_store(true,corrupted)
	blocked.begin_world(250821,"poolrooms")
	blocked.observe_player_room(world,Vector3(64,0,64))
	var flush_rejected:=blocked.flush()
	check("malformed_existing_notebook_is_read_only_and_preserved",rejected==ERR_FILE_CORRUPT and blocked.get_summary().read_only and flush_rejected==ERR_FILE_CANT_WRITE and FileAccess.get_file_as_string(corrupted)==corrupt_text)
	for node: Node in [note,second,blocked,world]: node.free()

func _run() -> void:
	_catalogue()
	_restart_and_settings()
	_notebook()
	var report := {"pass":errors.is_empty(),"errors":errors,"engine":Engine.get_version_info(),"checks":checks,"baseline":"Pre-wing git HEAD 980531f6d25c6ba9581d20036dd6765319b5f93d; immutable test fixtures with source hashes.","scope":"Godot CPU runtime catalogue/restart-plan/settings/notebook checks. No game startup, renderer acceptance, GPU water, restart process spawning, asset export, or Android execution."}
	FileAccess.open("res://output/poolrooms_wing/contracts/mode-contract.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("POOLROOMS_MODE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"cases":checks.size()}))
	quit(0 if errors.is_empty() else 1)
