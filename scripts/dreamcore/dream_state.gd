extends RefCounted
const Catalog = preload("res://scripts/dreamcore/dream_catalog.gd")
const VERSION := 1
var scene_id := "lime_gallery"
var progress: Dictionary = {}
var relaxed := true
var reduced_effects := true
var seed := 250821
func entry(id: String = "") -> Dictionary:
	if id.is_empty(): id = scene_id
	if not progress.has(id): progress[id] = {"values":{},"observed":{},"solved":false,"elapsed":0.0,"completed":false}
	return progress[id]
func operate(spec: Dictionary) -> bool:
	var current := entry()
	if not prerequisite(spec): return false
	var kind := str(spec.get("kind",""))
	if kind == "observe": return false
	if kind == "broadcast":
		# A sequential handoff, not three independent combination-lock dials.
		# Repeating an already acknowledged relay is harmless and wrong order
		# never destroys prior acknowledgements or sends the player back.
		var ordinal := int(spec.get("target",1))
		var cursor := int(current.observed.get("broadcast_cursor",0))
		if cursor+1 != ordinal: return false
		current.values[str(spec.id)] = ordinal
		current.observed.broadcast_cursor = ordinal
	elif kind == "departure_signal":
		current.values[str(spec.id)] = 1-int(current.values.get(str(spec.id),0))
	else:
		# New room-local devices may have two or three meaningful detents.
		# Absent opt-in retains the exact four-state behavior of existing rooms.
		var state_count := clampi(int(spec.get("state_count",4)),2,4)
		current.values[str(spec.id)] = (int(current.values.get(str(spec.id),0))+1)%state_count
	return true
func prerequisite(spec: Dictionary) -> bool:
	var required := str(spec.get("requires",""))
	return required.is_empty() or int(entry().values.get(required,0)) == int(spec.get("requires_value",1))
func advance(delta: float, playable: bool, specs: Array, observed_id: String = "") -> void:
	if not playable or not is_finite(delta) or delta <= 0: return
	var current := entry()
	var step := minf(delta,.25)
	if not relaxed and not current.solved: current.elapsed += step
	for spec: Dictionary in specs:
		if spec.get("kind","") == "observe" and str(spec.id) == observed_id and prerequisite(spec):
			current.observed[str(spec.id)] = minf(float(spec.get("observation_seconds",12)),float(current.observed.get(str(spec.id),0))+step)
	var solved := not specs.is_empty()
	var latch_completion := scene_id in Catalog.UNCANNY_IDS and not specs.is_empty()
	for spec: Dictionary in specs:
		latch_completion = latch_completion and bool(spec.get("latch_completion",false))
		solved = solved and prerequisite(spec)
		if spec.get("kind","") == "observe":
			solved = solved and float(current.observed.get(str(spec.id),0)) >= float(spec.get("observation_seconds",12))
		else: solved = solved and int(current.values.get(str(spec.id),0)) == int(spec.get("target",1))
	# A new opt-in spatial device stays freely reversible after understanding
	# it once. Reuse the existing saved solved flag; no new schema or old-room
	# prerequisite semantics. All stations must opt in, never just one of many.
	current.solved = solved or (latch_completion and bool(current.solved))
func corruption() -> float:
	return 0.0 if relaxed or entry().solved else clampf((float(entry().elapsed)-900.0)/600.0,0.0,1.0)
func repair() -> void: entry().elapsed = 0.0
func serialize() -> Dictionary:
	return {"version":VERSION,"scene_id":scene_id,"progress":progress.duplicate(true),"relaxed":relaxed,"reduced_effects":reduced_effects,"seed":str(seed)}
func restore(data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("version") != VERSION: return {"ok":false,"reason":"unknown_version"}
	if data.get("scene_id","") not in Catalog.IDS or not data.get("progress") is Dictionary: return {"ok":false,"reason":"invalid_scene"}
	if not data.get("relaxed") is bool or not data.get("reduced_effects") is bool: return {"ok":false,"reason":"invalid_settings"}
	var incoming: Dictionary = data.progress
	if incoming.size() > Catalog.IDS.size(): return {"ok":false,"reason":"oversized_progress"}
	for id: Variant in incoming:
		if id not in Catalog.IDS or not incoming[id] is Dictionary: return {"ok":false,"reason":"invalid_progress"}
		var row: Dictionary = incoming[id]
		if not row.get("values") is Dictionary or not row.get("observed") is Dictionary or not row.get("solved") is bool or not row.get("completed") is bool: return {"ok":false,"reason":"invalid_entry"}
		if row.values.size()>16 or row.observed.size()>16: return {"ok":false,"reason":"oversized_entry"}
		if not _number(row.get("elapsed")) or float(row.elapsed)<0 or float(row.elapsed)>1e8: return {"ok":false,"reason":"invalid_elapsed"}
		for key: Variant in row.values:
			var value: Variant = row.values[key]
			if not key is String or key.length()>80 or not _number(value) or float(value)!=floorf(float(value)) or int(value)<0 or int(value)>3: return {"ok":false,"reason":"invalid_value"}
			# Lightweight declared new-room schema; never load builder geometry
			# or assets while checking save bytes. Old nine controls stay 0..3.
			if Catalog.UNCANNY_BINARY_CONTROLS.has(id):
				if key != Catalog.UNCANNY_BINARY_CONTROLS[id] or int(value) > 1: return {"ok":false,"reason":"invalid_value"}
		for key: Variant in row.observed:
			if not key is String or key.length()>80 or not _number(row.observed[key]) or float(row.observed[key])<0 or float(row.observed[key])>3600: return {"ok":false,"reason":"invalid_observation"}
	var seed_text := str(data.get("seed",""))
	if not seed_text.is_valid_int() or seed_text.length()>10 or int(seed_text)<0 or int(seed_text)>2147483647: return {"ok":false,"reason":"invalid_seed"}
	scene_id = data.scene_id; progress = incoming.duplicate(true)
	relaxed = data.relaxed; reduced_effects = data.reduced_effects; seed = int(seed_text)
	return {"ok":true,"recovered_pending":false}
static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
