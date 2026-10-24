extends RefCounted
## Optional explicit desktop restart. Never called automatically at startup.
## Godot discards engine flags from OS.get_cmdline_args(): use the launcher's
## exact argv contract or refuse, rather than guess a renderer, GPU, pack or path.
const CONTRACT_ENV := "POOLCORE_RESTART_LAUNCH_V1"
const WORLD_FLAGS := ["--formal-hall", "--expanded-world", "--poolrooms-wing", "--legacy-world", "--original-world"]
const MODES := ["original", "formal", "expanded", "poolrooms"]
const UNSUPPORTED := ["--editor", "-e", "--project-manager", "-p", "--script", "-s", "--path", "--main-pack", "--scene", "--remote-debug", "--editor-pid", "--wid", "--check-only", "--quit", "--quit-after", "--headless", "--write-movie", "--test", "--import"]
var _requested := false

static func failure(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason}

static func _path_equal(a: String, b: String, platform: String) -> bool:
	a = a.replace("\\", "/").simplify_path()
	b = b.replace("\\", "/").simplify_path()
	return a.to_lower() == b.to_lower() if platform == "Windows" else a == b

static func _without_world_flags(args: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for argument: String in args:
		if argument not in WORLD_FLAGS: result.append(argument)
	return result

static func build_plan(contract: Dictionary, executable: String, user_args: PackedStringArray, platform: String, rendering_method: String, rendering_driver: String) -> Dictionary:
	if platform not in ["Windows", "Linux", "macOS"]:
		return failure("仅支持桌面版 / Desktop only.")
	if contract.get("version") != 1 or not contract.get("args") is Array:
		return failure("缺少完整启动参数 / Missing exact launcher arguments.")
	if not contract.get("executable") is String or not contract.get("pack") is String:
		return failure("启动信息无效 / Invalid launch identity.")
	var launched_executable: String = contract.executable
	var pack: String = contract.pack
	if not launched_executable.is_absolute_path() or not pack.is_absolute_path() or not _path_equal(launched_executable, executable, platform):
		return failure("启动程序不匹配 / Executable identity differs.")
	if not _path_equal(pack, executable.get_basename() + ".pck", platform):
		return failure("仅支持同名相邻 PCK / Matching adjacent PCK required.")
	var args := PackedStringArray()
	for value: Variant in contract.args:
		if not value is String or value.length() > 32767:
			return failure("启动参数无效 / Invalid launch argument.")
		args.append(value)
	if args.size() > 256:
		return failure("启动参数过多 / Too many launch arguments.")
	var separator := args.find("--")
	var plus_separator := args.find("++")
	if plus_separator != -1 and (separator == -1 or plus_separator < separator): separator = plus_separator
	var engine_args := args.slice(0, separator) if separator != -1 else args.duplicate()
	var original_users := args.slice(separator + 1) if separator != -1 else PackedStringArray()
	for argument: String in engine_args:
		var flag := argument.split("=", true, 1)[0]
		if flag in UNSUPPORTED or flag.begins_with("--export") or flag.begins_with("--dump") or argument.ends_with(".tscn") or argument.ends_with(".scn"):
			return failure("自定义场景/编辑器/测试启动不支持重启 / Exit fully; relaunch with supplied CMD, not custom scene/editor/test arguments.")
	for argument: String in original_users:
		if argument == "--qa" or argument.begins_with("--qa-") or argument in ["--pc-mainhall-lightmap-preview", "--mobile-preview"]:
			return failure("预览/测试模式不支持重启 / Preview or QA mode is unsupported.")
	if _without_world_flags(original_users) != _without_world_flags(user_args):
		return failure("当前参数与启动器不一致 / Current user arguments differ from launcher.")
	# Optional explicit flags must agree with the actual running renderer/driver.
	# Other engine flags, including GPU index and memory options, remain untouched.
	for pair: Array in [["--rendering-method", rendering_method], ["--rendering-driver", rendering_driver]]:
		var index := engine_args.find(pair[0])
		if index != -1 and (index + 1 >= engine_args.size() or engine_args[index + 1] != pair[1]):
			return failure("渲染器与启动参数不一致 / Active renderer differs from launch arguments.")
	var restart_args := engine_args.duplicate()
	# Pin an omitted renderer/driver to the verifiable effective running choice.
	# Never infer Vulkan from the engine version or replace an explicit option.
	if "--rendering-method" not in engine_args:
		restart_args.append_array(PackedStringArray(["--rendering-method", rendering_method]))
	if "--rendering-driver" not in engine_args:
		restart_args.append_array(PackedStringArray(["--rendering-driver", rendering_driver]))
	if separator != -1:
		restart_args.append(args[separator])
		restart_args.append_array(_without_world_flags(original_users))
	return {"ok":true, "args":restart_args, "executable":executable, "pack":pack}

func plan() -> Dictionary:
	if Engine.is_editor_hint() or Engine.is_embedded_in_editor() or EngineDebugger.is_active():
		return failure("请完全退出后通过启动器打开 / Exit fully and use the launcher, not the editor/debugger.")
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web"):
		return failure("仅支持桌面版 / Desktop only.")
	var serialized := OS.get_environment(CONTRACT_ENV)
	if serialized.is_empty() or serialized.length() > 65536:
		return failure("请完全退出后用随包 CMD 启动器打开 / Exit fully and use the supplied CMD launcher.")
	var parsed: Variant = JSON.parse_string(serialized)
	if not parsed is Dictionary: return failure("启动信息损坏 / Invalid launcher contract.")
	var result := build_plan(parsed, OS.get_executable_path(), OS.get_cmdline_user_args(), OS.get_name(), RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name())
	if not result.ok: return result
	if not FileAccess.file_exists(result.executable) or not FileAccess.file_exists(result.pack):
		return failure("启动文件已移动 / Executable or matching PCK is missing.")
	for argument: String in OS.get_cmdline_args():
		if argument.split("=", true, 1)[0] in UNSUPPORTED:
			return failure("当前启动方式不支持重启 / Current invocation is unsupported.")
	return result

func request(mode: String, seed_value: int, busy: bool, save_selection: Callable, orderly_quit: Callable) -> Dictionary:
	if _requested or busy or OS.is_restart_on_exit_set():
		return failure("正在切换或退出，请稍候 / A transition or shutdown is already in progress.")
	if mode not in MODES or not save_selection.is_valid() or not orderly_quit.is_valid():
		return failure("出生地或回调无效 / Invalid selection or callback.")
	var restart := plan()
	if not restart.ok: return restart
	_requested = true # Claim before save callbacks, including possible reentrant UI calls.
	var saved: Variant = save_selection.call(mode, seed_value)
	if not saved is int or saved != OK:
		_requested = false
		return failure("设置保存失败，未退出 / Settings save failed; game remains open.")
	OS.set_restart_on_exit(true, restart.args)
	if not OS.is_restart_on_exit_set() or OS.get_restart_on_exit_arguments() != restart.args:
		OS.set_restart_on_exit(false)
		_requested = false
		return failure("未能请求重启，请手动重新打开 / Restart could not be armed; reopen manually.")
	orderly_quit.call_deferred()
	return {"ok":true, "reason":"已保存，正在完全退出并重新打开 / Saved; exiting fully and reopening."}

static func save_config_atomic(config: ConfigFile, path: String) -> Error:
	# Same-directory replacement preserves the old file on pre-commit failure.
	# No cross-volume move, settings reset, or automatic restart on next startup.
	var temporary := path + ".restart-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec()) + ".tmp"
	var saved := config.save(temporary)
	if saved != OK: return saved
	var check := ConfigFile.new()
	saved = check.load(temporary)
	if saved == OK and check.encode_to_text() != config.encode_to_text(): saved = ERR_FILE_CORRUPT
	if saved == OK:
		saved = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if saved != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return saved
