class_name SourceWhitewaterParticles
extends RefCounted
## Direct SplashParticles host port from poolcore@66a4543. MPM is the ONLY spray
## source. State scalars stay double precision; instance buffers are float32.
signal return_ripple(position: Vector2, strength: float)
const MAX_PARTICLES := 1024
# PC host timing only. Source drag, gravity, buoyancy, contact search and cap
# remain unchanged. The original variable-delta host is kept for mobile/A-B.
const PC_STEP := 1.0 / 60.0
const PC_MAX_STEPS := 6
const PC_BACKLOG_LIMIT := 0.25
var independent_scheduling := not OS.has_feature("mobile") and not OS.get_cmdline_user_args().has("--source-whitewater-original-scheduling")
var _elapsed := 0.0
var _simulated_seconds := 0.0
var _discarded_seconds := 0.0
var _steps_last_frame := 0
var _host_ms_last_frame := 0.0
var _presentation_alpha := 1.0
const Liquid := preload("res://scripts/water/source_port/source_liquid_mpm.gd")
var ripples := 0
var drop_count := 0
var bubble_count := 0
var drop_rows := PackedFloat32Array()
var submerged_mesh := MultiMeshInstance3D.new()
var drop_mesh: ArrayMesh
var parts: Array[Dictionary] = []
var _surface: Callable
var _depth: Callable
var _flow: Callable
var _initialized := false
var _bubble_rows := PackedFloat32Array()

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	drop_mesh = Liquid.sphere_geometry(12, 8)
	var bubbles := MultiMesh.new()
	bubbles.transform_format = MultiMesh.TRANSFORM_3D
	# Three sphere triangles are CCW; high-level Godot meshes use clockwise
	# front faces. Reverse indices only for this native material mesh, retaining
	# the original positions/normals and source single-front-face rendering.
	var source_mesh := Liquid.sphere_geometry(8, 6)
	var arrays := source_mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for triangle in range(0,indices.size(),3):
		var second := indices[triangle+1]
		indices[triangle+1]=indices[triangle+2]
		indices[triangle+2]=second
	arrays[Mesh.ARRAY_INDEX]=indices
	var native_mesh := ArrayMesh.new()
	native_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	bubbles.mesh = native_mesh
	bubbles.instance_count = MAX_PARTICLES
	bubbles.visible_instance_count = 0
	_bubble_rows.resize(MAX_PARTICLES * 12)
	_bubble_rows.fill(0.0)
	submerged_mesh.multimesh = bubbles
	submerged_mesh.name = "Original entrained air"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c6e5e6")
	material.albedo_color.a = 0.26
	material.roughness = 0.1
	material.metallic = 0.0
	# Godot dielectric F0 = .16 * specular^2; retain source IOR 1.333.
	material.metallic_specular = ((1.333-1.0)/(1.333+1.0))/0.4
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = -1
	material.cull_mode = BaseMaterial3D.CULL_BACK
	# Godot owns native lighting of submerged bubbles; the source's captured
	# transparent order is preserved by attaching this mesh before base water.
	submerged_mesh.material_override = material
	submerged_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	submerged_mesh.extra_cull_margin = 1000.0

func configure(surface_at: Callable, depth_at: Callable, flow_at: Callable = Callable()) -> void:
	_surface = surface_at
	_depth = depth_at
	_flow = flow_at
	initialize()

func _add(p: Dictionary) -> void:
	if parts.size() >= MAX_PARTICLES:
		parts.pop_front()
	parts.append(p)

func release(position: Vector3, velocity: Vector3, size: float) -> void:
	release_values(position.x, position.y, position.z, velocity.x, velocity.y, velocity.z, size)

func release_values(x: float, y: float, z: float, vx: float, vy: float, vz: float, size: float) -> void:
	for value in [x, y, z, vx, vy, vz, size]:
		if not is_finite(value):
			return
	if size <= 0.0:
		return
	_add({"x":x,"y":y,"z":z,"vx":vx,"vy":vy,"vz":vz,"size":minf(0.025,size),"life":0.0,"max":2.0,"kind":0,"seed":x*7.0+z*13.0})

func bubbles(x: float, y: float, z: float, count: int, flow: Dictionary = {"u":0.0,"v":0.0}) -> void:
	for value in [x, y, z, float(count), float(flow.get("u",0.0)), float(flow.get("v",0.0))]:
		if not is_finite(value):
			return
	for _i in mini(96, count):
		var angle := randf()*TAU
		var radius := sqrt(randf())*0.18
		_add({"x":x+cos(angle)*radius,"y":y-0.04-randf()*0.28,"z":z+sin(angle)*radius,
			"vx":float(flow.get("u",0.0)),"vy":-0.05-randf()*0.18,"vz":float(flow.get("v",0.0)),
			"life":0.0,"max":3.0,"kind":1,"seed":randf()*7.0,"size":0.004+0.01*randf()})

