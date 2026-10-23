class_name SourceVolumetricFog
extends CompositorEffect
## Source Tyndall raymarch, after source water/whitewater and before tonemapping.
## This is NOT Godot's generic froxel fog and is NOT the separate FogExp2 layer.
## Source: beyond-the-basin 66a4543 app/pool-vct/engine.ts:717-773, 953-971.
const SHADER_DIR := "res://shaders/source_fog/"
const SOURCE_STEPS := 20
const SOURCE_RANGE := 36.0
const SOURCE_SUN := Vector3(.274,-.913,.274)
const SOURCE_STRENGTH := .05
const SOURCE_DEPTH_BIAS := .0015
const SOURCE_VARIANTS := [3,5,6]
var available := false
var last_error := ""
var rendered_frames := 0
var level := 0.0
var source_time := 0.0
var source_target := 0.0
var source_light_height := 10.2
var source_origin := Vector3.ZERO
var forced := false # Explicit QA override, matching source shaftsForced.
var projection_sample := Vector4.ZERO
var _formal := false
var _native_authored := false
var _disposed := false
var _camera: WeakRef
var _vertex_code := ""
var _fragment_code := ""
# Render-thread-owned fields; frame() publishes immutable snapshots.
var _rd: RenderingDevice
var _shader := RID()
var _ubo := RID()
var _sampler := RID()
var _owned: Array[RID] = []
var _targets: Dictionary = {}
var _gpu_frame := PackedFloat32Array([0.0,10.2,0.0,0.0,0.0])
var _gpu_origin := Vector3.ZERO
var _gpu_allowed := true
var _mobile := RenderingServer.get_current_rendering_method()=="mobile"

func _init() -> void:
	effect_callback_type=CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color=true
	access_resolved_depth=not _mobile
	_vertex_code=FileAccess.get_file_as_string(SHADER_DIR+"fullscreen.vert")
	_fragment_code=FileAccess.get_file_as_string(SHADER_DIR+"tyndall.frag")
	RenderingServer.call_on_render_thread(_initialize_gpu)

## This does not replace the camera's existing liquid/whitewater compositor.
## Host must append this effect AFTER those effects, on the main camera only.
func configure(camera: Camera3D) -> void:
	_camera=weakref(camera)

## Source caps elapsed dt to .2 before BOTH time and transition integration.
## Native world rooms stay absolute, unlike source's rebase at every crossing.
## Localizing the camera and view matrix preserves drifting air and shaft axis.
func frame(delta: float, coord: Vector2i, layout: Dictionary) -> void:
	var dt:=clampf(delta,0.0,.2)
	source_time+=dt
	_formal=bool(layout.get("formal",false))
	_native_authored=_formal or bool(layout.get("expanded",false))
	var variant:=int(layout.get("variant",0))
	var corrupt:=int(layout.get("corrupt",0))
	source_origin=Vector3(float(coord.x)*32.0,0.0,float(coord.y)*32.0)
	source_target=1.0 if forced or (variant in SOURCE_VARIANTS and corrupt<2) else 0.0
	level+=(source_target-level)*minf(1.0,dt*1.4)
	# Variant 6 deliberately keeps the source's 10.2 m anchor, not its ceiling.
	source_light_height=(14.0 if variant==3 else 9.2)+1.0
	_publish_frame()

func _publish_frame() -> void:
	if _disposed:return
	var data:=PackedFloat32Array([0.0,source_light_height,0.0,SOURCE_STRENGTH*level,source_time])
	RenderingServer.call_on_render_thread(_set_frame_gpu.bind(data,source_origin,not _native_authored))

func _set_frame_gpu(data: PackedFloat32Array, origin: Vector3, allowed: bool) -> void:
	if _disposed:return
	_gpu_frame=data
	_gpu_origin=origin
	_gpu_allowed=allowed

func debug_stats() -> Dictionary:
	return {"available":available,"error":last_error,"rendered_frames":rendered_frames,
		"steps":SOURCE_STEPS,"range":SOURCE_RANGE,"level":level,"target":source_target,
		"intensity":SOURCE_STRENGTH*level,"time":source_time,"light_height":source_light_height,
		"origin":str(source_origin),"enabled":enabled and not _native_authored,"formal_bypass":_formal,"native_authored_bypass":_native_authored,
		"algorithm":"source 20-step depth-occluded Tyndall","renderer":RenderingServer.get_current_rendering_method()}

func _own(rid: RID) -> RID:
	if rid.is_valid():_owned.append(rid)
	return rid

