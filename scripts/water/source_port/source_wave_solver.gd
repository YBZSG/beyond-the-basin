class_name SourceWaveSolver
extends RefCounted
## Direct GPU port of poolcore@66a4543602d9e774db07c2da12ce1d40d522532c:
## app/pool-vct/shallow-water.ts and ripple-detail.ts. No CPU wave surrogate.
## Runtime resources belong to the GLOBAL RenderingDevice, and all RD work runs
## on its render thread. Texture2DRD therefore interoperates with spatial shaders.
## Call dispose() before releasing the owner. configure() may safely be repeated.

signal ready
signal failed(reason: String)
signal physics_updated

const SOURCE_COMMIT := "66a4543602d9e774db07c2da12ce1d40d522532c"
const WATER_LEVEL := 0.32
const POOL_BOTTOM := -0.72
const REST_DEPTH := WATER_LEVEL - POOL_BOTTOM
const SW_SIZE := 768
const SW_DOMAIN := 96.0
const SW_PHYS := 384
const SW_STEP := 1.0 / 120.0
const DETAIL_DOMAIN := 48.0
const SOURCE_BATCH := 128
const SHADERS := ["swe_source", "swe_velocity", "swe_height", "swe_copy", "swe_downsample", "swe_resample", "detail_source", "detail_step", "detail_copy"]

# Original live-tunable defaults. wave_speed scales g, not time or amplitude.
var impact_scale := 1.0
var ring_waves := 12.0
var wave_speed := 1.0
var damping := 0.28
var viscosity := 0.0015
var wall_loss := 1.1
var max_steps := 8
var foam_gain := 0.7
var foam_decay := 0.5
var foam_diff := 0.003
var foam_splash := 1.0
var detail_frequency := 22.0
var detail_max_steps := 8
var detail_enabled := true
var size := SW_SIZE
var domain := SW_DOMAIN
var cell := SW_DOMAIN / SW_SIZE
var physics_size := SW_PHYS
var detail_size := SW_SIZE
var detail_domain := DETAIL_DOMAIN
var detail_cell := DETAIL_DOMAIN / SW_SIZE
var state_texture := Texture2DRD.new()
var detail_texture := Texture2DRD.new()
var depth_texture := Texture2DRD.new()
var physics_eta := PackedFloat32Array()
var physics_u := PackedFloat32Array()
var physics_v := PackedFloat32Array()
var settled := true
var energy := 0.0
var peak := 0.0
# Optional exact native decoder; the original interpreted path remains available.
# This switch changes host parsing only, never readback scheduling or simulation.
var native_readback_enabled := not OS.get_cmdline_user_args().has("--no-native-water-readback")
var _native_readback_parser: RefCounted
var _readback_parser_backend := "gdscript"
var _readback_native_ms := 0.0
var readback_bytes := 0
var is_ready := false
var last_error := ""

var _depth := PackedFloat32Array()
var _splats: Array[Vector4] = []
var _pushes: Array[Dictionary] = []
var _detail_sources: Array[Vector4] = []
var _acc := 0.0
var _clock := 0.0
var _quiet := 0.0
var _calm := 0.0
var _simulated := 0.0
var _dropped_time := 0.0
var _detail_acc := 0.0
var _detail_quiet := 10.0
var _pending_shift := Vector2.ZERO
var _detail_shift := Vector2.ZERO
var _terrain_dirty := false
var _depth_dirty := false
var _detail_dirty := true
var _disposed := false
var _generation := 0
var _epoch := 0
var _readback_pending := false
var _readback_started := 0.0
var _readback_landed := -INF
var _async_failed := false
var _sync_at := -INF
var _async_lands := 0
var _sync_reads := 0
var _rejected := 0
# Main-thread-only wall-clock diagnostics. Simulation-clock cadence is unchanged.
var _readback_serial := 0
var _readback_active_serial := 0
var _readback_started_usec := 0
var _readback_timeouts := 0
var _readback_async_errors := 0
var _readback_stale := 0
var _readback_publishes := 0
var _readback_parse_count := 0
var _readback_parse_ms := 0.0
var _readback_parse_max_ms := 0.0
var _readback_parse_total_ms := 0.0
var _readback_convert_ms := 0.0
var _readback_validate_reduce_ms := 0.0
var _readback_pack_ms := 0.0
var _readback_latency_ms := 0.0
var _readback_latency_max_ms := 0.0
var _readback_rd_queue_ms := 0.0
var _readback_transfer_ms := 0.0
var _readback_delivery_ms := 0.0
var _readback_sync_ms := 0.0
# Render-thread-only state, never accessed by main-thread numerical methods.
var _rd: RenderingDevice
var _shaders: Dictionary = {}
var _pipelines: Dictionary = {}
var _sets: Dictionary = {}
var _owned: Array[RID] = []
var _state: Array[RID] = []
var _detail: Array[RID] = []
var _source := RID()
var _detail_source := RID()
var _depth_rid := RID()
var _physics := RID()
var _source_buffer := RID()
var _current := 0
var _detail_current := 0
var _rd_epoch := -1

