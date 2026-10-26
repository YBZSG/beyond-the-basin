extends Node
## Bounded first-entry room signatures. Runtime alone owns readiness and pause.
## No camera, input, physics, source lighting, buses or water are modified.
signal arrival_started(identity: String, description: Dictionary)
const CampaignFont=preload("res://assets/fonts/campaign/PoolCoreCampaignSC.otf")
const DWELL_SECONDS := 0.35
const CUE_SECONDS := 3.8
const MAX_DELTA := 0.1
const MAX_SEEN := 28
const SAMPLE_RATE := 8000
const AUDIO_SECONDS := 1.2
const CHAPTER_MODES := {"lost_shift":"original", "maintenance":"expanded", "return_water":"poolrooms", "five_memories":"reference", "quiet_archive":"quiet", "daylight":"formal"}
# title, concise architectural text equivalent, acoustic family, accent colour.
const ROOMS := {
 "original":[
  ["旧泳池","水拍旧瓷砖，跳台隐在高处。","water","9db9b8"],
  ["漂浮物厅","漂浮物轻碰池沿，空厅传来细响。","drip","aabcc7"],
  ["沉阶水厅","阶沿没入浅水，脚下仍有去路。","drip","8fb6bb"],
  ["高拱门大厅","日光穿过高拱，回声拉长。","air","d5c6a1"],
  ["夜间浴场","低顶灯下，一段电流声并不平稳。","hum","b6c0a4"],
  ["跳台高廊","高处栏杆映着光，水声留在下方。","air","c2c9b8"],
  ["连通浴池","浅水连接岛台，干湿脚步交替。","water","a2c4b5"],
  ["柱阵水厅","柱影层层延伸，水声绕过暗处。","hum","9caabf"]],
 "expanded":[
  ["淋浴更衣间","长凳划开干湿区，滴水声贴近墙面。","drip","b9c1b5"],
  ["低拱静浴","四座浅池围着步道，低拱收住回声。","water","bcbda7"],
  ["天窗泳廊","真实天光落入蓝瓷，水面缓慢映亮。","air","a8c7cf"],
  ["设备过渡厅","设备门旁的导向牌，在风机声里静止。","hum","b6bba8"]],
 "poolrooms":[
  ["曲廊镜池","曲墙遮住池尾，反光先到达脚边。","water","a4c0ba"],
  ["拱顶水廊","两条水道向前延伸，天光只剩窄缝。","drip","aec7cc"],
  ["圆门侧浴","圆门框住静水，休息龛里声音变轻。","air","c5bea9"]],
 "reference":[
  ["釉光阶厅","干燥的楼梯向下，砖缝接住灯影。","drip","d1bfaf"],
  ["暗柱水厅","中轴灯照出方柱，侧面依然安静。","hum","a8b7ba"],
  ["青窗水廊","青窗照着水道，旧标志留在原位。","air","98c6cc"],
  ["粉阶八角池","粉色阶沿环住八角水面，穹顶叠起。","water","ceb2b8"],
  ["圆窗球池休息室","软垫收住脚步声，圆窗嵌在墙里。","air","c6bdab"]],
 "quiet":[
  ["天光环庭","天光穿过环庭，风在上层绕行。","air","c3cabb"],
  ["穹顶泳廊","拱券重复，长水道尽头仍留着暖光。","hum","d0c09f"],
  ["更衣回廊","旧柜与淋浴间之间，浅水漫过砖缝。","drip","b1c1b7"]],
 "formal":[
  ["采光主池厅","宽阔的水面接住自然光，空气渐静。","water","c6d0c4"],
  ["连续拱廊","干地脚步穿过一道又一道拱门。","air","d2c8b3"],
  ["静水侧池","侧池没有另一扇出口，适合停留片刻。","water","b5c4c4"],
  ["浅水天井","天空打开，浅浅的水几乎贴着地面。","air","c9d3cd"],
  ["穹顶静浴","水光托着穹顶，远处终于有了风声。","hum","d7ccb4"]]
}
var chapter_id := ""
var epoch := -1
var audio_enabled := false
var reduced_effects := false
var _suspended := false
var _seen: Dictionary = {}
var _candidate := ""
var _candidate_room: WeakRef
var _dwell := 0.0
var _active := ""
var _active_room: WeakRef
var _age := 0.0
var _layer: CanvasLayer
var _card: VBoxContainer
var _voice: AudioStreamPlayer3D
var _starts := 0
var _fixture: WeakRef
var _vane: WeakRef
var _vane_rest := Vector3.ZERO
var _lamps: Array = []
var _lamp_materials: Array = []
var _lamp_originals: Array = []
var _accent: OmniLight3D
var _description: Dictionary = {}
var _fixture_offset := 0.0


