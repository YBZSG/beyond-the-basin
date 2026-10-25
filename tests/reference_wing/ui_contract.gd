extends SceneTree
## Actual production UI modules and exact extracted main.gd methods. Dummy renderer only.
const Host=preload("res://tests/reference_wing/ui_host.gd")
const Settings=preload("res://scripts/reference_wing/reference_look_settings.gd")
const Catalog=preload("res://scripts/reference_wing/reference_catalog.gd")
const Restart=preload("res://scripts/app/world_restart.gd")
const DesktopSettings=preload("res://tests/reference_wing/ui_desktop_settings.gd")
var checks:Dictionary={}
var failures:Array[String]=[]
var details:Dictionary={}
class WaterDouble extends Node3D:
	var last_reference:Dictionary={}
	var tunings:Dictionary={}
	func set_reference_wave_settings(value:Dictionary)->void:last_reference=value.duplicate(true)
	func set_tuning(key:String,value:Variant)->void:tunings[key]=value
	func set_enabled(_value:bool)->void:pass
	func set_debug_view(_value:int)->void:pass
class RestartCapture extends Restart:
	var captured:Dictionary={}
	func request(mode:String,seed_value:int,busy:bool,save_selection:Callable,_orderly_quit:Callable)->Dictionary:
		captured={"mode":mode,"seed":seed_value,"busy":busy}
		if busy:return {"ok":false,"reason":"test busy"}
		var saved:Variant=save_selection.call(mode,seed_value)
		captured.saved=saved
		return {"ok":saved==OK,"reason":"Test double saved selection without arming a process restart"}
func _initialize()->void:_run.call_deferred()
func check(label:String,condition:bool)->void:
	checks[label]=condition
	if not condition:failures.append(label)
func new_host()->Node3D:
	var host:=Host.new();root.add_child(host);return host
func settings_file()->ConfigFile:
	var file:=ConfigFile.new();check("saved_config_is_readable",file.load("user://settings.cfg")==OK);return file