func _initialize_gpu() -> void:
	if _disposed:return
	_rd=RenderingServer.get_rendering_device()
	if _rd==null:
		last_error="Source Tyndall needs a RenderingDevice context (Forward+ or Mobile); headless/Compatibility cannot execute it."
		return
	var source:=RDShaderSource.new()
	source.source_vertex="#version 450\n"+_vertex_code
	source.source_fragment="#version 450\n"+_fragment_code
	var spirv:=_rd.shader_compile_spirv_from_source(source)
	for stage in [RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:
		var error:=spirv.get_stage_compile_error(stage)
		if not error.is_empty():
			last_error="Source Tyndall shader: "+error
			push_error(last_error)
			return
	_shader=_own(_rd.shader_create_from_spirv(spirv,"Original source Tyndall raymarch"))
	_ubo=_own(_rd.uniform_buffer_create(288))
	var sampler:=RDSamplerState.new()
	sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.mip_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler=_own(_rd.sampler_create(sampler))
	available=_shader.is_valid() and _ubo.is_valid() and _sampler.is_valid()
	if not available:last_error="Source Tyndall GPU resource creation failed."

func _target(color: RID, view: int) -> Dictionary:
	var old:Dictionary=_targets.get(view,{})
	if not old.is_empty() and old.color==color and _rd.framebuffer_is_valid(old.framebuffer):return old
	if not old.is_empty():
		if _rd.render_pipeline_is_valid(old.pipeline):_rd.free_rid(old.pipeline)
		if _rd.framebuffer_is_valid(old.framebuffer):_rd.free_rid(old.framebuffer)
	var framebuffer:=_rd.framebuffer_create([color])
	var raster:=RDPipelineRasterizationState.new()
	raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
	var multisample:=RDPipelineMultisampleState.new()
	var depth:=RDPipelineDepthStencilState.new()
	var blend:=RDPipelineColorBlendState.new()
	var attachment:=RDPipelineColorBlendStateAttachment.new()
	attachment.enable_blend=true
	attachment.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	attachment.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	attachment.src_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ZERO
	attachment.dst_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	blend.attachments=[attachment]
	var pipeline:=_rd.render_pipeline_create(_shader,_rd.framebuffer_get_format(framebuffer),RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,multisample,depth,blend)
	var result:Dictionary={"color":color,"framebuffer":framebuffer,"pipeline":pipeline}
	_targets[view]=result
	return result

static func native_projection(projection: Projection) -> Projection:
	# RenderSceneData may expose the already-corrected native projection. Correct
	# raw OpenGL-style matrices ONCE, as required by both native renderer paths.
	return Projection.create_depth_correction(true)*projection if projection.z.z<0.0 else projection

static func hdr_encoding_scale(format: int) -> float:
	# Godot Mobile encodes linear 0..2 in its 10-bit UNORM attachment.
	# Float HDR (including Mobile HDR2D) is already linear 0..infinity.
	return .5 if format in [RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32,RenderingDevice.DATA_FORMAT_A2R10G10B10_UNORM_PACK32] else 1.0

func _projection_data(projection: Projection, camera: Transform3D, size: Vector2i, encoding_scale: float = 1.0) -> PackedByteArray:
	var values:=PackedFloat32Array()
	for matrix:Projection in [projection,projection.inverse(),Projection(camera.affine_inverse()),Projection(camera)]:
		for column in 4:
			for row in 4:values.append(matrix[column][row])
	values.append_array(PackedFloat32Array([_gpu_frame[0],_gpu_frame[1],_gpu_frame[2],_gpu_frame[3]]))
	values.append_array(PackedFloat32Array([size.x,size.y,_gpu_frame[4],encoding_scale]))
	return values.to_byte_array()

func _render_callback(_type: int, render_data: RenderData) -> void:
	if _disposed or not available or not _gpu_allowed:return
	# Source compiles once even at zero intensity, then suppresses negligible
	# room-transition tails. Pipeline creation itself is the native warm-up.
	if rendered_frames>0 and _gpu_frame[3]<=SOURCE_STRENGTH*.004:return
	var buffers:=render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene:=render_data.get_render_scene_data()
	if buffers==null or scene==null:return
	if _mobile and buffers.get_msaa_3d()!=RenderingServer.VIEWPORT_MSAA_DISABLED:
		last_error="Mobile source Tyndall requires main viewport MSAA disabled; native compositor depth resolve is unsupported. Use the Mobile post-AA setting."
		return
	var size:=buffers.get_internal_size()
	if size.x<1 or size.y<1:return
	for view in buffers.get_view_count():
		var projection:=native_projection(scene.get_view_projection(view))
		projection_sample=Vector4(projection.x.x,projection.y.y,projection.z.z,projection.w.z)
		var camera:=scene.get_cam_transform()
		camera.origin+=camera.basis*scene.get_view_eye_offset(view)
		camera.origin-=_gpu_origin
		var color:=buffers.get_color_layer(view)
		var bytes:=_projection_data(projection,camera,size,hdr_encoding_scale(_rd.texture_get_format(color).format))
		_rd.buffer_update(_ubo,0,bytes.size(),bytes)
		var opaque_depth:=buffers.get_depth_layer(view)
		if not color.is_valid() or not opaque_depth.is_valid():continue
		var target:=_target(color,view)
		if not target.pipeline.is_valid():
			last_error="Source Tyndall additive HDR pipeline creation failed."
			return
		var parameters:=RDUniform.new()
		parameters.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		parameters.binding=0
		parameters.add_id(_ubo)
		var depth:=RDUniform.new()
		depth.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth.binding=1
		depth.add_id(_sampler)
		depth.add_id(opaque_depth)
		var group:=_rd.uniform_set_create([parameters,depth],_shader,0)
		var draw:=_rd.draw_list_begin(target.framebuffer)
		_rd.draw_list_bind_render_pipeline(draw,target.pipeline)
		_rd.draw_list_bind_uniform_set(draw,group,0)
		_rd.draw_list_draw(draw,false,1,3)
		_rd.draw_list_end()
		_rd.free_rid(group)
	rendered_frames+=1

func dispose() -> void:
	_disposed=true
	RenderingServer.call_on_render_thread(_dispose_gpu)

func _dispose_gpu() -> void:
	if _rd!=null:
		for target:Dictionary in _targets.values():
			if _rd.render_pipeline_is_valid(target.pipeline):_rd.free_rid(target.pipeline)
			if _rd.framebuffer_is_valid(target.framebuffer):_rd.free_rid(target.framebuffer)
		for i in range(_owned.size()-1,-1,-1):_rd.free_rid(_owned[i])
	_targets.clear()
	_owned.clear()
	_shader=RID();_ubo=RID();_sampler=RID()
	available=false
	_rd=null
