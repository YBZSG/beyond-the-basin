extends Node3D
## World-owned finite mechanical display. No input, save, player or water references.
## The runtime alone operates reservoir_shutter; this actor consumes a snapshot.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const P="soffit_reservoir_"
var _leaves:Array[Node3D]=[]
var _wheel:Node3D
var _lights:Array[OmniLight3D]=[]
var _playable=false
var _value=0
var _pose=0.0
var _target=0.0
var _initialized=false
var _reduced=true
var _blade_mesh:Mesh
var _bearing_mesh:Mesh
func _ready()->void:
 add_to_group("dream_scene_effect");_build();set_process(false);_apply_pose(0.0)
func _mesh(parent:Node3D,mesh:Mesh,pos:Vector3,key:String)->MeshInstance3D:
 var n=MeshInstance3D.new();n.mesh=mesh;n.position=pos;n.material_override=G.mat(P+key);n.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;parent.add_child(n);return n
func _box(parent:Node3D,pos:Vector3,size:Vector3,key:String)->MeshInstance3D:
 var mesh=BoxMesh.new();mesh.size=size;return _mesh(parent,mesh,pos,key)
func _rod(parent:Node3D,a:Vector3,b:Vector3,r:float,key:String,segments:int=16)->MeshInstance3D:
 var mesh=CylinderMesh.new();mesh.top_radius=r;mesh.bottom_radius=r;mesh.height=a.distance_to(b);mesh.radial_segments=segments;mesh.rings=0
 var n=_mesh(parent,mesh,(a+b)*.5,key);n.quaternion=Quaternion(Vector3.UP,(b-a).normalized());return n
func _quad(st:SurfaceTool,p:Array,n:Vector3)->void:
 for ids in [[0,1,2],[0,2,3]]:
  var a:Vector3=p[ids[0]];var b:Vector3=p[ids[1]];var c:Vector3=p[ids[2]]
  if (b-a).cross(c-a).dot(n)>0:
   var tmp=b;b=c;c=tmp
  st.set_normal(n)
  for v in [a,b,c]:st.add_vertex(v)
func _blade()->Mesh:
 if _blade_mesh!=null:return _blade_mesh
 # Full3.986m cassette silhouette; only real bearing clearance notches near
 # the shaft. Five pieces are merged into one shared leaf mesh, not5 draws.
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var parts=[[Vector3.ZERO,Vector3(3.86,1.60,.065)]]
 for side in [-1.,1.]:
  for y in [-.49,.49]:parts.append([Vector3(side*1.9615,y,0),Vector3(.063,.62,.065)])
 for part in parts:
  var mesh=BoxMesh.new();mesh.size=part[1];st.append_from(mesh,0,Transform3D(Basis.IDENTITY,part[0]))
 _blade_mesh=st.commit();_blade_mesh.resource_name="Soffit notched louver leaf";return _blade_mesh
func _bearing()->Mesh:
 if _bearing_mesh!=null:return _bearing_mesh
 # Through-bored shared bearing plate:70mm shaft /76mm bore,3mm radial gap.
 # Plate envelope is85 x210 x250mm; blade notch clears its whole sweep disk.
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);var angles:Array[float]=[]
 for j in 32:angles.append(j*TAU/32.)
 for sy in [-1.,1.]:
  for sz in [-1.,1.]:angles.append(fposmod(atan2(sz*.125,sy*.105),TAU))
 angles.sort();var outer:Array=[];var inner:Array=[]
 for angle in angles:
  var d=Vector2(cos(angle),sin(angle));var reach=minf(.105/absf(d.x) if absf(d.x)>.000001 else INF,.125/absf(d.y) if absf(d.y)>.000001 else INF)
  outer.append(Vector3(0,d.x*reach,d.y*reach));inner.append(Vector3(0,d.x*.038,d.y*.038))
 for j in angles.size():
  var k=(j+1)%angles.size();var radial:Vector3=(inner[j]+inner[k]).normalized();var mid:Vector3=(outer[j]+outer[k])*.5
  var edge_normal=Vector3(0,signf(mid.y),0) if absf(mid.y)>.10499 else Vector3(0,0,signf(mid.z))
  for side in [-1.,1.]:
   var dx=Vector3(side*.0425,0,0);_quad(st,[outer[j]+dx,outer[k]+dx,inner[k]+dx,inner[j]+dx],Vector3(side,0,0))
  _quad(st,[inner[j]+Vector3(-.0425,0,0),inner[k]+Vector3(-.0425,0,0),inner[k]+Vector3(.0425,0,0),inner[j]+Vector3(.0425,0,0)],-radial)
  _quad(st,[outer[j]+Vector3(-.0425,0,0),outer[k]+Vector3(-.0425,0,0),outer[k]+Vector3(.0425,0,0),outer[j]+Vector3(.0425,0,0)],edge_normal)
 _bearing_mesh=st.commit();_bearing_mesh.resource_name="Soffit through-bored bearing";return _bearing_mesh
