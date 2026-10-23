extends RefCounted
## Explicit requirements for the ORIGINAL SWE + APIC-MPM + photon pipeline.
## This is a guard/report, never a replacement solver or a fake-water fallback.
signal completed(report: Dictionary)
var report: Dictionary = {"checked":false, "supported":false, "errors":[]}

func start() -> void:
	RenderingServer.call_on_render_thread(_inspect)

func _inspect() -> void:
	var result := {"checked":true, "supported":false, "renderer":RenderingServer.get_current_rendering_method(), "device":RenderingServer.get_video_adapter_name(), "errors":[], "limits":{}, "formats":{}}
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		result.errors.append("No RenderingDevice: original water requires Vulkan Mobile or Forward+, not Compatibility/OpenGL or headless.")
		_publish.call_deferred(result)
		return
	var limits := [
		["compute_invocations", RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_INVOCATIONS, 128],
		["compute_x", RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_SIZE_X, 128],
		["compute_y", RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_SIZE_Y, 8],
		["dispatch_x", RenderingDevice.LIMIT_MAX_COMPUTE_WORKGROUP_COUNT_X, 4000],
		["storage_buffers", RenderingDevice.LIMIT_MAX_STORAGE_BUFFERS_PER_SHADER_STAGE, 4],
		["storage_images", RenderingDevice.LIMIT_MAX_STORAGE_IMAGES_PER_SHADER_STAGE, 4],
		["texture_size", RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D, 2048],
	]
	for item in limits:
		var actual := rd.limit_get(item[1])
		result.limits[item[0]] = actual
		if actual < item[2]: result.errors.append("%s requires %d, device provides %d." % [item[0], item[2], actual])
	var sampled := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var storage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var color := RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	var copy := RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var formats := [
		["RGBA16F storage/sampling/copy", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, sampled | storage | copy],
		["R32F storage/sampling/copy", RenderingDevice.DATA_FORMAT_R32_SFLOAT, sampled | storage | copy],
		["RGBA16F color/sampling/copy", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, sampled | color | copy],
		["RGBA32F color/sampling/copy", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, sampled | color | copy],
		["D32F depth attachment", RenderingDevice.DATA_FORMAT_D32_SFLOAT, RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT],
	]
	for item in formats:
		var supported := rd.texture_is_format_supported_for_usage(item[1], item[2])
		result.formats[item[0]] = supported
		if not supported: result.errors.append("Unsupported required texture format: " + item[0])
	# Shader compilation, 32-bit integer storage-buffer atomics, floating-point
	# blending, MSAA and async transfers must also succeed in the source pipeline.
	# Format support alone is NOT an Android device performance certification.
	result.supported = result.errors.is_empty()
	_publish.call_deferred(result)

func _publish(result: Dictionary) -> void:
	report = result
	completed.emit(report)

static func source_errors(stats: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["last_error", "error", "liquid_error", "caustic_error"]:
		var reason := str(stats.get(key, ""))
		if not reason.is_empty() and reason not in errors: errors.append(reason)
	var probe: Dictionary = stats.get("probe", {})
	var probe_error := str(probe.get("last_error", ""))
	if not probe_error.is_empty() and probe_error not in errors: errors.append(probe_error)
	var liquid: Dictionary = stats.get("liquid", {})
	var mpm_error := str(liquid.get("error", ""))
	if not mpm_error.is_empty() and mpm_error not in errors: errors.append(mpm_error)
	if liquid.get("backend", "") == "unavailable" and mpm_error.is_empty():
		errors.append("Original APIC-MPM backend unavailable.")
	return errors
