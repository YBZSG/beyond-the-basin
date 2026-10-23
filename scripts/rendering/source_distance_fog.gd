class_name SourceDistanceFog
extends CompositorEffect
## Exact source FogExp2 equation on opaque HDR, before screen copy/refraction.
## SSR/SSS separate-specular merge MUST be disabled for this camera. Otherwise
## POST_SKY is too early to fog the final merged material color correctly.
## Source Tyndall is a SEPARATE post-transparent effect.
const Fog=preload("res://scripts/rendering/source_volumetric_fog.gd")
const SOURCE_DENSITIES: Array[float]=[.036,.043,.053,.066]
const SOURCE_COLOR:=Color("22343d")
var density:=.036
var available:=false
var last_error:=""
var rendered_frames:=0
var rendered_msaa_frames:=0
var _formal:=false
var _native_authored:=false
var _disposed:=false
var _rd:RenderingDevice
var _codes:Dictionary={}
var _shaders:Dictionary={}
var _owned:Array[RID]=[]
var _targets:Dictionary={}
var _ubo:=RID()
var _sampler:=RID()
var _gpu_density:=.036
var _gpu_enabled:=true
var _separate_specular_disabled:=false

func _init()->void:
	effect_callback_type=CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT if RenderingServer.get_current_rendering_method()=="mobile" else CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY
	access_resolved_color=true
	access_resolved_depth=false # We sample the actual opaque MSAA depth directly.
	_codes.vertex=FileAccess.get_file_as_string("res://shaders/source_fog/fullscreen.vert")
	_codes.fragment=FileAccess.get_file_as_string("res://shaders/source_fog/distance.frag")
	RenderingServer.call_on_render_thread(_initialize_gpu)

## Host explicitly promises no native SSR/SSS on this camera, including captures.
## This guard avoids silently drawing at the wrong point of the native graph.
func configure(separate_specular_disabled:bool)->void:
	_separate_specular_disabled=separate_specular_disabled
	_publish()

func frame(delta:float,_coord:Vector2i,layout:Dictionary)->void:
	_formal=bool(layout.get("formal",false))
	_native_authored=_formal or bool(layout.get("expanded",false))
	var corrupt:=clampi(int(layout.get("corrupt",0)),0,3)
	var dt:=clampf(delta,0.0,.2)
	density+=(SOURCE_DENSITIES[corrupt]-density)*minf(1.0,dt*.6)
	_publish()

## Capture adapters copy the main-camera mood; they must not integrate it twice.
func set_density(value:float,formal:bool=false)->void:
	density=maxf(0.0,value)
	_formal=formal
	_native_authored=formal
	_publish()

func _publish()->void:
	if _disposed:return
	RenderingServer.call_on_render_thread(_set_frame_gpu.bind(density,not _native_authored and _separate_specular_disabled))
func _set_frame_gpu(value:float,allowed:bool)->void:
	_gpu_density=value
	_gpu_enabled=allowed

func debug_stats()->Dictionary:
	return {"available":available,"error":last_error,"density":density,"rendered_frames":rendered_frames,"rendered_msaa_frames":rendered_msaa_frames,"formal_bypass":_formal,"native_authored_bypass":_native_authored,"graph_compatible":_separate_specular_disabled,"algorithm":"source FogExp2 squared view-depth","enabled":enabled and not _native_authored and _separate_specular_disabled}
func _own(rid:RID)->RID:
	if rid.is_valid():_owned.append(rid)
	return rid
