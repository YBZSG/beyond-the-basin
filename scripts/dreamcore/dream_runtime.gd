extends Node
## Additive journey with its own save and finite outdoor worlds. No campaign
## migrations, source-controller edits, enemies, strobing or mandatory timers.
const Catalog = preload("res://scripts/dreamcore/dream_catalog.gd")
const Threshold = preload("res://scripts/dreamcore/dream_transition.gd")
const Ambience = preload("res://scripts/dreamcore/dream_ambience.gd")
const State = preload("res://scripts/dreamcore/dream_state.gd")
const Store = preload("res://scripts/dreamcore/dream_store.gd")
const DreamFont = preload("res://assets/fonts/dreamcore/PoolCoreDreamSC.otf")
var main: Node
var state := State.new()
var active := false
var busy := false
var writable := false
var fingerprint := ""
var message := ""
var save_path := "user://dreamcore_v1.json"
var _hud: Label
var _summary: Label
var _selector: OptionButton
var _enter: Button
var _repair: Button
var _reduced: CheckButton
var _relaxed: CheckButton
var _stations: Dictionary = {}
var _specs: Dictionary = {}
var _exit: Node3D
var _focused := true
var _autosave := 0.0
var _cooldown := 0.0
var _failed := false
var _cancel := false
var _tint: ColorRect
var _recovery: Button
var _environment_scene := ""
var return_spawn_mode := "original"
var return_seed := 250821
var _original_environment: Dictionary = {}
# Exact new-six palette isolation; never changes quality/enable/radius settings.
const UNCANNY_ENVIRONMENT_DEFAULTS := {"ssao_intensity":.75,"ssao_power":1.25,"sdfgi_bounce_feedback":.48,"sdfgi_energy":1.08,"tonemap_agx_contrast":1.15}
var _uncanny_environment_owner: WeakRef
var _uncanny_original_environment: Dictionary = {}
var _uncanny_applied_environment: Dictionary = {}
var _ambience: Node
var _threshold: Node
var _definition_cache: Dictionary = {}
var _campaign_entry_serial := ""
func initialize(owner_node: Node) -> void:
	main = owner_node
	return_spawn_mode = main._spawn_mode; return_seed = main.world_seed
	var profile := ConfigFile.new()
	if profile.load("user://dreamcore_profile.cfg") == OK:
		var selected := str(profile.get_value("dreamcore","save_path",save_path))
		if Store._safe(selected): save_path = selected
	var loaded := Store.load_state(save_path)
	state = loaded.state; writable = bool(loaded.get("writable",false)); fingerprint = str(loaded.get("fingerprint",""))
	_ambience = Ambience.new(); add_child(_ambience)
	_threshold = Threshold.new(); add_child(_threshold)
	_threshold.cancel_requested.connect(func():_cancel=true)
	_threshold.quit_requested.connect(func():main._safe_quit())
	_build_ui()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dreamcore=") and Catalog.available(arg.trim_prefix("--dreamcore=")):
			state.scene_id = arg.trim_prefix("--dreamcore="); active = true; main._spawn_mode = "dreamcore"
	if active:
		main.world_seed = state.seed
		_selector.select(maxi(0,Catalog.IDS.find(state.scene_id)))
		if is_instance_valid(main._campaign): main._campaign.active = false
func current_definition() -> Dictionary:
	if not _definition_cache.has(state.scene_id): _definition_cache[state.scene_id] = Catalog.definition(state.scene_id)
	return _definition_cache[state.scene_id]
