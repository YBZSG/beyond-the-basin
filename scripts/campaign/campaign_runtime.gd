extends Node
## Optional campaign coordinator. Existing sandbox, water and player code stay intact.
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Store=preload("res://scripts/campaign/campaign_store.gd")
const Transition=preload("res://scripts/campaign/campaign_transition.gd")
const Objectives=preload("res://scripts/campaign/campaign_objectives.gd")
const Interactables=preload("res://scripts/campaign/campaign_interactables.gd")
const CampaignFont=preload("res://assets/fonts/campaign/PoolCoreCampaignSC.otf")
const Arrivals=preload("res://scripts/campaign/campaign_arrivals.gd")
const Corruption=preload("res://scripts/campaign/campaign_corruption.gd")
const LOAD_TIMEOUT := 45.0
var load_timeout_seconds:=LOAD_TIMEOUT
var save_path:="user://campaign_v1.json"
var main:Node
var state:RefCounted
var active:=false
var busy:=false
var loading_chapter:=-1
var writable:=true
var fingerprint:=""
var message:=""
var _pending_rooms:Array=[]
var _collectibles:Dictionary={}
var _gate:Node3D
var _hud:Label
var _shade:ColorRect
var _loading:Label
var _menu_summary:Label
var _continue:Button
var _prefetch:PackedStringArray=[]
var _placement_pending:=false
var _epoch:=0
var _last_saved_room:=""
var _save_cooldown:=0.0
var _cancel_requested:=false
var _cancel:Button
var _quit:Button
var _bell_voice:AudioStreamPlayer3D
var _bell_sound:AudioStreamWAV
var _inspecting:=false
var _inspect_panel:PanelContainer
var _inspect_text:Label
var _arrivals:Node
var _arrival_epoch:=-1
var _extras:Dictionary={}
var _extra_values:Dictionary={}
var _recovery_required:=false
var _application_focused:=true
var _mount_failed:=false
var _rebuild_button:Button
var _recovery_button:Button
var _repair:Node3D
var _specs:Dictionary={}
var _corruption:RefCounted=Corruption.new()
var _cinematic:Node3D
var _autosave:=0.0
var _interaction_cooldown:=0.0
var _retry_armed_until:=0
var _retry_button:Button
var _repair_button:Button
var _relaxed_check:CheckButton
var _reduced_check:CheckButton

func initialize(owner_node:Node)->void:
	main=owner_node
	var profile:=ConfigFile.new()
	if profile.load("user://campaign_profile.cfg")==OK:
		save_path=str(profile.get_value("campaign","save_path",save_path))
	var loaded:Dictionary=Store.load_state(save_path)
	state=loaded.state;writable=bool(loaded.get("writable",false));fingerprint=str(loaded.get("fingerprint",""))
	if not writable:message="主线存档只读："+str(loaded.reason)
	active="--campaign" in OS.get_cmdline_user_args()
	if active:main._spawn_mode=str(Catalog.chapter(state.chapter_index,state.seed).mode);main.world_seed=state.seed
	_arrivals=Arrivals.new();add_child(_arrivals)
	_build_ui()
	set_process(true)

func world_chapter()->int:
	return loading_chapter if loading_chapter>=0 else state.chapter_index

func begin_or_continue()->void:
	if busy or main._switching_spawn:return
	active=true
	_recovery_required=false
	main._pc_mainhall_preview=false
	main._pc_preview_pending=-1
	main._spawn_mode=str(Catalog.chapter(state.chapter_index,state.seed).mode)
	await main.regenerate(state.seed)
	if not is_instance_valid(main) or not main._booted:return
	if main.world.get("chapter_index")==null or int(main.world.chapter_index)!=state.chapter_index:
		_recovery_required=true;_mount_failed=true;message="本章场景尚未重建成功。请重试或安全退出；原进度保留。";return
	await restore_checkpoint()
	message=Objectives.GOALS[state.chapter_index]

func leave_campaign()->void:
	if busy:return
	_inspecting=false
	if is_instance_valid(_inspect_panel):_inspect_panel.hide()
	flush()
	_corruption.reset()
	if is_instance_valid(_arrivals):_arrivals.clear()
	active=false
	_epoch+=1
	_pending_rooms.clear();_collectibles.clear();_extras.clear();_extra_values.clear()
	if is_instance_valid(_gate):_gate.queue_free()
	if is_instance_valid(_repair) and _repair!=_gate:_repair.queue_free()
	_gate=null;_repair=null;_specs.clear()
	message=""

func world_replacing()->void:
	_stop_bell()
	_inspecting=false
	if is_instance_valid(_inspect_panel):_inspect_panel.hide()
	_mount_failed=false
	if is_instance_valid(_arrivals):_arrivals.set_suspended(true)
	_corruption.reset()
	_epoch+=1;_pending_rooms.clear();_collectibles.clear();_extras.clear();_extra_values.clear();_gate=null;_repair=null;_specs.clear()

