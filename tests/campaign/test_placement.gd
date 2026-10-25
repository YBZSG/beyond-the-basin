extends SceneTree
## Geometry-only real-collision audit; no water/NR/GPU readiness claim.
const Catalog = preload("res://scripts/campaign/campaign_catalog.gd")
const World = preload("res://scripts/campaign/campaign_world.gd")
const Materials = preload("res://scripts/rendering/pool_materials.gd")
var rows: Array[Dictionary] = []
var failures: Array[String] = []
func vector(value: Vector3) -> Array:
	return [snappedf(value.x,.001),snappedf(value.y,.001),snappedf(value.z,.001)]
func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
func floor_at(space: PhysicsDirectSpaceState3D, desired: Vector3) -> Dictionary:
	return ray(space,desired+Vector3.UP*.15,desired-Vector3.UP*2.1)
func candidate(space: PhysicsDirectSpaceState3D, desired: Vector3) -> Dictionary:
	var hit := floor_at(space,desired)
	if hit.is_empty(): return {"ok":false,"reason":"no_floor"}
	if Vector3(hit.normal).y<.8:return {"ok":false,"reason":"non_horizontal_support","normal":vector(hit.normal)}
	var support: Vector3 = hit.position
	var target := support+Vector3.UP*.85
	var probe := PhysicsShapeQueryParameters3D.new()
	var small := SphereShape3D.new();small.radius=.13
	probe.shape=small;probe.collision_mask=1;probe.transform=Transform3D(Basis(),target)
	if not space.intersect_shape(probe,1).is_empty():return {"ok":false,"reason":"item_embedded"}
	var capsule := CapsuleShape3D.new();capsule.radius=.32;capsule.height=1.64
	probe.shape=capsule
	for index in range(8):
		var angle := float(index)*TAU/8.0
		var offset := Vector3(cos(angle),0,sin(angle))*.85
		var approach_hit := floor_at(space,desired+offset)
		if approach_hit.is_empty() or Vector3(approach_hit.normal).y<.8:continue
		var foot: Vector3 = approach_hit.position+Vector3.UP*.012
		if absf(foot.y-support.y)>.25:continue
		probe.transform=Transform3D(Basis(),foot+Vector3.UP*.82)
		if not space.intersect_shape(probe,1).is_empty():continue
		var supported := true
		for side: Vector3 in [Vector3(.23,0,.23),Vector3(-.23,0,.23),Vector3(.23,0,-.23),Vector3(-.23,0,-.23)]:
			var corner := ray(space,foot+side+Vector3.UP*.10,foot+side-Vector3.UP*.18)
			if corner.is_empty() or Vector3(corner.normal).y<.8: supported=false;break
		if not supported:continue
		if not ray(space,foot+Vector3.UP*1.55,target).is_empty():continue
		return {"ok":true,"position":vector(target),"support":vector(support),"normal":vector(hit.normal),"approach":vector(foot),"approach_clearance_radius":.32,"approach_body_height":1.64}
	return {"ok":false,"reason":"no_safe_approach","support":vector(support)}
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for chapter_index in range(Catalog.CHAPTER_COUNT):
		var chapter := Catalog.chapter(chapter_index)
		var world := World.new()
		world.chapter_index=chapter_index
		world.formal_mode=chapter.mode=="formal"
		world.expanded_mode=chapter.mode in ["expanded","poolrooms","reference"]
		world.poolrooms_mode=chapter.mode=="poolrooms"
		root.add_child(world)
		world.initialize(Catalog.DEFAULT_SEED,Materials.new())
		world.complete_pending_streaming()
		await physics_frame
		await physics_frame
		var space := world.get_world_3d().direct_space_state
		for item: Dictionary in chapter.items:
			var desired: Vector3 = item.local_position+Vector3(item.coord.x*32.0,0,item.coord.y*32.0)
			var test := candidate(space,desired)
			var row := {"chapter":chapter.id,"id":item.id,"desired":vector(desired),"original":test}
			if not test.ok:
				failures.append(item.id+":"+str(test.reason))
				for radius: float in [.4,.8,1.2,1.6]:
					var found := false
					for direction in range(8):
						var angle := float(direction)*TAU/8.0
						var alternate := desired+Vector3(cos(angle),0,sin(angle))*radius
						var alternate_test := candidate(space,alternate)
						if alternate_test.ok:
							row["suggested"]={"desired":vector(alternate),"test":alternate_test};found=true;break
					if found:break
			rows.append(row)
		world.queue_free()
		await process_frame
		await physics_frame
	var output := {"engine":Engine.get_version_info().string,"scope":"Real room collision; floor, capsule, four support corners and eye-to-item ray. Does not establish global route accessibility or visual validity.","count":rows.size(),"unsafe_originals":failures,"rows":rows}
	var file:=FileAccess.open("res://tests/campaign/placement-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"));file.close()
	print("CAMPAIGN_PLACEMENT ",JSON.stringify({"count":rows.size(),"unsafe_originals":failures}))
	quit(0 if failures.is_empty() else 1)