func configure(depth_image: Image, width_grid: int = SW_SIZE, water_domain: float = SW_DOMAIN, detail_grid: int = 0) -> void:
	assert(width_grid >= 2 and water_domain > 0.0)
	# Production quality tiers match the source: 384/768/1152 with 384 readback.
	# Small grids are deliberately supported only to exercise the identical GPU kernels in tests.
	assert(width_grid < SW_PHYS or width_grid % SW_PHYS == 0)
	_epoch += 1
	_generation += 1
	_disposed = false
	is_ready = false
	size = width_grid
	domain = water_domain
	cell = domain / size
	physics_size = SW_PHYS if size >= SW_PHYS else maxi(2, size / 2)
	detail_domain = domain * 0.5
	detail_size = width_grid if detail_grid <= 0 else detail_grid
	detail_cell = detail_domain / detail_size
	physics_eta.resize(physics_size * physics_size)
	physics_u.resize(physics_size * physics_size)
	physics_v.resize(physics_size * physics_size)
	physics_eta.fill(0.0)
	physics_u.fill(0.0)
	physics_v.fill(0.0)
	_splats.clear()
	_pushes.clear()
	_detail_sources.clear()
	_acc = 0.0
	_clock = 0.0
	_quiet = 0.0
	_calm = 0.0
	_detail_acc = 0.0
	_detail_quiet = 10.0
	_pending_shift = Vector2.ZERO
	_detail_shift = Vector2.ZERO
	_readback_pending = false
	_readback_active_serial = 0
	_readback_started_usec = 0
	_readback_started = 0.0
	_sync_at = -INF
	_readback_landed = -INF
	_async_failed = false
	settled = true
	energy = 0.0
	peak = 0.0
	if depth_image == null:
		_depth.resize(size * size)
		_depth.fill(REST_DEPTH)
		for z in size:
			for x in size:
				if pool_wall_at((x + 0.5) * cell - domain * 0.5, (z + 0.5) * cell - domain * 0.5):
					_depth[x + z * size] = 0.0
	else:
		_depth = _image_depth(depth_image)
	var source_texts: Dictionary = {}
	for shader_name in SHADERS:
		var path: String = "res://shaders/source_water/" + shader_name + ".glsl"
		if FileAccess.file_exists(path):
			source_texts[shader_name] = FileAccess.get_file_as_string(path).replace("#[compute]", "")
		else:
			# Exported PCKs may contain only the imported RDShaderFile, not raw GLSL.
			var imported := load(path) as RDShaderFile
			if imported == null:
				_initialization_failed(_epoch, "Missing source water shader: " + path)
				return
			source_texts[shader_name] = imported.get_spirv()
	_terrain_dirty = false
	_depth_dirty = false
	_detail_dirty = false
	RenderingServer.call_on_render_thread(_rd_configure.bind(_epoch, _depth.to_byte_array(), size, detail_size, physics_size, source_texts))

func _image_depth(image: Image) -> PackedFloat32Array:
	assert(image.get_width() == size and image.get_height() == size, "Depth image must match solver grid, x/z mapped to image x/y.")
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RF)
	return copy.get_data().to_float32_array()

func get_depth_image() -> Image:
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, _depth.to_byte_array())

func detail_active() -> bool:
	return detail_enabled and _detail_quiet < 8.0

## Original quality change: do not flatten live water. Call after configure(),
## before disposing previous. Both callbacks run in order on the global device.
func inherit(previous: SourceWaveSolver) -> void:
	assert(physics_size == previous.physics_size, "Production readback remains 384 at every quality tier.")
	physics_eta = previous.physics_eta.duplicate()
	physics_u = previous.physics_u.duplicate()
	physics_v = previous.physics_v.duplicate()
	_splats.append_array(previous._splats)
	_pushes.append_array(previous._pushes.duplicate(true))
	settled = previous.settled
	_quiet = previous._quiet
	_clock = previous._clock
	energy = previous.energy
	peak = previous.peak
	RenderingServer.call_on_render_thread(_rd_inherit.bind(previous, _epoch, _parameters(SW_STEP)))

func _rd_inherit(previous: SourceWaveSolver, epoch: int, parameters: PackedFloat32Array) -> void:
	if _rd == null or _rd_epoch != epoch or previous._state.is_empty():
		return
	_rd_dispatch("swe_resample", previous._state[previous._current], _source, _state[_current], parameters, int(parameters[0]))

func set_depth_image(image: Image) -> void:
	_depth = _image_depth(image)
	_depth_dirty = true
	_terrain_dirty = true
	_detail_dirty = true
	_generation += 1

## Source buildTerrain: vertical column intersection against boxes, oriented
## boxes, and upright circular pillars. Overhead geometry does not dam water.
## Each collider dictionary has center:Vector3, half:Vector3, optional rotation:Quaternion/radius:float.
func set_terrain(colliders: Array) -> void:
	_depth = build_depth_data(colliders, size, domain)
	_depth_dirty = true
	_terrain_dirty = true
	_detail_dirty = true
	_generation += 1

