extends Node
## Optional campaign coordinator. Existing sandbox, water and player code stay intact.
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
const State=preload("res://scripts/campaign/campaign_state.gd")
const Store=preload("res://scripts/campaign/campaign_store.gd")
const Descent=preload("res://scripts/campaign/campaign_descent.gd")
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

func initialize(owner_node:Node)->void:
	main=owner_node
	var loaded:Dictionary=Store.load_state(save_path)
	state=loaded.state;writable=bool(loaded.get("writable",false));fingerprint=str(loaded.get("fingerprint",""))
	if not writable:message="主线存档只读："+str(loaded.reason)
	active="--campaign" in OS.get_cmdline_user_args()
	if active:main._spawn_mode=str(Catalog.chapter(state.chapter_index,state.seed).mode);main.world_seed=state.seed
	_build_ui()
	set_process(true)

func world_chapter()->int:
	return loading_chapter if loading_chapter>=0 else state.chapter_index

func begin_or_continue()->void:
	if busy or main._switching_spawn:return
	active=true
	main._pc_mainhall_preview=false
	main._pc_preview_pending=-1
	main._spawn_mode=str(Catalog.chapter(state.chapter_index,state.seed).mode)
	await main.regenerate(state.seed)
	if not is_instance_valid(main) or not main._booted:return
	await restore_checkpoint()
	message="找回交接物，沿着检修通道继续下行。"

func leave_campaign()->void:
	if busy:return
	active=false
	_epoch+=1
	_pending_rooms.clear();_collectibles.clear()
	if is_instance_valid(_gate):_gate.queue_free()
	_gate=null
	message=""

func world_replacing()->void:
	_epoch+=1;_pending_rooms.clear();_collectibles.clear();_gate=null

func room_loaded(room:Node3D,coord:Vector2i,_layout:Dictionary)->void:
	if not active:return
	_pending_rooms.append({"room":weakref(room),"coord":coord,"epoch":_epoch})

func _process(delta:float)->void:
	if not is_instance_valid(main) or not main._booted:return
	_continue.disabled=busy or main._switching_spawn
	var chapter:Dictionary=Catalog.chapter(state.chapter_index,state.seed)
	_menu_summary.text=chapter.title+" · "+str(state.inventory.size())+" / 28 件交接物"+(" · 已通关" if state.completed else "")
	_hud.visible=active and not main.menu_open and not main.hud_hidden
	if not active:return
	if not _pending_rooms.is_empty() and not _placement_pending and main._booted:
		_place_pending()
	if not is_instance_valid(main.player) or main._switching_spawn or busy:return
	var coord:Vector2i=main.world.current_room
	var key:String=Catalog.room_key(coord)
	if not main.menu_open:
		_save_cooldown=maxf(0.0,_save_cooldown-delta)
		state.visit(key)
		if state.checkpoint_room!=_last_saved_room and _save_cooldown<=0:
			_save();_last_saved_room=state.checkpoint_room;_save_cooldown=2.0
	var target:=_target()
	var collected:=0
	for item:Dictionary in chapter.items:
		if state.inventory.has(item.id):collected+=1
	_hud.text=chapter.title+"\n"+chapter.objective+"  %d / %d"%[collected,chapter.items.size()]
	if not target.is_empty():
		_hud.text+="\n[E] "+str(target.label)
	elif state.can_depart():_hud.text+="\n交接完成，返回本层入口的检修终端。"
	else:
		for item:Dictionary in chapter.items:
			if not state.inventory.has(item.id):
				_hud.text+="\n线索："+str(item.room_name)+"（%d, %d）"%[item.coord.x,item.coord.y];break
	if not message.is_empty():_hud.text+="\n"+message

func _input(event:InputEvent)->void:
	if busy:
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
		return
	if not active or main.menu_open or main._switching_spawn:return
	if not event.is_action_pressed("interact") or event.is_echo():return
	var target:=_target()
	if target.is_empty():return
	get_viewport().set_input_as_handled()
	if target.id=="departure":
		if state.can_depart():_depart()
		else:message="通道尚未解锁：请找齐本层交接物。"
		return
	if state.collect(str(target.id)):
		var node:Node3D=_collectibles[target.id]
		_collectibles.erase(target.id);node.queue_free()
		message="已收好："+str(target.label)+"。不会因掉落丢失。"
		_save();_prefetch_next()

