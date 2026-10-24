extends SceneTree
const Controls = preload("res://scripts/rendering/nr_control_settings.gd")
const QualityPanel = preload("res://scripts/rendering/desktop_quality_panel.gd")
var failures: Array[String] = []
func expect(ok: bool, what: String) -> void:
	if not ok: failures.append(what)
func _initialize() -> void:
	var settings := {"nr":true,"frame_generation":true,"nr_layers":99,"nr_intensity":NAN,"nr_tone":-1.0,"nr_structure":2.0}
	Controls.normalize(settings)
	expect(settings.nr_layers == 4 and settings.nr_intensity == 1.0 and settings.nr_tone == 0.0 and settings.nr_structure == 1.0, "clamped finite supported controls")
	expect(not settings.frame_generation, "NR wins conflicting saved profile")
	var controls := Controls.new()
	var a: Dictionary = controls.publish(settings)
	var b: Dictionary = controls.publish(settings)
	expect(a.revision == b.revision, "identical requests do not reset temporal history")
	settings.nr_layers = 2
	var c: Dictionary = controls.publish(settings)
	expect(c.revision > a.revision, "actual changed request advances revision")
	var status := {"schema":1,"process_id":123,"emitted_msec":1000,"supported":true,"capability":"available","state":"active","applied_revision":c.revision,"applied_layers":2}
	expect(Controls.decode_status(JSON.stringify(status),123,1100,c.revision).applied_layers == 2, "native matching success acknowledged")
	expect(Controls.decode_status(JSON.stringify(status),124,1100,c.revision).applied_layers == 0, "inherited other-process status rejected")
	expect(Controls.decode_status(JSON.stringify(status),123,20000,c.revision).applied_layers == 0, "stale active state not presented as effective")
	expect(Controls.decode_status(JSON.stringify(status),123,1100,c.revision+1).applied_layers == 0, "old successful config not new request success")
	status.applied={"layers":1,"tone":.1,"structure":.5,"intensity":1.0}
	expect(Controls.decode_status(JSON.stringify(status),123,1100,c.revision,{"layers":2,"tone":.1,"structure":.5,"intensity":1.0}).applied_layers==0,"same revision with wrong applied values rejected")
	status.state="failed"
	expect(Controls.decode_status(JSON.stringify(status),123,1100,c.revision).applied_layers == 0, "failure cannot retain effective layers")
	expect(not Controls.decode_status("{",123,1100,0).acknowledged, "invalid status rejected")
	expect(not Controls.decode_status("",123,1100,0).supported, "old engine does not appear supported")
	var panel := QualityPanel.new()
	panel.settings_path="user://nr-controls-contract.cfg"
	panel.settings=QualityPanel.preset_settings("High")
	panel.settings.nr=true
	panel.settings.nr_layers=3
	panel.settings.nr_tone=0.45
	panel.settings.nr_structure=0.65
	panel.settings.frame_generation=true
	expect(panel.save_settings() == OK,"save profile")
	panel.load_settings()
	expect(panel.settings.nr_layers==3 and is_equal_approx(panel.settings.nr_tone,.45) and not panel.settings.frame_generation,"load values and normalize conflict")
	panel.select_preset("Medium")
	expect(panel.settings.nr_layers==3 and is_equal_approx(panel.settings.nr_structure,.65),"graphics preset preserves independent NR controls")
	panel.set_option("frame_generation",true)
	expect(not panel.settings.nr,"interactive FG turns NR off")
	panel.set_option("nr",true)
	expect(not panel.settings.frame_generation,"interactive NR turns FG off")
	panel.dlss_status={"active":true}
	panel.nr_status={"acknowledged":true,"fresh":true,"supported":true,"capability":"unknown"}
	expect(not panel._nr_controls_available(),"unknown native capability disables advanced controls")
	panel.nr_status.capability="available"
	expect(panel._nr_controls_available(),"verified native capability enables controls")
	panel.free()
	print("NR_CONTROL_CONTRACT ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"scope":"Actual stock Godot headless settings/state checks only; no NR engine dispatch, NVIDIA image or GPU performance validation."}))
	quit(0 if failures.is_empty() else 1)