## Pure source buildTerrain kernel. All inputs and returned pixels belong to the
## caller; no solver, SceneTree, RenderingServer, or shared state is touched.
static func build_depth_data(colliders: Array, width_grid: int, water_domain: float) -> PackedFloat32Array:
	assert(width_grid >= 2 and water_domain > 0.0)
	var size := width_grid
	var domain := water_domain
	var cell := domain / size
	var data := PackedFloat32Array()
	data.resize(size * size)
	data.fill(REST_DEPTH)
	for collider in colliders:
		var center: Vector3 = collider["center"]
		var half: Vector3 = collider["half"]
		var rotation: Quaternion = collider.get("rotation", Quaternion.IDENTITY)
		var rotated: bool = collider.has("rotation")
		var bounds := AABB(-half, half * 2.0)
		bounds = Transform3D(Basis(rotation), center) * bounds
		if bounds.position.y > WATER_LEVEL or bounds.end.y <= POOL_BOTTOM:
			continue
		var ix0 := maxi(0, ceili((bounds.position.x + domain * 0.5) / cell - 0.5))
		var iz0 := maxi(0, ceili((bounds.position.z + domain * 0.5) / cell - 0.5))
		var ix1 := mini(size - 1, floori((bounds.end.x + domain * 0.5) / cell - 0.5))
		var iz1 := mini(size - 1, floori((bounds.end.z + domain * 0.5) / cell - 0.5))
		var inverse := rotation.inverse()
		var direction := inverse * Vector3.DOWN
		for z in range(iz0, iz1 + 1):
			for x in range(ix0, ix1 + 1):
				var wx := (x + 0.5) * cell - domain * 0.5
				var wz := (z + 0.5) * cell - domain * 0.5
				var top := bounds.end.y
				if collider.has("radius") and not rotated:
					if Vector2(wx - center.x, wz - center.z).length_squared() > float(collider["radius"]) ** 2:
						continue
				elif rotated:
					var point := inverse * (Vector3(wx, WATER_LEVEL, wz) - center)
					var near := -INF
					var far := INF
					for axis in 3:
						if absf(direction[axis]) < 1e-8:
							if absf(point[axis]) > half[axis]:
								far = -INF
						else:
							var a := (-half[axis] - point[axis]) / direction[axis]
							var b := (half[axis] - point[axis]) / direction[axis]
							near = maxf(near, minf(a, b))
							far = minf(far, maxf(a, b))
					if near > far or far < 0.0:
						continue
					top = WATER_LEVEL - near
				var d := maxf(0.0, WATER_LEVEL - top)
				data[x + z * size] = minf(data[x + z * size], 0.0 if d < 0.04 else d)
	return data

static func pool_wall_at(x: float, z: float) -> bool:
	var mx := fposmod(x, 32.0)
	var mz := fposmod(z, 32.0)
	return (absf(mx - 16.0) <= 0.3 and minf(mz, 32.0 - mz) >= 4.0) or (absf(mz - 16.0) <= 0.3 and minf(mx, 32.0 - mx) >= 4.0)

func depth_at(position: Variant, z_value: float = NAN) -> float:
	var x: float = position.x if position is Vector2 else float(position)
	var z: float = position.y if position is Vector2 else z_value
	var ix := floori((x + domain * 0.5) / cell)
	var iz := floori((z + domain * 0.5) / cell)
	return _depth[ix + iz * size] if ix >= 0 and iz >= 0 and ix < size and iz < size and not _depth.is_empty() else 0.0

func is_land(position: Variant, z: float = NAN) -> bool:
	return depth_at(position, z) <= 0.0

func queue_impact(x: float, z: float, strength: float) -> void:
	if not _finite([x, z, strength]) or strength <= 0.0 or is_land(x, z):
		return
	_splats.append(Vector4(x, z, minf(0.13, strength * 0.3) * impact_scale, 0.42 + 0.2 * minf(strength, 0.5)))
	_wake()

func impact(x: float, z: float, strength: float) -> void:
	queue_impact(x, z, strength)

func queue_push(x: float, z: float, vx: float, vz: float, sigma: float) -> void:
	if not _finite([x, z, vx, vz, sigma]) or is_land(x, z) or Vector2(vx, vz).length() < 1e-6:
		return
	_pushes.append({"splat": Vector4(x, z, 0.0, clampf(sigma, 0.16, 2.0)), "momentum": Vector2(clampf(vx, -2.0, 2.0), clampf(vz, -2.0, 2.0))})
	_wake()

func push(x: float, z: float, vx: float, vz: float, sigma: float) -> void:
	queue_push(x, z, vx, vz, sigma)

func wake_dipole(x: float, z: float, dx: float, dz: float, speed: float, sigma: float) -> void:
	if not _finite([x, z, dx, dz, speed, sigma]) or speed < 0.05:
		return
	var amp := minf(0.06, 0.008 * speed * speed) * impact_scale
	var r := maxf(0.16, sigma)
	if not is_land(x + dx * r, z + dz * r):
		_splats.append(Vector4(x + dx * r, z + dz * r, amp, r * 0.9))
	if not is_land(x - dx * r, z - dz * r):
		_splats.append(Vector4(x - dx * r, z - dz * r, -amp, r * 0.9))
	_wake()

func queue_detail_impact(x: float, z: float, power: float, radius: float = 0.16) -> void:
	if not _finite([x, z, power, radius]) or absf(x) > detail_domain * 0.5 - 1.0 or absf(z) > detail_domain * 0.5 - 1.0 or power <= 0.0 or _detail_sources.size() >= SOURCE_BATCH:
		return
	_detail_sources.append(Vector4(x, z, minf(0.006, power), maxf(detail_cell * 2.0, radius)))
	_detail_quiet = 0.0

func _wake() -> void:
	settled = false
	_quiet = 0.0
	_calm = 0.0

static func _finite(values: Array) -> bool:
	for v in values:
		if not is_finite(float(v)):
			return false
	return true

func get_state_texture() -> Texture2DRD:
	return state_texture

func get_detail_texture() -> Texture2DRD:
	return detail_texture

func get_depth_texture() -> Texture2DRD:
	return depth_texture