func room_loaded(room:Node3D,coord:Vector2i,_layout:Dictionary)->void:
	if not active:return
	for spec:Dictionary in Catalog.chapter(world_chapter(),state.seed).room_specs:
		if spec.coord==coord:
			room.set_meta("campaign_source_mode",spec.source_mode);room.set_meta("campaign_source_index",spec.source_index);break
	_pending_rooms.append({"room":weakref(room),"coord":coord,"epoch":_epoch})

func _process(delta:float)->void:
	if not is_instance_valid(main) or not main._booted:return
	_continue.disabled=busy or main._switching_spawn
	_rebuild_button.visible=active and _mount_failed
	_rebuild_button.disabled=busy or main._switching_spawn
	_recovery_button.visible=not writable
	_recovery_button.disabled=busy
	if _retry_armed_until>0 and Time.get_ticks_msec()>_retry_armed_until:
		_retry_armed_until=0;_retry_button.text="重试本章机关…"
	_retry_button.disabled=not active or busy or main._switching_spawn or state.completed
	_repair_button.disabled=not active or busy or state.corruption()<=0.0
	_relaxed_check.disabled=busy;_reduced_check.disabled=busy
	var chapter:Dictionary=Catalog.chapter(state.chapter_index,state.seed)
	_menu_summary.text=chapter.title+(" · 已通关" if state.completed else " · "+Objectives.status(state.chapter_index,state.objective))
	if state.legacy_credit>0:_menu_summary.text+="\n旧版已收集记录保留；当前机关获得 %d 秒额外宽限。"%(state.legacy_credit*30)
	if not writable:_menu_summary.text+="\n只读恢复：本次进度无法写入，请保留原存档。"
	_hud.visible=active and not main.menu_open and not main.hud_hidden
	if not active:return
	if not main._audio_on:_stop_bell()
	if not _pending_rooms.is_empty() and not _placement_pending and main._booted:_place_pending()
	if not is_instance_valid(main.player) or main._switching_spawn or busy:return
	var playable:bool=not _recovery_required and _application_focused and not main.menu_open and main.world.current_room_ready() and main.water.is_terrain_ready() and _chapter_mount_ready()
	_interaction_cooldown=maxf(0.0,_interaction_cooldown-delta)
	_update_arrival(delta,playable)
	var was_solved:bool=state.objective.solved
	state.advance_time(delta,playable)
	if playable:
		_corruption.reduced_effects=state.reduced_effects
		_corruption.apply(main.world,state.corruption(),delta)
		_autosave+=minf(delta,.25)
		_save_cooldown=maxf(0.0,_save_cooldown-delta)
		state.visit(Catalog.room_key(main.world.current_room))
		if (state.checkpoint_room!=_last_saved_room and _save_cooldown<=0) or _autosave>=10.0 or was_solved!=state.objective.solved:
			_save();_last_saved_room=state.checkpoint_room;_save_cooldown=2.0;_autosave=0.0
	_refresh_stations()
	var target:=_target()
	_hud.text=chapter.title+"\n"+Objectives.GOALS[state.chapter_index]+"\n"+Objectives.status(state.chapter_index,state.objective)
	if state.relaxed:_hud.text+="\n舒缓模式 · 无时间侵蚀"
	elif not state.objective.solved:
		var remaining:float=maxf(0.0,state.pressure_limit()-state.elapsed)
		_hud.text+="\n稳定窗口 %02d:%02d"%[int(remaining)/60,int(remaining)%60]
		if state.corruption()>0.0:_hud.text+=" · 侵蚀 %d%% · 入口复位台 / 暂停菜单可修复"%int(state.corruption()*100)
	if not target.is_empty():
		_hud.text+="\n[E] "+str(target.label)
		if _specs.has(target.id):
			var spec:Dictionary=_specs[target.id]
			_hud.text+="\n"+Objectives.HINTS[state.chapter_index]+"  [Q] 阅读检修刻牌"
			if spec.kind=="pressure_panel":_hud.text+="\n"+Objectives.feedback(state.chapter_index,state.objective)
			else:_hud.text+="\n本设备读数："+str(state.objective.values[spec.index])
	elif state.can_depart():_hud.text+="\n系统稳定。返回本层入口终端继续。"
	else:_hud.text+="\n靠近设备查看刻线和操作提示；暂停菜单可修复或重试。"
	if _mount_failed:_hud.text+="\n设备布置未通过安全检查，计时暂停。请在菜单选择「重建本章场景」。"
	elif not _chapter_mount_ready():_hud.text+="\n正在检查本层设备与通道，计时暂停。"
	if not message.is_empty():_hud.text+="\n"+message

