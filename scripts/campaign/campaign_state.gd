extends RefCounted
## Durable progression; begin/finish are separate so a failed landing never skips a chapter.
const Catalog = preload("res://scripts/campaign/campaign_catalog.gd")
const Objectives = preload("res://scripts/campaign/campaign_objectives.gd")
const REVISION := 2
var seed: int = Catalog.DEFAULT_SEED
var chapter_index := 0
var inventory: Dictionary = {}
var visited: Dictionary = {}
var checkpoint_room := ""
var pending_transition := false
var completed := false
var objective: Dictionary = {}
var elapsed := 0.0
var relaxed := false
var reduced_effects := false
var legacy_credit := 0
var repairs := 0

func _init(seed_value: int = Catalog.DEFAULT_SEED) -> void:
	seed = clampi(seed_value,0,Catalog.MAX_SEED)
	checkpoint_room = str(Catalog.chapter(0,seed).items[0].room_key)
	objective = Objectives.initial(0)

func current_chapter() -> Dictionary:
	return Catalog.chapter(chapter_index,seed)

func collect(id: String) -> bool:
	if completed or pending_transition or inventory.has(id): return false
	for item: Dictionary in current_chapter().items:
		if item.id == id:
			inventory[id] = true
			return true
	return false

func visit(room: String) -> bool:
	if completed or pending_transition: return false
	for item: Dictionary in current_chapter().items:
		if item.room_key == room:
			checkpoint_room = room
			var key: String = str(current_chapter().id)+":"+room
			var fresh := not visited.has(key)
			visited[key] = true
			return fresh
	return false

func can_depart() -> bool:
	return not completed and not pending_transition and bool(objective.solved)

func operate(id: String) -> Dictionary:
	if completed or pending_transition: return {"accepted":false,"message":"当前不能操作。"}
	var index := -1
	for i in range(current_chapter().items.size()):
		if current_chapter().items[i].id==id: index=i
	var result: Dictionary = Objectives.action(chapter_index,objective,index)
	if result.accepted:
		objective=result.snapshot
		_stamp_completion()
	return result

func advance_time(delta: float, playable: bool) -> void:
	if not playable or completed or pending_transition or not is_finite(delta) or delta<=0.0: return
	# A suspended/stalled process is not player time. Never charge a long frame.
	var step := minf(delta,0.25)
	objective=Objectives.tick(chapter_index,objective,step)
	if not relaxed and not objective.solved: elapsed=minf(86400.0,elapsed+step)
	_stamp_completion()

func _stamp_completion() -> void:
	if objective.solved:
		for item: Dictionary in current_chapter().items: inventory[item.id]=true

func pressure_limit() -> float:
	return Objectives.LIMITS[chapter_index]+float(legacy_credit)*30.0

func corruption() -> float:
	if relaxed or completed or objective.solved: return 0.0
	return clampf((elapsed-pressure_limit())/120.0,0.0,1.0)

func repair() -> bool:
	if pending_transition or completed or corruption()<=0.0: return false
	elapsed=pressure_limit()*0.55
	repairs=mini(repairs+1,1000000)
	return true

func retry_chapter() -> bool:
	if pending_transition or completed: return false
	objective=Objectives.initial(chapter_index);elapsed=0.0;repairs=0
	for item: Dictionary in current_chapter().items: inventory.erase(item.id)
	legacy_credit=0
	checkpoint_room=str(current_chapter().items[0].room_key)
	return true

func begin_transition() -> bool:
	if not can_depart(): return false
	pending_transition = true
	return true

func cancel_transition() -> void:
	pending_transition = false

func finish_transition() -> bool:
	if not pending_transition or completed: return false
	pending_transition = false
	if chapter_index == Catalog.CHAPTER_COUNT-1:
		completed = true
	else:
		chapter_index += 1
		objective=Objectives.initial(chapter_index);elapsed=0.0;legacy_credit=0;repairs=0
		checkpoint_room = str(current_chapter().items[0].room_key)
	return true

func collected_count() -> int:
	var count := 0
	for item: Dictionary in current_chapter().items:
		if inventory.has(item.id): count += 1
	return count

func serialize() -> Dictionary:
	return {"revision":REVISION,"seed":seed,"chapter_index":chapter_index,"inventory":inventory.keys(),"visited":visited.keys(),"checkpoint_room":checkpoint_room,"pending_transition":pending_transition,"completed":completed,"objective":objective.duplicate(true),"elapsed":elapsed,"relaxed":relaxed,"reduced_effects":reduced_effects,"legacy_credit":legacy_credit,"repairs":repairs}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=minimum and float(value)<=maximum