func step(delta: float) -> bool:
	if _disposed or _depth.is_empty():
		return false
	var dt := maxf(0.0, delta) if is_finite(delta) else 0.0
	_clock += dt
	_quiet += dt
	_expire_readback()
	var h := minf(SW_STEP, 0.7 * cell / (sqrt(2.0) * (sqrt(9.81 * wave_speed * (REST_DEPTH + 0.35)) + 2.0)))
	var budget := clampi(max_steps, 1, 8)
	var elapsed := minf(dt, budget * h)
	var count := 0
	var sources: Array[Dictionary] = []
	var reset := false
	if not settled:
		_dropped_time += dt - elapsed
		_acc = minf(_acc + elapsed, budget * h)
		if _acc + 1e-10 >= h:
			for s in _splats:
				sources.append({"splat": s, "momentum": Vector2.ZERO})
			sources.append_array(_pushes)
			_splats.clear()
			_pushes.clear()
			while _acc + 1e-10 >= h and count < budget:
				_acc = maxf(0.0, _acc - h)
				_simulated += h
				count += 1
			_calm = _calm + elapsed if _clock - _readback_landed < 0.5 and peak < 0.0003 and _quiet > 2.0 else 0.0
			if sources.is_empty() and (_calm > 1.0 or _quiet > 22.0):
				reset = true
				physics_eta.fill(0.0)
				physics_u.fill(0.0)
				physics_v.fill(0.0)
				energy = 0.0
				peak = 0.0
				_acc = 0.0
				settled = true
				_generation += 1
	var detail_count := 0
	var detail_reset := false
	var ds: Array[Dictionary] = []
	var was_active := _detail_quiet < 8.0
	if not detail_enabled:
		detail_reset = was_active
		_detail_sources.clear()
		_detail_quiet = 10.0
		_detail_acc = 0.0
	else:
		_detail_quiet += dt
		if _detail_quiet >= 8.0:
			detail_reset = was_active
		else:
			var dbudget := clampi(detail_max_steps, 1, 8)
			_detail_acc = minf(_detail_acc + minf(dt, dbudget * SW_STEP), dbudget * SW_STEP)
			if _detail_acc + 1e-10 >= SW_STEP:
				for s in _detail_sources:
					ds.append({"splat": s, "momentum": Vector2.ZERO})
				_detail_sources.clear()
				while _detail_acc + 1e-10 >= SW_STEP and detail_count < dbudget:
					_detail_acc -= SW_STEP
					detail_count += 1
	var wants_readback := count > 0 and not reset and not _readback_pending and (not _async_failed or _clock - _sync_at >= 1.0 / 30.0)
	if wants_readback:
		_readback_pending = true
		_readback_started = _clock
		_readback_started_usec = Time.get_ticks_usec()
		_readback_serial += 1
		_readback_active_serial = _readback_serial
		if _async_failed:
			_sync_at = _clock
	var params := _parameters(h)
	var frame := {"epoch": _epoch, "generation": _generation, "steps": count, "detail_steps": detail_count, "sources": sources, "detail_sources": ds, "shift": _pending_shift / cell, "detail_shift": _detail_shift, "terrain": _terrain_dirty, "detail_dirty": _detail_dirty, "depth": _depth.to_byte_array() if _depth_dirty else PackedByteArray(), "reset": reset, "detail_reset": detail_reset, "readback": wants_readback, "readback_serial": _readback_active_serial, "readback_started_usec": _readback_started_usec, "sync": _async_failed, "clock": _clock, "params": params}
	_pending_shift = Vector2.ZERO
	_detail_shift = Vector2.ZERO
	_terrain_dirty = false
	_depth_dirty = false
	_detail_dirty = false
	RenderingServer.call_on_render_thread(_rd_frame.bind(frame))
	return count > 0 or detail_count > 0 or bool(frame.terrain) or reset or detail_reset