func _ready() -> void:
 process_mode=Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
 # Cleanup still runs if the coordinator stops ticking during pause/unload.
 if _active.is_empty(): return
 var room: Node=_active_room.get_ref() if _active_room!=null else null
 if get_tree().paused or not is_instance_valid(room) or not room.is_inside_tree():
  _stop_cue();_reset_candidate()

static func describe(chapter: String, mode: String, index: int) -> Dictionary:
 if CHAPTER_MODES.get(chapter,"") != mode or not ROOMS.has(mode): return {}
 var entries: Array = ROOMS[mode]
 var local_index := index - 8 if mode == "quiet" else index
 if local_index < 0 or local_index >= entries.size(): return {}
 var entry: Array = entries[local_index]
 return {"title":entry[0],"text":entry[1],"family":entry[2],"accent":Color(entry[3]),"source_mode":mode,"source_index":index,"pitch":118.0+float(local_index)*17.0+float(mode.length())*3.0}

func configure(next_chapter: String, next_epoch: int) -> void:
 if chapter_id == next_chapter and epoch == next_epoch: return
 _stop_cue();_reset_candidate()
 if chapter_id != next_chapter: _seen.clear()
 chapter_id=next_chapter;epoch=next_epoch;_suspended=false

func restore_seen(identities: Array) -> void:
 for value: Variant in identities:
  if value is String and _valid_identity(value) and _seen.size()<MAX_SEEN: _seen[value]=true

func set_audio_enabled(value: bool) -> void:
 audio_enabled=value
 if not value and is_instance_valid(_voice): _voice.stop();_voice.free();_voice=null

func set_suspended(value: bool) -> void:
 _suspended=value
 if value: _stop_cue();_reset_candidate()

func clear() -> void:
 _stop_cue();_reset_candidate();_seen.clear();chapter_id="";epoch=-1;_suspended=false

func _valid_identity(identity: String) -> bool:
 if not CHAPTER_MODES.has(chapter_id) or not identity.begins_with(chapter_id+":"): return false
 var coord := identity.substr(chapter_id.length()+1).split(",")
 return coord.size()==2 and coord[0].is_valid_int() and coord[1].is_valid_int()

func update_room(room: Node3D, identity: String, ready: bool, allowed: bool, delta: float) -> void:
 if _suspended or not allowed or not ready or not is_instance_valid(room) or not room.is_inside_tree() or not _valid_identity(identity):
  _stop_cue();_reset_candidate();return
 var dt := clampf(delta,0.0,MAX_DELTA) if is_finite(delta) else 0.0
 if not _active.is_empty():
  if _active!=identity or _active_room==null or _active_room.get_ref()!=room:
   _stop_cue()
  else:
   _age+=dt
   if _age>=CUE_SECONDS: _stop_cue()
   else:
    _animate_fixture(_age)
   if is_instance_valid(_card):
    _card.modulate.a=minf(clampf(_age/.55,0.0,1.0),clampf((CUE_SECONDS-_age)/.9,0.0,1.0))
 if _seen.has(identity): _reset_candidate();return
 var description := describe(chapter_id,str(room.get_meta("campaign_source_mode","")),int(room.get_meta("campaign_source_index",-100)))
 if description.is_empty(): _reset_candidate();return
 if _candidate!=identity or _candidate_room==null or _candidate_room.get_ref()!=room:
  _candidate=identity;_candidate_room=weakref(room);_dwell=0.0
 _dwell+=dt
 if _dwell<DWELL_SECONDS or _seen.size()>=MAX_SEEN: return
 _seen[identity]=true;_starts+=1
 _reset_candidate();_start_cue(room,identity,description)
 arrival_started.emit(identity,description.duplicate(true))

