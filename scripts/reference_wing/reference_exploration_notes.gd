extends "res://scripts/gameplay/exploration_notes.gd"
## Keep the old v1 notebook byte-compatible with the rollback project.
## The five-room reference wing is playable, but does not add an unknown mode
## to the existing save format. Legacy worlds still use the original behavior.
func begin_world(seed_value: int, spawn_mode: String) -> Error:
	if spawn_mode != "reference":
		return super.begin_world(seed_value, spawn_mode)
	if not enabled: return ERR_UNAVAILABLE
	_active_key = ""
	_active_seed = str(seed_value)
	_active_mode = spawn_mode
	_last_observation = ""
	_scope_note = "五境参考场景暂不记录探索手记；原地图记录保留。 / Reference wing is not recorded; existing discoveries are retained."
	return ERR_UNAVAILABLE