func _input(event:InputEvent)->void:
	if _inspecting:
		if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_Q):
			_close_inspect();get_viewport().set_input_as_handled()
		return
	if busy:
		if event.is_action_pressed("pause"):
			_cancel_requested=true
			if is_instance_valid(_cinematic):_cinematic.cancel()
			get_viewport().set_input_as_handled()
		return
	if not active or main.menu_open or main._switching_spawn:return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_Q:
		var inspected:=_target()
		if not inspected.is_empty() and _specs.has(inspected.id):
			_open_inspect(_specs[inspected.id]);get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("interact") or event.is_echo() or _interaction_cooldown>0.0:return
	var target:=_target()
	if target.is_empty():return
	get_viewport().set_input_as_handled();_interaction_cooldown=.25
	if target.id=="departure":
		if state.can_depart():_depart()
		else:message="系统尚未稳定。先完成本层设备操作，不需要寻找钥匙。"
		return
	if target.id=="repair":_repair_system();return
	if _extras.has(target.id):
		_extra_values[target.id]=1-int(_extra_values.get(target.id,0))
		var kind:String=str(_extras[target.id].get_meta("kind","locker"))
		if kind=="bell":_ring_bell(_extras[target.id])
		Interactables.update_station(_extras[target.id],{"kind":kind},{"value":_extra_values[target.id],"active":bool(_extra_values[target.id]),"solved":false})
		message="旧柜门轻轻打开，里面只有水汽留下的痕迹。" if kind=="locker" and _extra_values[target.id] else ("柜门合上了。" if kind=="locker" else "你拨动了值班铃的摆锤。")
		return
	var result:Dictionary=state.operate(str(target.id))
	message=str(result.get("message",""))
	if result.get("accepted",false):
		if _collectibles.has(target.id) and is_instance_valid(_collectibles[target.id]):Interactables.pulse_station(_collectibles[target.id])
		_refresh_stations();_save();_prefetch_next()

func _refresh_stations()->void:
	for id:String in _collectibles:
		if not _specs.has(id) or not is_instance_valid(_collectibles[id]):continue
		var spec:Dictionary=_specs[id]
		if spec.chapter!=state.chapter_index:continue
		Interactables.update_station(_collectibles[id],spec,Objectives.view(state.chapter_index,state.objective,spec.index))
	if is_instance_valid(_gate):Interactables.update_station(_gate,{"kind":"departure"},{"value":1 if state.can_depart() else 0,"active":state.can_depart(),"solved":state.can_depart(),"feedback":"出口就绪" if state.can_depart() else "系统联锁"})
	if is_instance_valid(_repair) and _repair!=_gate:Interactables.update_station(_repair,{"kind":"repair"},{"value":1 if state.corruption()>0 else 0,"active":state.corruption()>0,"solved":false,"feedback":"可复位侵蚀；机关进度保留"})

func flush()->void:
	_stop_bell()
	if is_instance_valid(_arrivals):_arrivals.set_suspended(true)
	_corruption.reset()
	if active and state!=null and writable:_save()

func _repair_system()->void:
	if busy or not active:return
	if state.repair():
		_corruption.reset();_save();message="应急电源已复位。机关进度保留，侵蚀退去；可继续探索。"
	else:message="系统暂不需要应急修复。"

func _retry_current()->void:
	if busy or not active or main._switching_spawn:return
	if Time.get_ticks_msec()>_retry_armed_until:
		_retry_armed_until=Time.get_ticks_msec()+5000
		_retry_button.text="再次点击：重置本章机关（保留前章）"
		return
	_retry_armed_until=0;_retry_button.text="重试本章机关…"
	var previous:Dictionary=state.serialize()
	if state.retry_chapter():
		if not _save():state.restore(previous);return
		_corruption.reset();_refresh_stations();restore_checkpoint()
		message="本章机关和稳定窗口已重置。前章进度不受影响。"

func _target()->Dictionary:
	if not is_instance_valid(main.player):return {}
	var camera:Node3D=main.player.camera
	var candidates:=_collectibles.duplicate()
	candidates.merge(_extras)
	if is_instance_valid(_gate):candidates["departure"]=_gate
	if is_instance_valid(_repair) and _repair!=_gate:candidates["repair"]=_repair
	var best:Dictionary={};var distance:=2.4
	for id:String in candidates:
		if not is_instance_valid(candidates[id]):continue
		var node:Node3D=candidates[id]
		var point:Vector3=node.global_position+Vector3.UP*1.24
		var offset:=point-camera.global_position
		if offset.length()>=distance or (-camera.global_basis.z).dot(offset.normalized())<.88:continue
		var query:=PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[main.player.get_rid()])
		var hit:Dictionary=main.player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (not hit.collider is Node or not node.is_ancestor_of(hit.collider)):continue
		distance=offset.length();best={"id":id,"label":str(node.get_meta("label","检修终端"))}
		if id=="departure" and _repair==_gate and state!=null and state.corruption()>0.0:
			best={"id":"repair","label":"通道终端 · 应急电源复位（保留机关进度）"}
	return best