func enter_scene(id: String = "") -> void:
	if busy or main._switching_spawn or (is_instance_valid(main._campaign) and main._campaign.busy): return
	if id.is_empty(): id = state.scene_id
	if not Catalog.available(id): message = "场景资源尚未就绪。"; return
	var previous_active := active
	var previous_failed := _failed
	var previous_id := state.scene_id
	var previous_mode: String = main._spawn_mode
	var previous_preview: bool = main._pc_mainhall_preview
	var previous_preview_pending: int = main._pc_preview_pending
	var previous_world_id: int = main.world.get_instance_id()
	var campaign_was_active: bool = is_instance_valid(main._campaign) and main._campaign.active
	if campaign_was_active: _campaign_entry_serial = JSON.stringify(main._campaign.state.serialize())
	if not active:
		return_spawn_mode = main._spawn_mode; return_seed = main.world_seed
	busy = true; _cancel = false; _failed = false
	_sync_scene_interactions(false)
	# Pause without rewriting original save bytes. Do not tear down its device
	# mounts until real world retirement: cancelling this beat is reversible.
	if is_instance_valid(main._campaign): main._campaign.active = false
	main.set_menu(true)
	if is_instance_valid(_threshold):
		# Hide the underlying menu rather than merely painting over it: keyboard
		# focus must not reach original campaign settings during a transaction.
		if is_instance_valid(main.get("_menu")): main._menu.hide()
		await _threshold.begin(previous_id if previous_active else id,str(Catalog.definition(id).title),state.reduced_effects)
		if not is_instance_valid(main) or not main._booted: return
	if _cancel:
		if is_instance_valid(_threshold): _threshold.hide_safely()
		_failed=previous_failed; busy=false
		if is_instance_valid(main._campaign): main._campaign.active=campaign_was_active
		message="已取消到安全菜单。原进度保留，可重新进入。"
		main.set_menu(true)
		return
	if is_instance_valid(_threshold): _threshold.preparing()
	active = true; state.scene_id = id
	if is_instance_valid(_selector): _selector.select(maxi(0,Catalog.IDS.find(id)))
	main._pc_mainhall_preview = false; main._pc_preview_pending = -1; main._spawn_mode = "dreamcore"
	message = "准备地形、水体与安全落点… Esc 可取消到菜单。"
	await main.regenerate(state.seed)
	if not is_instance_valid(main) or not main._booted: return
	if main.world.get_instance_id()==previous_world_id and (_cancel or _failed):
		# Retirement did not start: restore the exact previous live world and
		# original device references; original save/backup remain untouched.
		active=previous_active; state.scene_id=previous_id; _failed=previous_failed
		main._spawn_mode=previous_mode; main._pc_mainhall_preview=previous_preview; main._pc_preview_pending=previous_preview_pending
		if is_instance_valid(main._campaign): main._campaign.active=campaign_was_active
		if is_instance_valid(_threshold): _threshold.hide_safely()
		busy=false; main.set_menu(true)
		return
	var started := Time.get_ticks_msec()
	while not _cancel and not _failed and not _ready_to_play():
		if Time.get_ticks_msec()-started > 45000:
			_failed = true; message = "地形、水体或落点尚未就绪；进度未推进。可重建或安全退出。"; break
		await get_tree().process_frame
		if not is_instance_valid(main) or not main._booted: return
	if _cancel: _failed = true; message = "已取消到安全菜单。原进度保留，可重新进入。"
	if not _failed:
		if _save(): message = str(current_definition().get("subtitle","慢慢探索，不必赶路。"))
		if is_instance_valid(_threshold): await _threshold.finish(state.reduced_effects)
		if not is_instance_valid(main) or not main._booted: return
	else:
		if main.world.get("scene_id") == null: state.scene_id = previous_id
		if is_instance_valid(_threshold): _threshold.hide_safely()
	busy = false; main.set_menu(_failed or _cancel or not _focused)

func leave() -> void:
	if busy: return
	flush(); _release_scene_interactions(); _restore_environment();
	if is_instance_valid(_ambience): _ambience.restore()
	active = false; _stations.clear(); _specs.clear(); _exit = null
func world_replacing() -> void:
	_release_scene_interactions()
	_definition_cache.clear()
	_environment_scene = ""
	_stations.clear(); _specs.clear(); _exit = null
func room_loaded(room: Node3D, coord: Vector2i, layout: Dictionary) -> void:
	if not active or not layout.get("dreamcore",false): return
	var data := current_definition()
	for spec: Dictionary in data.get("stations",[]):
		var point: Vector3 = spec.position
		if main.world.get_room_coord(point) != coord: continue
		var station := _make_station(spec)
		room.add_child(station); station.position = point-room.position
		_stations[str(spec.id)] = station; _specs[str(spec.id)] = spec
	var exit_point: Vector3 = data.get("exit",data.spawn)
	if main.world.get_room_coord(exit_point) == coord:
		var exit_spec := {"id":"departure","label":"继续旅程","kind":"departure"}
		var authored_exit: Variant = data.get("exit_station",{})
		if authored_exit is Dictionary:
			# Authors may supply the real door handle presentation, never change
			# departure identity, completion rules, input ownership or position.
			for key: String in ["presentation","interaction_offset","readout","label"]:
				if authored_exit.has(key): exit_spec[key] = authored_exit[key]
		_exit = _make_station(exit_spec)
		room.add_child(_exit); _exit.position = exit_point-room.position
