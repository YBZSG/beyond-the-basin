class_name SourceLiquidSurface
extends CompositorEffect
## Original LiquidSurfacePass + WhitewaterPass render graph, implemented on the
## GLOBAL RD after transparent base water and before native post processing.
## Surface optics retain original math. Room Cubemap prefilter is the documented
## native replacement for Three PMREM CubeUV. No billboard fluid substitute.
const Liquid := preload("res://scripts/water/source_port/source_liquid_mpm.gd")
const DIR := "res://shaders/source_water/"
var last_error := ""
var available := false
var color_texture := Texture2DRD.new()
var rendered_frames := 0
var scene_target_rebuilds := 0
# Engine-owned descriptor cache is invalidated by dependency lifetime, not time.
# Keep direct allocation for exact native A/B fixtures; neither path changes draws.
var reuse_uniform_sets := not OS.get_cmdline_user_args().has("--no-water-descriptor-cache")
var descriptor_requests := 0
var descriptor_cache_requests := 0
var descriptor_transient_allocations := 0
var render_encode_ms := 0.0
var render_encode_max_ms := 0.0
# Exact command reductions only; keep independent A/B switches for native QA.
var cull_offscreen_liquid := not OS.get_cmdline_user_args().has("--no-liquid-offscreen-cull")
var reuse_filter_clears := not OS.get_cmdline_user_args().has("--repeat-liquid-filter-clears")
var last_draw_calls := 0
var last_filter_clears := 0
var last_instance_upload_bytes := 0
var last_culled_liquid_views := 0
var total_culled_liquid_views := 0
var _gpu_timestamps: RefCounted
var projection_sample := Vector4.ZERO
var _domain_origin := Vector3.ZERO
var _disposed := false
var _surface: Texture2DRD
var _depth: Texture2DRD
var _detail: Texture2DRD
var _environment: Texture
var _environment_mips := 0.0
var _codes: Dictionary = {}
var _dfg_bytes := PackedByteArray()
# Render-thread state only.
var _rd: RenderingDevice
var _owned: Array[RID] = []
var _targets_owned: Array[RID] = []
var _programs: Dictionary = {}
var _pipes: Dictionary = {}
var _size := Vector2i.ZERO
var _ubo := RID()
var _lights := RID()
var _linear := RID()
var _nearest := RID()
var _dummy_cube := RID()
var _dfg := RID()
var _shadow_nodes := RID()
var _shadow_triangles := RID()
var _shadow_node_size:=0
var _shadow_triangle_size:=0
var shadow_buffer_allocations:=0
var shadow_buffer_reuses:=0
var shadow_ready := false
var _geometry: Dictionary = {}
var _instance_buffers: Dictionary = {}
var _depth_target: Dictionary = {}
var _filters: Array[Dictionary] = []
var _composite: Dictionary = {}
var _whitewater: Dictionary = {}
var _whitewater_resolved := RID()
var _scene_fb := RID()
var _scene_color := RID()
var _final_copy_pipeline := RID()
var _rows := PackedFloat32Array()
var _drop_rows := PackedFloat32Array()
var _bounds := AABB()
var _wave := PackedFloat32Array([.125,.0625,0,1,1,1,.65,1,1,1,1,.6,0,0,0,0])
var _light_data := PackedFloat32Array()

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	for name in ["liquid_uniforms.glslinc","shared_waves.glslinc","liquid_fullscreen.vert","liquid_depth.vert","liquid_depth.frag","liquid_filter.frag","liquid_composite.frag","liquid_copy.frag","whitewater_color_depth.frag","whitewater_drop.vert","whitewater_drop.frag","whitewater_shadow_bvh.glslinc"]:
		_codes[name] = FileAccess.get_file_as_string(DIR + name)
	_dfg_bytes = FileAccess.get_file_as_bytes(DIR + "whitewater_dfg.rg16f")
	_light_data.resize(248)
	_light_data.fill(0.0)
	if OS.get_cmdline_user_args().has("--source-gpu-timings"):
		_gpu_timestamps = preload("res://scripts/water/source_port/source_gpu_timestamps.gd").new("liquid_surface", PackedStringArray(["begin", "depth", "filters", "composite", "whitewater", "copy", "end"]))
		_gpu_timestamps.start()
	RenderingServer.call_on_render_thread(_initialize_gpu)