func _reset_candidate() -> void:
 _candidate="";_candidate_room=null;_dwell=0.0

func _start_cue(room: Node3D, identity: String, description: Dictionary) -> void:
 _stop_cue();_active=identity;_active_room=weakref(room);_age=0.0
 _layer=CanvasLayer.new();_layer.layer=34;add_child(_layer)
 var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 margin.offset_left=-362;margin.offset_right=-28;margin.offset_top=84;margin.offset_bottom=182
 margin.mouse_filter=Control.MOUSE_FILTER_IGNORE;_layer.add_child(margin)
 _card=VBoxContainer.new();_card.theme=Theme.new();_card.theme.default_font=CampaignFont;_card.add_theme_constant_override("separation",7);_card.mouse_filter=Control.MOUSE_FILTER_IGNORE;_card.modulate.a=0.0;margin.add_child(_card)
 var line:=ColorRect.new();line.color=description.accent;line.custom_minimum_size=Vector2(0,2);line.mouse_filter=Control.MOUSE_FILTER_IGNORE;_card.add_child(line)
 var title:=Label.new();title.text=description.title;title.add_theme_font_size_override("font_size",20);title.add_theme_color_override("font_color",Color("e8e7dc"));title.add_theme_color_override("font_outline_color",Color(0,0,0,.8));title.add_theme_constant_override("outline_size",5);title.mouse_filter=Control.MOUSE_FILTER_IGNORE;_card.add_child(title)
 var body:=Label.new();body.text=description.text;body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_theme_font_size_override("font_size",15);body.add_theme_color_override("font_color",Color("c8d0cb"));body.add_theme_color_override("font_outline_color",Color(0,0,0,.9));body.add_theme_constant_override("outline_size",4);body.mouse_filter=Control.MOUSE_FILTER_IGNORE;_card.add_child(body)
 _description=description.duplicate(true)
 _attach_fixture(room,description)
 if audio_enabled:
  _voice=AudioStreamPlayer3D.new();_voice.max_polyphony=1;_voice.volume_db=-26.0;_voice.max_distance=18.0
  _voice.bus=&"Ambience" if AudioServer.get_bus_index(&"Ambience")>=0 else &"Master"
  _voice.stream=make_signature(description);room.add_child(_voice)
  var layout: Dictionary=room.get_meta("layout",{})
  _voice.position=layout.get("spawn_local",Vector3(0,1.0,12.0))+Vector3.UP*.6
  _voice.play()