func _place_pending()->void:
	_placement_pending=true
	var epoch:=_epoch
	await get_tree().physics_frame
	await get_tree().physics_frame
	if epoch!=_epoch or not _alive():_placement_pending=false;return
	var chapter:Dictionary=Catalog.chapter(world_chapter(),state.seed)
	for pending:Dictionary in _pending_rooms.duplicate():
		var room:Node3D=pending.room.get_ref()
		if not is_instance_valid(room) or pending.epoch!=epoch:continue
		for item:Dictionary in Objectives.specs(world_chapter(),state.seed):
			if item.coord!=pending.coord or _collectibles.has(item.id):continue
			var expected:Vector3=main.world.get_spawn_position(item.coord)
			var desired:=Vector3(item.coord.x*32+item.local_position.x,expected.y,item.coord.y*32+item.local_position.z)
			if chapter.id=="five_memories" and int(item.index)==0:desired=Vector3(.8,.6,-1.1)
			var placement:=_mount_position(desired,expected,expected)
			if placement.is_empty():
				_mount_failed=true;push_error("CAMPAIGN_MOUNT_UNAVAILABLE "+str(item.id));message="交接物落点检查失败，请勿继续："+str(item.label);continue
			var collectible:Node3D=Interactables.build_station(item)
			_specs[item.id]=item
			room.add_child(collectible);collectible.global_position=placement.position;_collectibles[item.id]=collectible
		# One departure terminal per region, near the safe entry, not inside a pool wall.
		if pending.coord==chapter.room_specs[0].coord and not is_instance_valid(_gate):
			var anchor:Vector3=main.world.get_spawn_position(pending.coord)
			var desired:Vector3=Vector3(1.4,4.76,12.8) if chapter.id=="five_memories" else anchor+Vector3(-2,0,0)
			var placement:=_mount_position(desired,anchor,anchor)
			if not placement.is_empty():
				_gate=Interactables.build_station({"id":"departure","kind":"departure","label":str(chapter.departure_label),"clue":"本层系统稳定后才能通行。"})
				room.add_child(_gate);_gate.global_position=placement.position
			else:_mount_failed=true;message="入口通道设备没有安全落点。请暂停并重试本章；不会跳过进度。";push_error("CAMPAIGN_GATE_UNAVAILABLE "+str(chapter.id))
		if pending.coord==chapter.room_specs[0].coord and not is_instance_valid(_repair):
			var anchor:Vector3=main.world.get_spawn_position(pending.coord)
			var placement:=_mount_position(anchor+Vector3(2.5,0,0),anchor+Vector3(0,0,3),anchor)
			if not placement.is_empty():
				_repair=Interactables.build_station({"id":"repair","kind":"repair","label":"应急电源复位","clue":"侵蚀出现后可复位；不清除机关进度。"})
				room.add_child(_repair);_repair.global_position=placement.position
			elif is_instance_valid(_gate):
				# Tight stair landings share the certified departure cabinet rather
				# than adding a second obstacle. Its handle becomes emergency reset
				# during corruption; normal departure returns once repaired.
				_repair=_gate;_gate.set_meta("shared_repair",true)
			else:_mount_failed=true;message="应急复位台没有安全落点；计时暂停，可在菜单重建本章。";push_error("CAMPAIGN_REPAIR_UNAVAILABLE "+str(chapter.id))
		if pending.coord==chapter.room_specs[0].coord or pending.coord==chapter.room_specs[-1].coord:
			var kind:String="bell" if pending.coord==chapter.room_specs[0].coord else "locker"
			var id:String="optional_"+kind
			if not _extras.has(id) and not ((chapter.id=="return_water" and kind=="bell") or (chapter.id=="five_memories" and kind=="locker")):
				# Unproven optional routes (court bell / reference locker) are omitted.
				var anchor:Vector3=main.world.get_spawn_position(pending.coord)
				var placement:=_mount_position(anchor+Vector3(4.5,0,0),anchor+Vector3(-4.5,0,0),anchor)
				if not placement.is_empty():
					var prop:Node3D=Interactables.build_station({"id":id,"kind":kind,"label":"拨动值班铃" if kind=="bell" else "打开 / 合上旧柜门","clue":"可自由摆弄，不影响通关。"})
					prop.set_meta("kind",kind);room.add_child(prop);prop.global_position=placement.position;_extras[id]=prop
	_pending_rooms.clear();_placement_pending=false
	_refresh_stations()