func _run()->void:
	if DisplayServer.get_name()!="headless" or RenderingServer.get_rendering_device()!=null:
		push_error("UI review only permits the headless dummy renderer");quit(2);return
	if "--reload-verification" in OS.get_cmdline_user_args():
		_test_separate_process_reload()
		print("REFERENCE_UI_CONTRACT ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"gpu_run":false}))
		quit(0 if failures.is_empty() else 1);return
	var static_checks:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/reference_wing/ui_sources.json"))
	for key:String in static_checks:check(key,static_checks[key])
	_test_persistence()
	_test_visibility()
	_test_modes_and_restart()
	_test_cameras()
	await _test_controls_and_layout()
	_prepare_separate_process_reload()
	print("REFERENCE_UI_CONTRACT ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"details":details,"engine":Engine.get_version_info().string,"gpu_run":false,"scope":"Isolated actual UI nodes and exact extracted main settings/mode callbacks, disk persistence and pure restart plan. No full game, GPU shader execution, actual restart, target visuals, RT/NR engine validation or import."}))
	quit(0 if failures.is_empty() else 1)
func _test_persistence()->void:
	var host:=new_host()
	host._load_settings()
	check("absent_file_defaults_both_additions_off",host._reference_settings==Settings.DEFAULT)
	var config:=ConfigFile.new()
	var legacy_water:Dictionary={"windWaves":false,"windStrength":0.73,"windDirection":245.0,"windDensity":1.35,"waveHeight":1.42,"solverSteps":6,"reflection":false,"futureWaterValue":"retain me"}
	var graphics:Dictionary={"preset":"Ultra","raytracing":true,"dlss":"Balanced","nr":true,"nr_layers":2,"nr_intensity":0.35,"nr_tone":0.65,"nr_structure":0.4,"frame_generation":false,"msaa":2,"taa":false,"scale":0.85,"water":"High","shadow_size":4096,"futureGraphics":Vector2(1,2)}
	var desktop:=ConfigFile.new()
	for key:String in graphics:desktop.set_value("graphics",key,graphics[key])
	check("separate_desktop_preferences_written",desktop.save("user://desktop_quality.cfg")==OK)
	var desktop_before:=FileAccess.get_file_as_bytes("user://desktop_quality.cfg")
	for key:String in graphics:config.set_value("graphics",key,graphics[key])
	config.set_value("water","settings",legacy_water);config.set_value("game","spawn_mode","poolrooms");config.set_value("game","seed",478)
	config.set_value("unowned","untouched",[1,"anything",false])
	check("legacy_fixture_written_to_disk",config.save("user://settings.cfg")==OK)
	host._load_settings()
	check("old_settings_migrate_reference_off",host._reference_settings==Settings.DEFAULT and host._spawn_mode=="poolrooms")
	host._change_reference_setting("referenceLook",true)
	host._change_reference_setting("referenceWaves",true)
	host._change_reference_setting("referenceWaveDirection",-450.0)
	host._change_reference_setting("referenceFringePx",1.35)
	var reference:Dictionary=host._reference_settings.duplicate(true)
	var reloaded:=new_host();reloaded._load_settings()
	check("actual_main_disk_roundtrip_reference_settings",reloaded._reference_settings==reference)
	check("main_roundtrip_direction_wrapped",reloaded._reference_settings.referenceWaveDirection==270.0)
	check("main_roundtrip_does_not_change_legacy_water",reloaded._water_settings==legacy_water)
	var after:=settings_file()
	var preserved:=true
	for key:String in graphics:preserved=preserved and after.get_value("graphics",key)==graphics[key]
	check("ordinary_autosave_keeps_rt_nr_graphics_and_unknowns",preserved and after.get_value("unowned","untouched")==[1,"anything",false])
	check("ordinary_autosave_keeps_world_selection",after.get_value("game","spawn_mode")=="poolrooms" and after.get_value("game","seed")==478)
	check("legacy_ccd_stays_session_only",not reloaded._ccd_on and reloaded._filter_mode==0 and reloaded._reference_settings.referenceLook)
	host._pc_mainhall_preview=true;host._pc_preview_return_spawn="reference";host._spawn_mode="formal"
	check("preview_autosave_succeeds",host._save_settings()==OK)
	check("preview_autosave_remembers_reference_return",settings_file().get_value("game","spawn_mode")=="reference")
	check("reference_atomic_restart_selection_save",host._save_settings("reference",9223372036854775807,true)==OK)
	after=settings_file()
	check("atomic_save_keeps_reference_and_max_seed",after.get_value("game","spawn_mode")=="reference" and after.get_value("game","seed")==9223372036854775807 and after.get_value("reference_wing","look")==reference)
	preserved=true
	for key:String in graphics:preserved=preserved and after.get_value("graphics",key)==graphics[key]
	check("atomic_save_keeps_rt_nr_graphics_and_water",preserved and after.get_value("water","settings")==legacy_water)
	var before:=FileAccess.get_file_as_string("user://settings.cfg")
	host._world_restart._requested=true
	check("queued_autosave_cannot_undo_restart",host._save_settings()==ERR_BUSY and FileAccess.get_file_as_string("user://settings.cfg")==before)
	host._world_restart._requested=false
	host._reference_settings={"referenceLook":"false","referenceWaves":true,"referenceWaveStrength":INF,"referenceWaveScale":-10,"referenceFringePx":999,"referenceGrain":NAN,"referenceWaveDirection":721,"legacyUnowned":"ignored"}
	check("invalid_reference_disk_write_sanitized",host._save_settings()==OK)
	reloaded._load_settings()
	check("invalid_reference_reload_sanitized",reloaded._reference_settings==Settings.sanitize(host._reference_settings))
	check("unknown_reference_keys_not_owned",not reloaded._reference_settings.has("legacyUnowned"))
	check("main_settings_never_rewrites_desktop_quality_file",FileAccess.get_file_as_bytes("user://desktop_quality.cfg")==desktop_before)
	host.free();reloaded.free()
func _test_visibility()->void:
	var host:=new_host();host.build_camera_fixture()
	var water:=WaterDouble.new();host.add_child(water);host.water=water
	check("default_post_hidden_exact_pass_bypass",not host._film_rect.visible)
	check("film_is_below_default_hud_and_mouse_transparent",host._film_rect.get_parent().layer==0 and host._film_rect.mouse_filter==Control.MOUSE_FILTER_IGNORE)
	for mode in range(4):
		host._reference_settings=Settings.DEFAULT.duplicate();host._set_filter(mode)
		check("legacy_mode_preserved_"+str(mode),host._film_rect.visible==(mode!=0) and host._film_rect.material.get_shader_parameter("look_mode")==mode)
		host._change_reference_setting("referenceLook",true)
		check("reference_composes_independently_"+str(mode),host._film_rect.visible and host._filter_mode==mode and host._film_rect.material.get_shader_parameter("reference_look_enabled"))
		host._change_reference_setting("referenceLook",false)
		check("reference_off_restores_legacy_visibility_"+str(mode),host._film_rect.visible==(mode!=0) and host._filter_mode==mode)
	host._set_filter(0);host._change_reference_setting("referenceWaves",true)
	check("waves_do_not_enable_filter",not host._film_rect.visible and water.last_reference.referenceWaves)
	host._change_reference_setting("referenceLook",true)
	for key:String in ["referenceFringePx","referenceGrain","referenceVignette"]:host._change_reference_setting(key,0.0)
	check("enabled_zero_filter_hidden_identity",not host._film_rect.visible and water.last_reference.referenceWaves)
	host._set_filter(2)
	check("zero_filter_keeps_existing_vhs",host._film_rect.visible and host._film_rect.material.get_shader_parameter("look_mode")==2)
	host._set_filter(-8);check("filter_mode_low_clamps",host._filter_mode==0)
	host._set_filter(88);check("filter_mode_high_clamps",host._filter_mode==3)
	host.free()
func _test_modes_and_restart()->void:
	var host:=new_host();host._booted=true;host._seed_edit=LineEdit.new();host.add_child(host._seed_edit);host._seed_edit.text="2468";host.build_world_options_fixture();host.add_child(host._spawn_select)
	check("world_selector_keeps_four_modes_and_appends_reference",host._spawn_select.item_count==5 and host._spawn_select.get_item_id(4)==4 and "REFERENCE WING" in host._spawn_select.get_item_text(4))
	for index in 5:
		host._choose_spawn(index)
		check("actual_mode_callback_"+str(index),host.regeneration_calls[-1]=={"mode":Host.SPAWN_MODES[index],"seed":2468})
	var calls:int=host.regeneration_calls.size();host._switching_spawn=true;host._choose_spawn(0)
	check("mode_switch_reentrancy_guard",host.regeneration_calls.size()==calls and host._spawn_select.selected==4)
	host._switching_spawn=false;host._seed_edit.text="3.25";host._choose_spawn(2)
	check("invalid_seed_never_switches_mode",host.regeneration_calls.size()==calls and host._spawn_mode=="reference")
	host._seed_edit.text="2468";host._pc_mainhall_preview=true;host._choose_spawn(4)
	check("preview_exit_targets_reference",host.preview_calls==[[false,"reference"]] and host.regeneration_calls.size()==calls)
	check("restart_supports_five_modes_and_reference_flag",Restart.MODES==Host.SPAWN_MODES and "--reference-wing" in Restart.WORLD_FLAGS)
	var exact:Dictionary={"version":1,"executable":"/tmp/game.exe","pack":"/tmp/game.pck","args":["--rendering-method","forward_plus","--rendering-driver","vulkan","--gpu-index","1","--","--reference-wing","--custom-flag=retain"]}
	var plan:Dictionary=Restart.build_plan(exact,"/tmp/game.exe",PackedStringArray(["--reference-wing","--custom-flag=retain"]),"Linux","forward_plus","vulkan")
	check("restart_strips_stale_reference_mode_only",plan.ok and plan.args==PackedStringArray(["--rendering-method","forward_plus","--rendering-driver","vulkan","--gpu-index","1","--","--custom-flag=retain"]))
	var no_renderer:Dictionary=exact.duplicate(true);no_renderer.args=["++","--poolrooms-wing","--custom-flag=retain"]
	plan=Restart.build_plan(no_renderer,"/tmp/game.exe",PackedStringArray(["--reference-wing","--custom-flag=retain"]),"Linux","forward_plus","d3d12")
	check("restart_pins_actual_driver_and_preserves_plus_separator",plan.ok and plan.args==PackedStringArray(["--rendering-method","forward_plus","--rendering-driver","d3d12","++","--custom-flag=retain"]))
	for world_flag:String in Restart.WORLD_FLAGS:
		var contract:Dictionary=exact.duplicate(true);contract.args=["--",world_flag,"--custom-flag=retain"]
		plan=Restart.build_plan(contract,"/tmp/game.exe",PackedStringArray([world_flag,"--custom-flag=retain"]),"Linux","forward_plus","vulkan")
		check("all_world_flags_removed_"+world_flag,plan.ok and world_flag not in plan.args and "--custom-flag=retain" in plan.args)
	for forbidden:String in ["--headless","--script","--editor","--path","--import"]:
		var contract:Dictionary=exact.duplicate(true);contract.args.push_front(forbidden)
		check("restart_rejects_"+forbidden,not Restart.build_plan(contract,"/tmp/game.exe",PackedStringArray(["--reference-wing","--custom-flag=retain"]),"Linux","forward_plus","vulkan").ok)
	check("restart_rejects_renderer_mismatch",not Restart.build_plan(exact,"/tmp/game.exe",PackedStringArray(["--reference-wing","--custom-flag=retain"]),"Linux","forward_plus","d3d12").ok)
	check("restart_rejects_unknown_user_argument_change",not Restart.build_plan(exact,"/tmp/game.exe",PackedStringArray(["--reference-wing","--different"]),"Linux","forward_plus","vulkan").ok)
	var restart:=Restart.new();var counters:Dictionary={"save":0,"quit":0}
	var result:Dictionary=restart.request("reference",123,false,func(_mode,_seed):counters.save+=1;return OK,func():counters.quit+=1)
	check("headless_restart_not_armed_without_launcher_contract",not result.ok and not OS.is_restart_on_exit_set() and counters.save==0 and counters.quit==0)
	var desktop:=DesktopSettings.new();desktop.name="DesktopQuality";desktop.preset="Ultra";desktop.settings={"raytracing":true,"nr":true,"nr_layers":2,"nr_intensity":0.35,"nr_tone":0.65,"nr_structure":0.4,"frame_generation":false,"msaa":2,"taa":false,"scale":.85,"water":"High","shadow_size":4096};host.add_child(desktop)
	host._world_restart=RestartCapture.new();host._spawn_select.select(4);host._world_restart_status=Label.new();host.add_child(host._world_restart_status);host._world_restart_button=Button.new();host.add_child(host._world_restart_button)
	host._restart_into_selected_world()
	check("actual_restart_ui_saves_reference_selection_without_process",host._world_restart.captured=={"mode":"reference","seed":2468,"busy":false,"saved":OK} and not OS.is_restart_on_exit_set())
	check("actual_restart_ui_freezes_selection_after_save",host._switching_spawn and host._spawn_select.disabled and host._world_restart_button.disabled)
	var desktop_disk:=ConfigFile.new();var graphics_ok:=desktop_disk.load("user://desktop_quality.cfg")==OK
	for key:String in desktop.settings:graphics_ok=graphics_ok and desktop_disk.get_value("graphics",key)==desktop.settings[key]
	check("actual_restart_callback_preserves_desktop_graphics_with_real_save",graphics_ok and desktop_disk.get_value("graphics","preset")=="Ultra")
	check("actual_restart_callback_commits_reference_and_seed",settings_file().get_value("game","spawn_mode")=="reference" and settings_file().get_value("game","seed")==2468)
	host.free()
func _test_cameras()->void:
	var records:Array=[]
	for index in 5:
		var data:Dictionary=Catalog.geometry(index);var camera:Dictionary=Catalog.camera(index)
		var view:Dictionary=data.get("camera_views",data.get("recommended_views",[]))[0]
		var offset:=Vector3(Catalog.COORDS[index].x*32,0,Catalog.COORDS[index].y*32)
		check("camera_world_offset_"+Catalog.IDS[index],camera.position==Catalog.vec3(view.get("position",view.get("from")))+offset and camera.target==Catalog.vec3(view.get("target",view.get("toward")))+offset)
		check("camera_finite_vertical_fov_"+Catalog.IDS[index],camera.position.is_finite() and camera.target.is_finite() and camera.position.distance_to(camera.target)>1.0 and view.get("fov_axis")=="vertical" and camera.fov>20 and camera.fov<130 and is_equal_approx(camera.fov,float(view.fov_degrees)))
		check("camera_explicit_reference_aspect_"+Catalog.IDS[index],view.has("reference_resolution") and camera.reference_resolution==view.get("reference_resolution") and camera.reference_resolution[0]>0 and camera.reference_resolution[1]>0)
		records.append({"room":Catalog.IDS[index],"position":str(camera.position),"target":str(camera.target),"vertical_fov":camera.fov,"reference_resolution":camera.reference_resolution})
	details.cameras=records
func _test_controls_and_layout()->void:
	var host:=new_host()
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
	var ui:=Control.new();viewport.add_child(ui);ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme:=Theme.new();theme.default_font_size=16;var font:=SystemFont.new();font.font_names=PackedStringArray(["Noto Sans CJK SC","Microsoft YaHei","Noto Sans","Arial"]);theme.default_font=font;ui.theme=theme
	host._menu=PanelContainer.new();ui.add_child(host._menu)
	var style:=StyleBoxFlat.new();style.content_margin_left=30;style.content_margin_right=30;style.content_margin_top=25;style.content_margin_bottom=24;host._menu.add_theme_stylebox_override("panel",style)
	host._reference_settings=Settings.DEFAULT.duplicate();host._build_water_panel(ui);host._advanced.show()
	var water:=WaterDouble.new();host.add_child(water);host.water=water
	var controls:Dictionary={}
	for key:String in Settings.DEFAULT:controls[key]=host._advanced.find_child(key,true,false)
	check("all_eight_reference_controls_constructed",controls.values().all(func(control):return control!=null))
	for key:String in Settings.DEFAULT:
		var control:Control=controls[key]
		check("focusable_"+key,control.focus_mode==Control.FOCUS_ALL)
		if control is CheckButton:
			control.button_pressed=true
			check("correct_toggle_callback_"+key,host._reference_settings[key]==true and water.last_reference[key]==true)
			control.button_pressed=false
			check("correct_toggle_off_callback_"+key,host._reference_settings[key]==false and water.last_reference[key]==false)
		else:
			var slider:HSlider=control
			slider.value=slider.max_value+100
			check("correct_slider_high_clamp_"+key,is_equal_approx(host._reference_settings[key],slider.max_value) and is_equal_approx(water.last_reference[key],slider.max_value))
			slider.value=slider.min_value-100
			check("correct_slider_low_clamp_"+key,is_equal_approx(host._reference_settings[key],slider.min_value) and is_equal_approx(water.last_reference[key],slider.min_value))
			var label:Label=slider.get_parent().get_child(2)
			check("numeric_label_matches_callback_"+key,label.text==String.num(slider.value,3))
	var saved_reference:Dictionary=host._reference_settings.duplicate(true);host._reset_wind_settings()
	check("wind_reset_never_modifies_reference_settings",host._reference_settings==saved_reference)
	var layouts:Array=[]
	for size:Vector2i in [Vector2i(1024,768),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3440,1440)]:
		viewport.size=size
		await process_frame;await process_frame;await process_frame
		var bounds:=Rect2(Vector2.ZERO,Vector2(size));var panel:Rect2=host._advanced.get_global_rect()
		check("panel_inside_desktop_"+str(size),bounds.encloses(panel))
		var scroll:ScrollContainer=host._advanced.get_child(0);var all_inside:=true;var min_slider:=INF
		for key:String in Settings.DEFAULT:
			var control:Control=controls[key];var rect:=control.get_global_rect()
			all_inside=all_inside and rect.position.x>=scroll.global_position.x and rect.end.x<=scroll.global_position.x+scroll.size.x
			if control is HSlider:min_slider=minf(min_slider,control.size.x)
		check("all_reference_controls_fit_horizontally_"+str(size),all_inside)
		var reference_visible:=true
		for key:String in Settings.DEFAULT:reference_visible=reference_visible and scroll.get_global_rect().encloses(controls[key].get_global_rect())
		check("all_reference_controls_initially_visible_"+str(size),reference_visible)
		check("reference_sliders_have_usable_width_"+str(size),min_slider>=100.0)
		check("desktop_scroll_follows_keyboard_focus_"+str(size),scroll.follow_focus)
		var list:VBoxContainer=scroll.get_child(0)
		var last_legacy_setting:OptionButton=list.get_child(list.get_child_count()-2)
		var back:Button=list.get_child(list.get_child_count()-1)
		var settings_before:Dictionary=host._reference_settings.duplicate(true)
		var water_before:Dictionary=host._water_settings.duplicate(true)
		var disk_before:=FileAccess.get_file_as_bytes("user://settings.cfg")
		last_legacy_setting.grab_focus()
		await process_frame;await process_frame
		check("last_legacy_setting_focus_scrolls_into_view_"+str(size),viewport.gui_get_focus_owner()==last_legacy_setting and scroll.scroll_vertical>0 and scroll.get_global_rect().encloses(last_legacy_setting.get_global_rect()))
		_push_focus_action(viewport,"ui_focus_next")
		await process_frame;await process_frame
		check("tab_to_back_scrolls_into_view_"+str(size),viewport.gui_get_focus_owner()==back and scroll.get_global_rect().encloses(back.get_global_rect()))
		var bottom_scroll:=scroll.scroll_vertical
		_push_focus_action(viewport,"ui_focus_prev")
		await process_frame;await process_frame
		check("reverse_tab_returns_to_last_legacy_setting_"+str(size),viewport.gui_get_focus_owner()==last_legacy_setting and scroll.get_global_rect().encloses(last_legacy_setting.get_global_rect()))
		controls.referenceWaves.grab_focus()
		await process_frame;await process_frame
		check("return_focus_to_reference_top_scrolls_back_"+str(size),viewport.gui_get_focus_owner()==controls.referenceWaves and scroll.scroll_vertical<bottom_scroll and scroll.get_global_rect().encloses(controls.referenceWaves.get_global_rect()))
		check("focus_scrolling_does_not_mutate_saved_settings_"+str(size),host._reference_settings==settings_before and host._water_settings==water_before and FileAccess.get_file_as_bytes("user://settings.cfg")==disk_before)
		layouts.append({"viewport":str(size),"panel":str(panel),"scroll":str(scroll.size),"minimum_reference_slider_width":min_slider,"scroll_follow_focus":scroll.follow_focus,"last_legacy_control":last_legacy_setting.get_class(),"bottom_focus_scroll":bottom_scroll,"returned_top_focus_scroll":scroll.scroll_vertical})
		# Keep each size's initial-layout observation independent of prior focus scrolling.
		viewport.gui_release_focus();scroll.scroll_vertical=0
		await process_frame;await process_frame
	details.layouts=layouts
	var strength:HSlider=controls.referenceWaveStrength;strength.grab_focus()
	check("reference_slider_can_receive_keyboard_focus",viewport.gui_get_focus_owner()==strength)
	var event:=InputEventAction.new();event.action="ui_right";event.pressed=true;viewport.push_input(event);event=InputEventAction.new();event.action="ui_right";event.pressed=false;viewport.push_input(event)
	await process_frame
	check("keyboard_arrow_updates_actual_reference_setting",host._reference_settings.referenceWaveStrength>0.0)
	var expected:Array=["referenceWaves","referenceWaveStrength","referenceWaveDirection","referenceWaveScale","referenceLook","referenceFringePx","referenceGrain","referenceVignette"]
	var focus_good:=true
	for index in expected.size()-1:focus_good=focus_good and controls[expected[index]].find_next_valid_focus()==controls[expected[index+1]]
	check("reference_keyboard_tab_order_matches_visual_order",focus_good)
	viewport.free();host.free()

func _push_focus_action(viewport:SubViewport,action:String)->void:
	var pressed:=InputEventAction.new();pressed.action=action;pressed.pressed=true;viewport.push_input(pressed)
	var released:=InputEventAction.new();released.action=action;released.pressed=false;viewport.push_input(released)

func _prepare_separate_process_reload()->void:
	var host:=new_host();host._load_settings();host._reference_settings=Settings.sanitize({"referenceLook":true,"referenceWaves":true,"referenceWaveStrength":.72,"referenceWaveDirection":182.0,"referenceWaveScale":1.21,"referenceFringePx":1.45,"referenceGrain":.011,"referenceVignette":.125});host._spawn_mode="reference";host.world_seed=-987654321
	check("final_disk_fixture_for_second_process",host._save_settings()==OK)
	var expected:=FileAccess.open("user://ui_reload_expected.bin",FileAccess.WRITE)
	expected.store_var({"reference":host._reference_settings,"water":host._water_settings,"spawn":"reference","seed":-987654321,"desktop":FileAccess.get_file_as_bytes("user://desktop_quality.cfg")});expected.close();host.free()
func _test_separate_process_reload()->void:
	var file:=FileAccess.open("user://ui_reload_expected.bin",FileAccess.READ)
	if file==null:check("first_process_fixture_exists",false);return
	var expected:Dictionary=file.get_var();file.close()
	var host:=new_host();host._load_settings()
	check("second_process_reference_opt_ins_and_values",host._reference_settings==expected.reference)
	check("second_process_water_and_wind_unchanged",host._water_settings==expected.water)
	check("second_process_selected_reference_world_and_seed",host._spawn_mode==expected.spawn and host.world_seed==expected.seed)
	check("second_process_legacy_camera_clean",host._filter_mode==0 and not host._ccd_on)
	check("second_process_desktop_preferences_unchanged",FileAccess.get_file_as_bytes("user://desktop_quality.cfg")==expected.desktop)
	host.free()
