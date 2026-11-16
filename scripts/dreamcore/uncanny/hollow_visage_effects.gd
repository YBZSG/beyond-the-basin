extends Node3D
## A bounded, static-position lighting comparison. No gaze, camera or face motion.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const STATION=preload("res://scripts/dreamcore/uncanny/hollow_visage_station_visuals.gd")
const HERO_POSITION=Vector3(-4.,3.,-22.5)
const HERO_TARGET=Vector3(2.,19.,-31.)
const COUNTER_POSITION=Vector3(4.,3.,-22.5)
const COUNTER_TARGET=Vector3(-2.,19.,-31.)
var _value:=0
var _playable:=false
var _reduced:=false
var _built:=false
var _handle:MeshInstance3D
var _lights:Array[SpotLight3D]=[]
func _ready()->void:
 add_to_group("dream_scene_effect");_build();set_process(false)
func _build()->void:
 if _built:return
 _built=true
 _handle=STATION.build_into(self)
 for side in [-1.,1.]:
  var light=SpotLight3D.new();light.name="FixedRaking_"+str(side);light.position=HERO_POSITION if side<0. else COUNTER_POSITION;add_child(light);light.look_at(HERO_TARGET if side<0. else COUNTER_TARGET,Vector3.UP)
  light.light_color=Color("eee3ca");light.spot_range=32.;light.spot_angle=46.;light.spot_angle_attenuation=.8;light.shadow_enabled=side<0.;light.shadow_bias=.02;light.shadow_normal_bias=.04;light.light_specular=.25;_lights.append(light)
 _snap()
func _snap()->void:
 if is_instance_valid(_handle):_handle.rotation.z=-.7 if _value==1 else .7
 for i in _lights.size():_lights[i].light_energy=(28. if i==0 else .16) if _value==1 else (14. if i==0 else 8.)
func apply_state(values:Dictionary,_observed:Dictionary,reduced_effects:bool)->void:
 _value=clampi(int(values.get("visage_raking",0)),0,1);_reduced=reduced_effects
 if _built:_snap()
func set_playable(value:bool)->void:
 _playable=value;set_process(false)
func set_audio_enabled(_value:bool)->void:pass
func diagnostics()->Dictionary:
 return {"value":_value,"fixed_raking":_value==1,"light_energies":[_lights[0].light_energy,_lights[1].light_energy] if _lights.size()==2 else [],"handle_rotation_z":_handle.rotation.z if is_instance_valid(_handle) else 0.,"playable":_playable,"processing":is_processing(),"audio_count":0,"moving_collision":false,"moving_face":false,"player_tracking":false,"light_count":_lights.size(),"shadow_casting_spots":1,"shadow_bias":.02,"shadow_normal_bias":.04,"hero_position_m":[HERO_POSITION.x,HERO_POSITION.y,HERO_POSITION.z],"hero_target_m":[HERO_TARGET.x,HERO_TARGET.y,HERO_TARGET.z],"counter_position_m":[COUNTER_POSITION.x,COUNTER_POSITION.y,COUNTER_POSITION.z],"counter_target_m":[COUNTER_TARGET.x,COUNTER_TARGET.y,COUNTER_TARGET.z],"spot_range_m":32.,"spot_half_angle_degrees":46.,"node_count":get_child_count()+1,"reduced_effects":_reduced}
func _exit_tree()->void:
 _playable=false;set_process(false)