func _target()->Dictionary:
	if not is_instance_valid(main.player):return {}
	var camera:Node3D=main.player.camera
	var candidates:=_collectibles.duplicate()
	if is_instance_valid(_gate):candidates["departure"]=_gate
	var best:Dictionary={};var distance:=2.4
	for id:String in candidates:
		var node:Node3D=candidates[id]
		if not is_instance_valid(node):continue
		var point:Vector3=node.global_position+Vector3.UP*1.24
		var offset:=point-camera.global_position
		if offset.length()>=distance or (-camera.global_basis.z).dot(offset.normalized())<.88:continue
		var query:=PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[main.player.get_rid()])
		var hit:Dictionary=main.player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (not hit.collider is Node or not node.is_ancestor_of(hit.collider)):continue
		distance=offset.length();best={"id":id,"label":str(node.get_meta("label","检修终端"))}
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
		for item:Dictionary in chapter.items:
			if item.coord!=pending.coord or state.inventory.has(item.id) or _collectibles.has(item.id):continue
			var expected:Vector3=main.world.get_spawn_position(item.coord)
			var desired:=Vector3(item.coord.x*32+item.local_position.x,expected.y,item.coord.y*32+item.local_position.z)
			var placement:=_mount_position(desired,expected)
			if placement.is_empty():
				push_error("CAMPAIGN_MOUNT_UNAVAILABLE "+str(item.id));message="交接物落点检查失败，请勿继续："+str(item.label);continue
			var collectible:=_build_station(str(item.id),str(item.label),false)
			room.add_child(collectible);collectible.global_position=placement.position;_collectibles[item.id]=collectible
		# One departure terminal per region, near the safe entry, not inside a pool wall.
		if pending.coord==chapter.room_specs[0].coord and not is_instance_valid(_gate):
			var anchor:Vector3=main.world.get_spawn_position(pending.coord)
			var placement:=_mount_position(anchor+Vector3(-2,0,0),anchor)
			if not placement.is_empty():
				_gate=_build_station("departure",str(chapter.departure_label),true)
				room.add_child(_gate);_gate.global_position=placement.position
	_pending_rooms.clear();_placement_pending=false

func _mount_position(desired:Vector3,fallback:Vector3)->Dictionary:
	var space:PhysicsDirectSpaceState3D=main.player.get_world_3d().direct_space_state
	var offsets:Array[Vector3]=[Vector3.ZERO,Vector3(1.2,0,0),Vector3(-1.2,0,0),Vector3(0,0,-1.2),Vector3(0,0,1.2),Vector3(2.4,0,0),Vector3(-2.4,0,0)]
	for base:Vector3 in [desired,fallback]:
		for offset:Vector3 in offsets:
			var point:=base+offset
			var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*1.5,1,[main.player.get_rid()])
			var hit:Dictionary=space.intersect_ray(ray)
			if hit.is_empty() or hit.normal.y<.85:continue
			var floor_point:Vector3=hit.position+Vector3.UP*.02
			var shape:=BoxShape3D.new();shape.size=Vector3(.48,1.58,.48)
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.transform.origin=floor_point+Vector3.UP*.81;query.exclude=[main.player.get_rid()]
			if not space.intersect_shape(query,1).is_empty():continue
			var overlaps:=false
			for object:Node3D in _collectibles.values():
				if is_instance_valid(object) and object.global_position.distance_to(floor_point)<1.1:overlaps=true
			if is_instance_valid(_gate) and _gate.global_position.distance_to(floor_point)<1.1:overlaps=true
			if not overlaps:return {"position":floor_point}
	return {}

func _build_station(id:String,label:String,terminal:bool)->Node3D:
	var root:=Node3D.new();root.name="Campaign_"+id;root.set_meta("label",label)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("546d70") if terminal else Color("b49b65");material.metallic=.5;material.roughness=.3
	var pedestal:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.32,1.1,.32);pedestal.mesh=box;pedestal.position.y=.55;pedestal.material_override=material;root.add_child(pedestal)
	var item:=MeshInstance3D.new();item.position.y=1.24;item.material_override=material
	if "阀" in label or "环" in label or "徽章" in label:
		var torus:=TorusMesh.new();torus.inner_radius=.08;torus.outer_radius=.16;item.mesh=torus;item.rotation_degrees.x=65
	elif "筒" in label or "丝" in label or "芯" in label:
		var cylinder:=CylinderMesh.new();cylinder.top_radius=.055;cylinder.bottom_radius=.055;cylinder.height=.22;item.mesh=cylinder;item.rotation_degrees.z=90
	else:
		var plate:=BoxMesh.new();plate.size=Vector3(.24,.14,.04) if not terminal else Vector3(.36,.24,.07);item.mesh=plate;item.rotation_degrees.x=-18
	if not terminal:
		var kind:=_object_kind(label)
		var packed:=load("res://assets/models/campaign/"+kind+".glb") as PackedScene
		if packed!=null:
			var authored:=packed.instantiate() as Node3D;authored.position=Vector3(0,1.19,0);root.add_child(authored);item.free();item=null
	if item!=null:root.add_child(item)
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	var collision:=CollisionShape3D.new();var collision_shape:=BoxShape3D.new();collision_shape.size=Vector3(.32,1.1,.32);collision.shape=collision_shape;collision.position.y=.55;body.add_child(collision);root.add_child(body)
	var sign:=Label3D.new();sign.text=label;sign.font_size=40;sign.pixel_size=.002;sign.position=Vector3(0,1.52,0);sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sign.no_depth_test=false;root.add_child(sign)
	return root