func configure(surface: Texture2DRD, depth: Texture2DRD, detail: Texture2DRD) -> void:
	_surface = surface
	_depth = depth
	_detail = detail

func configure_environment(cubemap: Texture, max_mip: float = -1.0) -> void:
	_environment = cubemap
	_environment_mips = max_mip if max_mip >= 0.0 else 0.0
	if (cubemap is Cubemap or cubemap is TextureCubemapRD) and max_mip < 0.0:
		_environment_mips = floor(log(float(maxi(1,cubemap.get_width()))) / log(2.0))

## Original capacity: 27 lights, including the 4 shadow-casting slots.
## Accept actual active scene lights. Dictionary: position or direction,
## color linear Color/Vector3, intensity, range (0=infinite), decay (default2).
## This is an explicit adapter, never invented lights. Native shadow atlases
## are not exposed to this RD pass; see SOURCE_LIQUID_PORT.md.
func set_lights(lights: Array) -> void:
	var data := PackedFloat32Array()
	data.resize(248)
	data.fill(0.0)
	data[0] = mini(27,lights.size())
	for i in mini(27,lights.size()):
		var light: Dictionary = lights[i]
		var position: Vector3 = light.get("direction",light.get("position",Vector3.ZERO))
		var color: Variant = light.get("color",Color.WHITE)
		var intensity := float(light.get("intensity",1.0))
		for axis in 3:
			data[4+i*4+axis] = position[axis]
			data[112+i*4+axis] = float(color[axis])*intensity
		data[4+i*4+3] = -1.0 if light.has("direction") else float(light.get("range",0.0))
		data[112+i*4+3] = float(light.get("decay",2.0))
		data[220+i] = 1.0 if bool(light.get("casts_shadow",i<4)) else 0.0
	RenderingServer.call_on_render_thread(_set_lights_gpu.bind(data))

## Same packed 48-byte nodes/triangles returned by SourceCaustics.build_triangle_bvh.
## Caller supplies actual local opaque geometry and refreshes moving casters.
func configure_shadow_bvh(bvh: Dictionary) -> void:
	if not bvh.has("nodes") or not bvh.has("triangles"):
		return
	RenderingServer.call_on_render_thread(_set_shadow_gpu.bind(bvh.nodes,bvh.triangles))

func _set_shadow_gpu(nodes: PackedByteArray, triangles: PackedByteArray) -> void:
	if _rd==null or nodes.size()<48 or triangles.size()<48:
		return
	if _shadow_node_size==nodes.size() and _shadow_triangle_size==triangles.size() and _shadow_nodes.is_valid() and _shadow_triangles.is_valid():
		_rd.buffer_update(_shadow_nodes,0,nodes.size(),nodes)
		_rd.buffer_update(_shadow_triangles,0,triangles.size(),triangles)
		shadow_buffer_reuses+=1
	else:
		for rid in [_shadow_nodes,_shadow_triangles]:
			if rid.is_valid():
				_owned.erase(rid)
				_rd.free_rid(rid)
		_shadow_nodes=_own(_rd.storage_buffer_create(nodes.size(),nodes))
		_shadow_triangles=_own(_rd.storage_buffer_create(triangles.size(),triangles))
		_shadow_node_size=nodes.size();_shadow_triangle_size=triangles.size()
		shadow_buffer_allocations+=2
	shadow_ready=true
	_light_data[2]=1.0
	_rd.buffer_update(_lights,0,992,_light_data.to_byte_array())

func _set_lights_gpu(data: PackedFloat32Array) -> void:
	data[2] = 1.0 if shadow_ready else 0.0
	_light_data = data
	if _rd != null and _lights.is_valid():
		_rd.buffer_update(_lights,0,data.size()*4,data.to_byte_array())

