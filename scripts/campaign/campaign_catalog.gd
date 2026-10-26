extends RefCounted
## A finite itinerary over the real existing catalog. Does not modify source RNG.
const Source = preload("res://scripts/world/room_catalog.gd")
const Expanded = preload("res://scripts/world/expanded_room_catalog.gd")
const Wing = preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd")
const Reference = preload("res://scripts/reference_wing/reference_catalog.gd")
const Formal = preload("res://scripts/world/formal_rooms.gd")
const DEFAULT_SEED := 250821
const CHAPTER_COUNT := 6
const MAX_SEED := 2147483647
static var _cache:Dictionary={}

static func room_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]

static func _item(id: String, label: String, coord: Vector2i, pos: Vector3, room_name: String) -> Dictionary:
	return {"id":id,"label":label,"coord":coord,"local_position":pos,"room_name":room_name,"room_key":room_key(coord)}

static func _original_coords(seed_value: int) -> Dictionary:
	var result := {}
	for coord: Vector2i in Source.ANCHORS:
		result[int(Source.ANCHORS[coord])] = coord
	# Search in concentric rings: deterministic, bounded and nearest first.
	for radius in range(1, 33):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(z)) != radius: continue
				var coord := Vector2i(x,z)
				var variant := int(Source.room_layout(coord, seed_value).variant)
				if not result.has(variant): result[variant] = coord
		if result.size() == 8: return result
	# No fabricated fallback identity if a future generator cannot find all types.
	return result