func _build()->void:
 # 20 linked metal louver cassettes, never a traversable/moving collision surface.
 for i in 20:
  var x=-38.0+i*4.;var root=Node3D.new();root.name="Louver_%02d"%i;root.position=Vector3(x,2.68,-64.0);add_child(root);_leaves.append(root)
  _mesh(root,_blade(),Vector3.ZERO,"paint")
  # Folded edges keep every blade full-depth. Closed top overlaps its real
  # frame; 14mm cassette joints prevent a false railing of glowing gaps.
  for y in [-.77,.77]:_box(root,Vector3(0,y,-.075),Vector3(3.986,.055,.15),"steel")
  _rod(root,Vector3(-2,0,0),Vector3(2,0,0),.035,"steel",20)
 # One true bored bearing per shared cassette boundary, not overlapping pairs.
 for i in 21:
  var x=-40.+i*4.;var bearing=_mesh(self,_bearing(),Vector3(x,2.68,-64),"steel");bearing.name="Bearing_%02d"%i
  var brace=_rod(self,Vector3(x,2.68,-63.875),Vector3(x,2.95,-63.8),.004,"steel");brace.name="Brace_%02d"%i
 # Human-size wheel: ring, hub, spokes, hand grip and capped shaft.
 _wheel=Node3D.new();_wheel.name="Handwheel";_wheel.position=Vector3(38.55,1.52,-26);add_child(_wheel)
 var torus=TorusMesh.new();torus.inner_radius=.29;torus.outer_radius=.34;torus.rings=64;torus.ring_segments=10
 var rim=_mesh(_wheel,torus,Vector3.ZERO,"paint");rim.rotation.z=PI*.5
 _rod(_wheel,Vector3(-.045,0,0),Vector3(.045,0,0),.075,"steel",24)
 for i in 6:
  var t=i*TAU/6.;_rod(_wheel,Vector3.ZERO,Vector3(0,sin(t)*.30,cos(t)*.30),.018,"steel")
 _rod(_wheel,Vector3(-.03,.24,0),Vector3(-.16,.24,0),.028,"dark_steel",20)
 # The two rear practical lights sit in the physical illuminated recess.
 for x in [-20.,20.]:
  var light=OmniLight3D.new();light.name="RecessPractical";light.position=Vector3(x,2.65,-66.0);light.light_color=Color("ffd09a");light.light_energy=.35;light.omni_range=36.;light.light_specular=0.0;light.shadow_enabled=false;add_child(light);_lights.append(light)
 # An existing fixture in the folded exit is fed by the same maintenance circuit.
 var exit_light=OmniLight3D.new();exit_light.name="SideExitPractical";exit_light.position=Vector3(43,2.6,-61);exit_light.light_color=Color("ffd09a");exit_light.omni_range=9.;exit_light.shadow_enabled=false;exit_light.light_specular=0.0;add_child(exit_light);_lights.append(exit_light)
func apply_state(values:Dictionary,_observed:Dictionary,reduced_effects:bool)->void:
 var next=clampi(int(values.get("reservoir_shutter",0)),0,1)
 var settings_changed=_reduced!=reduced_effects;_reduced=reduced_effects
 if _initialized and next==_value and not settings_changed:return
 if not _initialized or not _playable or reduced_effects:
  _value=next;_target=float(next);_pose=_target;_initialized=true;_apply_pose(_pose);set_process(false);return
 if next==_value:return
 _value=next;_target=float(next);set_process(true)
func set_playable(value:bool)->void:
 _playable=value
 if not value:set_process(false)
 elif _initialized and not _reduced and not is_equal_approx(_pose,_target):set_process(true)
func _process(delta:float)->void:
 if not _playable:set_process(false);return
 _pose=move_toward(_pose,_target,minf(delta,.05)*.42);_apply_pose(_pose)
 if is_equal_approx(_pose,_target):set_process(false)
func _apply_pose(value:float)->void:
 for leaf:Node3D in _leaves:leaf.rotation.x=deg_to_rad(65.)*value
 if is_instance_valid(_wheel):_wheel.rotation.x=TAU*1.25*value
 for light:OmniLight3D in _lights:light.light_energy=lerpf(.05,.75,value) if light.name=="SideExitPractical" else lerpf(.35,1.0,value)
func diagnostics()->Dictionary:
 return {"station":"reservoir_shutter","value":_value,"pose":_pose,"target":_target,"playable":_playable,"processing":is_processing(),"louver_count":_leaves.size(),"light_count":_lights.size(),"collision_count":0,"audio_count":0,"max_leaf_angle_degrees":65.0,"state_initialized":_initialized,"bearing_count":21,"shaft_radius":.035,"bearing_bore_radius":.038,"blade_notch_half_height":.18,"blade_half_height":.80,"closed_clear_slit_m":.16,"brace_radius":.004,"cassette_joint_m":.014}
func _exit_tree()->void:
 _playable=false;set_process(false);_leaves.clear();_lights.clear();_wheel=null
