extends RefCounted
## Durable progression; begin/finish are separate so a failed landing never skips a chapter.
const Catalog = preload("res://scripts/campaign/campaign_catalog.gd")
const REVISION := 1
var seed: int = Catalog.DEFAULT_SEED
var chapter_index := 0
var inventory: Dictionary = {}
var visited: Dictionary = {}
var checkpoint_room := ""
var pending_transition := false
var completed := false

func _init(seed_value: int = Catalog.DEFAULT_SEED) -> void:
	seed = clampi(seed_value,0,Catalog.MAX_SEED)
	checkpoint_room = str(Catalog.chapter(0,seed).items[0].room_key)

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
	if completed or pending_transition: return false
	for item: Dictionary in current_chapter().items:
		if not inventory.has(item.id): return false
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
		checkpoint_room = str(current_chapter().items[0].room_key)
	return true

func collected_count() -> int:
	var count := 0
	for item: Dictionary in current_chapter().items:
		if inventory.has(item.id): count += 1
	return count

func serialize() -> Dictionary:
	return {"revision":REVISION,"seed":seed,"chapter_index":chapter_index,"inventory":inventory.keys(),"visited":visited.keys(),"checkpoint_room":checkpoint_room,"pending_transition":pending_transition,"completed":completed}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=minimum and float(value)<=maximum

func restore(data: Variant) -> Dictionary:
	# Validate into locals. On failure this instance is unchanged.
	if not data is Dictionary: return {"ok":false,"reason":"Save root is not an object."}
	if not _integer(data.get("revision"),REVISION,REVISION): return {"ok":false,"reason":"Unsupported save revision."}
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
	seed=new_seed; chapter_index=index; inventory=new_inventory; visited=new_visited
	checkpoint_room=checkpoint; completed=bool(data.completed)
	# Crash or quit during the drop returns to the proven old room, never the unready next floor.
	pending_transition=false
	return {"ok":true,"reason":"","recovered_pending":bool(data.pending_transition)}