## Call after liquid.frame and whitewater.frame. Hosts publish NEW row arrays
## each frame, so queued callbacks hold immutable snapshots. PackedArrays are
## reference-shared in GDScript; mutating a published array would be a race.
func frame(liquid: RefCounted, particles: RefCounted, parameters: Dictionary = {}) -> void:
	var wave := PackedFloat32Array([
		float(parameters.get("poolCell",.125)),float(parameters.get("detailCell",.0625)),float(parameters.get("poolTime",0.0)),float(parameters.get("waveHeight",1.0)),
		float(parameters.get("rippleGain",1.0)),float(parameters.get("normalBoost",1.0)),float(parameters.get("microStrength",.65)),float(parameters.get("simulationOn",1.0)),
		float(parameters.get("ripplesOn",1.0)),float(parameters.get("microOn",1.0)),float(parameters.get("causticsScale",1.0)),float(parameters.get("causticsSpeed",.6)),0,0,0,0])
	var origin: Vector2 = parameters.get("microOrigin",Vector2.ZERO)
	wave[12]=origin.x
	wave[13]=origin.y
	var domain_origin: Variant = parameters.get("domainOrigin",Vector3.ZERO)
	var offset: Vector3 = Vector3(domain_origin.x,0.0,domain_origin.y) if domain_origin is Vector2 else domain_origin
	RenderingServer.call_on_render_thread(_set_frame_gpu.bind(liquid.instance_rows,liquid.bounds,particles.drop_rows,wave,offset))

func _set_frame_gpu(rows: PackedFloat32Array, box: AABB, drops: PackedFloat32Array, wave: PackedFloat32Array, domain_origin: Vector3) -> void:
	if _disposed:
		return
	_rows=rows
	_drop_rows=drops
	_bounds=box
	_wave=wave
	_domain_origin=domain_origin

func _own(rid: RID, target: bool = false) -> RID:
	if rid.is_valid():
		if target:
			_targets_owned.append(rid)
		else:
			_owned.append(rid)
	return rid