func _mount_position(desired:Vector3,fallback:Vector3,reserved:Vector3=Vector3.INF)->Dictionary:
	if not reserved.is_finite():reserved=fallback
	var space:PhysicsDirectSpaceState3D=main.player.get_world_3d().direct_space_state
	var offsets:Array[Vector3]=[Vector3.ZERO,Vector3(1.2,0,0),Vector3(-1.2,0,0),Vector3(0,0,-1.2),Vector3(0,0,1.2),Vector3(2.4,0,0),Vector3(-2.4,0,0)]
	for radius:float in [2.4,3.6,4.8,6.0]:
		for direction in range(8):
			var angle:float=TAU*float(direction)/8.0
			offsets.append(Vector3(cos(angle)*radius,0,sin(angle)*radius))
	for base:Vector3 in [desired,fallback]:
		for offset:Vector3 in offsets:
			var point:=base+offset
			var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*1.5,1,[main.player.get_rid()])
			var hit:Dictionary=space.intersect_ray(ray)
			if hit.is_empty() or hit.normal.y<.85:continue
			var floor_point:Vector3=hit.position+Vector3.UP*.02
			if _blocks_portal(floor_point):continue
			# Every room is a possible checkpoint. Keep the body/camera landing
			# and its first forward steps free, even when the player is elsewhere.
			var planar:=Vector2(floor_point.x-reserved.x,floor_point.z-reserved.z)
			if absf(floor_point.y-reserved.y)<2.0 and planar.length()<1.65:continue
			var toward_center:=Vector2(roundf(reserved.x/32.0)*32.0-reserved.x,roundf(reserved.z/32.0)*32.0-reserved.z).normalized()
			var along:float=clampf(planar.dot(toward_center),0.0,2.8)
			if absf(floor_point.y-reserved.y)<2.0 and (planar-toward_center*along).length()<1.05:continue
			var shape:=BoxShape3D.new();shape.size=Vector3(1.5,1.9,1.0)
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.transform.origin=floor_point+Vector3.UP*.97;query.exclude=[main.player.get_rid()]
			if not space.intersect_shape(query,1).is_empty():continue
			var overlaps:=false
			for object:Variant in _collectibles.values()+_extras.values():
				if is_instance_valid(object) and object.global_position.distance_to(floor_point)<2.0:overlaps=true
			if is_instance_valid(_gate) and _gate.global_position.distance_to(floor_point)<2.0:overlaps=true
			if is_instance_valid(_repair) and _repair.global_position.distance_to(floor_point)<2.0:overlaps=true
			# A real standing approach in front (+Z), not merely an empty prop box.
			query.transform.origin=floor_point+Vector3(0,.95,1.05);shape.size=Vector3(.7,1.8,1.1)
			if not space.intersect_shape(query,1).is_empty():continue
			var approach:=PhysicsRayQueryParameters3D.create(floor_point+Vector3(0,.3,1.1),floor_point+Vector3(0,-.35,1.1),1,[main.player.get_rid()])
			var approach_hit:Dictionary=space.intersect_ray(approach)
			if approach_hit.is_empty() or approach_hit.normal.y<.85:continue
			if not overlaps:return {"position":floor_point}
	return {}

func _save()->bool:
	if not writable:message="存档不可写，本次进度未保存。请先保留并处理原存档。";return false
	var result:Error=Store.save_state(state,save_path,fingerprint)
	if result!=OK:message="保存失败（%d），暂不进入下一层。"%result;return false
	var loaded:Dictionary=Store.load_state(save_path);fingerprint=str(loaded.get("fingerprint",""));return true

func restore_checkpoint()->void:
	if not active:return
	var pieces:PackedStringArray=state.checkpoint_room.split(",")
	if pieces.size()!=2:return
	var coord:=Vector2i(int(pieces[0]),int(pieces[1]))
	if coord not in main.world.finite_coords:return
	main.travel_to(coord,true)

func _prefetch_next()->void:
	if DisplayServer.get_name()=="headless":return # Dummy renderer has no safe threaded mesh upload.
	if not _prefetch.is_empty() or state.chapter_index+1>=Catalog.CHAPTER_COUNT:return
	var next:Dictionary=Catalog.chapter(state.chapter_index+1,state.seed)
	for spec:Dictionary in next.room_specs:
		var path:=""
		match str(spec.source_mode):
			"expanded":path=preload("res://scripts/art_pass/art_pass_selection.gd").room_geometry(preload("res://scripts/world/expanded_room_catalog.gd").MODULES[spec.source_index],"res://assets/models/expansion/"+preload("res://scripts/world/expanded_room_catalog.gd").MODULES[spec.source_index]+".glb")
			"poolrooms":path="res://assets/models/poolrooms_wing/"+preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd").FILES[spec.source_index]+".glb"
			"reference":path="res://assets/models/reference_wing/"+preload("res://scripts/reference_wing/reference_catalog.gd").IDS[spec.source_index]+".glb"
			"formal":path=preload("res://scripts/world/formal_rooms.gd").PATHS[spec.coord]
			"quiet":path=preload("res://scripts/world/room_builder.gd").AUTHORED[spec.source_index]
		if not path.is_empty() and ResourceLoader.load_threaded_request(path,"PackedScene")==OK:_prefetch.append(path)

func _landing_ready()->bool:
	if not _alive() or not is_instance_valid(main.player):return false
	var feet:Vector3=main.player.global_position
	var query:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.15,feet-Vector3.UP*.4,1,[main.player.get_rid()])
	var hit:Dictionary=main.player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<=.7 or absf(hit.position.y-feet.y)>=.35:return false
	var capsule:=CapsuleShape3D.new();capsule.radius=.32;capsule.height=1.64
	var clearance:=PhysicsShapeQueryParameters3D.new();clearance.shape=capsule;clearance.collision_mask=1;clearance.exclude=[main.player.get_rid()];clearance.transform.origin=feet+Vector3.UP*.84
	return main.player.get_world_3d().direct_space_state.intersect_shape(clearance,1).is_empty()