func _make_station(spec: Dictionary) -> Node3D:
	var root := Node3D.new(); root.name = "DreamStation_" + str(spec.id)
	root.set_meta("label",str(spec.get("label","控制台")))
	if str(spec.get("presentation","")) == "authored":
		# The room owns a visible fixed device. This identity has no invisible
		# collider/trigger and never bypasses the unchanged range/cone/LOS ray.
		var aim: Variant = spec.get("interaction_offset",Vector3.UP*1.1)
		var valid_aim: bool = aim is Vector3 and aim.is_finite() and aim.length() <= 1.8
		root.set_meta("interaction_offset",aim if valid_aim else Vector3.UP*1.1)
		root.set_meta("authored_station",true)
		if bool(spec.get("readout",true)):
			var readout := Label3D.new(); readout.name = "Readout"; readout.font = DreamFont
			readout.text = str(spec.get("label","")); readout.font_size = 36; readout.pixel_size = .004
			readout.position = root.get_meta("interaction_offset")+Vector3.UP*.15
			readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED; readout.no_depth_test = false; root.add_child(readout)
		return root
	var body := StaticBody3D.new(); body.collision_layer = 1; body.collision_mask = 0; root.add_child(body)
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(.58,.9,.34); mesh.mesh = box; mesh.position.y = .45
	var material := StandardMaterial3D.new(); material.albedo_color = Color("586a65"); material.roughness = .6; mesh.material_override = material; body.add_child(mesh)
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = box.size; collision.shape = shape; collision.position = mesh.position; body.add_child(collision)
	var face := MeshInstance3D.new(); var panel := BoxMesh.new(); panel.size = Vector3(.50,.18,.02); face.mesh = panel; face.position = Vector3(0,.75,.18)
	var glow := StandardMaterial3D.new(); glow.albedo_color = Color("c6e9c7"); glow.emission_enabled = true; glow.emission = Color("a4d8b5"); glow.emission_energy_multiplier = .3; face.material_override = glow; root.add_child(face)
	var label := Label3D.new(); label.name = "Readout"; label.font = DreamFont; label.text = str(spec.get("label","")); label.font_size = 36; label.pixel_size = .004; label.position = Vector3(0,1.17,0); label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test = false; root.add_child(label)
	_add_station_shape(root,spec,material)
	return root
func _ready_to_play() -> bool:
	return is_instance_valid(main.world) and main.world.get("scene_id") == state.scene_id and main.world.current_room_ready() and main.water.is_terrain_ready() and _landing_ready()
func _landing_ready() -> bool:
	if not is_instance_valid(main.player): return false
	var point: Vector3 = main.player.global_position
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.1,point-Vector3.UP*.3,1,[main.player.get_rid()])
	var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < .8: return false
	var shape := CapsuleShape3D.new(); shape.radius = .32; shape.height = 1.64
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.collision_mask = 1; query.exclude = [main.player.get_rid()]; query.transform.origin = point+Vector3.UP*.84
	return main.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func can_resume() -> bool: return not active or (not busy and not _failed and _ready_to_play())
func _target() -> Dictionary:
	if not is_instance_valid(main.player): return {}
	var camera: Node3D = main.player.camera
	var candidates := _stations.duplicate()
	if is_instance_valid(_exit): candidates["departure"] = _exit
	var best: Dictionary = {}; var distance := 2.7
	for id: String in candidates:
		if not is_instance_valid(candidates[id]): continue
		var node: Node3D = candidates[id]
		var point: Vector3 = node.global_position+node.get_meta("interaction_offset",Vector3.UP*1.1)
		var offset := point-camera.global_position
		if offset.length() >= distance or (-camera.global_basis.z).dot(offset.normalized()) < .86: continue
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[main.player.get_rid()])
		var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and (not hit.collider is Node or not node.is_ancestor_of(hit.collider)): continue
		distance = offset.length(); best = {"id":id,"label":str(node.get_meta("label",""))}
	return best
