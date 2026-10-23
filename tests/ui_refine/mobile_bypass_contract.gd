extends SceneTree
const Presentation = preload("res://scripts/ui/pool_interface_presentation.gd")
func _initialize() -> void:
	if "--mobile-preview" not in OS.get_cmdline_user_args(): quit(2); return
	var host := Node.new()
	root.add_child(host)
	var before := host.get_child_count()
	var bypassed := Presentation.install(host) == null and host.get_child_count() == before
	print("POOL_UI_MOBILE_BYPASS ", JSON.stringify({"passed":bypassed,"scope":"CPU-only PC-presentation bypass; no Android build, export or runtime change"}))
	host.free()
	quit(0 if bypassed else 1)