func frame(delta: float) -> void:
	if not _surface.is_valid():
		return
	var started := Time.get_ticks_usec()
	var supplied := maxf(0.0,delta) if is_finite(delta) else 0.0
	_steps_last_frame = 0
	if independent_scheduling:
		if parts.is_empty():
			# Never charge newly emitted drops for an earlier empty interval.
			_elapsed = 0.0
		elif supplied > 0.0:
			var accumulated := _elapsed + supplied
			var discarded := maxf(0.0,accumulated-PC_BACKLOG_LIMIT)
			_discarded_seconds += discarded
			_elapsed = minf(accumulated,PC_BACKLOG_LIMIT)
			var steps := mini(PC_MAX_STEPS,floori((_elapsed+1e-12)/PC_STEP))
			var interval := _elapsed
			# The sampler exposes only the latest SWE field. Split the existing
			# per-particle old->current surface interval across catch-up steps;
			# otherwise the first step mistakes a whole frame's rise for 1/60 s.
			# A local vertical offset preserves the current field's spatial shape.
			# No earlier field or time-varying flow is invented. At ordinary 60 Hz
			# there is one complete step, so no extra surface samples are needed.
			var interpolate_surface := steps > 0 and (steps > 1 or interval > PC_STEP+1e-12)
			if interpolate_surface or discarded > 0.0:
				for p in parts:
					var offset := 0.0
					if p.has("surface"):
						var latest := float(_surface.call(float(p.x),float(p.z)))
						if discarded > 0.0:
							# A discarded pause has no recoverable time history. Re-anchor
							# to the latest field rather than manufacture a rise impulse.
							p.surface = latest
						else:
							offset = float(p.surface)-latest
					p._pc_surface_offset = offset
			for step in steps:
				var fraction := minf(1.0,float(step+1)*PC_STEP/interval) if interpolate_surface else 1.0
				_step_particles(PC_STEP,fraction,step==steps-1)
				_elapsed = maxf(0.0,_elapsed-PC_STEP)
				_simulated_seconds += PC_STEP
				_steps_last_frame += 1
				if parts.is_empty():
					_elapsed = 0.0
					break
		# Standard previous/current interpolation avoids 60 Hz stair steps on
		# 120+ Hz displays. It changes presentation only, at up to one tick lag.
		_presentation_alpha = clampf(_elapsed/PC_STEP,0.0,1.0)
	else:
		var dt := minf(supplied,0.05)
		_step_particles(dt)
		_simulated_seconds += dt
		_discarded_seconds += supplied-dt
		_steps_last_frame = 1
		_presentation_alpha = 1.0
	# Generate/upload visual rows only once, not once per catch-up substep.
	_update_geometry()
	_host_ms_last_frame = float(Time.get_ticks_usec()-started)/1000.0

func _step_particles(dt: float, surface_fraction: float = 1.0, remember_previous: bool = false) -> void:
	# Original host compacts its existing array; do not allocate a second
	# dictionary list every frame. Drag is common to every particle this step.
	var write := 0
	var air_drag := exp(-dt * 0.45)
	var water_drag := 1.0 - exp(-dt * 5.0)
	var buoyancy := 1.0 - exp(-dt * 4.0)
	for p in parts:
		p.life = float(p.life)+dt
		if float(p.life)>float(p.max):
			continue
		var ox := float(p.x)
		var oy := float(p.y)
		var oz := float(p.z)
		if remember_previous:
			p._pc_render_previous = Vector3(ox,oy,oz)
		var surface_offset := float(p.get("_pc_surface_offset",0.0))*(1.0-surface_fraction) if surface_fraction < 1.0 else 0.0
		if int(p.kind)==0:
			p.vy = float(p.vy)-9.81*dt
			p.vx = float(p.vx)*air_drag
			p.vz = float(p.vz)*air_drag
		else:
			var current: Variant = _flow.call(float(p.x),float(p.z)) if _flow.is_valid() else {"u":0.0,"v":0.0}
			var u := float(current.x) if current is Vector2 else float(current.get("u",0.0))
			var v := float(current.y) if current is Vector2 else float(current.get("v",0.0))
			p.vx = float(p.vx)+(u-float(p.vx))*water_drag
			p.vz = float(p.vz)+(v-float(p.vz))*water_drag
			if int(p.kind)==1:
				p.vy = float(p.vy)+(0.24-float(p.vy))*buoyancy
		p.x = float(p.x)+float(p.vx)*dt
		p.z = float(p.z)+float(p.vz)*dt
		if _depth.is_valid() and float(_depth.call(float(p.x),float(p.z)))<=0.0:
			p.x=ox
			p.z=oz
			p.vx=float(p.vx)*0.1
			p.vz=float(p.vz)*0.1
			if float(_depth.call(ox,oz))<=0.0:
				continue
		var surface := float(_surface.call(float(p.x),float(p.z)))+surface_offset
		p.y=float(p.y)+float(p.vy)*dt
		if int(p.kind)==0 and float(p.y)-float(p.size)*0.5<=surface and (float(p.vy)<0.0 or oy-float(p.size)*0.5>(float(p.surface) if p.has("surface") else float(_surface.call(ox,oz))+surface_offset)):
			var start_now := float(_surface.call(ox,oz))+surface_offset
			var previous := float(p.get("surface",start_now))
			var lo := 0.0
			var hi := 1.0
			for _j in 7:
				var t := (lo+hi)*0.5
				var x := ox+(float(p.x)-ox)*t
				var z := oz+(float(p.z)-oz)*t
				var height := float(_surface.call(x,z))+surface_offset+(previous-start_now)*(1.0-t)
				if oy+(float(p.y)-oy)*t-float(p.size)*0.5>height:
					lo=t
				else:
					hi=t
			var t := (lo+hi)*0.5
			var rise := (surface-previous)/dt if dt>0.0 else 0.0
			var strength := minf(0.0025,maxf(0.000025,220.0*float(p.size)*float(p.size)*float(p.size)*maxf(0.1,rise-float(p.vy))))
			return_ripple.emit(Vector2(ox+(float(p.x)-ox)*t,oz+(float(p.z)-oz)*t),strength)
			ripples+=1
			continue
		if int(p.kind)==1 and float(p.y)>=surface-0.006:
			return_ripple.emit(Vector2(float(p.x),float(p.z)),0.0001)
			ripples+=1
			continue
		p.surface=surface
		parts[write] = p
		write += 1
	parts.resize(write)