static func make_signature(description: Dictionary) -> AudioStreamWAV:
 # Procedural quiet signature, not a claim of room convolution or source recordings.
 var bytes:=PackedByteArray();var count:=int(SAMPLE_RATE*AUDIO_SECONDS);bytes.resize(count*2)
 var hz:=float(description.get("pitch",150.0));var family:=str(description.get("family","air"))
 for i in range(count):
  var t:=float(i)/SAMPLE_RATE
  var envelope:=sin(PI*t/AUDIO_SECONDS);envelope*=envelope
  var sample:=0.0
  match family:
   "drip":
    var phase:=fmod(t,.36)
    sample=sin(TAU*(hz*3.0-80.0*phase)*phase)*exp(-phase*22.0)*minf(phase*120.0,1.0)
   "hum":sample=sin(TAU*hz*t)*.45+sin(TAU*hz*1.007*t)*.2
   "water":sample=(sin(t*(hz*6.0+173.0)+sin(t*41.0)*3.0)+sin(t*(hz*8.0+299.0)+sin(t*67.0)*4.0))*.22
   _:sample=(sin(t*(hz*2.0+131.0)+sin(t*17.0)*5.0)+sin(t*(hz*3.0+181.0)+sin(t*23.0)*6.0))*.18
  bytes.encode_s16(i*2,int(clampf(sample*envelope,-1.0,1.0)*12000.0))
 var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=SAMPLE_RATE;stream.stereo=false;stream.loop_mode=AudioStreamWAV.LOOP_DISABLED;stream.data=bytes
 return stream

static func visual_sample(mode: String, index: int, seconds: float, reduced: bool = false) -> Dictionary:
 # Each lens makes one slow activation, never a flash train. Three actual spatial
 # lenses read as electrical cascade / rising pressure / routed flow / reading /
 # breathing ventilation / daylight, while the inspection tag moves independently.
 var t:=clampf(seconds,0.0,CUE_SECONDS)
 var fade_out:=smoothstep(CUE_SECONDS,CUE_SECONDS-.9,t)
 var offsets:Array=[0.0,.28,.56]
 var shape:="electrical_cascade"
 match mode:
  "expanded":offsets=[.62,.31,0.0];shape="pressure_rise"
  "poolrooms":offsets=[.32,0.0,.64] if index%2==0 else [.64,0.0,.32];shape="routed_flow"
  "reference":offsets=[.4,0.0,.4];shape="reading_spread"
  "quiet":offsets=[0.0,.12,.24];shape="ventilation_breath"
  "formal":offsets=[0.0,.18,.36];shape="daylight_open"
 var levels:Array=[]
 for i in 3:
  var offset:float=float(offsets[(i+index%3)%3]) if mode=="original" else float(offsets[i])
  var attack:float=.62+float(posmod(index,4))*.08
  if mode=="formal":attack=1.15+float(index)*.04
  var level:float=smoothstep(offset,offset+attack,t)*fade_out
  if mode=="quiet":level*=.72+.28*sin(PI*t/CUE_SECONDS)
  if reduced:level=smoothstep(0.0,1.0,t)*fade_out
  levels.append(level)
 var envelope:=sin(PI*t/CUE_SECONDS)
 var tilt:=Vector3.ZERO
 if not reduced:
  match mode:
   "original":tilt.z=.055*envelope
   "expanded":tilt.x=.11*envelope
   "poolrooms":tilt.z=(.14 if index%2==0 else -.14)*envelope
   "reference":tilt.x=.055*envelope;tilt.z=.04*envelope
   "quiet":tilt.x=.18*sin(TAU*t/CUE_SECONDS)*envelope;tilt.z=.09*envelope
   "formal":tilt.x=-.07*envelope
 var maximum:float=maxf(float(levels[0]),maxf(float(levels[1]),float(levels[2])))
 return {"levels":levels,"tilt":tilt,"energy":maximum*.58,"pattern":shape}