func _process(delta: float) -> void:
	if not is_instance_valid(main) or not main._booted: return
	_enter.disabled = busy or main._switching_spawn
	_selector.disabled = busy or main._switching_spawn
	_recovery.visible = not writable; _recovery.disabled = busy
	if busy and is_instance_valid(main._campaign): main._campaign._continue.disabled = true
	_relaxed.disabled = busy; _reduced.disabled = busy
	_summary.text = TranslationServer.translate("新增地图 · 独立进度 / DREAMCORE") + (TranslationServer.translate(" · 只读，原文件保留") if not writable else "")
	if not message.is_empty(): _summary.text += "\n"+tr(message)
	_hud.visible = active and main.hints_visible()
	if not active:
		_sync_scene_interactions(false)
		return
	var playable := _scene_playable()
	_sync_scene_interactions(playable)
	if is_instance_valid(_ambience): _ambience.update(playable and main._audio_on and main._ambience_on)
	var target := _target() if playable else {}
	var data := current_definition()
	var observed_id := _observed_id(target) if playable else ""
	state.advance(delta,playable,data.get("stations",[]),observed_id)
	if target.is_empty() and not observed_id.is_empty(): target = {"id":observed_id,"label":str(_specs.get(observed_id,{}).get("label",TranslationServer.translate("观察点")))}
	_update_readouts()
	_tint.color.a = move_toward(_tint.color.a, state.corruption()*(.025 if state.reduced_effects else .08) if playable else 0.0, delta*.015)
	_cooldown = maxf(0,_cooldown-delta)
	if playable:
		_autosave += minf(delta,.25)
		if _autosave >= 10: _save(); _autosave = 0
	_hud.text = tr(str(data.get("title","")))+"\n"+tr(str(data.get("goal","观察空间，读懂设施，再继续。")))
	_hud.text += TranslationServer.translate("\n舒缓探索 · 不计时") if state.relaxed else TranslationServer.translate("\n可选侵蚀 %d%% · 菜单可随时修复") % int(state.corruption()*100)
	if not target.is_empty():
		if target.id == "departure": _hud.text += TranslationServer.translate("\n[E] 继续旅程") if state.entry().solved else TranslationServer.translate("\n设施尚未稳定；观察刻牌与读数。")
		elif _specs.has(target.id):
			var spec: Dictionary = _specs[target.id]
			_hud.text += "\n"+tr(str(spec.label))+" · "+tr(str(spec.get("clue","")))
			if spec.get("kind","") == "observe": _hud.text += TranslationServer.translate("\n静静观察 %.0f / %.0f 秒") % [state.entry().observed.get(target.id,0),spec.get("observation_seconds",12)]
			else: _hud.text += "\n[E] "+_feedback(spec)
	if state.entry().solved: _hud.text += TranslationServer.translate("\n设施已稳定。可继续漫游，或前往离场终端。")
	if not message.is_empty(): _hud.text += "\n"+tr(message)
func _input(event: InputEvent) -> void:
	if not is_instance_valid(main) or not main._booted: return
	if busy and event.is_action_pressed("pause"):
		_cancel=true
		if is_instance_valid(_threshold): _threshold.cancel()
		get_viewport().set_input_as_handled(); return
	if not active: return
	if main.menu_open or busy or not _focused or main._switching_spawn or _failed or _cooldown>0: return
	if not event.is_action_pressed("interact") or event.is_echo(): return
	if not is_instance_valid(main.world) or not main.world.current_room_ready() or not main.water.is_terrain_ready(): return
	var target := _target()
	if target.is_empty(): return
	get_viewport().set_input_as_handled(); _cooldown = .25
	if target.id == "departure":
		if not state.entry().solved: return
		var was_completed: bool = state.entry().completed
		state.entry().completed = true
		if not _save(): state.entry().completed = was_completed; return
		var next := Catalog.next_id(state.scene_id)
		if next.is_empty(): message = "旅程已记录。这里依然空旷，你可以留下，也可以从菜单重访。"; main.set_menu(true)
		else: enter_scene(next)
	elif _specs.has(target.id):
		var spec: Dictionary = _specs[target.id]
		if state.operate(spec):
			message = _feedback(spec); _save()
			if spec.get("kind","") == "broadcast" and is_instance_valid(_ambience): _ambience.broadcast(spec.position,int(spec.get("target",1)))
		else: message = "上游尚未接通，或前一段广播尚未交接。已完成的部分保留。"
func flush() -> void:
	if active and not busy and not _failed: _save()
func _save() -> bool:
	if not writable: message = "独立续篇存档只读；原文件未改动，本次进度未保存。"; return false
	var result := Store.save_state(state,save_path,fingerprint)
	if result != OK: message = TranslationServer.translate("续篇保存失败（%d）；不推进旅程。") % result; return false
	fingerprint = str(Store.load_state(save_path).get("fingerprint","")); return true
func restore_checkpoint() -> void:
	if active and not busy: main.travel_to(Vector2i.ZERO,true)
