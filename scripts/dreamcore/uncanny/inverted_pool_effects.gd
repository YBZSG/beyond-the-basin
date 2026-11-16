extends Node3D
## Normal-gravity plumb-line in a physically guarded service groove. No player/world references.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const P="inverted_pool_"
var _wheel:Node3D
var _weight:Node3D
var _line:MeshInstance3D
var _value=0
var _pose=0.0
var _target=0.0
var _playable=false
var _reduced=true
var _initialized=false
func _ready()->void:
 add_to_group("dream_scene_effect");_build();_apply_pose(0.);set_process(false)
func _mesh(parent:Node3D,m:Mesh,p:Vector3,key:String)->MeshInstance3D:
 var n=MeshInstance3D.new();n.mesh=m;n.position=p;n.material_override=G.mat(P+key);parent.add_child(n);return n
func _rod(parent:Node3D,a:Vector3,b:Vector3,r:float,key:String,segments:int=16)->MeshInstance3D:
 var m=CylinderMesh.new();m.top_radius=r;m.bottom_radius=r;m.height=a.distance_to(b);m.radial_segments=segments;m.rings=0;var n=_mesh(parent,m,(a+b)*.5,key);n.quaternion=Quaternion(Vector3.UP,(b-a).normalized());return n
func _build()->void:
 _wheel=Node3D.new();_wheel.name="ManualWinchCrank";_wheel.position=Vector3(29.45,1.52,-20);add_child(_wheel)
 var torus=TorusMesh.new();torus.inner_radius=.25;torus.outer_radius=.29;torus.rings=48;torus.ring_segments=10;var rim=_mesh(_wheel,torus,Vector3.ZERO,"paint");rim.rotation.z=PI*.5
 for i in 5:
  var t=i*TAU/5.;_rod(_wheel,Vector3.ZERO,Vector3(0,sin(t)*.26,cos(t)*.26),.018,"steel")
 _rod(_wheel,Vector3(-.04,0,0),Vector3(.04,0,0),.065,"steel",20);_rod(_wheel,Vector3(0,.22,0),Vector3(-.18,.22,0),.027,"dark_steel")
 # Fixed sheave above the protected groove; line remains vertical in world coordinates.
 var pulley=TorusMesh.new();pulley.inner_radius=.19;pulley.outer_radius=.23;pulley.rings=48;pulley.ring_segments=10;var pn=_mesh(self,pulley,Vector3(31.15,18.5,-20),"steel");pn.rotation.z=PI*.5
 _rod(self,Vector3(30.52,18.5,-20),Vector3(31.8,18.5,-20),.055,"steel",20)
 _weight=Node3D.new();_weight.name="PlumbWeightNormalGravity";_weight.position=Vector3(31.15,17.6,-19.77);add_child(_weight)
 var body=CylinderMesh.new();body.top_radius=.16;body.bottom_radius=.16;body.height=.30;body.radial_segments=24;body.rings=0;_mesh(_weight,body,Vector3(0,.09,0),"steel")
 var tip=CylinderMesh.new();tip.top_radius=.16;tip.bottom_radius=0.;tip.height=.24;tip.radial_segments=24;tip.rings=0;_mesh(_weight,tip,Vector3(0,-.18,0),"dark_steel")
 _rod(_weight,Vector3(0,.24,0),Vector3(0,.36,0),.025,"steel",16)
 # Unit-height mesh scales without any per-frame mesh/resource rebuild.
 var line_mesh=CylinderMesh.new();line_mesh.top_radius=.008;line_mesh.bottom_radius=.008;line_mesh.height=1.;line_mesh.radial_segments=8;line_mesh.rings=0;_line=_mesh(self,line_mesh,Vector3(31.15,18.,-19.77),"dark_steel")
func apply_state(values:Dictionary,_observed:Dictionary,reduced_effects:bool)->void:
 var next=clampi(int(values.get("inverted_plumb",0)),0,1);_reduced=reduced_effects
 if _initialized and not _playable:
  _value=next;_target=float(next);set_process(false);return
 if not _initialized or _reduced:
  _value=next;_target=float(next);_pose=_target;_initialized=true;_apply_pose(_pose);set_process(false);return
 if next==_value:return
 _value=next;_target=float(next);set_process(true)
func set_playable(value:bool)->void:
 _playable=value
 if not value:set_process(false)
 elif _initialized and _reduced:
  _pose=_target;_apply_pose(_pose);set_process(false)
 elif _initialized and not is_equal_approx(_pose,_target):set_process(true)
func set_audio_enabled(_value:bool)->void:pass
func _process(delta:float)->void:
 if not _playable:set_process(false);return
 _pose=move_toward(_pose,_target,minf(delta,.05)*.12);_apply_pose(_pose)
 if is_equal_approx(_pose,_target):set_process(false)
func _apply_pose(value:float)->void:
 var y=lerpf(17.6,2.0,value)
 if is_instance_valid(_weight):_weight.position.y=y
 if is_instance_valid(_wheel):_wheel.rotation.x=-TAU*3.0*value
 if is_instance_valid(_line):_line.position=Vector3(31.15,(18.5+y+.36)*.5,-19.77);_line.scale=Vector3(1,18.5-y-.36,1)
func diagnostics()->Dictionary:return {"station":"inverted_plumb","value":_value,"pose":_pose,"target":_target,"initialized":_initialized,"playable":_playable,"processing":is_processing(),"weight_position":[31.15,_weight.position.y if is_instance_valid(_weight) else 17.6,-19.77],"min_weight_y":2.0,"max_weight_y":17.6,"normal_gravity_axis":[0,-1,0],"enclosed_service_groove":true,"audio_count":0,"collision_count":0,"per_frame_mesh_rebuilds":0}
func _exit_tree()->void:
 _playable=false;set_process(false);_wheel=null;_weight=null;_line=null