static func chapters(seed_value: int = DEFAULT_SEED) -> Array[Dictionary]:
	if _cache.has(seed_value):return _cache[seed_value]
	var items: Array[Dictionary] = []
	var coords := _original_coords(seed_value)
	var names := ["值班室铜钥匙", "漂流防水筒", "水位刻度片", "拱厅铭牌", "夜班保险丝", "跳台检修卡", "连池阀柄", "柱厅线路图"]
	for index in range(8):
		if not coords.has(index): continue
		items.append(_item("source_%d" % index,names[index],coords[index],Vector3(0,.35,13.0),Source.ATMOSPHERES[index].name))
	var result: Array[Dictionary] = [{"id":"lost_shift","title":"第一章 · 无人的值班","mode":"original","objective":"找回八处值班记录，恢复检修通道。","items":items,"departure_label":"开启检修井","story":"你沿着还在工作的灯，寻找上一班留下的交接物。"}]
	items = []
	var expanded_coords := [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]
	var expanded_labels := ["更衣柜门牌", "静浴阀门芯", "天窗反射片", "设备室通行章"]
	for index in range(4):
		items.append(_item("facility_"+Expanded.MODULES[index],expanded_labels[index],expanded_coords[index],Vector3(0,1.3,9.8),Expanded.NAMES[index]))
	result.append({"id":"maintenance","title":"第二章 · 恢复水路","mode":"expanded","objective":"收集四件维护部件，打开下层回水通道。","items":items,"departure_label":"打开回水井","story":"水路依旧通向更深处，检修记录却停在了昨天。"})
	items = []
	var wing_coords := [Vector2i.ZERO,Vector2i.UP,Vector2i.RIGHT]
	var wing_labels := ["曲廊黄铜徽章", "水廊压力表", "圆门锁芯"]
	for index in range(3):
		items.append(_item("wing_"+Wing.MODULES[index],wing_labels[index],wing_coords[index],Wing.SPAWNS[index]+Vector3(0,.75,-.8),Wing.NAMES[index]))
	result.append({"id":"return_water","title":"第三章 · 回水的方向","mode":"poolrooms","objective":"找齐三件回水装置，解锁旧浴场的下行口。","items":items,"departure_label":"释放下行舱","story":"反光里的门重复出现，但只有一扇与水声相连。"})
	items = []
	var reference_labels := ["阶厅编号瓷片", "暗柱灯管端盖", "青窗红色通行牌", "八角池刻度环", "圆窗房旧手环"]
	for index in range(5):
		items.append(_item("reference_"+Reference.IDS[index],reference_labels[index],Reference.COORDS[index],Reference.SPAWNS[index]+Vector3(0,.75,-.65),Reference.NAMES[index]))
	result.append({"id":"five_memories","title":"第四章 · 五间记忆","mode":"reference","objective":"五处遗留物组成最后一份交接记录。","items":items,"departure_label":"进入深层采光井","story":"这里既像公共浴场，也像被水浸湿的记忆。"})
	items = []
	var quiet_coords := [Vector2i.ZERO,Vector2i.UP,Vector2i.RIGHT]
	var quiet_labels := ["环庭通风栅片", "穹廊检修尺", "旧更衣柜手牌"]
	for index in range(3):
		items.append(_item("quiet_%d"%index,quiet_labels[index],quiet_coords[index],Vector3(0,.35,13.0),Source.ATMOSPHERES[8+index].name))
	result.append({"id":"quiet_archive","title":"第五章 · 封存的静翼","mode":"original","objective":"取回三件旧馆遗留物，重启通往采光层的通风井。","items":items,"departure_label":"打开通风井","story":"新馆的交接记录，指向一片早已封存的旧馆。"})
	items = []
	var formal_labels := ["主池泵房钥匙", "拱廊玻璃棱片", "侧池排水塞", "天井日照刻度", "穹顶出口铭牌"]
	for index in range(5):
		var coord: Vector2i = Formal.COORDS[index]
		var spawn: Vector3 = Formal.spawn(coord)-Vector3(coord.x*32.0,0,coord.y*32.0)
		items.append(_item("formal_%d"%index,formal_labels[index],coord,spawn+Vector3(0,.75,-.7),Formal.layout(coord,seed_value).name))
	result.append({"id":"daylight","title":"第六章 · 光的出口","mode":"formal","objective":"完成最后五处交接，开启回到地面的出口。","items":items,"departure_label":"完成交接 · 开启出口","story":"水不再向下流，远处终于有了风声。"})
	# Explicit source identity separates authored originals from display mode.
	for entry: Dictionary in result:
		entry["room_specs"] = []
		for item_index in range(entry.items.size()):
			var item: Dictionary = entry.items[item_index]
			var source_mode: String = "quiet" if entry.id=="quiet_archive" else str(entry.mode)
			entry.room_specs.append({"coord":item.coord,"source_coord":item.coord,"source_mode":source_mode,"source_index":item_index+8 if source_mode=="quiet" else item_index})
	var goals: Array = ["隔离故障照明支路并恢复馈电。", "平衡相互牵制的三路水压。", "重定向回水并稳定出口水位。", "按建筑回声重演四拍记忆。", "按联锁次序恢复旧馆通风。", "汇聚日光并开启穹顶出口。"]
	var departures: Array = ["通过侧向检修门", "启动泵房升降台", "穿过弯曲回水廊", "推开记忆屏风", "打开通风检修门", "走向日光出口"]
	var stories: Array = ["上一班没有留下钥匙，只留下仍在呼吸的电路。", "水压彼此牵制，静止的指针也能讲述管路的方向。", "出口不在最响的水声后面，而在两段流向相遇的地方。", "空间记得经过它的次序。", "先让噪声停止，再让空气流动。", "光需要方向，不需要通行证。"]
	for i in range(result.size()):
		result[i].objective=goals[i];result[i].departure_label=departures[i];result[i].story=stories[i]
	_cache[seed_value]=result
	return result

static func chapter(index: int, seed_value: int = DEFAULT_SEED) -> Dictionary:
	if index < 0 or index >= CHAPTER_COUNT: return {}
	return chapters(seed_value)[index]

static func item_by_id(id: String, seed_value: int = DEFAULT_SEED) -> Dictionary:
	for entry: Dictionary in chapters(seed_value):
		for item: Dictionary in entry.items:
			if item.id == id: return item
	return {}
