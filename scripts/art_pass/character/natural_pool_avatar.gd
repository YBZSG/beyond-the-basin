extends "res://scripts/art_pass/character/handoff_pool_avatar.gd"
## Additive visual-only natural-hand binding. The controller, source animation
## clocks, collision, water coupling, head/mirror masks and original helpers stay
## unchanged. A bad/missing contract falls back before constructing the rig.
const Contract = preload("res://scripts/art_pass/character/natural_hand_contract.gd")
const NaturalFingers = preload("res://scripts/art_pass/character/natural_finger_poses.gd")
const NaturalHandIK = preload("res://scripts/art_pass/character/natural_hand_ik.gd")
const FALLBACK_MODEL := "res://assets/water_motion/explorer_water_motion.scn"
@export var hand_contract_path := "res://assets/character_refinement/model_contract.json"
@export var allow_preview_contract := false
const IMPORTED_CONTRACT_META := "poolcore_natural_hand_contract"
var _natural_contract_source := "unavailable"
var _natural_contract: Dictionary = {}
var _natural_contract_status: Dictionary = {"valid":false,"reason":"not_loaded"}

func _init() -> void:
	arm_air_swim_handoff_enabled = "--no-arm-swim-continuation" not in OS.get_cmdline_user_args()

func _allow_arm_handoff() -> bool:
	# A rejected natural model must retain the exact original animation graph.
	return super._allow_arm_handoff() and bool(_natural_contract_status.get("valid",false))

func _load_visual() -> void:
	var source_json_exists := FileAccess.file_exists(hand_contract_path)
	_natural_contract = Contract.read(hand_contract_path)
	_natural_contract_source = "source_json" if source_json_exists else "unavailable"
	var packed: PackedScene = avatar_scene
	if packed == null and ResourceLoader.exists(model_path): packed = load(model_path) as PackedScene
	if packed != null:
		# Instantiation uses shared mesh/animation resources. The short-lived probe
		# contains no running scene/tree or player and is freed before actual setup.
		var probe: Node = packed.instantiate()
		# Non-resource JSON is not guaranteed to survive export filters. The
		# asset post-import packs the same editable source data in the scene.
		# Never use it to conceal an existing but invalid source JSON file.
		if not source_json_exists and probe.has_meta(IMPORTED_CONTRACT_META):
			var embedded: Variant = probe.get_meta(IMPORTED_CONTRACT_META)
			if embedded is Dictionary:
				_natural_contract = embedded.duplicate(true)
				_natural_contract_source = "imported_scene_metadata"
		_natural_contract_status = Contract.validate(_natural_contract,Contract.find_skeleton(probe),model_path,allow_preview_contract)
		probe.free()
	else:
		_natural_contract_status = {"valid":false,"reason":"model_unavailable"}
	if not bool(_natural_contract_status.get("valid",false)):
		push_warning("Natural hand contract rejected; original avatar retained: " + str(_natural_contract_status))
		_natural_contract.clear()
		model_path = FALLBACK_MODEL
		avatar_scene = null
	super._load_visual()

func _build_animation_tree() -> void:
	super._build_animation_tree()
	if _natural_contract.is_empty() or not bool(_natural_contract_status.get("valid",false)): return
	var hands := NaturalHandIK.new()
	hands.model_contract = _natural_contract
	hands.setup(_skeleton)
	_hand_ik = hands
	var fingers := NaturalFingers.new()
	fingers.model_contract = _natural_contract
	fingers.setup(_skeleton)
	_finger_poses = fingers

func get_debug_state() -> Dictionary:
	var result: Dictionary = super.get_debug_state()
	result.natural_hand_contract = _natural_contract_status.duplicate()
	result.natural_hand_model_path = model_path
	result.natural_hand_contract_source = _natural_contract_source
	return result
