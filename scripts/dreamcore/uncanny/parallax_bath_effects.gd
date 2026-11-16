extends Node3D
## One bounded, non-colliding mechanical folding rule in a fixed guarded recess.
## No player, source-water, input, camera, save or global-light references.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
var _hinge:Node3D
var _target:=0
var _reduced:=false
var _playable:=false
var _built:=false
func _ready()->void:
 add_to_group("dream_scene_effect");_build();set_process(false)
func _part(groups:Dictionary,size:Vector3,at:Vector3,key:String)->void:
 if not groups.has(key):
  var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);groups[key]=surface
 var st:SurfaceTool=groups[key];var box=BoxMesh.new();box.size=size;var arrays=box.surface_get_arrays(0)
 var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 for index:int in indices:
  var point:Vector3=verts[index]+at;st.set_normal(normals[index]);st.set_uv(G.metric_uv(point,normals[index]));st.add_vertex(point)
func _segment(parent:Node3D,direction:float,offset_z:float)->void:
 var groups:Dictionary={}
 _part(groups,Vector3(.038,.9,.115),Vector3(0,direction*.45,offset_z),"ruler")
 for i in 10:
  var y=direction*float(i)*.1;var width=.08 if i%5==0 else .047
  _part(groups,Vector3(.004,.008,width),Vector3(-.022,y,offset_z-.015),"mark")
  if i<9:
   for j in [1,2,3,4]:_part(groups,Vector3(.004,.003,.025),Vector3(-.022,y+direction*float(j)*.02,offset_z-.025),"mark")
 # Tick microdetail is two material batches per rule, not a hundred draw nodes.
 for key:String in groups:
  var st:SurfaceTool=groups[key];st.generate_tangents();var n=MeshInstance3D.new();n.mesh=st.commit();n.material_override=G.mat("parallax_bath_"+key);parent.add_child(n)
func _build()->void:
 if _built:return
 _built=true
 var fixed=Node3D.new();fixed.position=Vector3(7.19,1.3,-47);add_child(fixed);_segment(fixed,-1.,-.09)
 _hinge=Node3D.new();_hinge.position=Vector3(7.13,1.3,-47);add_child(_hinge);_segment(_hinge,1.,.09)
 var pin=MeshInstance3D.new();var cylinder=CylinderMesh.new();cylinder.top_radius=.065;cylinder.bottom_radius=.065;cylinder.height=.20;cylinder.radial_segments=24;pin.mesh=cylinder;pin.rotation.z=PI*.5;pin.position=Vector3(7.145,1.3,-47);pin.material_override=G.mat("parallax_bath_steel");add_child(pin)
 _snap()
func _snap()->void:
 if is_instance_valid(_hinge):_hinge.rotation.x=0.0 if _target==1 else PI
func apply_state(values:Dictionary,_observed:Dictionary,reduced_effects:bool)->void:
 var next=clampi(int(values.get("parallax_measure",0)),0,1)
 _target=next;_reduced=reduced_effects
 # Idempotent, instant restoration; the pose—not a UI counter—is the result.
 # No temporal animation is needed for this quiet mechanical disclosure.
 if _built:_snap()
func set_playable(value:bool)->void:
 _playable=value;set_process(false)
func diagnostics()->Dictionary:
 return {"value":_target,"unfolded":_target==1,"hinge_rotation_x":_hinge.rotation.x if is_instance_valid(_hinge) else -1.0,"rule_height_m":1.8 if _target==1 else .9,"playable":_playable,"processing":is_processing(),"audio_count":0,"rigid_bodies":0,"moving_collision":false,"node_count":_count(self),"reduced_effects":_reduced}
func _count(n:Node)->int:
 var count=1
 for c in n.get_children():count+=_count(c)
 return count
func _exit_tree()->void:
 _playable=false;set_process(false)