func _build_ui() -> void:
	var layer := CanvasLayer.new(); layer.layer = 91; add_child(layer)
	_tint = ColorRect.new(); _tint.color = Color(.10,.13,.12,0); _tint.mouse_filter = Control.MOUSE_FILTER_IGNORE; _tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layer.add_child(_tint)
	_hud = Label.new(); _hud.position = Vector2(28,104); _hud.size = Vector2(710,300); _hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _hud.add_theme_font_override("font",DreamFont); layer.add_child(_hud); _hud.hide()
	var column: Node = main._spawn_select.get_parent().get_parent()
	_summary = Label.new(); _summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(_summary)
	_selector = OptionButton.new()
	for title: String in Catalog.TITLES: _selector.add_item(title)
	_selector.select(maxi(0,Catalog.IDS.find(state.scene_id))); column.add_child(_selector)
	_enter = Button.new(); _enter.text = "进入所选地图 / ENTER"; _enter.pressed.connect(func():enter_scene(Catalog.IDS[_selector.selected])); column.add_child(_enter)
	_relaxed = CheckButton.new(); _relaxed.text = "地图舒缓探索（默认）：无计时侵蚀"; _relaxed.button_pressed = state.relaxed; _relaxed.toggled.connect(func(value:bool):state.relaxed=value;_save()); column.add_child(_relaxed)
	_reduced = CheckButton.new(); _reduced.text = "地图减弱效果（无频闪）"; _reduced.button_pressed = state.reduced_effects; _reduced.toggled.connect(func(value:bool):state.reduced_effects=value;_save()); column.add_child(_reduced)
	_repair = Button.new(); _repair.text = "地图应急复位（保留设施进度）"; _repair.pressed.connect(_repair_pressure); column.add_child(_repair)
	_recovery = Button.new(); _recovery.text = "地图另存恢复副本（保留原文件）"; _recovery.pressed.connect(_recover); column.add_child(_recovery)
	var theme := Theme.new(); theme.default_font = DreamFont
	for control: Control in [_summary,_selector,_enter,_relaxed,_reduced,_repair,_recovery]: control.theme = theme
	var controls := [_summary,_selector,_enter,_relaxed,_reduced,_repair,_recovery]
	for index in controls.size(): column.move_child(controls[index],4+index)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_sync_scene_interactions(false)
		if active and is_instance_valid(main) and main._booted: main.set_menu(true)
func apply_environment() -> void:
	if not active or not is_instance_valid(main.environment): return
	if _environment_scene == state.scene_id: return
	# A previous indoor palette tween must not overwrite the authored outdoor
	# environment after the scene has switched. The source class is untouched.
	if is_instance_valid(main.lighting):
		var previous_mood: Tween = main.lighting.get("_mood_tween")
		if is_instance_valid(previous_mood) and previous_mood.is_valid(): previous_mood.kill()
	_environment_scene = state.scene_id
	if is_instance_valid(_ambience): _ambience.configure(main,state.scene_id)
	var data := current_definition()
	var environment: Environment = main.environment.environment
	if _original_environment.is_empty():
		_original_environment = {"sky":environment.sky,"ambient_light_color":environment.ambient_light_color,"ambient_light_energy":environment.ambient_light_energy,"tonemap_exposure":environment.tonemap_exposure}
		for property: String in ["fog_enabled","fog_density","fog_height","fog_height_density","fog_light_color","fog_sky_affect"]:
			_original_environment[property] = environment.get(property)
		var original_sun: DirectionalLight3D = main.environment.get_node_or_null("ApertureSun")
		if original_sun != null:
			_original_environment.sun_color=original_sun.light_color; _original_environment.sun_energy=original_sun.light_energy; _original_environment.sun_rotation=original_sun.rotation_degrees
	_apply_uncanny_environment(environment)
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = _color(data.get("sky_top","#7999ae"))
	sky.sky_horizon_color = _color(data.get("sky_horizon","#c2cbbd"))
	sky.ground_horizon_color = sky.sky_horizon_color
	sky.ground_bottom_color = _color(data.get("ground_color","#3d5048"))
	var resource := Sky.new(); resource.sky_material = sky
	if data.has("sky_shader") and ResourceLoader.exists(str(data.sky_shader)):
		var sky_material := ShaderMaterial.new(); sky_material.shader = load(str(data.sky_shader)) as Shader
		if data.has("sky_panorama") and ResourceLoader.exists(str(data.sky_panorama)):
			sky_material.set_shader_parameter("panorama",load(str(data.sky_panorama)))
		# Explicit scene-local gain; absent keys and every other scene keep defaults.
		if state.scene_id == "soffit_reservoir" and data.has("sky_radiance_gain"):
			var gain: Variant = data.sky_radiance_gain
			if (gain is int or gain is float) and is_finite(float(gain)):
				sky_material.set_shader_parameter("radiance_gain",clampf(float(gain),1.0,8.0))
		resource.sky_material = sky_material
	environment.sky = resource
	environment.ambient_light_color = _color(data.get("ambient","#c7d5d0"))
	environment.ambient_light_energy = float(data.get("ambient_energy",.35))
	environment.tonemap_exposure = float(data.get("exposure",1.1))
	# Optional extension-only native height mist; horizontal source fog remains
	# source-owned. Zero native distance density avoids duplicating that term.
	environment.fog_enabled = float(data.get("fog_height_density",0.0)) > 0.0
	environment.fog_density = 0.0
	environment.fog_height = float(data.get("fog_height",0.0))
	environment.fog_height_density = float(data.get("fog_height_density",0.0))
	environment.fog_light_color = _color(data.get("fog_color","#aebdbb"))
	environment.fog_sky_affect = 0.0
	var sun: DirectionalLight3D = main.environment.get_node_or_null("ApertureSun")
	if sun != null:
		sun.light_color = _color(data.get("sun_color","#f1dfb5"))
		sun.light_energy = float(data.get("sun_energy",.7))
		sun.rotation_degrees = data.get("sun_rotation",Vector3(-18,-35,0))
	main.water.refresh_capture_lighting()

