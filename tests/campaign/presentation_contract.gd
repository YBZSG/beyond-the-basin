extends SceneTree
const Transition = preload("res://scripts/campaign/campaign_transition.gd")
const Corruption = preload("res://scripts/campaign/campaign_corruption.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var original := Camera3D.new(); world.add_child(original); original.make_current()
	for mode in range(6):
		var transition := Transition.new(); transition.configure(mode); transition.position = Vector3(8192,0,8192); world.add_child(transition)
		check(root.get_camera_3d() == original, "build does not steal camera")
		transition.activate_camera()
		check(root.get_camera_3d() == transition.camera, "explicit activation")
		var meshes := transition.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 10, "contained detailed geometry %d" % mode)
		for mesh: MeshInstance3D in meshes:
			check(mesh.mesh.get_aabb().size.is_finite() and mesh.mesh.get_aabb().size.length() < 30.0, "finite geometry")
			check(mesh.layers == Transition.STAGE_LAYER, "isolated cinematic layer")
			var finish := mesh.material_override as StandardMaterial3D
			if finish.albedo_texture != null:
				check(finish.normal_enabled and finish.uv1_world_triplanar, "mapped PBR world repeat")
				check(float(finish.get_meta("campaign_repeat_metres",0)) >= 0.25, "no texture stretched to object bounds")
				check(finish.roughness_texture != null and finish.normal_texture != null, "complete existing PBR maps")
		for sample in range(101):
			transition._sample(float(sample)/100.0)
			check(transition.camera.position.is_finite() and transition.camera.position.length() < 20.0, "bounded trajectory")
			for mesh: MeshInstance3D in meshes:
				var relative: Vector3 = mesh.global_transform.affine_inverse() * transition.camera.global_position
				check(not mesh.mesh.get_aabb().grow(0.06).has_point(relative), "camera clearance mode %d frame %d mesh %s" % [mode,sample,mesh.name])
		for progress in [0.0,0.55,1.0]:
			transition._sample(progress)
			for y in [-1.0,0.0,1.0]:
				for x in [-1.0,-0.5,0.0,0.5,1.0]:
					var ray: Vector3 = transition.camera.global_basis * Vector3(x*tan(deg_to_rad(34.0))*16.0/9.0,y*tan(deg_to_rad(34.0)),-1.0).normalized()
					var occluded := false
					for mesh: MeshInstance3D in meshes:
						var inverse := mesh.global_transform.affine_inverse()
						var hit: Variant = mesh.mesh.get_aabb().intersects_ray(inverse*transition.camera.global_position,inverse.basis*ray)
						if hit != null and (mesh.global_transform*hit).distance_to(transition.camera.global_position) < transition.camera.far: occluded = true; break
					check(occluded, "no void exposed mode %d progress %s" % [mode,progress])
		transition.play()
		await process_frame
		check(not transition.request_skip(), "no skip before safe handoff")
		transition.set_safe_to_skip(true)
		check(transition.request_skip(), "skip when safe")
		await process_frame
		check(not transition._playing, "skip resolves async play")
		transition.release_camera()
		check(root.get_camera_3d() == original, "release restores camera")
		transition.play()
		await process_frame
		transition.cancel()
		await process_frame
		check(root.get_camera_3d() == original, "cancel restores camera")
		transition.reduced_effects = true
		transition._sample(0); var point: Vector3 = transition.camera.position
		transition._sample(1)
		check(point.is_equal_approx(transition.camera.position), "reduced motion fixed camera")
		transition.play()
		await process_frame
		transition.queue_free()
		await process_frame
		check(root.get_camera_3d() == original, "scene free restores camera")
	var natural := Transition.new(); natural.reduced_effects = true; world.add_child(natural)
	natural.play()
	await process_frame
	paused = true
	var paused_position: Vector3 = natural.camera.position
	await process_frame; await process_frame; await process_frame
	check(natural.camera.position == paused_position, "paused scene consumes no transition time")
	paused = false
	natural.cancel()
	await process_frame
	await natural.play()
	check(not natural._playing, "natural async completion")
	check(root.get_camera_3d() == natural.camera, "completion holds camera for black handoff")
	natural.release_camera(); natural.queue_free(); await process_frame
	# A newly installed world camera must not be stolen by a stale vignette.
	var old := Transition.new(); world.add_child(old); old.activate_camera()
	var replacement := Camera3D.new(); world.add_child(replacement); replacement.make_current()
	old.queue_free(); await process_frame
	check(root.get_camera_3d() == replacement, "new camera ownership preserved")
	var lamps: Array[OmniLight3D] = []
	for index in range(8):
		var light := OmniLight3D.new(); light.light_color = Color(0.9,0.8,0.7); light.light_energy = 2.75; world.add_child(light); lamps.append(light)
	lamps[0].set_meta("campaign_preserve_light", true)
	var corruption := Corruption.new()
	for frame in range(1500): corruption.apply(world,1.0,0.1)
	check(corruption.displayed_severity == 1.0, "slow escalation reaches bound")
	check(lamps[0].light_color == Color(0.9,0.8,0.7) and lamps[0].light_energy == 2.75, "safety lamp preserved")
	for light in lamps:
		check(light.light_energy >= 2.75*0.16 and light.light_energy <= 2.75, "bounded light power")
	var elapsed: float = corruption._elapsed
	corruption.apply(world,1.0,0.0)
	check(corruption._elapsed == elapsed, "no time consumed while paused")
	corruption.reset()
	for light in lamps: check(light.light_color == Color(0.9,0.8,0.7) and light.light_energy == 2.75, "exact authored light restoration")
	corruption.reduced_effects = true
	for frame in range(1500): corruption.apply(world,1.0,0.1)
	for light in lamps: check(light.light_energy >= 2.75*0.91, "reduced effects no outage")
	var other := Node3D.new(); root.add_child(other); corruption.apply(other,0.5,0.1)
	for light in lamps: check(light.light_energy == 2.75, "world replacement restores")
	corruption.reset()
	var streamed := OmniLight3D.new(); streamed.light_energy = 1.25; other.add_child(streamed)
	corruption.apply(other, 0.8, 0.1)
	streamed.free()
	corruption.apply(other, 0.8, 0.1)
	corruption.apply(other, NAN, INF)
	check(corruption.displayed_severity == 0.0, "nonfinite input safely reset")
	corruption.reset(); other.free(); world.free()
	print("CAMPAIGN_PRESENTATION_CONTRACT ", "PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