func restore(data: Variant) -> Dictionary:
	# Validate into locals. On failure this instance is unchanged.
	if not data is Dictionary: return {"ok":false,"reason":"Save root is not an object."}
	if not _integer(data.get("revision"),1,REVISION): return {"ok":false,"reason":"Unsupported save revision."}
	if not _integer(data.get("seed"),0,Catalog.MAX_SEED): return {"ok":false,"reason":"Invalid seed."}
	if not _integer(data.get("chapter_index"),0,Catalog.CHAPTER_COUNT-1): return {"ok":false,"reason":"Invalid chapter."}
	if not data.get("pending_transition") is bool or not data.get("completed") is bool: return {"ok":false,"reason":"Invalid transition state."}
	if not data.get("inventory") is Array or data.inventory.size()>28 or not data.get("visited") is Array or data.visited.size()>28: return {"ok":false,"reason":"Invalid collection list."}
	var new_seed := int(data.seed)
	var index := int(data.chapter_index)
	var all := Catalog.chapters(new_seed)
	var allowed := {}
	var allowed_rooms := {}
	var required := {}
	for chapter_number in range(index+1):
		for item: Dictionary in all[chapter_number].items:
			allowed[item.id] = true
			allowed_rooms[str(all[chapter_number].id)+":"+str(item.room_key)] = true
			if chapter_number<index: required[item.id]=true
	var new_inventory := {}
	for id: Variant in data.inventory:
		if not id is String or not allowed.has(id) or new_inventory.has(id): return {"ok":false,"reason":"Unknown, future or duplicate item."}
		new_inventory[id] = true
	for id: String in required:
		if not new_inventory.has(id): return {"ok":false,"reason":"A previous chapter is incomplete."}
	var new_visited := {}
	for id: Variant in data.visited:
		if not id is String or not allowed_rooms.has(id) or new_visited.has(id): return {"ok":false,"reason":"Unknown, future or duplicate room."}
		new_visited[id] = true
	var checkpoint: Variant = data.get("checkpoint_room")
	var checkpoint_ok := false
	for item: Dictionary in all[index].items:
		if item.room_key == checkpoint: checkpoint_ok=true
	if not checkpoint is String or not checkpoint_ok: return {"ok":false,"reason":"Invalid checkpoint room."}
	if data.completed and (index!=Catalog.CHAPTER_COUNT-1 or data.pending_transition): return {"ok":false,"reason":"Invalid completion state."}
	if data.completed or data.pending_transition:
		for item: Dictionary in all[index].items:
			if not new_inventory.has(item.id): return {"ok":false,"reason":"Incomplete departure checkpoint."}
	var new_objective: Dictionary = Objectives.initial(index)
	var new_elapsed := 0.0
	var new_relaxed := false
	var new_reduced := false
	var new_credit := 0
	var new_repairs := 0
	if int(data.revision)==1:
		# Never revoke a v1 cleared chapter. Partial gathered objects remain recorded;
		# new mechanisms start safe with 30 seconds grace for each retained object.
		for item: Dictionary in all[index].items:
			if new_inventory.has(item.id): new_credit+=1
		new_objective.solved=new_credit==all[index].items.size()
	else:
		if not Objectives.valid(index,data.get("objective")): return {"ok":false,"reason":"Invalid objective snapshot."}
		if not (data.get("elapsed") is int or data.get("elapsed") is float) or not is_finite(float(data.elapsed)) or float(data.elapsed)<0.0 or float(data.elapsed)>86400.0: return {"ok":false,"reason":"Invalid active-play timer."}
		if not data.get("relaxed") is bool or not data.get("reduced_effects") is bool: return {"ok":false,"reason":"Invalid accessibility options."}
		if not _integer(data.get("legacy_credit"),0,all[index].items.size()) or not _integer(data.get("repairs"),0,1000000): return {"ok":false,"reason":"Invalid recovery counters."}
		new_objective=data.objective.duplicate(true);new_elapsed=float(data.elapsed)
		for i in range(new_objective.values.size()):new_objective.values[i]=int(new_objective.values[i])
		for i in range(new_objective.sequence.size()):new_objective.sequence[i]=int(new_objective.sequence[i])
		new_relaxed=data.relaxed;new_reduced=data.reduced_effects;new_credit=int(data.legacy_credit);new_repairs=int(data.repairs)
		if (data.completed or data.pending_transition) and not new_objective.solved: return {"ok":false,"reason":"Unsolved departure checkpoint."}
		if new_objective.solved:
			for item: Dictionary in all[index].items:
				if not new_inventory.has(item.id): return {"ok":false,"reason":"Missing completed objective stamp."}
	objective=new_objective;elapsed=new_elapsed;relaxed=new_relaxed;reduced_effects=new_reduced;legacy_credit=new_credit;repairs=new_repairs
	seed=new_seed; chapter_index=index; inventory=new_inventory; visited=new_visited
	checkpoint_room=checkpoint; completed=bool(data.completed)
	# Crash or quit during the drop returns to the proven old room, never the unready next floor.
	pending_transition=false
	return {"ok":true,"reason":"","recovered_pending":bool(data.pending_transition)}
