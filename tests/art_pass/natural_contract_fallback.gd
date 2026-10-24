extends SceneTree
## Actual imported-scene and packed-resource contract fallback, not full game.
const Avatar = preload("res://scripts/art_pass/character/natural_pool_avatar.gd")
const Contract = preload("res://scripts/art_pass/character/natural_hand_contract.gd")
const MODEL := "res://assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb"
const SOURCE := "res://assets/character_refinement/natural_hand_finish/model_contract.json"
var checks: Array[Dictionary] = []
var report_path := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()

func _case(label: String, path: String, scene: PackedScene, expected_valid: bool, expected_source: String, preview: bool) -> void:
	var avatar := Avatar.new()
	avatar.model_path = MODEL
	avatar.hand_contract_path = path
	avatar.allow_preview_contract = preview
	avatar.avatar_scene = scene
	root.add_child(avatar)
	avatar.set_process(false)
	avatar._load_visual()
	var valid: bool = bool(avatar._natural_contract_status.get("valid",false))
	var pass_case := valid == expected_valid and avatar._natural_contract_source == expected_source
	pass_case = pass_case and avatar.model_path == (MODEL if expected_valid else Avatar.FALLBACK_MODEL)
	pass_case = pass_case and (not avatar._allow_arm_handoff() if not expected_valid else true)
	checks.append({"case":label,"pass":pass_case,"status":avatar._natural_contract_status,"source":avatar._natural_contract_source,"loaded_path":avatar.model_path,"animation_tree_created":avatar._tree != null,"preview":preview})
	avatar.free()

func _run() -> void:
	var imported: PackedScene = load(MODEL)
	var source: Dictionary = Contract.read(SOURCE)
	_case("accepted_source_json_strict_production",SOURCE,imported,true,"source_json",false)
	_case("missing_json_uses_accepted_imported_metadata","user://intentionally_missing_contract.json",imported,true,"imported_scene_metadata",false)
	var malformed := FileAccess.open("user://invalid_contract.json",FileAccess.WRITE)
	malformed.store_string("{}")
	malformed.close()
	_case("existing_invalid_json_cannot_hide_behind_metadata","user://invalid_contract.json",imported,false,"source_json",false)
	var diagnostic_source: Dictionary = source.duplicate(true)
	diagnostic_source.acceptance = "diagnostic"
	var diagnostic_file := FileAccess.open("user://diagnostic_contract.json",FileAccess.WRITE)
	diagnostic_file.store_string(JSON.stringify(diagnostic_source))
	diagnostic_file.close()
	_case("unaccepted_source_rejected_by_production","user://diagnostic_contract.json",imported,false,"source_json",false)
	var without_meta: Node = imported.instantiate()
	without_meta.remove_meta(Avatar.IMPORTED_CONTRACT_META)
	var no_meta := PackedScene.new()
	var repack := no_meta.pack(without_meta)
	without_meta.free()
	checks.append({"case":"pack_no_metadata_fixture","pass":repack==OK,"error":repack})
	_case("missing_json_and_metadata_retain_original","user://intentionally_missing_contract.json",no_meta,false,"unavailable",false)
	var save_error := ResourceSaver.save(imported,"user://contract_model.scn")
	var packer := PCKPacker.new()
	var start := packer.pck_start("user://contract_model.pck")
	var add := packer.add_file("res://art_contract_packed/model.scn", "user://contract_model.scn") if start==OK else start
	var flush := packer.flush() if start==OK and add==OK else add
	var mounted := ProjectSettings.load_resource_pack("user://contract_model.pck") if flush==OK else false
	checks.append({"case":"serialized_pck_without_raw_json","pass":save_error==OK and start==OK and add==OK and flush==OK and mounted,"save":save_error,"pack_start":start,"add":add,"flush":flush,"mounted":mounted})
	if mounted:
		var restored: PackedScene = load("res://art_contract_packed/model.scn")
		_case("accepted_packed_metadata_survives_missing_json","user://intentionally_missing_contract.json",restored,true,"imported_scene_metadata",false)
	var passed := true
	for check: Dictionary in checks: passed = passed and bool(check.pass)
	var result := {"pass":passed,"checks":checks,"source_acceptance":source.acceptance,"scope":"Current-engine imported model and isolated packed-resource fallback; not full-game or export-preset validation."}
	if not report_path.is_empty():
		var out := FileAccess.open(report_path,FileAccess.WRITE)
		if out != null: out.store_string(JSON.stringify(result,"  "))
	print("NATURAL_CONTRACT_FALLBACK ",JSON.stringify(result))
	quit(0 if passed else 1)
