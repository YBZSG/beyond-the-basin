extends Node3D
## A sealed cinematic service shaft, not a claim of simultaneous vertical worlds.
## Hidden handoff occurs only at full black; collision-ready landing is a separate phase.
var camera: Camera3D
var lid: MeshInstance3D
var material: StandardMaterial3D
func _ready() -> void:
	material = StandardMaterial3D.new();material.albedo_color=Color("344c50");material.roughness=.52
	# Four walls overlap in the hidden outer corners; no zero-thickness planes.
	_box("West",Vector3(-1.8,-4.5,0),Vector3(.4,15,4.0))
	_box("East",Vector3(1.8,-4.5,0),Vector3(.4,15,4.0))
	_box("North",Vector3(0,-4.5,-1.8),Vector3(4.0,15,.4))
	_box("South",Vector3(0,-4.5,1.8),Vector3(4.0,15,.4))
	_box("Ceiling",Vector3(0,3.0,0),Vector3(4.0,.4,4.0))
	_box("Bottom",Vector3(0,-12.0,0),Vector3(4.0,.4,4.0))
	for y in [1.8,-1.2,-4.2,-7.2,-10.2]:
		_box("SeamBand",Vector3(0,y,-1.56),Vector3(3.25,.12,.08))
		var lamp:=OmniLight3D.new();lamp.position=Vector3(0,y,-1.25);lamp.light_color=Color("9ccfce");lamp.light_energy=.35;lamp.omni_range=4.0;lamp.shadow_enabled=true;add_child(lamp)
	lid=_box("OpeningHatch",Vector3(0,-.1,0),Vector3(3.2,.2,3.2))
	camera=Camera3D.new();camera.position=Vector3(0,1.6,.15);camera.rotation_degrees.x=-38;camera.fov=72;camera.near=.08;camera.far=30;add_child(camera);camera.current=true

func _box(label:String,point:Vector3,size:Vector3)->MeshInstance3D:
	var mesh:=MeshInstance3D.new();mesh.name=label;var shape:=BoxMesh.new();shape.size=size;mesh.mesh=shape;mesh.position=point;mesh.material_override=material;add_child(mesh);return mesh

func descend()->void:
	# Absolute tween targets are frame-rate independent and cannot fall forever.
	var animation:=create_tween().set_parallel(true)
	animation.tween_property(lid,"position:x",3.5,.45).set_trans(Tween.TRANS_CUBIC)
	animation.tween_property(camera,"position:y",-8.8,1.65).set_delay(.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await animation.finished