func _alive()->bool:
	return is_instance_valid(main) and bool(main._booted)

func _depart()->void:
	if busy or not state.can_depart():return
	var previous:Dictionary=state.serialize()
	if not state.begin_transition():return
	if not _save():state.cancel_transition();return
	busy=true;_cancel_requested=false
	main.player.release_prop()
	main.set_menu(true)
	_shade.show();_loading.text="通道已解锁 · Esc 可取消";_loading.show();_cancel.show();_quit.show()
	await _fade(1.0,.25)
	if not _alive():return
	var shaft:=Transition.new();shaft.configure(state.chapter_index);shaft.reduced_effects=state.reduced_effects;shaft.position=Vector3(8192,0,8192);main.add_child(shaft);_cinematic=shaft;shaft.activate_camera()
	main._menu.hide();_loading.hide()
	await _fade(0.0,.2)
	if not _alive():return
	await shaft.play()
	if not _alive():return
	await _fade(1.0,.25)
	if not _alive():return
	if state.chapter_index==Catalog.CHAPTER_COUNT-1:
		if not _cancel_requested:
			state.finish_transition()
			if not _save():state.restore(previous)
		else:state.restore(previous)
		shaft.release_camera();shaft.queue_free();_cinematic=null;main.player.camera.current=true
		_cancel.hide();_quit.hide();await _fade(0.0,.4)
		if not _alive():return
		busy=false;_shade.hide();_loading.hide();main.set_menu(false)
		message="交接完成。你终于找到了天光。主线已通关，可继续自由探索。" if state.completed else "已返回出口前，机关进度保留。"
		return
	_loading.text="正在准备下一层，落点与水体就绪后继续…";_loading.show();_cancel.show();_quit.show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	loading_chapter=state.chapter_index+1
	var next:Dictionary=Catalog.chapter(loading_chapter,state.seed)
	_prefetch_next()
	var retained:Array=[]
	var loading_started:int=Time.get_ticks_msec()
	for path:String in _prefetch:
		while not _cancel_requested and ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if (Time.get_ticks_msec()-loading_started)/1000.0>load_timeout_seconds:
				_cancel_requested=true;message="资源准备超时，已安全返回。可重试或检查资源。";break
			await get_tree().process_frame
			if not _alive():return
		if _cancel_requested:break
		if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED:retained.append(ResourceLoader.load_threaded_get(path))
	var switched:=false
	if not _cancel_requested:
		main._spawn_mode=str(next.mode)
		var previous_world_id:int=main.world.get_instance_id()
		await main.regenerate(state.seed,true)
		if not _alive():return
		switched=main.world.get_instance_id()!=previous_world_id
		main._menu.hide()
		while not _cancel_requested and (not main.world.current_room_ready() or not main.water.is_terrain_ready() or not _landing_ready() or not _mounts_ready_for(loading_chapter)):
			if _mount_failed:
				_cancel_requested=true;message="下一章设备未通过安全布置，正在返回。";break
			if (Time.get_ticks_msec()-loading_started)/1000.0>load_timeout_seconds:
				_cancel_requested=true;message="落点或水体准备超时，返回前章。可重试或安全退出。";break
			await get_tree().process_frame
			if not _alive():return
		await get_tree().physics_frame
		if not _alive():return
		await get_tree().physics_frame
		if not _alive():return
	var landed:=switched and not _cancel_requested
	if landed:
		state.finish_transition();loading_chapter=-1
		landed=_save()
	if not landed:
		state.restore(previous);loading_chapter=-1
		main._spawn_mode=str(Catalog.chapter(state.chapter_index,state.seed).mode)
		_loading.text="正在返回上一检查点，机关进度保留…"
		if switched:
			await main.regenerate(state.seed)
			if not _alive():return
		if main.world.get("chapter_index")!=null and int(main.world.chapter_index)!=state.chapter_index:
			_recovery_required=true;_mount_failed=true
		await restore_checkpoint()
		if not _alive():return
		message="已返回上一检查点，机关进度保留。未跳过关卡；可重试或检查水体与存档状态。"
	else:message=str(Catalog.chapter(state.chapter_index,state.seed).story)
	_prefetch.clear()
	shaft.release_camera();shaft.queue_free();_cinematic=null;main.player.camera.current=true
	_cancel.hide();_quit.hide()
	await _fade(0.0,.4)
	if not _alive():return
	busy=false
	_shade.hide();_loading.hide()
	main.set_menu(_recovery_required)
	if _recovery_required:message="回程场景尚未准备好。已锁住移动并保留原章进度；请重建本章或安全退出。"

func _fade(alpha:float,duration:float)->void:
	var tween:=create_tween();tween.tween_property(_shade,"color:a",alpha,duration);await tween.finished

