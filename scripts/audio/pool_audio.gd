class_name NativePoolAudio
extends Node3D
## Source recordings with separate, bounded first-person gait and water voices.
## Water simulation remains source-exact; this node only observes player motion.
signal footstep_started(clip_name: String, gain: float, pitch: float)

const CLIP_NAMES := ["ambience", "drop_1", "drop_2", "drop_3", "drop_light", "drop_heavy", "step_swish", "step_stir", "step_dry_1", "step_dry_2", "step_run", "duck_pickup", "duck_hit", "egg_hit", "tap", "stir", "wade"]
const GAIT_CLIPS := ["tile_walk_1", "tile_walk_2", "tile_run", "step_swish_loop", "step_stir_loop"]
const FOOTSTEP_BUS := &"Footsteps"
const SILENT_DB := -80.0
const MIN_FOOTSTEP_INTERVAL := 0.16
var clips: Dictionary = {}
var ambience: AudioStreamPlayer
var wade: AudioStreamPlayer
var swish: AudioStreamPlayer
var footstep: AudioStreamPlayer
var enabled := true
var ambience_enabled := true
var active := false
var previous_drop := -1
var previous_dry := false
var voices: Array[AudioStreamPlayer3D] = []
var _wade_level := SILENT_DB
var _wading := false
var _player: CharacterBody3D
var _water: Node
var _previous_position := Vector3.ZERO
var _have_position := false
var _clock := 0.0
var _last_footstep_time := -10.0
var _last_footstep_frame := -1
var _footstep_events := 0
var _rejected_steps := 0
var _last_footstep_clip := ""
var _last_motion_speed := 0.0

func _ready() -> void:
	# Sample AFTER player movement, rather than desired input velocity.
	process_physics_priority = 100
	for clip_name in CLIP_NAMES:
		var path := "res://assets/sfx/%s.ogg" % clip_name
		if ResourceLoader.exists(path):
			clips[clip_name] = load(path)
	for clip_name in GAIT_CLIPS:
		var path := "res://assets/sfx/native_gait/%s.wav" % clip_name
		if ResourceLoader.exists(path):
			clips[clip_name] = load(path)
	_ensure_footstep_bus()
	ambience = _new_player(&"Ambience", -18.0)
	_start_loop(ambience, "ambience")
	wade = _new_player(&"Pool", SILENT_DB)
	_start_loop(wade, "step_stir_loop")
	swish = _new_player(&"Pool", SILENT_DB)
	_start_loop(swish, "step_swish_loop")
	footstep = _new_player(FOOTSTEP_BUS, SILENT_DB)
	# One contact voice, not 24 accumulating spatial/reverberant voices.
	footstep.max_polyphony = 1
	set_active(false)

func _new_player(bus_name: StringName, gain_db: float) -> AudioStreamPlayer:
	var result := AudioStreamPlayer.new()
	result.bus = bus_name
	result.volume_db = gain_db
	add_child(result)
	return result

func _start_loop(player: AudioStreamPlayer, clip_name: String) -> void:
	if not clips.has(clip_name):
		return
	var stream: AudioStream = clips[clip_name].duplicate()
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	player.stream = stream
	player.play()