func _parameters(h: float) -> PackedFloat32Array:
	return PackedFloat32Array([float(size), domain, cell, float(physics_size), h, damping + 1.5 * smoothstep(8.0, 14.0, _quiet), 9.81 * wave_speed, viscosity, foam_gain, foam_decay, foam_diff, foam_splash, 0.0, wall_loss, minf(ring_waves, PI / (2.0 * cell)), 0.0, 0.0, 0.0, detail_domain, detail_cell, minf(detail_frequency, PI / (2.0 * detail_cell)), 0.0, float(detail_size), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

func _rd_configure(epoch: int, depth_bytes: PackedByteArray, grid_size: int, detail_grid: int, phys_size: int, shader_sources: Dictionary) -> void:
	_rd_release()
	_rd = RenderingServer.get_rendering_device()
	_rd_epoch = epoch
	if _rd == null:
		_initialization_failed.call_deferred(epoch, "Source water requires the Forward+/Mobile global RenderingDevice. Headless/Compatibility has no global GPU device.")
		return
	for shader_name in SHADERS:
		var spirv: RDShaderSPIRV
		if shader_sources[shader_name] is RDShaderSPIRV:
			spirv = shader_sources[shader_name]
		else:
			var shader_source := RDShaderSource.new()
			shader_source.source_compute = shader_sources[shader_name]
			spirv = _rd.shader_compile_spirv_from_source(shader_source)
		var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():
			_initialization_failed.call_deferred(epoch, shader_name + ": " + error)
			_rd_release()
			return
		var shader := _rd.shader_create_from_spirv(spirv)
		_shaders[shader_name] = shader
		_pipelines[shader_name] = _rd.compute_pipeline_create(shader)
	for i in 2:
		_state.append(_rd_texture(grid_size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, PackedByteArray(), 8))
		_detail.append(_rd_texture(detail_grid, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, PackedByteArray(), 8))
	_source = _rd_texture(grid_size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, PackedByteArray(), 8)
	_detail_source = _rd_texture(detail_grid, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, PackedByteArray(), 8)
	_physics = _rd_texture(phys_size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, PackedByteArray(), 8)
	_depth_rid = _rd_texture(grid_size, RenderingDevice.DATA_FORMAT_R32_SFLOAT, depth_bytes, 4)
	_source_buffer = _rd.storage_buffer_create(SOURCE_BATCH * 32)
	_owned.append(_source_buffer)
	_current = 0
	_detail_current = 0
	state_texture.texture_rd_rid = _state[_current]
	detail_texture.texture_rd_rid = _detail[_detail_current]
	depth_texture.texture_rd_rid = _depth_rid
	_initialization_ready.call_deferred(epoch)

func _initialization_ready(epoch: int) -> void:
	if epoch != _epoch or _disposed:
		return
	is_ready = true
	last_error = ""
	ready.emit()

func _initialization_failed(epoch: int, reason: String) -> void:
	if epoch != _epoch or _disposed:
		return
	last_error = reason
	is_ready = false
	push_error(reason)
	failed.emit(reason)

func _rd_texture(width: int, format: int, contents: PackedByteArray, bytes_per_pixel: int) -> RID:
	var desc := RDTextureFormat.new()
	desc.width = width
	desc.height = width
	desc.format = format
	desc.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	desc.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var bytes := contents
	if bytes.is_empty():
		bytes.resize(width * width * bytes_per_pixel)
		bytes.fill(0)
	var result := _rd.texture_create(desc, RDTextureView.new(), [bytes])
	_owned.append(result)
	return result

func _rd_set(shader_name: String, input: RID, source: RID, output: RID) -> RID:
	var key := "%s:%s:%s:%s" % [shader_name, input.get_id(), source.get_id(), output.get_id()]
	if _sets.has(key):
		return _sets[key]
	var uniforms: Array[RDUniform] = []
	var resources: Array[RID] = [input, _depth_rid, source, output, _source_buffer]
	for i in 5:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if i == 4 else RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = i
		uniform.add_id(resources[i])
		uniforms.append(uniform)
	var result := _rd.uniform_set_create(uniforms, _shaders[shader_name], 0)
	_sets[key] = result
	return result

func _rd_dispatch(shader_name: String, input: RID, source: RID, output: RID, parameters: PackedFloat32Array, width: int) -> void:
	var compute := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute, _pipelines[shader_name])
	_rd.compute_list_bind_uniform_set(compute, _rd_set(shader_name, input, source, output), 0)
	var bytes := parameters.to_byte_array()
	_rd.compute_list_set_push_constant(compute, bytes, bytes.size())
	_rd.compute_list_dispatch(compute, ceili(width / 8.0), ceili(width / 8.0), 1)
	_rd.compute_list_end()

func _rd_inject(events: Array, detail: bool, parameters: PackedFloat32Array) -> void:
	var target := _detail_source if detail else _source
	_rd.texture_clear(target, Color(0, 0, 0, 0), 0, 1, 0, 1)
	for start in range(0, events.size(), SOURCE_BATCH):
		var count := mini(SOURCE_BATCH, events.size() - start)
		var values := PackedFloat32Array()
		values.resize(SOURCE_BATCH * 8)
		values.fill(0.0)
		for k in count:
			var event: Dictionary = events[start + k]
			var splat: Vector4 = event.splat
			var momentum: Vector2 = event.momentum
			for component in 4:
				values[k * 8 + component] = splat[component]
			values[k * 8 + 4] = momentum.x
			values[k * 8 + 5] = momentum.y
		var bytes := values.to_byte_array()
		_rd.buffer_update(_source_buffer, 0, bytes.size(), bytes)
		var p := parameters.duplicate()
		p[15] = count
		p[21] = 0.0 if start == 0 else 1.0
		_rd_dispatch("detail_source" if detail else "swe_source", _state[_current], target, target, p, int(p[0]))

func _rd_frame(frame: Dictionary) -> void:
	if _rd == null or _rd_epoch != int(frame.epoch) or _state.is_empty():
		return
	var p: PackedFloat32Array = frame.params
	var width := int(p[0])
	var phys_width := int(p[3])
	var detail_width := int(p[22])
	var dp := p.duplicate()
	dp[0] = float(detail_width)
	var depth_bytes: PackedByteArray = frame.depth
	if not depth_bytes.is_empty():
		_rd.texture_update(_depth_rid, 0, depth_bytes)
	var shift: Vector2 = frame.shift
	if bool(frame.terrain) or not shift.is_zero_approx():
		# Math.round from JS (ties toward +infinity), not Godot's away-from-zero round.
		p[16] = floorf(shift.x + 0.5)
		p[17] = floorf(shift.y + 0.5)
		_rd_dispatch("swe_copy", _state[_current], _source, _state[1 - _current], p, width)
		_current = 1 - _current
	var detail_shift: Vector2 = frame.detail_shift
	if bool(frame.detail_dirty) or not detail_shift.is_zero_approx():
		dp[16] = detail_shift.x
		dp[17] = detail_shift.y
		_rd_dispatch("detail_copy", _detail[_detail_current], _detail_source, _detail[1 - _detail_current], dp, detail_width)
		_detail_current = 1 - _detail_current
	p[16] = 0.0
	p[17] = 0.0
	var events: Array = frame.sources
	if int(frame.steps) > 0:
		_rd_inject(events, false, p)
		for index in int(frame.steps):
			p[12] = 1.0 if index == 0 and not events.is_empty() else 0.0
			_rd_dispatch("swe_velocity", _state[_current], _source, _state[1 - _current], p, width)
			_rd_dispatch("swe_height", _state[1 - _current], _source, _state[_current], p, width)
	if bool(frame.reset):
		for texture in _state:
			_rd.texture_clear(texture, Color(0, 0, 0, 0), 0, 1, 0, 1)
	if int(frame.detail_steps) > 0:
		var detail_events: Array = frame.detail_sources
		_rd_inject(detail_events, true, dp)
		for index in int(frame.detail_steps):
			dp[12] = 1.0 if index == 0 and not detail_events.is_empty() else 0.0
			_rd_dispatch("detail_step", _detail[_detail_current], _detail_source, _detail[1 - _detail_current], dp, detail_width)
			_detail_current = 1 - _detail_current
	if bool(frame.detail_reset):
		for texture in _detail:
			_rd.texture_clear(texture, Color(0, 0, 0, 0), 0, 1, 0, 1)
	# Update stable wrappers within this render-thread callback. Other GPU systems
	# queued after step(), e.g. source caustics, can safely resolve these live RIDs.
	state_texture.texture_rd_rid = _state[_current]
	detail_texture.texture_rd_rid = _detail[_detail_current]
	if bool(frame.readback):
		_rd_dispatch("swe_downsample", _state[_current], _source, _physics, p, phys_width)
		var generation: int = frame.generation
		var timestamp: float = frame.clock
		var serial: int = frame.readback_serial
		var requested_usec: int = frame.readback_started_usec
		var transfer_started_usec := Time.get_ticks_usec()
		if bool(frame.sync):
			var bytes := _rd.texture_get_data(_physics, 0)
			_receive_readback.call_deferred(bytes, generation, timestamp, false, serial, requested_usec, transfer_started_usec, Time.get_ticks_usec())
		else:
			var result := _rd.texture_get_data_async(_physics, 0, func(bytes: PackedByteArray) -> void: _receive_readback.call_deferred(bytes, generation, timestamp, true, serial, requested_usec, transfer_started_usec, Time.get_ticks_usec()))
			if result != OK:
				_readback_failed.call_deferred(generation, timestamp, serial)

func _expire_readback() -> void:
	if _readback_pending and _clock - _readback_started > 1.0:
		_readback_pending = false
		_readback_active_serial = 0
		_async_failed = true
		_readback_timeouts += 1

func _readback_failed(_generation_at_request: int, timestamp: float, serial: int = 0) -> void:
	if serial != 0 and serial != _readback_active_serial:
		return
	if timestamp != _readback_started:
		return
	_readback_pending = false
	_readback_active_serial = 0
	# A genuine async transport failure remains a transport failure after a
	# terrain generation change, just as source flushReadback checks failed first.
	if not _disposed:
		_async_failed = true
		_readback_async_errors += 1

func _record_readback_parse(started_usec: int) -> void:
	_readback_parse_ms = (Time.get_ticks_usec() - started_usec) / 1000.0
	_readback_parse_max_ms = maxf(_readback_parse_max_ms, _readback_parse_ms)
	_readback_parse_total_ms += _readback_parse_ms
	_readback_parse_count += 1

static func _readback_channel(decoded: PackedByteArray, width: int, component: int) -> PackedFloat32Array:
	# Shift whole RGBA32F components, then let the native RF converter select R.
	# Padding is only in the discarded channels of the last texel. This is an
	# exact strided copy, not image resampling, averaging or a lower-resolution read.
	var shifted := decoded if component == 0 else decoded.slice(component * 4)
	shifted.resize(decoded.size())
	var image := Image.create_from_data(width, width, false, Image.FORMAT_RGBAF, shifted)
	image.convert(Image.FORMAT_RF)
	return image.get_data().to_float32_array()

func _receive_readback(bytes: PackedByteArray, generation: int, timestamp: float, asynchronous: bool, serial: int = 0, requested_usec: int = 0, transfer_started_usec: int = 0, ready_usec: int = 0) -> void:
	# A completed synchronous API call counts even if a generation change means
	# its pixels are no longer publishable. Rejected payloads still count as reads.
	if not asynchronous:
		_sync_reads += 1
		if ready_usec > 0 and transfer_started_usec > 0:
			_readback_sync_ms = (ready_usec - transfer_started_usec) / 1000.0
	# Production callbacks carry a unique ID. A retired async request must never
	# publish later or clear a newer pending read, including after reconfigure.
	# ID zero is retained for direct CPU parser tests, never used by _rd_frame.
	if serial != 0 and serial != _readback_active_serial:
		_readback_stale += 1
		return
	if timestamp == _readback_started:
		_readback_pending = false
		_readback_active_serial = 0
	if _disposed or generation != _generation:
		_readback_stale += 1
		return
	var started_usec := Time.get_ticks_usec()
	if requested_usec > 0:
		_readback_latency_ms = (started_usec - requested_usec) / 1000.0
		_readback_latency_max_ms = maxf(_readback_latency_max_ms, _readback_latency_ms)
		_readback_rd_queue_ms = (transfer_started_usec - requested_usec) / 1000.0
		_readback_transfer_ms = (ready_usec - transfer_started_usec) / 1000.0
		_readback_delivery_ms = (started_usec - ready_usec) / 1000.0
		if not asynchronous:
			_readback_sync_ms = _readback_transfer_ms
	# Like the source, counts describe landed reads, even if parsing rejects them.
	if asynchronous:
		_async_lands += 1
	readback_bytes += bytes.size()
	_readback_convert_ms = 0.0
	_readback_validate_reduce_ms = 0.0
	_readback_pack_ms = 0.0
	_readback_native_ms = 0.0
	_readback_parser_backend = "gdscript"
	if bytes.size() != physics_size * physics_size * 8:
		_rejected += 1
		_record_readback_parse(started_usec)
		return
	if native_readback_enabled and _native_readback_parser == null and ClassDB.class_exists("SourceWaterReadback"):
		_native_readback_parser = ClassDB.instantiate("SourceWaterReadback") as RefCounted
	var next_eta: PackedFloat32Array
	var next_u: PackedFloat32Array
	var next_v: PackedFloat32Array
	var next_energy := 0.0
	var next_peak := 0.0
	if native_readback_enabled and _native_readback_parser != null:
		var native_started := Time.get_ticks_usec()
		# One strict ordered binary64 pass, not a parallel/reassociated reduction.
		# Native arrays are private until all half channels and sentinels validate.
		var parsed: Array = _native_readback_parser.parse_rgba16f(bytes, physics_size, REST_DEPTH)
		_readback_native_ms = (Time.get_ticks_usec() - native_started) / 1000.0
		_readback_parser_backend = "native_exact"
		if parsed.size() != 5:
			_rejected += 1
			_record_readback_parse(started_usec)
			return
		next_eta = parsed[0]
		next_u = parsed[1]
		next_v = parsed[2]
		next_energy = parsed[3]
		next_peak = parsed[4]
	else:
		# Standard-engine fallback: unchanged native Image half conversion,
		# original ordered GDScript reductions and exact channel extraction.
		var image := Image.create_from_data(physics_size, physics_size, false, Image.FORMAT_RGBAH, bytes)
		image.convert(Image.FORMAT_RGBAF)
		var decoded := image.get_data()
		var values := decoded.to_vector4_array()
		var converted_usec := Time.get_ticks_usec()
		_readback_convert_ms = (converted_usec - started_usec) / 1000.0
		var total := 0.0
		var maximum := 0.0
		for value in values:
			if value.w != 1.0 or not value.is_finite():
				_rejected += 1
				_readback_validate_reduce_ms = (Time.get_ticks_usec() - converted_usec) / 1000.0
				_record_readback_parse(started_usec)
				return
			var h := value.x
			var u := value.y
			var v := value.z
			total += h * h + (u * u + v * v) * REST_DEPTH / 9.81
			maximum = maxf(maximum, maxf(absf(h), maxf(absf(u) * 0.1, absf(v) * 0.1)))
		var validated_usec := Time.get_ticks_usec()
		_readback_validate_reduce_ms = (validated_usec - converted_usec) / 1000.0
		next_eta = _readback_channel(decoded, physics_size, 0)
		next_u = _readback_channel(decoded, physics_size, 1)
		next_v = _readback_channel(decoded, physics_size, 2)
		next_energy = total / next_eta.size()
		next_peak = maximum
		_readback_pack_ms = (Time.get_ticks_usec() - validated_usec) / 1000.0
	# No public field changes until all texels validate and all fields exist.
	var publication_started := Time.get_ticks_usec()
	physics_eta = next_eta
	physics_u = next_u
	physics_v = next_v
	energy = next_energy
	peak = next_peak
	_readback_landed = _clock
	_readback_publishes += 1
	_readback_pack_ms += (Time.get_ticks_usec() - publication_started) / 1000.0
	_record_readback_parse(started_usec)
	physics_updated.emit()

func _sample(field: PackedFloat32Array, x: float, z: float) -> float:
	if is_land(x, z):
		return 0.0
	var physics_cell := domain / physics_size
	var gx := (x + domain * 0.5) / physics_cell - 0.5
	var gz := (z + domain * 0.5) / physics_cell - 0.5
	var ix := clampi(floori(gx), 0, physics_size - 2)
	var iz := clampi(floori(gz), 0, physics_size - 2)
	var fx := clampf(gx - ix, 0.0, 1.0)
	var fz := clampf(gz - iz, 0.0, 1.0)
	var i := ix + iz * physics_size
	return lerpf(lerpf(field[i], field[i + 1], fx), lerpf(field[i + physics_size], field[i + physics_size + 1], fx), fz)

func height_at(position: Variant, z_value: float = NAN) -> float:
	var x: float = position.x if position is Vector2 else float(position)
	var z: float = position.y if position is Vector2 else z_value
	return _sample(physics_eta, x, z)

func flow_at(position: Variant, z_value: float = NAN) -> Vector2:
	var x: float = position.x if position is Vector2 else float(position)
	var z: float = position.y if position is Vector2 else z_value
	return Vector2(_sample(physics_u, x, z), _sample(physics_v, x, z))

func slope_at(position: Variant, z_or_radius: float = 0.38, probe_radius: float = 0.38) -> Vector4:
	var x: float = position.x if position is Vector2 else float(position)
	var z: float = position.y if position is Vector2 else z_or_radius
	var radius: float = z_or_radius if position is Vector2 else probe_radius
	if is_land(x, z) or is_land(x - radius, z) or is_land(x + radius, z) or is_land(x, z - radius) or is_land(x, z + radius):
		return Vector4.ZERO
	var slope_x := (_sample(physics_eta, x + radius, z) - _sample(physics_eta, x - radius, z)) / (2.0 * radius)
	var slope_z := (_sample(physics_eta, x, z + radius) - _sample(physics_eta, x, z - radius)) / (2.0 * radius)
	var eta := _sample(physics_eta, x, z)
	var acceleration := (Vector2(slope_x, slope_z) * -9.81).limit_length(3.0)
	var drift := (flow_at(x, z) * eta * 110.0).limit_length(1.5)
	return Vector4(acceleration.x, acceleration.y, drift.x, drift.y)

func rebase(dx: float, dz: float) -> void:
	if dx == 0.0 and dz == 0.0:
		return
	_pending_shift += Vector2(dx, dz)
	_detail_shift += Vector2(dx, dz) / detail_cell
	_generation += 1
	for i in _splats.size():
		_splats[i].x -= dx
		_splats[i].y -= dz
	for event in _pushes:
		var splat: Vector4 = event.splat
		splat.x -= dx
		splat.y -= dz
		event.splat = splat
	for i in _detail_sources.size():
		_detail_sources[i].x -= dx
		_detail_sources[i].y -= dz
	var sx := floori(dx / (domain / physics_size) + 0.5)
	var sz := floori(dz / (domain / physics_size) + 0.5)
	physics_eta = _shift_field(physics_eta, sx, sz)
	physics_u = _shift_field(physics_u, sx, sz)
	physics_v = _shift_field(physics_v, sx, sz)

func _shift_field(field: PackedFloat32Array, sx: int, sz: int) -> PackedFloat32Array:
	# The original integer shift/zero-fill, copied with the native RF image
	# blitter instead of three 384² interpreted element loops on every door.
	# No filtering, conversion, interpolation or simulation math is involved.
	var target:=Image.create(physics_size,physics_size,false,Image.FORMAT_RF)
	target.fill(Color(0,0,0,0))
	if absi(sx)<physics_size and absi(sz)<physics_size and field.size()==physics_size*physics_size:
		var source:=Image.create_from_data(physics_size,physics_size,false,Image.FORMAT_RF,field.to_byte_array())
		var area:=Rect2i(maxi(0,sx),maxi(0,sz),physics_size-absi(sx),physics_size-absi(sz))
		target.blit_rect(source,area,Vector2i(maxi(0,-sx),maxi(0,-sz)))
	return target.get_data().to_float32_array()

static func crest_power(eta: float, u: float, v: float, divergence: float, depth: float, gravity: float, curvature: float = 1.0) -> float:
	if not _finite([eta, u, v, divergence, depth, gravity, curvature]) or depth <= 0.0 or gravity <= 0.0 or eta < 0.015:
		return 0.0
	var speed := Vector2(u, v).length()
	var critical := sqrt(gravity * maxf(depth, 0.05))
	var kinetic := smoothstep(0.16, 1.44, speed * speed)
	var trapped := smoothstep(1.8, 4.0, -divergence)
	var crest := smoothstep(0.65, 1.25, speed / critical) * smoothstep(0.08, 0.8, curvature)
	return kinetic * maxf(trapped, crest) * smoothstep(0.015, 0.045, eta)

static func crest_foam_power(eta: float, u: float, v: float, curvature: float) -> float:
	if not _finite([eta, u, v, curvature]):
		return 0.0
	return smoothstep(0.008, 0.05, eta) * smoothstep(0.0025, 0.09, u * u + v * v) * smoothstep(0.035, 0.45, curvature)

func debug() -> Dictionary:
	return {
		"grid": size, "cell": cell, "clock": _clock, "simulated": _simulated,
		"dropped_time": _dropped_time, "landed": _readback_landed,
		"pending": _readback_pending,
		"pending_ms": (Time.get_ticks_usec() - _readback_started_usec) / 1000.0 if _readback_pending and _readback_started_usec > 0 else 0.0,
		"async_failed": _async_failed, "readback_bytes": readback_bytes,
		"readback_timeouts": _readback_timeouts, "readback_async_errors": _readback_async_errors,
		"readback_stale": _readback_stale, "readback_publishes": _readback_publishes,
		"readback_parse_count": _readback_parse_count, "readback_parse_ms": _readback_parse_ms,
		"readback_parse_max_ms": _readback_parse_max_ms, "readback_parse_total_ms": _readback_parse_total_ms,
		"readback_convert_ms": _readback_convert_ms,
		"readback_validate_reduce_ms": _readback_validate_reduce_ms,
		"readback_pack_ms": _readback_pack_ms,
		"readback_native_ms": _readback_native_ms, "readback_parser_backend": _readback_parser_backend,
		"native_readback_enabled": native_readback_enabled, "native_readback_available": ClassDB.class_exists("SourceWaterReadback"),
		"readback_latency_ms": _readback_latency_ms, "readback_latency_max_ms": _readback_latency_max_ms,
		"readback_rd_queue_ms": _readback_rd_queue_ms, "readback_transfer_ms": _readback_transfer_ms,
		"readback_delivery_ms": _readback_delivery_ms, "readback_sync_ms": _readback_sync_ms,
		"energy": energy, "peak": peak, "settled": settled,
		"async_lands": _async_lands, "sync_reads": _sync_reads, "rejected": _rejected,
		"pending_splats": _splats.size(), "pending_pushes": _pushes.size(),
		"ready": is_ready, "error": last_error,
	}

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	is_ready = false
	_generation += 1
	_epoch += 1
	_readback_pending = false
	_readback_active_serial = 0
	_splats.clear()
	_pushes.clear()
	_detail_sources.clear()
	RenderingServer.call_on_render_thread(_rd_release)

func _rd_release() -> void:
	# Detach high-level wrappers BEFORE freeing their RD resources.
	state_texture.texture_rd_rid = RID()
	detail_texture.texture_rd_rid = RID()
	depth_texture.texture_rd_rid = RID()
	if _rd != null:
		for rid in _sets.values():
			if _rd.uniform_set_is_valid(rid):
				_rd.free_rid(rid)
		for rid in _pipelines.values():
			if rid.is_valid():
				_rd.free_rid(rid)
		for rid in _shaders.values():
			if rid.is_valid():
				_rd.free_rid(rid)
		for rid in _owned:
			if rid.is_valid():
				_rd.free_rid(rid)
	_sets.clear()
	_pipelines.clear()
	_shaders.clear()
	_owned.clear()
	_state.clear()
	_detail.clear()
	_rd = null
	_rd_epoch = -1