func _attach_fixture(room: Node3D, description: Dictionary) -> void:
 # Only an explicitly authored station courtesy lamp is eligible. No existing
 # architecture light, puzzle status/needle or arbitrary mesh is ever changed.
 var station: Node3D
 for child: Node in room.get_children():
  if child is Node3D and child.has_node("ArrivalLamp0") and str(child.get_meta("kind","")) not in ["departure","repair","bell","locker"]:
   station=child;break
 if station==null:return
 _fixture=weakref(station);_description=description.duplicate(true);_fixture_offset=_age
 var vane:=station.get_node_or_null("ArrivalVane") as Node3D
 if vane!=null:_vane=weakref(vane);_vane_rest=vane.rotation
 for i in 3:
  var lamp:=station.get_node_or_null("ArrivalLamp%d"%i) as MeshInstance3D
  if lamp==null or not lamp.material_override is StandardMaterial3D:continue
  _lamps.append(weakref(lamp));_lamp_originals.append(lamp.material_override)
  var owned:=lamp.material_override.duplicate() as StandardMaterial3D
  owned.emission_enabled=true;owned.emission=Color("ffe0ab");owned.emission_energy_multiplier=0.0
  lamp.material_override=owned;_lamp_materials.append(owned)
 if _lamps.is_empty():return
 _accent=OmniLight3D.new();_accent.name="ArrivalCourtesyLight";_accent.set_meta("campaign_preserve_light",true);_accent.light_color=Color("ffe0c1");_accent.light_energy=0.0
 _accent.omni_range=2.8;_accent.omni_attenuation=1.6;_accent.shadow_enabled=false
 station.add_child(_accent);_accent.position=Vector3(-.52,1.45,.23)
 _animate_fixture(0.0)

func _animate_fixture(seconds: float) -> void:
 if _description.is_empty():return
 if _fixture!=null and not is_instance_valid(_fixture.get_ref()):
  _restore_fixture();return
 if _fixture==null and _active_room!=null:
  var room:Node3D=_active_room.get_ref()
  if is_instance_valid(room):_attach_fixture(room,_description)
  if _fixture==null:return
 var sample:=visual_sample(str(_description.source_mode),int(_description.source_index),maxf(0.0,seconds-_fixture_offset),reduced_effects)
 var late_fade:=smoothstep(CUE_SECONDS,CUE_SECONDS-.9,seconds) if _fixture_offset>0.0 else 1.0
 for i in _lamp_materials.size():
  var material:StandardMaterial3D=_lamp_materials[i]
  var level:=float(sample.levels[i])*late_fade
  var neutral:StandardMaterial3D=_lamp_originals[i]
  material.albedo_color=neutral.albedo_color.lerp(Color("ffe0ab"),level*.72)
  material.emission_energy_multiplier=level*1.8
 if _vane!=null:
  var vane:Node3D=_vane.get_ref()
  if is_instance_valid(vane):vane.rotation=_vane_rest+Vector3(sample.tilt)*late_fade
 if is_instance_valid(_accent):_accent.light_energy=float(sample.energy)*late_fade

func _restore_fixture() -> void:
 for i in _lamps.size():
  var lamp:MeshInstance3D=_lamps[i].get_ref()
  # Never overwrite a newer effect owner/material replacement.
  if is_instance_valid(lamp) and lamp.material_override==_lamp_materials[i]:lamp.material_override=_lamp_originals[i]
 if _vane!=null:
  var vane:Node3D=_vane.get_ref()
  if is_instance_valid(vane):vane.rotation=_vane_rest
 if is_instance_valid(_accent):_accent.free()
 _accent=null;_fixture=null;_vane=null;_lamps.clear();_lamp_materials.clear();_lamp_originals.clear();_description.clear();_fixture_offset=0.0

func _stop_cue() -> void:
 _restore_fixture()
 if is_instance_valid(_voice): _voice.stop();_voice.free()
 _voice=null
 if is_instance_valid(_layer): _layer.free()
 _layer=null;_card=null;_active="";_active_room=null;_age=0.0

func diagnostics() -> Dictionary:
 return {"seen":_seen.size(),"starts":_starts,"active":_active,"candidate":_candidate,"dwell":_dwell,"voice_count":1 if is_instance_valid(_voice) else 0,"layer_count":1 if is_instance_valid(_layer) else 0,"epoch":epoch,"fixture_count":1 if _fixture!=null and is_instance_valid(_fixture.get_ref()) else 0,"light_count":1 if is_instance_valid(_accent) else 0}

func _exit_tree() -> void:
 _stop_cue()