func _observed_id(target: Dictionary) -> String:
	var camera: Node3D = main.player.camera
	for spec: Dictionary in current_definition().get("stations",[]):
		if spec.get("kind","") != "observe": continue
		if not state.prerequisite(spec): continue
		if not spec.has("observation_target"):
			if target.get("id","") == str(spec.id): return str(spec.id)
			continue
		if main.player.global_position.distance_to(spec.position) > float(spec.get("observation_radius",5.0)): continue
		var toward: Vector3 = spec.observation_target-camera.global_position
		if (-camera.global_basis.z).dot(toward.normalized()) < .94: continue
		if not _observation_line_clear(camera.global_position,spec.observation_target): continue
		return str(spec.id)
	return ""

func _recover() -> void:
	if writable or busy: return
	var path := "user://dreamcore_recovery_%d.json" % Time.get_unix_time_from_system()
	if FileAccess.file_exists(path): message = "恢复副本已存在，请稍后再试。"; return
	var result := Store.save_state(state,path)
	if result != OK: message = "恢复副本无法写入；原文件仍保留。"; return
	var profile := ConfigFile.new(); profile.set_value("dreamcore","save_path",path)
	if profile.save("user://dreamcore_profile.cfg") != OK: message = "副本已保存但路径未记住："+path; return
	save_path = path; writable = true; fingerprint = str(Store.load_state(path).get("fingerprint",""))
	message = "已启用独立恢复副本；旧存档与中断写入证据均保留。"

static func _color(value: Variant) -> Color:
	return value if value is Color else Color(str(value))

func _apply_uncanny_environment(environment: Environment) -> void:
	if state.scene_id not in Catalog.UNCANNY_IDS:
		_restore_uncanny_environment()
		return
	# A replacement Environment is a distinct owner, never a restoration target
	# for the retired instance. New-to-new reuse keeps the first snapshot.
	if _uncanny_environment_owner == null or _uncanny_environment_owner.get_ref() != environment:
		_uncanny_original_environment.clear(); _uncanny_applied_environment.clear()
		_uncanny_environment_owner = weakref(environment)
		for property: String in UNCANNY_ENVIRONMENT_DEFAULTS:
			_uncanny_original_environment[property] = environment.get(property)
	for property: String in UNCANNY_ENVIRONMENT_DEFAULTS:
		environment.set(property,UNCANNY_ENVIRONMENT_DEFAULTS[property])
		_uncanny_applied_environment[property] = environment.get(property)

func _restore_uncanny_environment() -> void:
	var owner: Environment = _uncanny_environment_owner.get_ref() as Environment if _uncanny_environment_owner != null else null
	var current: Environment = main.environment.environment if is_instance_valid(main) and is_instance_valid(main.get("environment")) else null
	var still_owned := owner != null and owner == current
	var latest: Variant = main.get("_last_layout") if is_instance_valid(main) else null
	# A later ordinary/formal lighting callback takes precedence, even when its
	# numerical values happen to equal this room's baseline.
	if latest is Dictionary and not latest.is_empty() and not latest.get("dreamcore",false): still_owned = false
	if still_owned:
		# A changed field is no longer ours; restore the other four independently.
		# Equal-valued external writes are not distinguishable without a setter
		# revision token; the non-Dream callback guard above covers that case.
		for property: String in _uncanny_original_environment:
			if owner.get(property) == _uncanny_applied_environment.get(property):
				owner.set(property,_uncanny_original_environment[property])
	_uncanny_environment_owner = null
	_uncanny_original_environment.clear(); _uncanny_applied_environment.clear()

