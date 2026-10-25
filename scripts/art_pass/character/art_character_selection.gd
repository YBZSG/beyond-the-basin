extends RefCounted
## Setup-only, reversible authored model selection. Existing controller, mobile
## model, legacy flags, head/shadow policy and fabric application remain owned by
## main.gd and the unchanged PoolAvatar implementation.
const MobileProfile = preload("res://scripts/mobile/pool_mobile_profile.gd")
const NaturalAvatar = preload("res://scripts/art_pass/character/handmade_pool_avatar.gd")
const MODEL := "res://assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb"
const CONTRACT := "res://assets/character_refinement/natural_hand_finish/model_contract.json"
const DISABLE_FLAGS := ["--legacy-art-pass", "--legacy-art-character", "--legacy-avatar-model", "--legacy-water-actions"]

static func is_enabled() -> bool:
	if MobileProfile.is_mobile_session(): return false
	for flag: String in DISABLE_FLAGS:
		if flag in OS.get_cmdline_user_args(): return false
	return true

static func script_or_original(original: Script) -> Script:
	if not is_enabled(): return original
	if not ResourceLoader.exists(MODEL):
		push_warning("Authored character asset unavailable; retaining original avatar")
		return original
	# Full imported-rest validation still occurs before constructing the rig.
	# An invalid/unaccepted contract also falls back to the exact original graph.
	return NaturalAvatar

static func apply_selected_model(avatar: Node3D) -> void:
	if avatar.get_script() != NaturalAvatar: return
	avatar.model_path = MODEL
	avatar.hand_contract_path = CONTRACT
	avatar.allow_preview_contract = false