func _build_ui()->void:
	var layer:=CanvasLayer.new();layer.name="CampaignInterface";layer.layer=90;add_child(layer)
	_hud=Label.new();_hud.position=Vector2(28,104);_hud.size=Vector2(690,300);_hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_hud.add_theme_font_size_override("font_size",16);_hud.add_theme_color_override("font_color",Color("e0e8de"));layer.add_child(_hud);_hud.hide()
	_shade=ColorRect.new();_shade.color=Color(0,0,0,0);_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_shade.mouse_filter=Control.MOUSE_FILTER_STOP;layer.add_child(_shade);_shade.hide()
	_loading=Label.new();_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER);_loading.position=Vector2(-280,-24);_loading.size=Vector2(560,48);_loading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;layer.add_child(_loading);_loading.hide()
	_cancel=Button.new();_cancel.text="返回上一检查点";_cancel.position=Vector2(28,220);_cancel.pressed.connect(func():
		_cancel_requested=true
		if is_instance_valid(_cinematic):_cinematic.cancel()
	);layer.add_child(_cancel);_cancel.hide()
	_quit=Button.new();_quit.text="安全退出";_quit.position=Vector2(28,268);_quit.pressed.connect(func():main._safe_quit());layer.add_child(_quit);_quit.hide()
	var selector:Node=main._spawn_select
	var column:Node=selector.get_parent().get_parent()
	_menu_summary=Label.new();_menu_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_menu_summary)
	_continue=Button.new();_continue.text="主线 · 继续旅程 / CAMPAIGN";_continue.pressed.connect(begin_or_continue);column.add_child(_continue)
	column.move_child(_menu_summary,2);column.move_child(_continue,3)

	_rebuild_button=Button.new();_rebuild_button.text="重建本章场景（保留机关进度）";_rebuild_button.pressed.connect(begin_or_continue);column.add_child(_rebuild_button)
	_recovery_button=Button.new();_recovery_button.text="另存恢复副本（保留原存档）";_recovery_button.pressed.connect(_create_recovery_save);column.add_child(_recovery_button)
	_relaxed_check=CheckButton.new();_relaxed_check.text="舒缓模式：不计时、不侵蚀";_relaxed_check.button_pressed=state.relaxed
	_relaxed_check.toggled.connect(func(value:bool):state.relaxed=value;_corruption.reset();_save())
	column.add_child(_relaxed_check)
	_reduced_check=CheckButton.new();_reduced_check.text="减弱主线异变：柔和新照明与镜头";_reduced_check.button_pressed=state.reduced_effects
	_reduced_check.toggled.connect(func(value:bool):state.reduced_effects=value;_corruption.reset();_save())
	column.add_child(_reduced_check)
	_repair_button=Button.new();_repair_button.text="应急修复：保留机关进度";_repair_button.pressed.connect(_repair_system);column.add_child(_repair_button)
	_retry_button=Button.new();_retry_button.text="重试本章机关…";_retry_button.pressed.connect(_retry_current);column.add_child(_retry_button)
	# Recovery and accessibility belong beside Continue, not below graphics settings.
	var campaign_theme:=Theme.new();campaign_theme.default_font=CampaignFont
	for control:Control in [_hud,_loading,_menu_summary,_continue,_cancel,_quit,_relaxed_check,_reduced_check,_repair_button,_retry_button,_rebuild_button,_recovery_button]:control.theme=campaign_theme
	_inspect_panel=PanelContainer.new();_inspect_panel.theme=campaign_theme;_inspect_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);_inspect_panel.position=Vector2(-320,-150);_inspect_panel.size=Vector2(640,300);layer.add_child(_inspect_panel)
	var panel_style:=StyleBoxFlat.new();panel_style.bg_color=Color("152527");panel_style.set_content_margin_all(24);panel_style.border_color=Color("b4aa83");panel_style.set_border_width_all(2);_inspect_panel.add_theme_stylebox_override("panel",panel_style)
	var inspection_column:=VBoxContainer.new();inspection_column.add_theme_constant_override("separation",18);_inspect_panel.add_child(inspection_column)
	_inspect_text=Label.new();_inspect_text.custom_minimum_size=Vector2(590,0);_inspect_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_inspect_text.add_theme_font_size_override("font_size",20);inspection_column.add_child(_inspect_text)
	var close_reading:=Button.new();close_reading.text="合上刻牌 · Q / Esc（阅读期间计时暂停）";close_reading.pressed.connect(_close_inspect);inspection_column.add_child(close_reading);_inspect_panel.hide()
	var campaign_controls:Array=[_relaxed_check,_reduced_check,_repair_button,_retry_button,_rebuild_button,_recovery_button]
	for i in range(campaign_controls.size()):column.move_child(campaign_controls[i],4+i)

func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_FOCUS_IN:_application_focused=true
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_focused=false
		_inspecting=false
		if is_instance_valid(_inspect_panel):_inspect_panel.hide()
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and active and is_instance_valid(main) and main._booted:
		main.set_menu(true)

