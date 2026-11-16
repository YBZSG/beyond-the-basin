extends Node
## Original synthesized quiet ambience. Not sampled from reference games.
## No footsteps are replaced; inherited tile contacts remain a known limitation.
var main: Node
var voice: AudioStreamPlayer
var signal_voice: AudioStreamPlayer3D
var _saved_effects: Array = []
var _scene_id := ""
var _signals: Dictionary = {}
func configure(owner_node: Node, scene_id: String) -> void:
	main = owner_node
	if voice == null:
		voice = AudioStreamPlayer.new(); voice.bus = &"Ambience"; voice.volume_db = -26; add_child(voice)
	if _scene_id == scene_id: return
	if _saved_effects.is_empty():
		for bus_name: StringName in [&"Pool",&"Footsteps"]:
			var index := AudioServer.get_bus_index(bus_name)
			if index < 0: continue
			for effect_index in AudioServer.get_bus_effect_count(index):
				var effect := AudioServer.get_bus_effect(index,effect_index) as AudioEffectReverb
				if effect != null: _saved_effects.append({"effect":effect,"wet":effect.wet,"room_size":effect.room_size})
	var outdoor := scene_id in ["sportsground","sluice_courtyard","night_busstop"]
	for saved: Dictionary in _saved_effects:
		saved.effect.wet = .015 if outdoor else .065
		saved.effect.room_size = .3 if outdoor else .6
	_scene_id = scene_id
	# Reference rooms reuse quiet, licensed original extension loops. Do not
	# load a nonexistent file or retain a previous scene's stream silently.
	var audio_id: String = {"cloud_ballpit":"oculus_hall","hanging_hand":"aquarium_atrium","stair_labyrinth":"lime_gallery", "soffit_reservoir":"lime_gallery", "parallax_bath":"oculus_hall", "crossing_channels":"sluice_courtyard", "inverted_pool":"aquarium_atrium", "hollow_visage":"lime_gallery", "glasswell_bath":"aquarium_atrium"}.get(scene_id,scene_id)
	var path := "res://assets/dreamcore/audio/"+audio_id+".wav"
	var stream := load(path) as AudioStreamWAV
	if stream != null:
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD; stream.loop_begin=0; stream.loop_end=stream.mix_rate*16
		voice.stream=stream; voice.play(); voice.stream_paused=true
func update(audible: bool) -> void:
	if voice != null: voice.stream_paused = not audible
	if is_instance_valid(main) and is_instance_valid(main.pool_audio) and is_instance_valid(main.pool_audio.ambience):
		main.pool_audio.ambience.stream_paused = true
	if not audible and is_instance_valid(signal_voice): signal_voice.stop()
func restore() -> void:
	if voice != null: voice.stop()
	if signal_voice != null: signal_voice.stop()
	for saved: Dictionary in _saved_effects:
		saved.effect.wet=saved.wet; saved.effect.room_size=saved.room_size
	_saved_effects.clear(); _scene_id=""
	if is_instance_valid(main) and is_instance_valid(main.pool_audio): main.pool_audio.set_ambience(main._ambience_on)
func broadcast(at: Vector3, count: int) -> void:
	if not is_instance_valid(main) or not main._audio_on or main.menu_open: return
	if not _signals.has(count): _signals[count] = _signal(count)
	if signal_voice == null:
		signal_voice = AudioStreamPlayer3D.new(); signal_voice.bus = &"Master"; signal_voice.max_distance=35; signal_voice.unit_size=2; signal_voice.volume_db=-24; add_child(signal_voice)
	signal_voice.global_position=at+Vector3.UP*1.4; signal_voice.stream=_signals[count]; signal_voice.play()
static func _wind(id: String) -> AudioStreamWAV:
	var rate := 16000; var count := rate*16
	var data := PackedByteArray(); data.resize(count*2)
	var random := RandomNumberGenerator.new(); random.seed = 98231+id.hash()
	var low := 0.0
	for index in count:
		var t := float(index)/rate
		low = lerpf(low,random.randf_range(-1,1),.025)
		var envelope := pow(sin(PI*float(index)/count),2)
		var hum := sin(TAU*(48.0 if id == "night_busstop" else 60.0)*t)*.014
		var sample := low*envelope*.55 + hum
		data.encode_s16(index*2,int(clampf(sample,-.2,.2)*32767))
	var stream := AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=rate; stream.stereo=false; stream.data=data
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD; stream.loop_begin=0; stream.loop_end=count
	return stream
static func _signal(count: int) -> AudioStreamWAV:
	var rate := 16000; var samples := int((float(count)*.32+.12)*rate)
	var data := PackedByteArray(); data.resize(samples*2)
	for index in samples:
		var t := float(index)/rate; var phase := fmod(t,.32)
		var amplitude := sin(PI*phase/.13) if phase<.13 and int(t/.32)<count else 0.0
		data.encode_s16(index*2,int(sin(TAU*440*t)*amplitude*.25*32767))
	var stream := AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=rate; stream.data=data; return stream