func _initialize_gpu()->void:
	if _disposed:return
	_rd=RenderingServer.get_rendering_device()
	if _rd==null:
		last_error="Source FogExp2 needs a RenderingDevice context (Forward+ or Mobile); headless/Compatibility cannot execute it."
		return
	for msaa in [false,true]:
		var source:=RDShaderSource.new()
		source.source_vertex="#version 450\n"+str(_codes.vertex)
		source.source_fragment="#version 450\n"+("#define SOURCE_FOG_MSAA\n" if msaa else "")+str(_codes.fragment)
		var spirv:=_rd.shader_compile_spirv_from_source(source)
		for stage in [RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:
			var error:=spirv.get_stage_compile_error(stage)
			if not error.is_empty():
				last_error="Source FogExp2 shader: "+error
				push_error(last_error);return
		_shaders[msaa]=_own(_rd.shader_create_from_spirv(spirv,"Source opaque FogExp2 "+str(msaa)))
	_ubo=_own(_rd.uniform_buffer_create(96))
	var sampler:=RDSamplerState.new()
	sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler=_own(_rd.sampler_create(sampler))
	available=_shaders.size()==2 and _ubo.is_valid() and _sampler.is_valid()

func _target(color:RID,view:int,samples:int)->Dictionary:
	var old:Dictionary=_targets.get(view,{})
	if not old.is_empty() and old.color==color and _rd.framebuffer_is_valid(old.framebuffer):return old
	if not old.is_empty():
		if _rd.render_pipeline_is_valid(old.pipeline):_rd.free_rid(old.pipeline)
		if _rd.framebuffer_is_valid(old.framebuffer):_rd.free_rid(old.framebuffer)
	var framebuffer:=_rd.framebuffer_create([color])
	var raster:=RDPipelineRasterizationState.new();raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
	var multisample:=RDPipelineMultisampleState.new();multisample.sample_count=samples
	var msaa:=samples!=RenderingDevice.TEXTURE_SAMPLES_1
	multisample.enable_sample_shading=msaa;multisample.min_sample_shading=1.0 if msaa else 0.0
	var blend:=RDPipelineColorBlendState.new()
	var attachment:=RDPipelineColorBlendStateAttachment.new()
	attachment.enable_blend=true
	attachment.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	attachment.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	attachment.src_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ZERO
	attachment.dst_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	blend.attachments=[attachment]
	var pipeline:=_rd.render_pipeline_create(_shaders[msaa],_rd.framebuffer_get_format(framebuffer),RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,multisample,RDPipelineDepthStencilState.new(),blend)
	var result:Dictionary={"color":color,"framebuffer":framebuffer,"pipeline":pipeline}
	_targets[view]=result
	return result

func _render_callback(_type:int,render_data:RenderData)->void:
	if _disposed or not available or not _gpu_enabled:return
	var buffers:=render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene:=render_data.get_render_scene_data()
	if buffers==null or scene==null:return
	var size:=buffers.get_internal_size()
	if size.x<1 or size.y<1:return
	var msaa:=buffers.get_msaa_3d()!=RenderingServer.VIEWPORT_MSAA_DISABLED
	var samples:=buffers.get_texture_samples() if msaa else RenderingDevice.TEXTURE_SAMPLES_1
	var fog_color:=SOURCE_COLOR.srgb_to_linear()
	for view in buffers.get_view_count():
		var color:=buffers.get_color_layer(view,msaa)
		var encoding_scale:=Fog.hdr_encoding_scale(_rd.texture_get_format(color).format)
		var inverse:=Fog.native_projection(scene.get_view_projection(view)).inverse()
		var values:=PackedFloat32Array()
		for column in 4:
			for row in 4:values.append(inverse[column][row])
		values.append_array(PackedFloat32Array([fog_color.r*encoding_scale,fog_color.g*encoding_scale,fog_color.b*encoding_scale,_gpu_density,size.x,size.y,0,0]))
		var bytes:=values.to_byte_array();_rd.buffer_update(_ubo,0,bytes.size(),bytes)
		var opaque_depth:=buffers.get_depth_layer(view,msaa)
		if not color.is_valid() or not opaque_depth.is_valid():
			last_error="Source FogExp2 opaque color/depth attachments unavailable; no fallback approximation applied."
			return
		var target:=_target(color,view,samples)
		if not target.pipeline.is_valid():
			last_error="Source FogExp2 per-sample HDR blend pipeline unsupported; no fallback approximation applied."
			return
		var parameters:=RDUniform.new();parameters.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;parameters.binding=0;parameters.add_id(_ubo)
		var depth:=RDUniform.new();depth.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;depth.binding=1;depth.add_id(_sampler);depth.add_id(opaque_depth)
		var group:=_rd.uniform_set_create([parameters,depth],_shaders[msaa],0)
		var draw:=_rd.draw_list_begin(target.framebuffer)
		_rd.draw_list_bind_render_pipeline(draw,target.pipeline);_rd.draw_list_bind_uniform_set(draw,group,0);_rd.draw_list_draw(draw,false,1,3);_rd.draw_list_end();_rd.free_rid(group)
		# The next screen copy and eventual transparent resolve both see the SAME
		# fogged samples. Merely editing resolved color would be overwritten.
		if msaa:_rd.texture_resolve_multisample(color,buffers.get_color_layer(view))
	rendered_frames+=1
	if msaa:rendered_msaa_frames+=1
func dispose()->void:
	_disposed=true
	RenderingServer.call_on_render_thread(_dispose_gpu)
func _dispose_gpu()->void:
	if _rd!=null:
		for target:Dictionary in _targets.values():
			if _rd.render_pipeline_is_valid(target.pipeline):_rd.free_rid(target.pipeline)
			if _rd.framebuffer_is_valid(target.framebuffer):_rd.free_rid(target.framebuffer)
		for i in range(_owned.size()-1,-1,-1):_rd.free_rid(_owned[i])
	_targets.clear();_owned.clear();_shaders.clear()
	available=false;_rd=null
