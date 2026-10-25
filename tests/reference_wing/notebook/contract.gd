extends SceneTree
const Candidate=preload("res://scripts/reference_wing/reference_exploration_notes.gd")
const Original=preload("res://scripts/gameplay/exploration_notes.gd")
func _initialize():
	var c=Candidate.new();var o=Original.new();c.enabled=true;o.enabled=true
	var old_record={"seed":"250821","mode":"original","coords":["0,0"],"archetypes":[{"id":"original:0","name":"Original"}],"last":"0,0","coordinate_limit_reached":false}
	c._worlds={"original:250821":old_record.duplicate(true)};o._worlds=c._worlds.duplicate(true)
	var before=c.get_snapshot()
	assert(c.begin_world(250821,"reference")==ERR_UNAVAILABLE)
	assert(c._active_key.is_empty())
	assert(c._scope_note.contains("原地图记录保留"))
	assert(not c.observe_player_room(null,Vector3.ZERO))
	assert(c.get_snapshot()==before)
	assert(not c._dirty)
	for mode in ["original","expanded","poolrooms","formal"]:
		assert(c.begin_world(250821,mode)==o.begin_world(250821,mode))
		assert(c.get_summary()==o.get_summary())
	assert(Original.validate_document(c.get_snapshot()).is_empty())
	c.free();o.free();print("REFERENCE_NOTEBOOK_PRESERVE_PASS 15 assertions; no storage access");quit()
