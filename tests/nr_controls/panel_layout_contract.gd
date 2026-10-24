extends SceneTree
const QualityPanel = preload("res://scripts/rendering/desktop_quality_panel.gd")
var failures: Array[String] = []
class Host extends Node3D:
	var _quality="High"
	var _gi_on=false
	var _caustics_on=false
	var _water_settings={}
	var _booted=true
	var menu_open=true
	var water: Node
	var materials: RefCounted
	var environment: WorldEnvironment
	var _menu: PanelContainer
func expect(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var host := Host.new()
	root.add_child(host)
	host.environment=WorldEnvironment.new()
	host.environment.environment=Environment.new()
	host.add_child(host.environment)
	var ui := Control.new()
	host.add_child(ui)
	host._menu=PanelContainer.new()
	host._menu.add_child(VBoxContainer.new())
	ui.add_child(host._menu)
	var panel := QualityPanel.new()
	host.add_child(panel)
	panel.configure(host,"user://nr-layout-contract.cfg")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=size
		ui.size=size
		panel.open_panel()
		for i in 3: await process_frame
		expect(panel._panel.position.x >= 0 and panel._panel.position.y >= 0,"panel top-left within viewport %s" % size)
		expect(panel._panel.position.x+panel._panel.size.x <= size.x and panel._panel.position.y+panel._panel.size.y <= size.y,"panel lower-right within viewport %s" % size)
		expect(panel._options.nr_layers.item_count==4,"four bounded NR choices")
		expect(panel._options.nr_layers.disabled,"actual stock/headless engine cannot enable experimental layers")
		for slider in panel._nr_sliders.values(): expect(not slider.editable,"stock NR sliders disabled")
		panel._scroll.scroll_vertical=100000
		for i in 3: await process_frame
		var back: Button=panel._scroll.get_child(0).get_child(-1)
		expect(back.text.contains("BACK"),"last control is back")
		expect(back.get_global_rect().end.y<=panel._scroll.get_global_rect().end.y+2.0,"last row reachable by scrolling %s"%size)
		panel.close_panel()
		expect(host._menu.visible and not panel._panel.visible,"back restores menu")
	host.queue_free()
	await process_frame
	print("NR_PANEL_LAYOUT ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"scope":"Headless native UI layout and unsupported-engine gating, not a screenshot or NVIDIA NR execution."}))
	quit(0 if failures.is_empty() else 1)