func _compile(name: String, vertex: String, fragment: String, uniforms: bool = true) -> void:
	var common := str(_codes["liquid_uniforms.glslinc"]) if uniforms else ""
	var source := RDShaderSource.new()
	source.source_vertex="#version 450\n"+common+vertex
	source.source_fragment="#version 450\n"+common+fragment.replace("__SHARED_WAVES__",str(_codes["shared_waves.glslinc"])).replace("__DIRECT_SHADOW_BVH__",str(_codes["whitewater_shadow_bvh.glslinc"]))
	var spirv := _rd.shader_compile_spirv_from_source(source)
	for stage in [RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:
		var error := spirv.get_stage_compile_error(stage)
		if not error.is_empty():
			last_error=name+": "+error
			push_error(last_error)
			return
	_programs[name]=_own(_rd.shader_create_from_spirv(spirv,"Source water "+name))

func _initialize_gpu() -> void:
	_rd=RenderingServer.get_rendering_device()
	if _rd==null or _disposed:
		last_error="RenderingDevice unavailable; source liquid renderer needs Forward+/Mobile with a graphics context."
		return
	var sample := RDSamplerState.new()
	sample.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sample.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sample.mip_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sample.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sample.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sample.repeat_w=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sample.max_lod=32.0
	_linear=_own(_rd.sampler_create(sample))
	sample.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sample.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sample.mip_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest=_own(_rd.sampler_create(sample))
	_ubo=_own(_rd.uniform_buffer_create(352))
	_lights=_own(_rd.uniform_buffer_create(992,_light_data.to_byte_array()))
	var blank := PackedByteArray()
	blank.resize(8)
	blank.fill(0)
	var format := RDTextureFormat.new()
	format.texture_type=RenderingDevice.TEXTURE_TYPE_CUBE
	format.array_layers=6
	format.width=1
	format.height=1
	format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_dummy_cube=_own(_rd.texture_create(format,RDTextureView.new(),[blank,blank,blank,blank,blank,blank]))
	format=RDTextureFormat.new()
	format.width=16
	format.height=16
	format.format=RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_dfg=_own(_rd.texture_create(format,RDTextureView.new(),[_dfg_bytes]))
	var full := str(_codes["liquid_fullscreen.vert"])
	_compile("depth",str(_codes["liquid_depth.vert"]),str(_codes["liquid_depth.frag"]))
	_compile("filter",full,str(_codes["liquid_filter.frag"]))
	_compile("composite",full,str(_codes["liquid_composite.frag"]))
	_compile("copy",full,str(_codes["liquid_copy.frag"]),false)
	_compile("color_depth",full,str(_codes["whitewater_color_depth.frag"]),false)
	_compile("drop",str(_codes["whitewater_drop.vert"]),str(_codes["whitewater_drop.frag"]))
	var empty := PackedByteArray()
	empty.resize(48)
	empty.fill(0)
	empty.encode_s32(32,-1)
	empty.encode_s32(36,-1)
	_shadow_nodes=_own(_rd.storage_buffer_create(48,empty))
	_shadow_triangles=_own(_rd.storage_buffer_create(48,empty))
	_geometry["liquid"]=_sphere(10,8)
	_geometry["drop"]=_sphere(12,8)
	_instance_buffers["liquid"]=_own(_rd.storage_buffer_create(18000*3*48))
	_instance_buffers["drop"]=_own(_rd.storage_buffer_create(1024*48))
	available=_programs.size()==6

func _sphere(width: int, height: int) -> Dictionary:
	var mesh := Liquid.sphere_geometry(width,height)
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vertices := PackedFloat32Array()
	vertices.resize(positions.size()*4)
	for i in positions.size():
		vertices[i*4]=positions[i].x
		vertices[i*4+1]=positions[i].y
		vertices[i*4+2]=positions[i].z
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertex_buffer := _own(_rd.storage_buffer_create(vertices.size()*4,vertices.to_byte_array()))
	var index_buffer := _own(_rd.index_buffer_create(indices.size(),RenderingDevice.INDEX_BUFFER_FORMAT_UINT32,indices.to_byte_array()))
	var index_array := _own(_rd.index_array_create(index_buffer,0,indices.size()))
	return {"vertices":vertex_buffer,"indices":index_array}

func _resource_failure(detail: String) -> void:
	available=false
	last_error="Source liquid GPU resource failure: "+detail
	push_error(last_error)

func _target(format_id: int, depth: bool = false, samples: int = RenderingDevice.TEXTURE_SAMPLES_1) -> Dictionary:
	var f := RDTextureFormat.new()
	f.width=_size.x
	f.height=_size.y
	f.format=format_id
	f.samples=samples
	f.usage_bits=RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var color := _own(_rd.texture_create(f,RDTextureView.new()),true)
	if not color.is_valid():
		_resource_failure("color format %s / samples %s" % [format_id,samples])
		return {"texture":RID(),"framebuffer":RID()}
	var attachments: Array[RID] = [color]
	if depth:
		f=RDTextureFormat.new()
		f.width=_size.x
		f.height=_size.y
		f.samples=samples
		f.format=RenderingDevice.DATA_FORMAT_D32_SFLOAT
		f.usage_bits=RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
		var depth_rid:=_own(_rd.texture_create(f,RDTextureView.new()),true)
		if not depth_rid.is_valid():
			_resource_failure("depth attachment / samples %s" % samples)
			return {"texture":color,"framebuffer":RID()}
		attachments.append(depth_rid)
	var framebuffer:=_own(_rd.framebuffer_create(attachments),true)
	if not framebuffer.is_valid():_resource_failure("framebuffer format %s / samples %s" % [format_id,samples])
	return {"texture":color,"framebuffer":framebuffer}

func _pipeline(name: String, framebuffer: RID, depth_test: bool = false, always_depth: bool = false, samples: int = RenderingDevice.TEXTURE_SAMPLES_1, alpha: bool = false) -> RID:
	if not framebuffer.is_valid() or not _rd.framebuffer_is_valid(framebuffer):
		_resource_failure("invalid framebuffer for "+name)
		return RID()
	var raster := RDPipelineRasterizationState.new()
	raster.cull_mode=RenderingDevice.POLYGON_CULL_BACK if name=="depth" or name=="drop" else RenderingDevice.POLYGON_CULL_DISABLED
	raster.front_face=RenderingDevice.POLYGON_FRONT_FACE_COUNTER_CLOCKWISE
	var depth := RDPipelineDepthStencilState.new()
	depth.enable_depth_test=depth_test
	depth.enable_depth_write=depth_test
	depth.depth_compare_operator=RenderingDevice.COMPARE_OP_ALWAYS if always_depth else RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL
	var multisample := RDPipelineMultisampleState.new()
	multisample.sample_count=samples
	var blend := RDPipelineColorBlendState.new()
	var attachment := RDPipelineColorBlendStateAttachment.new()
	if alpha:
		attachment.enable_blend=true
		attachment.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_SRC_ALPHA
		attachment.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		attachment.src_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	blend.attachments=[attachment]
	var pipeline:=_own(_rd.render_pipeline_create(_programs[name],_rd.framebuffer_get_format(framebuffer),RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,multisample,depth,blend),true)
	if not pipeline.is_valid():_resource_failure("pipeline "+name)
	return pipeline

func _resize(size: Vector2i) -> void:
	color_texture.texture_rd_rid=RID()
	_free_targets()
	_size=size
	_depth_target=_target(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,true)
	_filters=[_target(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT),_target(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)]
	_composite=_target(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	_whitewater=_target(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,true,RenderingDevice.TEXTURE_SAMPLES_4)
	var resolved := _target(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	_whitewater_resolved=resolved.texture
	if not available:return
	_pipes["depth"]=_pipeline("depth",_depth_target.framebuffer,true)
	_pipes["filter"]=_pipeline("filter",_filters[0].framebuffer)
	_pipes["composite"]=_pipeline("composite",_composite.framebuffer)
	_pipes["copy_composite"]=_pipeline("copy",_composite.framebuffer)
	_pipes["color_depth"]=_pipeline("color_depth",_whitewater.framebuffer,true,true,RenderingDevice.TEXTURE_SAMPLES_4)
	_pipes["drop"]=_pipeline("drop",_whitewater.framebuffer,true,false,RenderingDevice.TEXTURE_SAMPLES_4,true)
	color_texture.texture_rd_rid=_composite.texture

func _uniform(kind: int, binding: int, ids: Array[RID]) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type=kind
	u.binding=binding
	for id in ids:
		u.add_id(id)
	return u

func _buffer(binding: int, rid: RID, uniform: bool = false) -> RDUniform:
	return _uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if uniform else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,binding,[rid])

func _texture(binding: int, rid: RID, linear: bool = false) -> RDUniform:
	return _uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,binding,[_linear if linear else _nearest,rid])

func _uniform_set(name: String, uniforms: Array[RDUniform]) -> RID:
	descriptor_requests += 1
	if reuse_uniform_sets:
		descriptor_cache_requests += 1
		# Godot owns these sets and automatically retires them when a bound
		# texture, buffer, or shader is freed. Never manually free a cached RID.
		return UniformSetCacheRD.get_cache(_programs[name],0,uniforms)
	descriptor_transient_allocations += 1
	return _rd.uniform_set_create(uniforms,_programs[name],0)

func _draw(framebuffer: RID, pipeline: RID, group: RID, flags: int = 0, clear: Color = Color.BLACK, scissor: Rect2i = Rect2i(), indices: RID = RID(), instances: int = 1, push: PackedByteArray = PackedByteArray()) -> void:
	last_draw_calls += 1
	var list := _rd.draw_list_begin(framebuffer,flags,PackedColorArray([clear]),0.0)
	if scissor.size.x>0 and scissor.size.y>0:
		_rd.draw_list_enable_scissor(list,Rect2(scissor))
	_rd.draw_list_bind_render_pipeline(list,pipeline)
	_rd.draw_list_bind_uniform_set(list,group,0)
	if not push.is_empty():
		_rd.draw_list_set_push_constant(list,push,push.size())
	if indices.is_valid():
		_rd.draw_list_bind_index_array(list,indices)
	_rd.draw_list_draw(list,indices.is_valid(),instances,0 if indices.is_valid() else 3)
	_rd.draw_list_end()
	if not reuse_uniform_sets:
		_rd.free_rid(group)

func _projection_data(projection: Projection, camera: Transform3D, environment_ready: bool) -> PackedByteArray:
	var values := PackedFloat32Array()
	for matrix: Projection in [projection,projection.inverse(),Projection(camera.affine_inverse()),Projection(camera)]:
		for column in 4:
			for row in 4:
				values.append(matrix[column][row])
	values.append_array(PackedFloat32Array([_size.x,_size.y,absf(float(_size.y)*projection.y.y*0.5),_environment_mips]))
	values.append_array(_wave)
	values.append_array(PackedFloat32Array([1.0 if environment_ready else 0.0,0,0,0]))
	return values.to_byte_array()

func _project_region(projection: Projection, camera: Transform3D, near_plane: float) -> Rect2i:
	if _rows.is_empty():
		return Rect2i()
	if not _bounds.position.is_finite() or not _bounds.size.is_finite():
		return Rect2i(Vector2i.ZERO,_size)
	# Viewport-seeded extrema artificially kept a 26-pixel edge strip even
	# when every corner lay outside. True extrema permit a proven empty region.
	var lo := Vector2(INF,INF) if cull_offscreen_liquid else Vector2(_size)
	var hi := Vector2(-INF,-INF) if cull_offscreen_liquid else Vector2.ZERO
	var view := camera.affine_inverse()
	for i in 8:
		var point := Vector3(_bounds.end.x if i&1 else _bounds.position.x,_bounds.end.y if i&2 else _bounds.position.y,_bounds.end.z if i&4 else _bounds.position.z)
		point=view*point
		if point.z>=-near_plane:
			# A near-plane crossing is not an empty/offscreen region. Keep the
			# source conservative full-viewport fallback as an explicit rectangle.
			return Rect2i(Vector2i.ZERO,_size)
		var clip := projection*Vector4(point.x,point.y,point.z,1.0)
		var pixel := Vector2((clip.x/clip.w*.5+.5)*_size.x,(clip.y/clip.w*.5+.5)*_size.y)
		lo=lo.min(pixel)
		hi=hi.max(pixel)
	var first := Vector2i(maxi(0,floori(lo.x)-26),maxi(0,floori(lo.y)-26))
	var last := Vector2i(mini(_size.x,ceili(hi.x)+26),mini(_size.y,ceili(hi.y)+26))
	return Rect2i(first,(last-first).max(Vector2i.ZERO))

func _prepare_scene_copy_target(color: RID) -> bool:
	# A nonzero RID is not proof its RenderingDevice resource still exists.
	# Rebuild only this final-copy target, preserving all fluid state and math.
	if _scene_color==color and _rd.framebuffer_is_valid(_scene_fb) and _rd.render_pipeline_is_valid(_final_copy_pipeline):
		return true
	if _scene_fb.is_valid():
		_targets_owned.erase(_scene_fb)
		if _rd.framebuffer_is_valid(_scene_fb):_rd.free_rid(_scene_fb)
	if _final_copy_pipeline.is_valid():
		_targets_owned.erase(_final_copy_pipeline)
		if _rd.render_pipeline_is_valid(_final_copy_pipeline):_rd.free_rid(_final_copy_pipeline)
	_scene_color=color
	_scene_fb=_own(_rd.framebuffer_create([color]),true)
	_final_copy_pipeline=_pipeline("copy",_scene_fb)
	scene_target_rebuilds+=1
	return available and _rd.framebuffer_is_valid(_scene_fb) and _rd.render_pipeline_is_valid(_final_copy_pipeline)

func _render_callback(_type: int, render_data: RenderData) -> void:
	last_draw_calls=0
	last_filter_clears=0
	last_instance_upload_bytes=0
	last_culled_liquid_views=0
	render_encode_ms=0.0
	if _disposed or not available or (_rows.is_empty() and _drop_rows.is_empty()):
		return
	if _surface==null or _depth==null or _detail==null:
		return
	var encode_started := Time.get_ticks_usec()
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers==null or scene==null:
		return
	var size := buffers.get_internal_size()
	if size.x<1 or size.y<1:
		return
	if size!=_size:
		_resize(size)
	if not available:return
	var environment := _dummy_cube
	var env_ready := false
	if _environment!=null:
		var rid := RenderingServer.texture_get_rd_texture(_environment.get_rid(),false)
		if rid.is_valid():
			environment=rid
			env_ready=true
	var surface := _surface.texture_rd_rid
	var depth := _depth.texture_rd_rid
	var detail := _detail.texture_rd_rid
	if not surface.is_valid() or not depth.is_valid() or not detail.is_valid():
		return
	var liquid_uploaded := false
	var drops_uploaded := false
	for view in buffers.get_view_count():
		var projection := scene.get_view_projection(view)
		projection_sample=Vector4(projection.x.x,projection.y.y,projection.z.z,projection.w.z)
		var near_plane := projection.get_z_near()
		# RenderSceneData normally exposes the already corrected native projection.
		# Godot4.6 correction performs both reverse-Z [0,1] and framebuffer Y flip.
		# Do not correct a projection already delivered in native depth space.
		if projection.z.z<0.0:
			projection=Projection.create_depth_correction(true)*projection
		var camera := scene.get_cam_transform()
		camera.origin+=camera.basis*scene.get_view_eye_offset(view)
		# Simulation/height textures/instance rows use solver-local coordinates.
		# Native opaque depth stays valid because translation does not change view depth.
		camera.origin-=_domain_origin
		var region := _project_region(projection,camera,near_plane)
		var draw_liquid := not _rows.is_empty()
		if draw_liquid and cull_offscreen_liquid and not region.has_area():
			draw_liquid=false
			last_culled_liquid_views+=1
			total_culled_liquid_views+=1
		var color := buffers.get_color_layer(view)
		if not draw_liquid and _drop_rows.is_empty():
			# No sphere can cover this view. Leave the native scene untouched;
			# simulation, snapshots, particles and other views still advance.
			color_texture.texture_rd_rid=color
			continue
		_gpu_mark("begin",{"view":view,"liquid":draw_liquid,"drops":not _drop_rows.is_empty(),"offscreen_cull":cull_offscreen_liquid,"reuse_filter_clears":reuse_filter_clears})
		if draw_liquid and not liquid_uploaded:
			_rd.buffer_update(_instance_buffers.liquid,0,_rows.size()*4,_rows.to_byte_array())
			last_instance_upload_bytes+=_rows.size()*4
			liquid_uploaded=true
		if not _drop_rows.is_empty() and not drops_uploaded:
			_rd.buffer_update(_instance_buffers.drop,0,_drop_rows.size()*4,_drop_rows.to_byte_array())
			last_instance_upload_bytes+=_drop_rows.size()*4
			drops_uploaded=true
		var bytes := _projection_data(projection,camera,env_ready)
		_rd.buffer_update(_ubo,0,bytes.size(),bytes)
		var opaque_depth := buffers.get_depth_layer(view)
		if not _prepare_scene_copy_target(color):return
		var base := color
		if draw_liquid:
			var geometry: Dictionary = _geometry.liquid
			var group := _uniform_set("depth",[_buffer(0,_ubo,true),_buffer(1,geometry.vertices),_buffer(2,_instance_buffers.liquid)])
			_draw(_depth_target.framebuffer,_pipes.depth,group,RenderingDevice.DRAW_CLEAR_COLOR_0|RenderingDevice.DRAW_CLEAR_DEPTH,Color(10000,0,0,1),region,geometry.indices,_rows.size()/12)
			_gpu_mark("depth")
			var source: RID = _depth_target.texture
			for step in 4:
				var output: Dictionary = _filters[step%2]
				group=_uniform_set("filter",[_buffer(0,_ubo,true),_texture(1,source)])
				var direction := PackedFloat32Array([1.0 if step%2==0 else 0.0,0.0 if step%2==0 else 1.0,0,0]).to_byte_array()
				# Each target is initialized once, then its identical scissor is
				# completely overwritten on the second visit. Outside pixels keep
				# the sentinel from that first clear. All four filters still run.
				var clear_flags := RenderingDevice.DRAW_CLEAR_COLOR_0 if step<2 or not reuse_filter_clears else 0
				if clear_flags!=0:last_filter_clears+=1
				_draw(output.framebuffer,_pipes.filter,group,clear_flags,Color(10000,0,0,1),region,RID(),1,direction)
				source=output.texture
			_gpu_mark("filters")
			group=_uniform_set("composite",[_buffer(0,_ubo,true),_texture(1,source),_texture(2,color,true),_texture(3,opaque_depth),_texture(4,surface,true),_texture(5,depth),_texture(6,detail,true),_texture(7,environment,true)])
			_draw(_composite.framebuffer,_pipes.composite,group)
			base=_composite.texture
		else:
			_gpu_mark("depth")
			_gpu_mark("filters")
		_gpu_mark("composite")
		if not _drop_rows.is_empty():
			# Copy color + stable opaque depth into a SEPARATE 4x MSAA target.
			var group := _uniform_set("color_depth",[_texture(1,base,true),_texture(2,opaque_depth)])
			_draw(_whitewater.framebuffer,_pipes.color_depth,group,RenderingDevice.DRAW_CLEAR_COLOR_0|RenderingDevice.DRAW_CLEAR_DEPTH)
			var geometry: Dictionary = _geometry.drop
			group=_uniform_set("drop",[_buffer(0,_ubo,true),_buffer(1,geometry.vertices),_buffer(2,_instance_buffers.drop),_texture(3,base,true),_texture(7,environment,true),_buffer(8,_lights,true),_texture(9,_dfg,true),_buffer(10,_shadow_nodes),_buffer(11,_shadow_triangles)])
			_draw(_whitewater.framebuffer,_pipes.drop,group,0,Color.BLACK,Rect2i(),geometry.indices,_drop_rows.size()/12)
			_rd.texture_resolve_multisample(_whitewater.texture,_whitewater_resolved)
			base=_whitewater_resolved
		_gpu_mark("whitewater")
		color_texture.texture_rd_rid=base
		if base!=color:
			_draw(_scene_fb,_final_copy_pipeline,_uniform_set("copy",[_texture(1,base,true)]))
		_gpu_mark("copy")
		_gpu_mark("end")
	rendered_frames+=1
	render_encode_ms=float(Time.get_ticks_usec()-encode_started)/1000.0
	render_encode_max_ms=maxf(render_encode_max_ms,render_encode_ms)

func _gpu_mark(stage: String, metadata: Dictionary = {}) -> void:
	if _gpu_timestamps != null:_gpu_timestamps.mark(_rd,stage,metadata)

func debug_stats() -> Dictionary:
	return {"scene_target_rebuilds":scene_target_rebuilds,"draw_calls":last_draw_calls,"filter_clears":last_filter_clears,"instance_upload_bytes":last_instance_upload_bytes,"culled_liquid_views":last_culled_liquid_views,"total_culled_liquid_views":total_culled_liquid_views,"cull_offscreen_liquid":cull_offscreen_liquid,"reuse_filter_clears":reuse_filter_clears,"render_encode_ms":render_encode_ms,"render_encode_max_ms":render_encode_max_ms,"gpu":_gpu_timestamps.diagnostics() if _gpu_timestamps != null else {"enabled":false}}

func _free_targets() -> void:
	# This FB references an engine-owned scene color. Its dependency can have
	# already retired during resize; all other targets here are self-owned.
	if _scene_fb.is_valid() and not _rd.framebuffer_is_valid(_scene_fb):
		_targets_owned.erase(_scene_fb)
	for i in range(_targets_owned.size()-1,-1,-1):
		_rd.free_rid(_targets_owned[i])
	_targets_owned.clear()
	_pipes.clear()
	_scene_color=RID()
	_scene_fb=RID()
	_final_copy_pipeline=RID()

func dispose() -> void:
	_disposed=true
	if _gpu_timestamps != null:_gpu_timestamps.dispose()
	RenderingServer.call_on_render_thread(_dispose_gpu)

func _dispose_gpu() -> void:
	# _disposed prevents new callbacks; queued render-thread work retires before
	# resources below. Only RIDs created by this class are freed explicitly.
	color_texture.texture_rd_rid=RID()
	if _rd!=null:
		_free_targets()
		for i in range(_owned.size()-1,-1,-1):
			_rd.free_rid(_owned[i])
	_owned.clear()
	_programs.clear()
	_geometry.clear()
	_instance_buffers.clear()
	_depth_target.clear()
	_filters.clear()
	_composite.clear()
	_whitewater.clear()
	# frame() borrows producer arrays; release our references, not their contents.
	_rows=PackedFloat32Array()
	_drop_rows=PackedFloat32Array()
	_bounds=AABB()
	_size=Vector2i.ZERO
	_ubo=RID();_lights=RID();_linear=RID();_nearest=RID()
	_dummy_cube=RID();_dfg=RID();_shadow_nodes=RID();_shadow_triangles=RID()
	_whitewater_resolved=RID();_scene_color=RID();_scene_fb=RID();_final_copy_pipeline=RID()
	available=false
	shadow_ready=false
	_rd=null
	# These are caller-owned high-level Resources. Drop references on the owner
	# thread only after callbacks stopped; never free their Godot-owned RIDs.
	_clear_input_references.call_deferred()

func _clear_input_references() -> void:
	_surface=null
	_depth=null
	_detail=null
	_environment=null
	_codes.clear()
	_dfg_bytes.clear()
	_light_data.clear()