func _update_geometry() -> void:
	drop_count=0
	bubble_count=0
	var rows := PackedFloat32Array()
	rows.resize(parts.size()*12)
	var show_previous := independent_scheduling and _presentation_alpha < 1.0
	var blend_previous := show_previous and _presentation_alpha > 1e-12
	for p in parts:
		var position: Vector3
		if show_previous and p.has("_pc_render_previous"):
			position = p._pc_render_previous
			if blend_previous:
				position = position.lerp(Vector3(float(p.x),float(p.y),float(p.z)),_presentation_alpha)
		else:
			position = Vector3(float(p.x),float(p.y),float(p.z))
		var radius := float(p.size)*0.5
		var basis := Basis.IDENTITY
		if int(p.kind)==0:
			var velocity := Vector3(float(p.vx),float(p.vy),float(p.vz))
			var speed := sqrt(float(p.vx)**2+float(p.vy)**2+float(p.vz)**2)
			var stretch := 1.0+minf(0.65,speed*speed*0.045)*(0.8+0.2*sin(float(p.life)*32.0+float(p.seed)))
			if speed>0.001:
				basis=Basis(Quaternion(Vector3.UP,velocity.normalized()))
			basis=basis.scaled_local(Vector3(radius/sqrt(stretch),radius*stretch,radius/sqrt(stretch)))
			var k := drop_count*12
			rows[k]=basis.x.x
			rows[k+1]=basis.y.x
			rows[k+2]=basis.z.x
			rows[k+4]=basis.x.y
			rows[k+5]=basis.y.y
			rows[k+6]=basis.z.y
			rows[k+8]=basis.x.z
			rows[k+9]=basis.y.z
			rows[k+10]=basis.z.z
			rows[k+3]=position.x
			rows[k+7]=position.y
			rows[k+11]=position.z
			drop_count+=1
		else:
			if _initialized:
				# One native upload, rather than up to 1,024 setter/renderer calls.
				# MultiMesh expects the same row-major 3x4 matrix as the drop pass.
				var k := bubble_count*12
				_bubble_rows[k]=radius
				_bubble_rows[k+5]=radius
				_bubble_rows[k+10]=radius
				_bubble_rows[k+3]=position.x
				_bubble_rows[k+7]=position.y
				_bubble_rows[k+11]=position.z
			bubble_count+=1
	rows.resize(drop_count*12)
	drop_rows=rows
	if _initialized:
		if bubble_count>0:
			submerged_mesh.multimesh.buffer=_bubble_rows
		submerged_mesh.multimesh.visible_instance_count=bubble_count

func rebase(shift: Vector3) -> void:
	for p in parts:
		p.x=float(p.x)-shift.x
		p.y=float(p.y)-shift.y
		p.z=float(p.z)-shift.z
		if p.has("surface"):
			p.surface=float(p.surface)-shift.y
		if p.has("_pc_render_previous"):
			p._pc_render_previous=Vector3(p._pc_render_previous)-shift

func stats() -> Dictionary:
	var spray := 0
	var air := 0
	for p in parts:
		if int(p.kind)==0:
			spray+=1
		else:
			air+=1
	return {"spray":spray,"bubbles":air,"ripples":ripples,
		"scheduling":{"mode":"fixed_pc" if independent_scheduling else "original",
		"stepSeconds":PC_STEP if independent_scheduling else 0.0,"maxStepsPerFrame":PC_MAX_STEPS,
		"stepsLastFrame":_steps_last_frame,"backlogSeconds":_elapsed,
		"simulatedSeconds":_simulated_seconds,"discardedSeconds":_discarded_seconds,
		"hostMsLastFrame":_host_ms_last_frame,"presentationAlpha":_presentation_alpha,
		"presentationMaxLagSeconds":PC_STEP if independent_scheduling else 0.0}}

func dispose() -> void:
	_elapsed = 0.0
	parts.clear()
	drop_rows.clear()
	_bubble_rows.clear()
	drop_count=0
	bubble_count=0
	if is_instance_valid(submerged_mesh):
		submerged_mesh.queue_free()
