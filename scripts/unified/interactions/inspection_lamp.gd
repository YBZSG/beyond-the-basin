extends Node3D
## Original procedural inspection hardware. Host owns targeting/input/session.
@export var interaction_id := "connector/inspection_lamp"
## Set before entering tree. Existing mesh references are never hot-swapped.
@export var hardware_material: Material
## Wall adapter: north-wall backplate, operation and beam both face +Z.
@export var wall_mount_positive_z := false
var _used_external_material := false
var _head: Node3D
var _light: SpotLight3D
var _lever: Node3D
var _playable := false
var _initialized := false
var _value := 0
var _yaw := -0.35
var _target_yaw := -0.35
var _energy := 0.0
var _target_energy := 0.0
func _ready() -> void:
 add_to_group("dream_scene_effect")
 _build(); set_process(false)
func _box(parent: Node3D, size: Vector3, position_: Vector3, material: Material) -> void:
 var mesh := BoxMesh.new(); mesh.size=size
 var part := MeshInstance3D.new();part.mesh=mesh;part.position=position_;part.material_override=material;parent.add_child(part)
func _build() -> void:
 var metal: Material = hardware_material
 _used_external_material = metal != null
 if metal == null:
  var fallback := StandardMaterial3D.new();fallback.albedo_color=Color("424a49");fallback.metallic=0.65;fallback.roughness=0.55;metal=fallback
 _box(self,Vector3(.14,.24,.07),Vector3(0,1.1,0),metal)
 _lever=Node3D.new();_lever.position=Vector3(0,1.1,.06);add_child(_lever)
 _box(_lever,Vector3(.025,.09,.03),Vector3(0,.035,0),metal)
 _box(self,Vector3(.035,.95,.035),Vector3(0,1.68,-.015),metal)
 if wall_mount_positive_z: _box(self,Vector3(.035,.035,.16),Vector3(0,2.16,.05),metal)
 _head=Node3D.new();_head.position=Vector3(0,2.16,.11 if wall_mount_positive_z else 0.0);add_child(_head)
 _box(_head,Vector3(.24,.15,.18),Vector3(0,0,0),metal)
 _light=SpotLight3D.new();_light.position=Vector3(0,-.025,-.11);_light.rotation.x=-.55 if wall_mount_positive_z else -.2
 if wall_mount_positive_z:
  _light.position.z=.11;_light.rotation.y=PI
 _light.spot_range=4.0 if wall_mount_positive_z else 32.;_light.spot_angle=24.;_light.light_color=Color("e4dec9");_light.light_energy=0.;_light.shadow_enabled=wall_mount_positive_z
 _head.add_child(_light)
 _apply_pose()
func apply_state(values_: Dictionary, _observed: Dictionary, _reduced_effects: bool) -> void:
 var next := clampi(int(values_.get(interaction_id,0)),0,2)
 _value=next;_target_energy=0.0 if next==0 else 2.0;_target_yaw=-.35 if next<=1 else .35
 if not _initialized or not _playable:
  _initialized=true;_yaw=_target_yaw;_energy=_target_energy;_apply_pose();set_process(false)
 else: set_process(not is_equal_approx(_yaw,_target_yaw) or not is_equal_approx(_energy,_target_energy))
func set_playable(value: bool) -> void:
 _playable=value
 set_process(value and _initialized and (not is_equal_approx(_yaw,_target_yaw) or not is_equal_approx(_energy,_target_energy)))
func set_audio_enabled(_value_: bool) -> void: pass
func _process(delta: float) -> void:
 if not _playable: set_process(false);return
 var step:=minf(maxf(delta,0.0),.05)
 _yaw=move_toward(_yaw,_target_yaw,step*.7);_energy=move_toward(_energy,_target_energy,step*3.)
 _apply_pose()
 if is_equal_approx(_yaw,_target_yaw) and is_equal_approx(_energy,_target_energy): set_process(false)
func _apply_pose() -> void:
 if is_instance_valid(_head):_head.rotation.y=_yaw
 if is_instance_valid(_light):_light.light_energy=_energy
 if is_instance_valid(_lever):_lever.rotation.x=0.0 if _value==0 else (-.25 if _value==1 else .25)
func diagnostics() -> Dictionary:
 return {"value":_value,"energy":_energy,"yaw":_yaw,"playable":_playable,"processing":is_processing(),"collision_count":0,"audio_count":0,"shadow_light_count":1 if is_instance_valid(_light) and _light.shadow_enabled else 0,"prototype_visual":true,"external_material":_used_external_material}
func _exit_tree() -> void:
 _playable=false;set_process(false);_head=null;_light=null;_lever=null
