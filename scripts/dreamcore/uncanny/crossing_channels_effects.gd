extends Node3D
## Bounded acoustic flap and quiet existing tap. Runtime owns input/state/audio options.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const P="crossing_channels_"
var _wheel:Node3D
var _flap:Node3D
var _far_flag:Node3D
var _audio:AudioStreamPlayer3D
var _value=0
var _pose=0.0
var _target=0.0
var _playable=false
var _reduced=true
var _initialized=false
var _audio_enabled=false
var _echo_pending=0.0
var _echo_audio_armed=false
func _ready()->void:
 add_to_group("dream_scene_effect");_build();_apply_pose(0.);set_process(false)
func _mesh(parent:Node3D,mesh:Mesh,p:Vector3,key:String)->MeshInstance3D:
 var n=MeshInstance3D.new();n.mesh=mesh;n.position=p;n.material_override=G.mat(P+key);parent.add_child(n);return n
func _rod(parent:Node3D,a:Vector3,b:Vector3,r:float,key:String,segments:int=16)->void:
 var m=CylinderMesh.new();m.top_radius=r;m.bottom_radius=r;m.height=a.distance_to(b);m.radial_segments=segments;m.rings=0;var n=_mesh(parent,m,(a+b)*.5,key);n.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
func _box(parent:Node3D,p:Vector3,s:Vector3,key:String)->void:
 var m=BoxMesh.new();m.size=s;_mesh(parent,m,p,key)
func _build()->void:
 _wheel=Node3D.new();_wheel.name="ListeningHandwheel";_wheel.position=Vector3(20,5.52,-21.44);add_child(_wheel)
 var torus=TorusMesh.new();torus.inner_radius=.25;torus.outer_radius=.29;torus.rings=48;torus.ring_segments=10;var rim=_mesh(_wheel,torus,Vector3.ZERO,"paint");rim.rotation.x=PI*.5
 for i in 5:
  var t=i*TAU/5.;_rod(_wheel,Vector3.ZERO,Vector3(cos(t)*.255,sin(t)*.255,0),.018,"steel")
 _rod(_wheel,Vector3(0,0,-.035),Vector3(0,0,.045),.065,"steel",20)
 _rod(_wheel,Vector3(.21,0,0),Vector3(.21,0,.14),.025,"dark_steel")
 _flap=Node3D.new();_flap.name="TwoPathAcousticFlap";_flap.position=Vector3(20,6.22,-21.72);add_child(_flap)
 _box(_flap,Vector3.ZERO,Vector3(.65,.40,.07),"paint");_rod(_flap,Vector3(-.38,0,0),Vector3(.38,0,0),.035,"steel")
 # Two physically readable route index plates. Pointer sweeps between left/near and right/long route.
 for x in [-.36,.36]:_box(self,Vector3(20+x,5.96,-21.55),Vector3(.23,.10,.035),"blue" if x<0 else "cyan")
 _rod(_wheel,Vector3.ZERO,Vector3(0,.36,.025),.014,"steel")
 _far_flag=Node3D.new();_far_flag.name="MechanicalEchoIndicator";_far_flag.position=Vector3(-31,7.2,-22.63);add_child(_far_flag)
 _box(_far_flag,Vector3(0,.16,0),Vector3(.36,.32,.035),"cyan");_rod(_far_flag,Vector3(-.24,0,0),Vector3(.24,0,0),.025,"steel")
 _audio=AudioStreamPlayer3D.new();_audio.name="QuietBoundedReturnTap";_audio.stream=load("res://assets/sfx/tap.ogg");_audio.volume_db=-25.;_audio.max_distance=65.;_audio.unit_size=5.;_audio.position=Vector3(20,5.8,-22);add_child(_audio)
func apply_state(values:Dictionary,_observed:Dictionary,reduced_effects:bool)->void:
 var next=clampi(int(values.get("channel_resonator",0)),0,1);_reduced=reduced_effects
 if _initialized and not _playable:
  _value=next;_target=float(next);set_process(false);return
 if not _initialized or _reduced:
  _value=next;_target=float(next);_pose=_target;_initialized=true;_echo_pending=0.;_apply_pose(_pose);_far_flag.rotation.x=PI*.5*_pose;set_process(false);return
 if next==_value:return
 _value=next;_target=float(next);_echo_pending=.72 if next==1 else .01;_echo_audio_armed=_audio_enabled and not _reduced
 if next==0:_far_flag.rotation.x=0.
 set_process(true)
func set_playable(value:bool)->void:
 _playable=value
 if not value:
  _echo_pending=0.;_echo_audio_armed=false;set_process(false)
  if is_instance_valid(_audio):_audio.stop()
 elif _initialized and _reduced:
  _pose=_target;_apply_pose(_pose);set_process(false)
  _far_flag.rotation.x=PI*.5*_pose
 elif _initialized and not is_equal_approx(_pose,_target):set_process(true)
func set_audio_enabled(value:bool)->void:
 _audio_enabled=value
 if not value:_echo_audio_armed=false
 if not value and is_instance_valid(_audio):_audio.stop()
func _process(delta:float)->void:
 if not _playable:set_process(false);return
 _pose=move_toward(_pose,_target,minf(delta,.05)*.65);_apply_pose(_pose)
 if _echo_pending>0:
  _echo_pending=maxf(0.,_echo_pending-delta)
  if _echo_pending<=0:
   _far_flag.rotation.x=PI*.5*float(_value)
   if _audio_enabled and _echo_audio_armed and not _reduced:
    _audio.position=Vector3(-31,7.2,-22.6) if _value==1 else Vector3(20,5.8,-22);_audio.volume_db=-29. if _value==1 else -25.;_audio.pitch_scale=.82 if _value==1 else .96;_audio.play()
   _echo_audio_armed=false
 if is_equal_approx(_pose,_target) and _echo_pending<=0:
  _far_flag.rotation.x=PI*.5*_pose;set_process(false)
func _apply_pose(value:float)->void:
 if is_instance_valid(_wheel):_wheel.rotation.z=lerpf(-.70,.70,value)
 if is_instance_valid(_flap):_flap.rotation.x=deg_to_rad(67.)*value
func diagnostics()->Dictionary:return {"station":"channel_resonator","value":_value,"pose":_pose,"target":_target,"initialized":_initialized,"playable":_playable,"processing":is_processing(),"audio_enabled":_audio_enabled,"audio_playing":_audio.playing if is_instance_valid(_audio) else false,"echo_pending_seconds":_echo_pending,"echo_audio_armed":_echo_audio_armed,"flap_degrees":rad_to_deg(_flap.rotation.x) if is_instance_valid(_flap) else 0.,"far_flag_degrees":rad_to_deg(_far_flag.rotation.x) if is_instance_valid(_far_flag) else 0.,"audio_count":1,"collision_count":0,"mechanism_nodes":3}
func _exit_tree()->void:
 _playable=false;_echo_pending=0.;_echo_audio_armed=false;set_process(false)
 if is_instance_valid(_audio):_audio.stop()
 _audio=null;_wheel=null;_flap=null;_far_flag=null
