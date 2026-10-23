extends SceneTree
## Bounded actual-Godot UI preview. No world, water simulation, imported art,
## user settings or background scenes. Presentation is tested over real controls.
const GRAPHICS = preload("res://scripts/rendering/desktop_quality_panel.gd")
class Host extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _save_settings(_mode: String = "", _seed: int = 0, _atomic: bool = false) -> Error: return OK

var output := "res://output/ui-refine/preview"
var stage := "before"
var errors: Array[String] = []
var records: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()
func _settle() -> void:
	for frame: int in 5: await process_frame
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for argument: String in args:
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--stage="): stage = argument.trim_prefix("--stage=")
	var layout_only := "--layout-only" in args
	if DisplayServer.get_name() == "headless" and not layout_only:
		push_error("Native display required for screenshot; use --layout-only for CPU geometry.")
		quit(2); return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	RenderingServer.set_default_clear_color(Color("101d24"))
	var host := Host.new()
	root.add_child(host)
	host.set_process(false)
	host.set_physics_process(false)
	host._setup_inputs()
	host._build_interface()
	host._destination.add_item("迎宾池 / ARRIVAL POOL")
	GRAPHICS.install(host, "user://preview-graphics.cfg")
	if stage == "after" and not host.has_node("PoolInterfacePresentation"):
		load("res://scripts/ui/pool_interface_presentation.gd").install(host)
	await _settle()
	var resolutions := [Vector2i(1280, 720), Vector2i(1920, 1080)] if stage == "after" else [Vector2i(1280, 720)]
	for resolution: Vector2i in resolutions:
		root.content_scale_size = resolution
		await _settle()
		for panel_name: String in (["menu", "water", "graphics"] if stage == "after" else ["menu", "water"]):
			host._menu.visible = panel_name == "menu"
			host._advanced.visible = panel_name == "water"
			var graphics := host.get_node("DesktopQuality")
			graphics._panel.visible = panel_name == "graphics"
			if stage == "after": host.get_node("PoolInterfacePresentation").refresh_layout()
			await _settle()
			var panel: Control = host._menu if panel_name == "menu" else (host._advanced if panel_name == "water" else graphics._panel)
			var record: Dictionary = {"panel":panel_name, "resolution":str(resolution), "panel_rect":str(panel.get_global_rect())}
			if not Rect2(Vector2.ZERO, Vector2(resolution)).encloses(panel.get_global_rect()): errors.append("Panel exceeds viewport: " + panel_name)
			if not layout_only:
				await RenderingServer.frame_post_draw
				var picture := root.get_texture().get_image()
				var bytes := picture.save_png_to_buffer()
				if bytes.is_empty() or bytes.size() > 1024 * 1024: errors.append("Image empty or > 1 MiB")
				var path := "%s/%s-%s-%dx%d.png" % [output, stage, panel_name, resolution.x, resolution.y]
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file: file.store_buffer(bytes); file.close()
				else: errors.append("Could not save " + path)
				record["image"] = path
				record["image_dimensions"] = [picture.get_width(), picture.get_height()]
				record["bytes"] = bytes.size()
			records.append(record)
	if is_instance_valid(host.world) or is_instance_valid(host.water): errors.append("Preview constructed world or water")
	var result := {"passed":errors.is_empty(), "errors":errors, "stage":stage, "layout_only":layout_only, "records":records, "scope":"Actual production Godot controls; UI only, no water, world or gameplay startup", "renderer":RenderingServer.get_current_rendering_method()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(result, "  ")); report.close()
	print("POOL_UI_PREVIEW ", JSON.stringify(result))
	host.free()
	quit(0 if errors.is_empty() else 1)
