@tool
extends EditorScenePostImport
## Asset-only import metadata. No controller, physics or release event code.
## https://docs.godotengine.org/en/stable/classes/class_editorscenepostimport.html
const LOOPING := ["Idle", "Walk", "Run", "Hold", "Climb", "Wade", "Swim", "SwimIdle", "JumpAir"]
const CLIPS := ["Idle", "Walk", "Run", "Hold", "Climb", "Wade", "Swim", "SwimIdle", "JumpRise", "JumpAir", "Land", "ThrowCharge", "ThrowRelease", "ThrowRecover"]

func _post_import(scene: Node) -> Object:
	_apply_metadata(scene)
	_embed_contract(scene)
	return scene

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null

func _embed_contract(scene: Node) -> void:
	# JSON remains the editable authoring source. Imported root metadata survives
	# exports that intentionally omit raw JSON. Reimport when the contract changes.
	var path: String = get_source_file().get_base_dir().path_join("model_contract.json")
	if not FileAccess.file_exists(path):
		push_error("Natural hand contract embedding failed: missing " + path)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("Natural hand contract embedding failed: invalid JSON at " + path)
		return
	var contract: Dictionary = json.data
	var validator = load("res://scripts/art_pass/character/natural_hand_contract.gd")
	var validity: Dictionary = validator.validate(contract, _find_skeleton(scene), get_source_file(), true)
	if not validity.get("valid", false):
		push_error("Natural hand contract embedding rejected: " + str(validity))
		return
	scene.set_meta("poolcore_natural_hand_contract", contract.duplicate(true))
	scene.set_meta("poolcore_natural_hand_contract_source_sha256", FileAccess.get_sha256(path))

func _apply_metadata(node: Node) -> void:
	if node is AnimationPlayer:
		var seen: Array[String] = []
		for key: String in node.get_animation_list():
			var clip: String = key.get_slice("/", key.get_slice_count("/") - 1)
			if clip not in CLIPS:
				continue
			var animation: Animation = node.get_animation(key)
			animation.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
			if clip == "ThrowRelease":
				animation.add_marker("RELEASE", 0.0)
				animation.set_meta("release_seconds", 0.0)
				animation.set_meta("physics_authority", "Immediate controller launch; no delayed reattachment")
			seen.append(clip)
		if seen.size() != CLIPS.size():
			push_error("Natural hand import expected exactly 14 named source clips, got " + str(seen))
	for child: Node in node.get_children():
		_apply_metadata(child)
