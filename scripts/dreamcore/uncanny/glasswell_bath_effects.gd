extends Node3D
## A finite mechanical pointer and genuine down-well lamp; presentation only.
## No retained player/water/main/save references; no collision or camera authority.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const P="glasswell_bath_"
const RECEIVER=preload("res://shaders/dreamcore/uncanny/glasswell_planar_receiver.gdshader")
var _pointer:Node3D
var _button:MeshInstance3D
var _lamp:OmniLight3D
var _indicator:MeshInstance3D
var _indicator_material:ShaderMaterial
var _sound:AudioStreamPlayer3D
var _playable=false
var _audio_enabled=false
var _reduced=true
var _initialized=false
var _value=0
var _pose=0.0
var _target=0.0
func _ready()->void:
 add_to_group("dream_scene_effect");_build();_apply_pose(0.);set_process(false)
func _box(parent:Node3D,p:Vector3,s:Vector3,key:String)->MeshInstance3D:
 var m=BoxMesh.new();m.size=s;var n=MeshInstance3D.new();n.mesh=m;n.position=p;n.material_override=G.mat(P+key);parent.add_child(n);return n
func _build()->void:
 _pointer=Node3D.new();_pointer.name="MechanicalDepthPointer";_pointer.position=Vector3(-20,1.48,17.268);add_child(_pointer)
 _box(_pointer,Vector3(0,.068,0),Vector3(.013,.14,.009),"ink")
 _box(_pointer,Vector3.ZERO,Vector3(.037,.037,.014),"bronze")
 _button=_box(self,Vector3(-19.78,1.26,17.274),Vector3(.054,.044,.036),"ink")
 _indicator_material=ShaderMaterial.new();_indicator_material.shader=RECEIVER;_indicator_material.resource_name="glasswell_depth_indicator_receiver";_indicator_material.set_shader_parameter("uv1_scale",Vector3.ONE);_indicator_material.set_shader_parameter("uv1_offset",Vector3.ZERO);_indicator_material.set_shader_parameter("normal_strength",1.0)
 _indicator_material.set_shader_parameter("use_textures",false);_indicator_material.set_shader_parameter("base_tint",Color("d2e0c7"));_indicator_material.set_shader_parameter("base_roughness",1.0);_indicator_material.set_shader_parameter("base_metallic",0.0);_indicator_material.set_shader_parameter("base_specular",.5)
 _indicator_material.set_shader_parameter("emission_tint",Color("d2e0c7"));_indicator_material.set_shader_parameter("emission_energy",.25)
 _indicator=_box(self,Vector3(-14.855,-38.40,7),Vector3(.085,.105,.63),"warm");_indicator.material_override=_indicator_material
 _lamp=OmniLight3D.new();_lamp.name="RealDryShaftDepthIndicator";_lamp.position=Vector3(-14.4,-38.35,7);_lamp.light_color=Color("d2e0c7");_lamp.omni_range=14.;_lamp.light_energy=.12;_lamp.light_specular=.3;_lamp.shadow_enabled=false;add_child(_lamp)
 _sound=AudioStreamPlayer3D.new();_sound.name="BoundedSoundingTap";_sound.stream=load("res://assets/sfx/tap.ogg");_sound.position=Vector3(-20,1.45,17);_sound.volume_db=-15.;_sound.pitch_scale=.65;_sound.max_distance=14.;add_child(_sound)
func apply_state(values:Dictionary,_observed:Dictionary,reduced_effects:bool)->void:
 var next=clampi(int(values.get("glasswell_sounder",0)),0,1)
 if _initialized and next==_value and reduced_effects==_reduced:return
 _reduced=reduced_effects
 if not _initialized or not _playable or _reduced:
  _value=next;_target=float(next);_pose=_target;_initialized=true;_apply_pose(_pose);set_process(false);return
 if next==_value:return
 _value=next;_target=float(next)
 if next==1 and _audio_enabled and is_instance_valid(_sound):_sound.play()
 set_process(true)
func set_playable(value:bool)->void:
 _playable=value
 if not value:
  set_process(false)
  if is_instance_valid(_sound):_sound.stop()
 elif _initialized and not _reduced and not is_equal_approx(_pose,_target):set_process(true)
func set_audio_enabled(value:bool)->void:
 _audio_enabled=value
 if not value and is_instance_valid(_sound):_sound.stop()
func _process(delta:float)->void:
 if not _playable:set_process(false);return
 _pose=move_toward(_pose,_target,minf(delta,.05)*.7);_apply_pose(_pose)
 if is_equal_approx(_pose,_target):set_process(false)
func _apply_pose(value:float)->void:
 if is_instance_valid(_pointer):_pointer.rotation.z=deg_to_rad(135.-value*270.)
 if is_instance_valid(_button):_button.position.z=17.274-value*.018
 if is_instance_valid(_lamp):_lamp.light_energy=lerpf(.12,1.15,value)
 if _indicator_material!=null:_indicator_material.set_shader_parameter("emission_energy",lerpf(.25,3.0,value))
func diagnostics()->Dictionary:
 return {"station":"glasswell_sounder","value":_value,"pose":_pose,"target":_target,"playable":_playable,"processing":is_processing(),"state_initialized":_initialized,"pointer_count":1,"light_count":1,"collision_count":0,"audio_count":1,"audio_playing":is_instance_valid(_sound) and _sound.playing,"audio_enabled":_audio_enabled,"well_indicator_y":-38.4,"floor_changed":false,"water_changed":false}
func _exit_tree()->void:
 _playable=false;set_process(false)
 if is_instance_valid(_sound):_sound.stop()
 _sound=null;_pointer=null;_button=null;_lamp=null;_indicator=null;_indicator_material=null