func _restore_environment() -> void:
	_restore_uncanny_environment()
	if _original_environment.is_empty() or not is_instance_valid(main.environment): return
	var environment: Environment = main.environment.environment
	for property: String in ["sky","ambient_light_color","ambient_light_energy","tonemap_exposure","fog_enabled","fog_density","fog_height","fog_height_density","fog_light_color","fog_sky_affect"]:
		environment.set(property,_original_environment[property])
	var sun: DirectionalLight3D = main.environment.get_node_or_null("ApertureSun")
	if sun != null and _original_environment.has("sun_color"):
		sun.light_color = _original_environment.sun_color; sun.light_energy = _original_environment.sun_energy; sun.rotation_degrees = _original_environment.sun_rotation
	_original_environment.clear(); _environment_scene = ""

func _feedback(spec: Dictionary) -> String:
	var value := int(state.entry().values.get(str(spec.id),0))
	if spec.has("value_labels"):
		var labels: Array = spec.value_labels
		if value >= 0 and value < labels.size():
			return tr(str(spec.get("action","调整")))+" · "+tr(str(labels[value]))
	match str(spec.get("kind","")):
		"broadcast": return TranslationServer.translate("广播交接 %d / 3 · 按起点→中场→终点依次发送；不是旋钮密码") % int(state.entry().observed.get("broadcast_cursor",0))
		"sluice": return TranslationServer.translate("水路指示：") + [TranslationServer.translate("关闭 CLOSED"),TranslationServer.translate("北线 NORTH"),TranslationServer.translate("东线 EAST"),TranslationServer.translate("溢流 OVERFLOW")][value] + (TranslationServer.translate(" · 上游未就绪") if not state.prerequisite(spec) else TranslationServer.translate(" · 调整出流方向"))
		"departure_signal": return TranslationServer.translate("站牌信号已接通；去远处观察点等候回应") if value == 1 else TranslationServer.translate("接通末班站牌（无倒计时催促）")
		"light": return TranslationServer.translate("光色：") + [TranslationServer.translate("夜色"),TranslationServer.translate("清晨"),TranslationServer.translate("天光"),TranslationServer.translate("暮色")][value]
		"flow": return TranslationServer.translate("模式：") + [TranslationServer.translate("关闭"),TranslationServer.translate("微弱"),TranslationServer.translate("安静"),TranslationServer.translate("全部")][value]
		_: return TranslationServer.translate("调整 · 当前 %d") % value

func _add_station_shape(root: Node3D, spec: Dictionary, material: Material) -> void:
	var kind := str(spec.get("kind",""))
	var detail := MeshInstance3D.new(); detail.name = "Mechanism"; detail.material_override = material
	if kind == "broadcast":
		var aerial := CylinderMesh.new(); aerial.top_radius=.015; aerial.bottom_radius=.015; aerial.height=.8; aerial.radial_segments=8
		detail.mesh=aerial; detail.position=Vector3(-.2,1.28,-.08)
	elif kind == "sluice" or kind == "flow":
		var wheel := TorusMesh.new(); wheel.inner_radius=.19; wheel.outer_radius=.25; wheel.rings=16; wheel.ring_segments=8
		detail.mesh=wheel; detail.rotation_degrees.x=90; detail.position=Vector3(0,1.0,.18)
	elif kind == "observe":
		var scope := CylinderMesh.new(); scope.top_radius=.08; scope.bottom_radius=.08; scope.height=.45; scope.radial_segments=12
		detail.mesh=scope; detail.rotation_degrees.x=90; detail.position=Vector3(0,1.3,0)
	elif kind == "departure_signal":
		var plate := BoxMesh.new(); plate.size=Vector3(.65,.9,.08); detail.mesh=plate; detail.position=Vector3(0,1.4,-.12)
	else:
		var dial := CylinderMesh.new(); dial.top_radius=.12; dial.bottom_radius=.12; dial.height=.08; dial.radial_segments=16
		detail.mesh=dial; detail.rotation_degrees.x=90; detail.position=Vector3(0,1.0,.15)
	root.add_child(detail)