func _create_recovery_save()->void:
	if busy or writable:return
	var previous_path:=save_path
	var recovery_path:="user://campaign_recovery_%d.json"%Time.get_unix_time_from_system()
	if FileAccess.file_exists(recovery_path):message="恢复副本已存在，请稍后重试。";return
	var result:Error=Store.save_state(state,recovery_path)
	if result!=OK:message="无法创建恢复副本（%d）；原存档保留。"%result;return
	var profile:=ConfigFile.new();profile.set_value("campaign","save_path",recovery_path)
	if profile.save("user://campaign_profile.cfg")!=OK:
		message="恢复副本已保存，但无法记住副本路径："+recovery_path;return
	save_path=recovery_path;writable=true
	var loaded:Dictionary=Store.load_state(save_path);fingerprint=str(loaded.get("fingerprint",""))
	message="恢复副本已启用；原存档未改动："+previous_path

func _update_arrival(delta:float,playable:bool)->void:
	if not is_instance_valid(_arrivals):return
	_arrivals.reduced_effects=state.reduced_effects
	_arrivals.set_audio_enabled(main._audio_on and main._ambience_on)
	if _arrival_epoch!=_epoch or _arrivals.chapter_id!=str(state.current_chapter().id):
		_arrivals.configure(str(state.current_chapter().id),_epoch)
		_arrivals.restore_seen(state.visited.keys());_arrival_epoch=_epoch
	_arrivals.set_suspended(not playable or main.hud_hidden)
	var room:Node3D=main.world.resident_rooms.get(main.world.current_room)
	if is_instance_valid(room):
		_arrivals.update_room(room,str(state.current_chapter().id)+":"+Catalog.room_key(main.world.current_room),main.world.current_room_ready(),playable and not main.hud_hidden,delta)

func _chapter_mount_ready()->bool:
	return _mounts_ready_for(state.chapter_index)

func _mounts_ready_for(index:int)->bool:
	return not _mount_failed and _collectibles.size()==Catalog.chapter(index,state.seed).items.size() and is_instance_valid(_gate) and is_instance_valid(_repair)

func can_resume()->bool:
	return not active or not _recovery_required

func _blocks_portal(point:Vector3)->bool:
	# Keep each finite cell's real connecting threshold and lead-in free.
	# The mask includes half a cabinet's width beyond the 3 m clear opening.
	for coord:Vector2i in main.world.finite_coords:
		var local:Vector3=point-Vector3(coord.x*32.0,0,coord.y*32.0)
		for direction:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			if coord+direction not in main.world.finite_coords:continue
			if direction.x!=0:
				if absf(local.x-float(direction.x)*16.0)<4.0 and absf(local.z)<2.4:return true
			elif absf(local.z-float(direction.y)*16.0)<4.0 and absf(local.x)<2.4:return true
	return false

func _open_inspect(spec:Dictionary)->void:
	if busy or not active or main.menu_open:return
	_inspecting=true;main.set_menu(true);main._menu.hide()
	_inspect_text.text=str(spec.label)+"\n\n"+str(spec.clue)+"\n\n当前读数："+Objectives.feedback(state.chapter_index,state.objective)
	_inspect_panel.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _close_inspect()->void:
	if not _inspecting:return
	_inspecting=false;_inspect_panel.hide();main.set_menu(false)

func _ring_bell(station:Node3D)->void:
	if not is_instance_valid(station) or main.menu_open or not main._audio_on:return
	if _bell_sound==null:
		var rate:=16000
		var samples:=int(float(rate)*1.2)
		var pcm:=PackedByteArray();pcm.resize(samples*2)
		for i in range(samples):
			var time:float=float(i)/float(rate)
			var attack:float=minf(1.0,time/.008)
			var sample:float=attack*(sin(TAU*880.0*time)*exp(-time*4.2)+.42*sin(TAU*1377.0*time)*exp(-time*6.8)+.22*sin(TAU*2035.0*time)*exp(-time*9.0))*.45
			pcm.encode_s16(i*2,int(clampf(sample,-1.0,1.0)*32767.0))
		_bell_sound=AudioStreamWAV.new();_bell_sound.format=AudioStreamWAV.FORMAT_16_BITS;_bell_sound.mix_rate=rate;_bell_sound.stereo=false;_bell_sound.data=pcm
	if not is_instance_valid(_bell_voice):
		_bell_voice=AudioStreamPlayer3D.new();_bell_voice.name="CampaignServiceBell";_bell_voice.max_polyphony=1;_bell_voice.max_distance=10.0;_bell_voice.unit_size=2.0;_bell_voice.volume_db=-20.0;main.add_child(_bell_voice)
	_bell_voice.stop();_bell_voice.global_position=station.global_position+Vector3.UP*1.3;_bell_voice.stream=_bell_sound;_bell_voice.play()

func _stop_bell()->void:
	if is_instance_valid(_bell_voice):_bell_voice.stop()
