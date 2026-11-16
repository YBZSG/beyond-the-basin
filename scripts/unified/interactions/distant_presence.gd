extends Node3D
## TEST PROXY, not final creature art. Never translates, pursues or harms.
@export var interaction_id := "connector/wall_presence"
@export var debug_proxy_visible := false
var _body: Node3D
var _playable := false
var _initialized := false
var _reduced := true
var _value := 0
var _time := 0.0
func _ready() -> void:
 add_to_group("dream_scene_effect")
 _body=Node3D.new();_body.name="PROXY_ONLY_ReplaceWithAuthoredCreature";_body.visible=debug_proxy_visible;add_child(_body)
 var material:=StandardMaterial3D.new();material.albedo_color=Color("59635e");material.roughness=.92
 # Simple slab silhouette deliberately marked as a placeholder, not a monster asset.
 var mesh:=BoxMesh.new();mesh.size=Vector3(3.2,7.,.8)
 var part:=MeshInstance3D.new();part.mesh=mesh;part.position=Vector3(0,3.5,0);part.material_override=material;_body.add_child(part)
 set_meta("prototype_only",true);set_process(false)
func apply_state(values_: Dictionary, _observed: Dictionary, reduced_effects: bool) -> void:
 var next:=clampi(int(values_.get(interaction_id,0)),0,2)
 _reduced=reduced_effects
 if not _initialized or not _playable:
  _initialized=true;_value=next;_time=4.0;_rest();set_process(false);return
 if next!=_value:
  _value=next
  if next==2 and not _reduced:_time=0.0;set_process(true)
  else:_rest();set_process(false)
 elif _reduced:_rest();set_process(false)
func set_playable(value: bool) -> void:
 _playable=value
 if not value:_rest();set_process(false)
 # Never replay a pulse missed during pause/loading or zone restoration.
func set_audio_enabled(_value_: bool) -> void: pass
func _process(delta: float) -> void:
 if not _playable or _reduced:_rest();set_process(false);return
 _time=minf(4.0,_time+minf(maxf(delta,0.0),.05))
 if is_instance_valid(_body):_body.scale.z=1.0+sin(_time*PI/4.0)*.002
 if _time>=4.0:_rest();set_process(false)
func _rest() -> void:
 if is_instance_valid(_body):_body.scale=Vector3.ONE
func diagnostics() -> Dictionary:
 return {"value":_value,"playable":_playable,"processing":is_processing(),"reduced_effects":_reduced,"prototype_visual":true,"debug_proxy_visible":is_instance_valid(_body) and _body.visible,"anchor":transform.origin,"collision_count":0,"audio_count":0,"timer_count":0,"has_pursuit":false,"has_damage":false}
func _exit_tree() -> void:
 _playable=false;set_process(false);_body=null
