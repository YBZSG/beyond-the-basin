extends SceneTree
const CampaignWorld=preload("res://scripts/campaign/campaign_world.gd")
const Materials=preload("res://scripts/rendering/pool_materials.gd")
const Catalog=preload("res://scripts/campaign/campaign_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,reason:String)->void:
	checks+=1
	if not value:failures.append(reason);push_error(reason)
func _initialize()->void:call_deferred("run")
func run()->void:
	for index in range(Catalog.CHAPTER_COUNT):
		var data:Dictionary=Catalog.chapter(index)
		var world:=CampaignWorld.new();world.chapter_index=index
		world.formal_mode=data.mode=="formal";world.expanded_mode=data.mode in ["expanded","poolrooms","reference"];world.poolrooms_mode=data.mode=="poolrooms"
		root.add_child(world);world.initialize(250821,Materials.new());world.complete_pending_streaming()
		check(world.is_ready,"chapter %d ready"%index)
		check(world.resident_rooms.size()<=16,"chapter resident bound "+str(index))
		for spec:Dictionary in data.room_specs:
			check(world.is_room_ready(spec.coord),"target ready "+str(spec.coord))
			check(world.get_layout(spec.coord).name==data.items[data.room_specs.find(spec)].room_name,"identity preserved "+str(spec.coord))
			var spawn:Vector3=world.get_spawn_position(spec.coord)
			check(world.get_room_coord(spawn)==spec.coord,"spawn own room")
		await physics_frame;await physics_frame
		if data.mode not in ["reference","formal"]:
			for coord:Vector2i in world.finite_coords:
				for direction:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					if coord+direction in world.finite_coords:continue
					var center:=Vector3(coord.x*32,1.0,coord.y*32)
					var start:=center+Vector3(direction.x*15.7,0,direction.y*15.7)
					var end:=center+Vector3(direction.x*17,0,direction.y*17)
					var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,1))
					check(not hit.is_empty(),"opaque perimeter physical closure %s %s"%[coord,direction])
		world.queue_free();await process_frame;await process_frame
	print("CAMPAIGN_WORLD_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
