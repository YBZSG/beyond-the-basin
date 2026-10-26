extends SceneTree
const FontAsset=preload("res://assets/fonts/campaign/PoolCoreCampaignSC.otf")
const Objectives=preload("res://scripts/campaign/campaign_objectives.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:
	var tested:FontFile=FontAsset.duplicate();tested.allow_system_fallback=false
	var text:="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 : / · → （）% [Q] [E]"
	for file:String in ["campaign_runtime.gd","campaign_objectives.gd","campaign_arrivals.gd","campaign_interactables.gd","campaign_state.gd"]:text+=FileAccess.get_file_as_string("res://scripts/campaign/"+file)
	for chapter:Dictionary in Catalog.chapters():
		for item:Dictionary in chapter.items:text+=str(item.room_name)
	var seen:Dictionary={}
	for i in text.length():
		var code:int=text.unicode_at(i)
		if code<=32 or seen.has(code):continue
		seen[code]=true;checks+=1
		if not tested.has_char(code):failures.append("Missing glyph U+%04X"%code)
	# At intended read distance, optional Q inspection provides 20px text even
	# when world-space plate labels are too small for a particular display.
	checks+=1
	if FontAsset.get_string_size("阅读检修刻牌",HORIZONTAL_ALIGNMENT_LEFT,-1,20).x>590:failures.append("Inspection title exceeds panel")
	print("CAMPAIGN_FONT_TEST ",JSON.stringify({"checks":checks,"failures":failures,"font":"bundled PoolCore Campaign SC","world_plate_legibility":"Q modal provides20px equivalent; target-PC screenshot still required"}))
	quit(0 if failures.is_empty() else 1)
