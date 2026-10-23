extends RefCounted
## Global-RD room-cube worker. All non-mailbox methods run on the render thread.
## No local device, submit, sync, CPU mip generation, or readback in copy/mip path.
const Lease = preload("res://scripts/water/source_port/source_gpu_room_cube_lease.gd")
const Cube = preload("res://scripts/water/source_port/source_gpu_room_cube.gd")
const MIP_SHADER := """#version 450
// Exact ordinary Image mip arithmetic, NOT PMREM or a GGX convolution.
// Godot 4.6.3-stable core/io/image.cpp average_4_half and core/math/math_funcs.h.
// UINT alias views preserve exact half inputs, including subnormals/signed zero.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16ui, set = 0, binding = 0) uniform readonly uimage2D source_bits;
layout(rgba16ui, set = 0, binding = 1) uniform writeonly uimage2D target_bits;

float decode_half(uint h) {
    uint sign = (h & 0x8000u) << 16;
    uint exponent = h & 0x7c00u;
    uint fraction = h & 0x03ffu;
    if (exponent == 0u) {
        if (fraction == 0u) return uintBitsToFloat(sign);
        fraction <<= 1;
        uint shifts = 0u;
        while ((fraction & 0x0400u) == 0u) { fraction <<= 1; shifts++; }
        return uintBitsToFloat(sign + ((112u - shifts) << 23) + ((fraction & 0x03ffu) << 13));
    }
    if (exponent == 0x7c00u) return uintBitsToFloat(sign + 0x7f800000u + (fraction << 13));
    return uintBitsToFloat(sign + (((h & 0x7fffu) + 0x1c000u) << 13));
}

uint encode_half_cpu(float value) {
    uint bits = floatBitsToUint(value);
    uint sign = (bits >> 31) << 15;
    uint mantissa = bits & 0x007fffffu;
    uint exponent = bits & 0x7f800000u;
    if (exponent >= 0x47800000u) {
        uint payload = mantissa != 0u && exponent == 0x7f800000u ? 0x03ffu : 0u;
        return sign | 0x7c00u | payload;
    }
    // Exact CPU behavior: all subnormal outputs AND negative zero become +0.
    if (exponent <= 0x38000000u) return 0u;
    return sign | ((exponent - 0x38000000u) >> 13) | (mantissa >> 13);
}

uint average_cpu(uint a, uint b, uint c, uint d) {
    // 'precise' requires NoContraction and propagates to these operations.
    // Do not replace with dot(), pairwise sums, hardware bilinear, or half stores.
    precise float top = decode_half(a) + decode_half(b);
    precise float with_bottom_left = top + decode_half(c);
    precise float all_four = with_bottom_left + decode_half(d);
    precise float mean = all_four * 0.25;
    return encode_half_cpu(mean);
}

void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, imageSize(target_bits)))) return;
    ivec2 q = p * 2;
    uvec4 tl = imageLoad(source_bits, q);
    uvec4 tr = imageLoad(source_bits, q + ivec2(1, 0));
    uvec4 bl = imageLoad(source_bits, q + ivec2(0, 1));
    uvec4 br = imageLoad(source_bits, q + ivec2(1, 1));
    uvec4 result;
    for (int channel = 0; channel < 4; ++channel) {
        result[channel] = average_cpu(tl[channel], tr[channel], bl[channel], br[channel]);
    }
    imageStore(target_bits, p, result);
}
"""
const ALPHA_SHADER := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16ui, set = 0, binding = 0) uniform uimage2D base_bits;
void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, imageSize(base_bits)))) return;
    uvec4 bits = imageLoad(base_bits, p);
    bits.a = 0x3c00u;
    imageStore(base_bits, p, bits);
}
"""
const FLOAT_FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const BITS_FORMAT := RenderingDevice.DATA_FORMAT_R16G16B16A16_UINT
const CUBE_USAGE := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
const SOURCE_USAGE := RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
var owner := Lease.new()
var rd: RenderingDevice
var cube := RID()
var shader := RID()
var pipeline := RID()
var views: Array[RID] = []
var sets: Array[RID] = []
var wrapper: TextureCubemapRD
var size := 64
var level_count := 7
var copied: Array[int] = []
var state := "new"
var events: Array[Dictionary] = []
var mutex := Mutex.new()
var gate: RefCounted
var source_server_rid := RID()
var observed_source_rd_id := 0
var alpha_shader := RID()
var alpha_pipeline := RID()
var alpha_sets: Array[RID] = []
var logical_format := -1
var lease_released := false
var stats: Dictionary = {"copies": [], "mips": [], "view_metadata": [], "validation_readback_requests": 0,
	"validation_readback_bytes": 0, "runtime_pixel_readbacks": 0, "runtime_cpu_mip_jobs": 0,
	"production_uploads": 0, "wrapper_created": false, "wrapper_ready": false,
	"published": false, "original_freed_by_owner": false}

func post(kind: String, value: Dictionary = {}) -> void:
	mutex.lock()
	events.append({"kind": kind, "time_usec": Time.get_ticks_usec(), "value": value})
	mutex.unlock()

func take_events() -> Array[Dictionary]:
	mutex.lock()
	var result: Array[Dictionary] = events.duplicate()
	events.clear()
	mutex.unlock()
	return result

func fail(reason: String) -> void:
	state = "failed"
	post("error", {"reason": reason})

func configure(shared_gate: RefCounted, borrowed_source: RID) -> void:
	gate = shared_gate
	source_server_rid = borrowed_source

func allocate(dimension: int) -> void:
	if not bool(gate.snapshot().active): return
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 6 or version.patch != 3:
		fail("Exact half-mip CPU contract is validated for Godot 4.6.3 only"); return
	if dimension < 2 or dimension > 4096 or (dimension & (dimension - 1)) != 0:
		fail("GPU room cube requires a power-of-two extent from 2 to 4096"); return
	rd = RenderingServer.get_rendering_device()
	if rd == null: fail("Global RenderingDevice is unavailable; use async CPU path."); return
	
	size = dimension
	level_count = 1 + int(log(float(size)) / log(2.0))
	var caps := {"float_cube_usage": rd.texture_is_format_supported_for_usage(FLOAT_FORMAT, CUBE_USAGE),
		"integer_alias_usage": rd.texture_is_format_supported_for_usage(BITS_FORMAT, CUBE_USAGE),
		"float_source_copy": rd.texture_is_format_supported_for_usage(FLOAT_FORMAT, SOURCE_USAGE),
		"float_linear_filter": rd.sampler_is_format_supported_for_filter(FLOAT_FORMAT, RenderingDevice.SAMPLER_FILTER_LINEAR),
		"device": rd.get_device_name(), "vendor": rd.get_device_vendor_name()}
	stats["capabilities"] = caps
	for key in ["float_cube_usage", "integer_alias_usage", "float_source_copy", "float_linear_filter"]:
		if not caps[key]: fail("Required capability unsupported: " + key + "; precision/resolution fallback prohibited."); return
	var source := RDShaderSource.new()
	source.source_compute = MIP_SHADER
	var spirv := rd.shader_compile_spirv_from_source(source)
	var compiler_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compiler_error.is_empty(): fail("Exact half shader compile failed: " + compiler_error); return
	shader = owner.own(rd.shader_create_from_spirv(spirv, "pc_gpu_cube_exact_half"), "shader")
	if not shader.is_valid(): fail("Shader creation failed"); return
	pipeline = owner.own(rd.compute_pipeline_create(shader), "pipeline")
	if not pipeline.is_valid(): fail("Compute pipeline creation failed"); return
	var format := RDTextureFormat.new()
	format.width = size; format.height = size; format.depth = 1
	format.array_layers = 6; format.mipmaps = level_count
	format.texture_type = RenderingDevice.TEXTURE_TYPE_CUBE
	format.format = FLOAT_FORMAT; format.samples = RenderingDevice.TEXTURE_SAMPLES_1
	format.usage_bits = CUBE_USAGE
	# Both formats must be declared. Alias support is NOT inferred from equal size.
	format.add_shareable_format(FLOAT_FORMAT)
	format.add_shareable_format(BITS_FORMAT)
	var payload := 0
	for mip in level_count: payload += (size >> mip) * (size >> mip) * 8 * 6
	cube = owner.own(rd.texture_create(format, RDTextureView.new()), "cube", payload)
	if not cube.is_valid() or not rd.texture_is_valid(cube): fail("Mutable-format RGBA16F cube allocation failed; use async CPU path."); return
	if rd.texture_is_shared(cube): fail("Original cube unexpectedly shared; TextureCubemapRD requires owned original."); return
	var actual := rd.texture_get_format(cube)
	if actual.texture_type != RenderingDevice.TEXTURE_TYPE_CUBE or actual.array_layers != 6 or actual.mipmaps != level_count or actual.format != FLOAT_FORMAT:
		fail("Original cube format/shape differs from requested immutable publication contract"); return
	for face in 6:
		for mip in level_count:
			var view := RDTextureView.new()
			view.format_override = BITS_FORMAT
			# Exact 4.6.3 signature: view, original, face, mip, count, 2D slice.
			var rid := owner.own(rd.texture_create_shared_from_slice(view, cube, face, mip, 1, RenderingDevice.TEXTURE_SLICE_2D), "view")
			if not rid.is_valid() or not rd.texture_is_valid(rid): fail("UINT one-face/one-mip alias unsupported at face %d mip %d" % [face, mip]); return
			var vf := rd.texture_get_format(rid)
			# 4.6.3 texture_get_format returns Texture backing metadata; the
			# override is stored only in the driver's TextureView, not Texture.format.
			# Thus reported_format must remain FLOAT_FORMAT, NOT BITS_FORMAT.
			# Successful alias bit interpretation is still proved by every mip byte.
			var observation := {"face": face, "mip": mip, "requested_view_format": view.format_override,
				"reported_backing_format": vf.format, "type": vf.texture_type, "width": vf.width,
				"height": vf.height, "depth": vf.depth, "mipmaps": vf.mipmaps, "layers": vf.array_layers,
				"shared": rd.texture_is_shared(rid), "usage_bits": vf.usage_bits}
			stats.view_metadata.append(observation)
			if vf.format != FLOAT_FORMAT or vf.texture_type != RenderingDevice.TEXTURE_TYPE_2D or vf.mipmaps != 1 or vf.array_layers != 1 or vf.width != (size >> mip) or vf.height != (size >> mip) or vf.depth != 1 or not observation.shared or (vf.usage_bits & RenderingDevice.TEXTURE_USAGE_STORAGE_BIT) == 0:
				fail("Shared view backing metadata/shape mismatch: " + JSON.stringify(observation)); return
			views.append(rid)
	for face in 6:
		for mip in range(1, level_count):
			var input := RDUniform.new(); input.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; input.binding = 0
			input.add_id(views[face * level_count + mip - 1])
			var output := RDUniform.new(); output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; output.binding = 1
			output.add_id(views[face * level_count + mip])
			var set_rid := owner.own(rd.uniform_set_create([input, output], shader, 0), "uniform_set")
			if not set_rid.is_valid(): fail("Mip descriptor creation failed"); return
			sets.append(set_rid)
	var alpha_source := RDShaderSource.new()
	alpha_source.source_compute = ALPHA_SHADER
	var alpha_spirv := rd.shader_compile_spirv_from_source(alpha_source)
	var alpha_error := alpha_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not alpha_error.is_empty(): fail("Logical RGB alpha shader compile failed: " + alpha_error); return
	alpha_shader = owner.own(rd.shader_create_from_spirv(alpha_spirv, "room_cube_rgb_alpha"), "shader")
	if not alpha_shader.is_valid(): fail("Logical RGB alpha shader creation failed"); return
	alpha_pipeline = owner.own(rd.compute_pipeline_create(alpha_shader), "pipeline")
	if not alpha_pipeline.is_valid(): fail("Logical RGB alpha pipeline creation failed"); return
	for face in 6:
		var image := RDUniform.new(); image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; image.binding = 0
		image.add_id(views[face * level_count])
		var uniform := owner.own(rd.uniform_set_create([image], alpha_shader, 0), "uniform_set")
		if not uniform.is_valid(): fail("Logical RGB alpha descriptor creation failed"); return
		alpha_sets.append(uniform)
	state = "allocated"
	post("allocated", {"capabilities": caps, "levels": level_count, "cube_payload_bytes": payload})

func copy_viewport(ticket: RefCounted) -> void:
	if not gate.is_current(ticket): return
	if state != "allocated": fail("Viewport copy in invalid state " + state); return
	var snapshot: Dictionary = ticket.snapshot()
	if int(snapshot.source_identity) != source_server_rid.get_id(): fail("Borrowed viewport identity changed"); return
	var borrowed := RenderingServer.texture_get_rd_texture(source_server_rid, false)
	if not borrowed.is_valid() or not rd.texture_is_valid(borrowed): fail("Borrowed viewport RD texture unavailable"); return
	if observed_source_rd_id == 0: observed_source_rd_id = borrowed.get_id()
	elif observed_source_rd_id != borrowed.get_id(): fail("Viewport RD identity changed within capture"); return
	var current_format := RenderingServer.texture_get_format(source_server_rid)
	if current_format not in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH]: fail("GPU copy supports exact logical RGBH/RGBAH only; retaining async CPU fallback"); return
	if logical_format < 0: logical_format = current_format
	elif logical_format != current_format: fail("Viewport logical format changed within capture"); return
	copy_borrowed_source(borrowed, int(snapshot.face), int(snapshot.draw_sequence))
	if state != "failed": post("copy_ack", {"ticket": ticket})

func copy_borrowed_source(borrowed_source: RID, face: int, draw_sequence: int) -> void:
	# Borrowed input is validated but NEVER owned or released by this method.
	if copied.has(face) or face != copied.size(): fail("Duplicate or out-of-order face ticket"); return
	if not rd.texture_is_valid(borrowed_source): fail("Borrowed source RID invalid"); return
	var sf := rd.texture_get_format(borrowed_source)
	if sf.width != size or sf.height != size or sf.depth != 1 or sf.mipmaps < 1 or sf.format != FLOAT_FORMAT or sf.texture_type != RenderingDevice.TEXTURE_TYPE_2D or sf.array_layers != 1 or sf.samples != RenderingDevice.TEXTURE_SAMPLES_1 or (sf.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT) == 0:
		fail("Borrowed source dimensions/format/type/layers/samples/copy-from usage incompatible"); return
	var start := Time.get_ticks_usec()
	# 2D z=0, depth=1; 4.6.3 nine-argument layer/mip copy, no conversion.
	var error := rd.texture_copy(borrowed_source, cube, Vector3.ZERO, Vector3.ZERO, Vector3(size, size, 1), 0, 0, 0, face)
	if error != OK: fail("2D -> cube copy failed at face %d: %s" % [face, error_string(error)]); return
	copied.append(face)
	var record := {"face": face, "draw_sequence": draw_sequence, "encoding_usec": Time.get_ticks_usec() - start, "source_owned_by_copy": false}
	stats.copies.append(record)
	post("copy_encoded", record)

func encode_mips(ticket: RefCounted) -> void:
	if not gate.is_current(ticket): return
	if not bool(gate.snapshot().complete): fail("Copy acknowledgments incomplete before mips"); return
	if state != "allocated" or copied.size() != 6: fail("Mip chain before exactly six distinct copies"); return
	var chain_start := Time.get_ticks_usec()
	# RGBH is backed by RGBAH. CPU RGBH conversion drops arbitrary source alpha,
	# and Cubemap upload reintroduces opaque alpha. Reproduce that on the GPU.
	if logical_format == Image.FORMAT_RGBH:
		var alpha_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(alpha_list, alpha_pipeline)
		for face in 6:
			rd.compute_list_bind_uniform_set(alpha_list, alpha_sets[face], 0)
			rd.compute_list_dispatch(alpha_list, ceili(float(size) / 8.0), ceili(float(size) / 8.0), 1)
		rd.compute_list_end()
	# One separate list per dependency level. RD tracks the real shared views.
	for mip in range(1, level_count):
		var start := Time.get_ticks_usec()
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		for face in 6:
			rd.compute_list_bind_uniform_set(list, sets[face * (level_count - 1) + mip - 1], 0)
			var extent := size >> mip
			rd.compute_list_dispatch(list, ceili(float(extent) / 8.0), ceili(float(extent) / 8.0), 1)
		rd.compute_list_end()
		stats.mips.append({"level": mip, "encoding_usec": Time.get_ticks_usec() - start})
	stats["chain_encoding_usec"] = Time.get_ticks_usec() - chain_start
	state = "mips_encoded"
	post("mips_encoded", {"levels": level_count, "encoding_usec": stats.chain_encoding_usec})

func initialize_wrapper(ticket: RefCounted) -> void:
	if not gate.is_current(ticket): return
	if state != "mips_encoded": fail("Wrapper initialization before complete encoded chain"); return
	wrapper = Cube.new()
	wrapper.retain_payload(owner)
	lease_released = true
	stats.wrapper_created = true
	wrapper.texture_rd_rid = cube
	# The setter may enqueue setup; readiness is checked by a later render-thread ticket.
	state = "wrapper_queued"
	post("wrapper_queued")

func inspect_wrapper(ticket: RefCounted) -> void:
	if not gate.is_current(ticket): return
	if state != "wrapper_queued": fail("Wrapper inspection in invalid state " + state); return
	if wrapper.texture_rd_rid != cube or wrapper.get_width() != size or wrapper.get_layers() != 6 or not wrapper.has_mipmaps():
		fail("TextureCubemapRD deferred setup incomplete or wrong shape"); return
	var bridge := RenderingServer.texture_get_rd_texture(wrapper.get_rid(), false)
	if not bridge.is_valid() or not rd.texture_is_valid(bridge): fail("Wrapper RenderingServer sampling bridge invalid"); return
	var bf := rd.texture_get_format(bridge)
	if bf.texture_type != RenderingDevice.TEXTURE_TYPE_CUBE or bf.mipmaps != level_count or bf.array_layers != 6 or bf.format != FLOAT_FORMAT:
		fail("Sampling bridge lost cube, mip, layer, or HDR format contract"); return
	state = "ready"
	stats.wrapper_ready = true
	post("ready", {"texture": wrapper, "ticket": ticket, "max_lod": level_count - 1, "bridge_borrowed": true, "bridge_shared": rd.texture_is_shared(bridge)})


func dispose() -> void:
	# Publication transfers payload ownership to the consumer-visible texture.
	# Dropping this worker MUST NOT detach a texture retained by a material.
	wrapper = null
	if not lease_released and rd != null:
		owner.dispose(rd)
		lease_released = true
	mutex.lock()
	events.clear()
	mutex.unlock()
	cube = RID(); views.clear(); sets.clear(); alpha_sets.clear()
	state = "disposed"
