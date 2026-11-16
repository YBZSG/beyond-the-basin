extends RefCounted
## Context-specific original models; origins stay at existing floor-level anchors.
## Sports: backless aluminum 2.424 x .49 m, seat 0.455 m.
## Shelter: four ash seat slats, reclined back faces shelter wall (-Z), seat 0.455 m.
static func build(root:Node3D,p:Vector3,kind:String)->void:
	var model:PackedScene=load("res://assets/dreamcore/outdoor/seating/"+kind+"_bench.glb")
	var n:Node3D=model.instantiate();n.name=kind.capitalize()+"Bench";n.position=p;root.add_child(n)
static func sports_collision(p:Vector3)->AABB:
	# Rotated +90 degrees with the authored seat, retaining track-side anchor.
	return AABB(p+Vector3(-.045,0,-1.212),Vector3(.49,.458,2.424))
static func bus_collision(p:Vector3)->Array:
	return [AABB(p+Vector3(-1.1,0,-.25),Vector3(2.2,.457,.53)),
		AABB(p+Vector3(-1.1,.55,-.385),Vector3(2.2,.422,.16)),
		AABB(p+Vector3(-1.068,.4,-.235),Vector3(.066,.298,.44)),
		AABB(p+Vector3(1.002,.4,-.235),Vector3(.066,.298,.44))]