func _update_readouts() -> void:
	for id: String in _stations:
		if not is_instance_valid(_stations[id]) or not _specs.has(id): continue
		var station: Node3D = _stations[id]
		var label := station.get_node_or_null("Readout") as Label3D
		if label == null: continue
		var spec: Dictionary = _specs[id]
		var value := int(state.entry().values.get(id,0))
		var suffix := str(value)
		if spec.has("value_labels") and value >= 0 and value < spec.value_labels.size(): suffix = str(spec.value_labels[value])
		elif spec.get("kind","") == "broadcast": suffix = TranslationServer.translate("已发送") if value>0 else TranslationServer.translate("等待交接")
		elif spec.get("kind","") == "sluice": suffix = [TranslationServer.translate("关闭"),TranslationServer.translate("北线"),TranslationServer.translate("东线"),TranslationServer.translate("溢流")][value]
		elif spec.get("kind","") == "observe": suffix = "%d / %d s" % [int(state.entry().observed.get(id,0)),int(spec.get("observation_seconds",12))]
		elif spec.get("kind","") == "departure_signal": suffix = TranslationServer.translate("已接通") if value == 1 else TranslationServer.translate("未接通")
		elif spec.get("kind","") == "light": suffix = [TranslationServer.translate("夜色"),TranslationServer.translate("清晨"),TranslationServer.translate("天光"),TranslationServer.translate("暮色")][value]
		elif spec.get("kind","") == "flow": suffix = [TranslationServer.translate("关闭"),TranslationServer.translate("微弱"),TranslationServer.translate("安静"),TranslationServer.translate("全部")][value]
		var text := tr(str(spec.get("label","")))+"\n"+tr(suffix)
		if label.text != text: label.text = text

func _observation_line_clear(from: Vector3, to: Vector3) -> bool:
	var excluded: Array[RID] = [main.player.get_rid()]
	for pass_index in range(8):
		var ray := PhysicsRayQueryParameters3D.create(from,to,1,excluded)
		var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.position.distance_to(to)<=3.0: return true
		var collider: Variant = hit.get("collider")
		# Physical glazing stays solid to the unchanged player. Only a separate,
		# explicitly authored transparent collider may pass a scenic gaze ray.
		if not collider is CollisionObject3D or not collider.get_meta("dream_observation_transparent",false): return false
		excluded.append(collider.get_rid())
	return false

func _repair_pressure() -> void:
	state.repair()
	if _save(): message = "侵蚀已复位，设施进度保留。"

func preserve_unchanged_campaign_on_quit() -> bool:
	# A cancelled threshold can restore the original live campaign. Quitting
	# from that unchanged safe menu must not canonicalize its original bytes.
	# Any real subsequent campaign progress changes the serialization and
	# therefore retains the original runtime's normal flush behaviour.
	return not _campaign_entry_serial.is_empty() and is_instance_valid(main._campaign) and JSON.stringify(main._campaign.state.serialize()) == _campaign_entry_serial

func _sync_scene_interactions(playable: bool) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.get("world")): return
	var world: Node = main.world
	if not world.has_method("set_scene_playable"): return
	if world.has_method("has_scene_effects") and world.has_scene_effects():
		if active and world.get("scene_id") == state.scene_id:
			var progress := state.entry()
			world.apply_scene_state(progress.values,progress.observed,state.reduced_effects)
		world.set_scene_audio_enabled(playable and _scene_playable() and bool(main.get("_audio_on")) and bool(main.get("_ambience_on")))
	var player: CharacterBody3D = (main.get("player") as CharacterBody3D) if active else null
	world.set_scene_playable(playable and _scene_playable(),player)
func _release_scene_interactions() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.get("world")): return
	if main.world.has_method("release_scene_interactions"): main.world.release_scene_interactions()
func menu_changed(open: bool) -> void:
	# Main calls synchronously after disabling input: held references cannot
	# survive a menu frame or move a frozen actor during a modal transition.
	if open: _sync_scene_interactions(false)
	# Resume is deliberately deferred until the authoritative readiness gate.
func _exit_tree() -> void:
	_restore_uncanny_environment()
	_release_scene_interactions()

func _scene_playable() -> bool:
	if not active or busy or _failed or not _focused or not is_instance_valid(main): return false
	if not main._booted or main.menu_open or main._switching_spawn: return false
	if not is_instance_valid(main.get("world")) or not is_instance_valid(main.get("water")): return false
	return main.world.current_room_ready() and main.water.is_terrain_ready()

func prepare_player_relocation() -> void:
	# The original warp helper transports any held prop with the player. A
	# physical pit ball stays in its authored world instead, released first.
	_sync_scene_interactions(false)