func _ensure_footstep_bus() -> void:
	if AudioServer.get_bus_index(FOOTSTEP_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, FOOTSTEP_BUS)
	AudioServer.set_bus_send(index, &"Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.45
	reverb.damping = 0.72
	reverb.spread = 0.65
	reverb.hipass = 0.18
	reverb.predelay_msec = 12.0
	reverb.wet = 0.075
	reverb.dry = 1.0
	AudioServer.add_bus_effect(index, reverb)

func attach_player(player: CharacterBody3D, water: Node) -> void:
	_player = player
	_water = water
	_reset_movement()

func _physics_process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	if not is_instance_valid(_player):
		return
	var point := _player.global_position
	if not active or not enabled or not bool(_player.get("enabled")) or is_instance_valid(_player.get("climbing")):
		_previous_position = point
		_have_position = true
		stop_wading()
		return
	if not _have_position:
		_previous_position = point
		_have_position = true
		stop_wading()
		return
	var travelled := Vector2(point.x - _previous_position.x, point.z - _previous_position.z).length()
	_previous_position = point
	# Warps and room-origin shifts are not footsteps/water movement.
	if travelled > maxf(1.0, delta * 8.0):
		stop_wading()
		return
	var speed := travelled / maxf(delta, 0.001)
	var wet := _is_submerged(point) and absf(_player.velocity.y) < 1.0
	set_wading(speed, wet and travelled > 0.0001)

func _is_submerged(point: Vector3) -> bool:
	if not is_instance_valid(_water) or not _water.has_method("is_water_at") or not bool(_water.call("is_water_at", point)):
		return false
	if _water.has_method("depth_at") and float(_water.call("depth_at", point)) <= 0.0:
		return false
	if not _water.has_method("surface_height_at"):
		return false
	return point.y < float(_water.call("surface_height_at", point))

func _process(delta: float) -> void:
	var audible := active and enabled
	var target := _wade_level if audible and _wading else SILENT_DB
	# Fade in a little more slowly than fade out, as in source update/stopWading.
	var rate := 8.33 if _wading else 14.29
	for loop in [wade, swish]:
		if not is_instance_valid(loop):
			continue
		var level: float = target + (3.0 if loop == swish and _wading else 0.0)
		loop.volume_db = lerpf(loop.volume_db, level, 1.0 - exp(-delta * rate))
		if not _wading and loop.volume_db < SILENT_DB + 0.1:
			loop.volume_db = SILENT_DB
			loop.stream_paused = true
	voices = voices.filter(func(voice): return is_instance_valid(voice))

func _reset_movement() -> void:
	_have_position = false
	_last_motion_speed = 0.0
	stop_wading()
	for loop in [wade, swish]:
		if is_instance_valid(loop):
			loop.volume_db = SILENT_DB
			loop.stream_paused = true

func _stop_contacts() -> void:
	if is_instance_valid(footstep):
		footstep.stop()
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	voices.clear()

func set_active(value: bool) -> void:
	active = value
	for bus_name in [&"Pool", FOOTSTEP_BUS]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_mute(index, not (active and enabled))
	if not active or not enabled:
		_stop_contacts()
		_reset_movement()
	if is_instance_valid(ambience):
		ambience.stream_paused = not (active and enabled and ambience_enabled)

func set_enabled(value: bool) -> void:
	enabled = value
	set_active(active)

func set_ambience(value: bool) -> void:
	ambience_enabled = value
	if is_instance_valid(ambience):
		ambience.stream_paused = not (active and enabled and ambience_enabled)

func set_room(layout: Dictionary) -> void:
	if is_instance_valid(ambience):
		ambience.pitch_scale = 1.0 - float(layout.get("corrupt", 0)) * 0.028
	var ceiling := float(layout.get("ceiling", 9.2))
	var pool_index := AudioServer.get_bus_index(&"Pool")
	if pool_index >= 0 and AudioServer.get_bus_effect_count(pool_index) > 0:
		var effect := AudioServer.get_bus_effect(pool_index, 0) as AudioEffectReverb
		if effect:
			effect.room_size = clampf(ceiling / 16.0, 0.35, 0.95)
			effect.wet = clampf(0.15 + ceiling * 0.007, 0.15, 0.30)
	var step_index := AudioServer.get_bus_index(FOOTSTEP_BUS)
	if step_index >= 0 and AudioServer.get_bus_effect_count(step_index) > 0:
		var effect := AudioServer.get_bus_effect(step_index, 0) as AudioEffectReverb
		if effect:
			effect.room_size = clampf(ceiling / 24.0, 0.35, 0.60)
			effect.wet = clampf(0.045 + ceiling * 0.003, 0.06, 0.095)

func set_wading(speed: float, in_water: bool) -> void:
	_wading = active and enabled and in_water and speed > 0.1
	_last_motion_speed = speed
	_wade_level = lerpf(-21.0, -12.0, clampf(speed / 5.2, 0.0, 1.0)) if _wading else SILENT_DB
	if _wading:
		for loop in [wade, swish]:
			if is_instance_valid(loop):
				loop.pitch_scale = clampf(0.85 + speed * 0.07, 0.85, 1.15)
				loop.stream_paused = false

func stop_wading() -> void:
	_wading = false
	_wade_level = SILENT_DB
	_last_motion_speed = 0.0

func play_clip(clip_name: String, at: Vector3, gain: float = 0.6, pitch: float = 1.0) -> void:
	if not active or not enabled or not clips.has(clip_name) or voices.size() >= 24:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = clips[clip_name]
	voice.bus = &"Pool"
	voice.volume_db = linear_to_db(maxf(gain, 0.001))
	voice.pitch_scale = pitch
	voice.max_distance = 30.0
	voice.unit_size = 3.0
	voice.attenuation_filter_cutoff_hz = 10000.0
	add_child(voice)
	voice.global_position = at
	voices.append(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func _play_footstep(sprinting: bool, at: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	if not active or not enabled or not is_instance_valid(footstep) or frame == _last_footstep_frame or _clock - _last_footstep_time < MIN_FOOTSTEP_INTERVAL:
		_rejected_steps += 1
		return
	if is_instance_valid(_player):
		var travelled := Vector2(_player.global_position.x - _previous_position.x, _player.global_position.z - _previous_position.z).length()
		if not bool(_player.get("enabled")) or is_instance_valid(_player.get("climbing")) or not _player.is_on_floor() or absf(_player.velocity.y) >= 1.0 or _is_submerged(at) or travelled <= 0.0001 or travelled > 1.0:
			_rejected_steps += 1
			return
	var clip_name := "tile_run" if sprinting else ("tile_walk_2" if previous_dry else "tile_walk_1")
	if not clips.has(clip_name):
		return
	if not sprinting:
		previous_dry = not previous_dry
	stop_wading()
	var gain := 0.34 if sprinting else 0.30
	var pitch := randf_range(0.985, 1.015)
	footstep.stop()
	footstep.stream = clips[clip_name]
	footstep.volume_db = linear_to_db(gain)
	footstep.pitch_scale = pitch
	footstep.play()
	_last_footstep_frame = frame
	_last_footstep_time = _clock
	_last_footstep_clip = clip_name
	_footstep_events += 1
	footstep_started.emit(clip_name, gain, pitch)

func impact(at: Vector3, power: float) -> void:
	previous_drop = (previous_drop + 1 + randi_range(0, 1)) % 3
	play_clip("drop_%d" % (previous_drop + 1), at, clampf(0.35 + power, 0.35, 0.85), randf_range(0.96, 1.04))

func interaction(kind: String, at: Vector3, power: float) -> void:
	match kind:
		"step_dry", "footstep", "dry_step", "step_tile": _play_footstep(false, at)
		"step_run", "run_step": _play_footstep(true, at)
		"duck_pickup", "duck_hit", "egg_hit", "tap": play_clip(kind, at, clampf(0.4 + power * 0.3, 0.4, 0.85))
		"grab_duck": play_clip("duck_pickup", at, 0.8)
		"hit_duck": play_clip("duck_hit", at, 0.65)
		"hit_egg": play_clip("egg_hit", at, 0.65)
		"ball_hit", "ball_pickup", "grab_ball", "hit_ball": play_clip("drop_light", at, 0.4)
		"water_tap", "tap_water": play_clip("tap", at, 0.65)

func get_status() -> Dictionary:
	return {"active": active, "enabled": enabled, "wading": _wading, "wade_target_db": _wade_level,
		"measured_speed": _last_motion_speed, "footstep_events": _footstep_events, "rejected_steps": _rejected_steps,
		"last_footstep_clip": _last_footstep_clip, "contact_voices": voices.size(),
		"footstep_polyphony": footstep.max_polyphony if is_instance_valid(footstep) else 0,
		"footstep_bus": str(footstep.bus) if is_instance_valid(footstep) else "", "gait_assets": GAIT_CLIPS.size()}

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	for loop in [ambience, wade, swish, footstep]:
		if is_instance_valid(loop):
			loop.stop()
			loop.stream = null
	voices.clear()
	clips.clear()
