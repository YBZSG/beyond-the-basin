extends SceneTree
const Catalog = preload("res://scripts/campaign/campaign_catalog.gd")
const State = preload("res://scripts/campaign/campaign_state.gd")
const Store = preload("res://scripts/campaign/campaign_store.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, note: String) -> void:
	checks += 1
	if not value: failures.append(note); push_error(note)
func complete_chapter(state: RefCounted) -> void:
	for item: Dictionary in state.current_chapter().items: check(state.collect(item.id),"collect "+item.id)
func _initialize() -> void:
	var catalog := Catalog.chapters()
	check(catalog.size()==6,"six existing regions")
	var ids := {}
	var count := 0
	for chapter: Dictionary in catalog:
		check(chapter.items.size()==chapter.room_specs.size(),"spec closure")
		for item: Dictionary in chapter.items:
			check(not ids.has(item.id),"globally unique ID"); ids[item.id]=true; count+=1
	check(count==28,"28 room archetypes including archived quiet wing")
	for index in range(8):
		var item: Dictionary = catalog[0].items[index]
		check(int(Catalog.Source.room_layout(item.coord,250821).variant)==index,"source variant "+str(index))
	var state := State.new()
	check(not state.can_depart(),"locked before collect")
	check(not state.collect("formal_0"),"future item rejected")
	check(not state.collect("bogus"),"unknown item rejected")
	check(not state.begin_transition(),"early transition rejected")
	check(not state.finish_transition(),"landing without departure rejected")
	check(state.collect("source_0"),"collect first item")
	check(not state.collect("source_0"),"repeat pickup idempotent")
	check(not state.visit("999,999"),"bad checkpoint rejected")
	check(state.visit("0,0"),"room discovered")
	check(not state.visit("0,0"),"repeat visit not new")
	for item: Dictionary in catalog[0].items:
		if item.id!="source_0":check(state.collect(item.id),"collect remaining")
	check(state.can_depart(),"departure unlocked")
	check(state.begin_transition(),"begin departure")
	check(not state.begin_transition(),"duplicate departure rejected")
	check(not state.collect("facility_shower_changing"),"pickup blocked during departure")
	var pending := state.serialize()
	var recovered := State.new()
	check(recovered.restore(pending).recovered_pending,"pending recover marker")
	check(recovered.chapter_index==0 and not recovered.pending_transition,"failed landing remains original chapter")
	check(recovered.inventory.size()==8,"failed landing retains items")
	check(state.finish_transition(),"confirmed landing advances")
	check(state.chapter_index==1,"advanced once")
	check(not state.finish_transition(),"second landing rejected")
	var roundtrip := State.new()
	check(roundtrip.restore(JSON.parse_string(JSON.stringify(state.serialize()))).ok,"JSON round trip")
	var invalid := state.serialize()
	invalid.chapter_index=4
	check(not roundtrip.restore(invalid).ok,"skip chapter with missing keys rejected")
	check(roundtrip.chapter_index==1,"invalid restore leaves state unchanged")
	invalid=state.serialize();invalid.inventory.append("formal_0")
	check(not roundtrip.restore(invalid).ok,"future saved key rejected")
	invalid=state.serialize();invalid.inventory.append("source_0")
	check(not roundtrip.restore(invalid).ok,"duplicate saved key rejected")
	invalid=state.serialize();invalid.completed=true
	check(not roundtrip.restore(invalid).ok,"premature ending rejected")
	invalid=state.serialize();invalid.chapter_index=1.5
	check(not roundtrip.restore(invalid).ok,"fractional chapter rejected")
	invalid=state.serialize();invalid.seed=-1
	check(not roundtrip.restore(invalid).ok,"bad seed rejected")
	invalid=state.serialize();invalid.checkpoint_room="999,999"
	check(not roundtrip.restore(invalid).ok,"bad saved checkpoint rejected")
	for _chapter_index in range(1,Catalog.CHAPTER_COUNT):
		complete_chapter(state)
		check(state.begin_transition(),"unlock later chapter")
		check(state.finish_transition(),"finish later landing")
	check(state.completed,"complete last chapter")
	check(not state.can_depart(),"ending cannot depart again")
	check(roundtrip.restore(state.serialize()).ok and roundtrip.completed,"ending save reload")
	var path := "user://campaign-tests/"+str(Time.get_ticks_usec())+"_中文 space/save.json"
	check(Store.load_state(path).status=="new","absent save new state")
	check(Store.save_state(recovered,path)==OK,"first atomic write")
	var loaded := Store.load_state(path)
	check(loaded.ok and loaded.state.inventory.size()==8,"first read")
	check(Store.save_state(state,path,loaded.fingerprint)==OK,"replace with fingerprint")
	check(Store.save_state(recovered,path,loaded.fingerprint)==ERR_BUSY,"stale writer rejected")
	check(Store.load_state(path+".bak").state.chapter_index==0,"previous state backup")
	var file := FileAccess.open(path,FileAccess.WRITE);file.store_string("{bad");file.close()
	loaded=Store.load_state(path)
	check(loaded.ok and loaded.status=="backup_read_only" and not loaded.writable,"corrupt primary backup recovery")
	check(Store.save_state(state,path)==ERR_FILE_CORRUPT,"corrupt primary not overwritten")
	check(FileAccess.get_file_as_string(path)=="{bad","invalid data preserved")
	check(Store.save_state(state,"user://../escape.json")==ERR_FILE_BAD_PATH,"path traversal rejected")
	check(not Store.load_state("/tmp/not-user.json").ok,"absolute path rejected")
	print("CAMPAIGN_STATE_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