func _object_kind(label:String)->String:
	if "钥匙" in label:return "key"
	if "阀" in label or "环" in label or "徽章" in label:return "valve"
	if "筒" in label or "丝" in label or "芯" in label:return "fuse"
	if "图" in label or "记录" in label:return "diagram"
	return "card"

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
	return not hit.is_empty() and hit.normal.y>.7 and absf(hit.position.y-feet.y)<.35

func _alive()->bool:
	return is_instance_valid(main) and bool(main._booted)

func _depart()->void:
	if busy or not state.can_depart():return
	var previous:Dictionary=state.serialize()
	if not state.begin_transition():return
	if not _save():state.cancel_transition();return
	if state.chapter_index==Catalog.CHAPTER_COUNT-1:
		state.finish_transition()
		if not _save():state.restore(previous);return
		message="交接完成。你终于找到了天光。主线已通关，可继续自由探索。"
		return
	busy=true;_cancel_requested=false
	main.player.release_prop()
	main.set_menu(true)
	_shade.show();_loading.text="检修通道已解锁";_loading.show()
	await _fade(1.0,.25)
	if not _alive():return
	var shaft:=Descent.new();shaft.position=Vector3(8192,0,8192);main.add_child(shaft)
	main._menu.hide();_loading.hide()
	await _fade(0.0,.2)
	if not _alive():return
	await shaft.descend()
	if not _alive():return
	await _fade(1.0,.25)
	if not _alive():return
	_loading.text="正在准备下一层，落点与水体就绪后继续…";_loading.show();_cancel.show();_quit.show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	loading_chapter=state.chapter_index+1
	var next:Dictionary=Catalog.chapter(loading_chapter,state.seed)
	_prefetch_next()
	var retained:Array=[]
	for path:String in _prefetch:
		while not _cancel_requested and ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
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
		while not _cancel_requested and (not main.world.current_room_ready() or not main.water.is_terrain_ready() or not _landing_ready()):
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
		_loading.text="正在返回上一检查点，已收集物品保留…"
		if switched:
			await main.regenerate(state.seed)
			if not _alive():return
		await restore_checkpoint()
		if not _alive():return
		message="已返回上一检查点。未跳过关卡；请检查水体准备或存档状态。"
	else:message=str(Catalog.chapter(state.chapter_index,state.seed).story)
	_prefetch.clear()
	shaft.queue_free();main.player.camera.current=true
	_cancel.hide();_quit.hide()
	await _fade(0.0,.4)
	if not _alive():return
	busy=false
	_shade.hide();_loading.hide()
	main.set_menu(false)

func _fade(alpha:float,duration:float)->void:
	var tween:=create_tween();tween.tween_property(_shade,"color:a",alpha,duration);await tween.finished

func _build_ui()->void:
	var layer:=CanvasLayer.new();layer.name="CampaignInterface";layer.layer=90;add_child(layer)
	_hud=Label.new();_hud.position=Vector2(28,104);_hud.add_theme_font_size_override("font_size",16);_hud.add_theme_color_override("font_color",Color("e0e8de"));layer.add_child(_hud);_hud.hide()
	_shade=ColorRect.new();_shade.color=Color(0,0,0,0);_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_shade.mouse_filter=Control.MOUSE_FILTER_STOP;layer.add_child(_shade);_shade.hide()
	_loading=Label.new();_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER);_loading.position=Vector2(-280,-24);_loading.size=Vector2(560,48);_loading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;layer.add_child(_loading);_loading.hide()
	_cancel=Button.new();_cancel.text="返回上一检查点";_cancel.position=Vector2(28,220);_cancel.pressed.connect(func():_cancel_requested=true);layer.add_child(_cancel);_cancel.hide()
	_quit=Button.new();_quit.text="安全退出";_quit.position=Vector2(28,268);_quit.pressed.connect(func():main._safe_quit());layer.add_child(_quit);_quit.hide()
	var selector:Node=main._spawn_select
	var column:Node=selector.get_parent().get_parent()
	_menu_summary=Label.new();_menu_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_menu_summary)
	_continue=Button.new();_continue.text="主线 · 继续下行 / CAMPAIGN";_continue.pressed.connect(begin_or_continue);column.add_child(_continue)
	column.move_child(_menu_summary,2);column.move_child(_continue,3)
