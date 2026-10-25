extends SceneTree
func find_type(n: Node, type: String) -> Node:
	if n.is_class(type): return n
	for c in n.get_children():
		var found := find_type(c,type)
		if found != null: return found
	return null
func _initialize() -> void:
	var source := load("res://assets/character_refinement/handmade_motion/explorer_handmade_motion.glb").instantiate() as Node
	var target := load("res://assets/character_refinement/natural_hand_finish/explorer_natural_hand.glb").instantiate() as Node
	root.add_child(source);root.add_child(target)
	var ss := find_type(source,"Skeleton3D") as Skeleton3D
	var ts := find_type(target,"Skeleton3D") as Skeleton3D
	assert(ss.get_bone_count()==54 and ts.get_bone_count()==54)
	var error := 0.0
	for i in ss.get_bone_count():
		var j := ts.find_bone(ss.get_bone_name(i))
		assert(j>=0)
		var a := ss.get_bone_global_rest(i)
		var b := ts.get_bone_global_rest(j)
		error=maxf(error,a.origin.distance_to(b.origin))
		for axis in 3: error=maxf(error,a.basis[axis].distance_to(b.basis[axis]))
	assert(error<0.0001,"Exported author rig rest differs from runtime rig")
	var ap := find_type(source,"AnimationPlayer") as AnimationPlayer
	var library := AnimationLibrary.new()
	var counts := {}
	for name in ap.get_animation_list():
		var leaf := str(name).get_file()
		if leaf not in ["Pickup","SetDown","WadeRest"]: continue
		var anim := ap.get_animation(name).duplicate(true) as Animation
		for track in range(anim.get_track_count()-1,-1,-1):
			var path := anim.track_get_path(track)
			var bone := str(path.get_subname(0)) if path.get_subname_count()>0 else ""
			if bone in ["Root","Hips"] or bone.begins_with("UpperLeg") or bone.begins_with("LowerLeg") or bone.begins_with("Foot") or bone.begins_with("Toe") or anim.track_get_type(track)!=Animation.TYPE_ROTATION_3D:
				anim.remove_track(track)
			else: anim.track_set_path(track,NodePath("Skeleton3D:"+bone))
		print("TRACKS ",leaf," ",anim.get_track_count())
		assert(anim.get_track_count()==42) # Constant Neck/Head tracks optimized out by importer.
		anim.loop_mode=Animation.LOOP_LINEAR if leaf=="WadeRest" else Animation.LOOP_NONE
		library.add_animation(leaf,anim);counts[leaf]=anim.get_track_count()
	assert(library.get_animation_list().size()==3)
	assert(ResourceSaver.save(library,"res://assets/character_refinement/handmade_motion/handmade_actions.tres")==OK)
	print("HANDMADE_LIBRARY_OK ",counts," rest_error=",error)
	source.queue_free();target.queue_free();quit()
