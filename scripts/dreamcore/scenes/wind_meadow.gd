extends RefCounted
## Original stable additive density LOD. Far roots never move or get replaced:
## approaching the camera smoothly reveals extra mid/near roots at fixed sites.
## Per-root fades finish BEFORE small local-origin batches can distance-cull.
const Cache=preload("res://scripts/dreamcore/scenes/wind_meadow_cache.gd")
static var cache_warnings:Dictionary={}
const TILE_SIZE:=8.0
const MAX_PER_BATCH:=2048
const LAYERS:=[
	{"name":"far","density":2.0,"leaves":4,"fade":Vector2(42,60)},
	{"name":"mid","density":6.0,"leaves":8,"fade":Vector2(22,38)},
	{"name":"near","density":26.0,"leaves":16,"fade":Vector2(10,22)}]
static var meshes:Dictionary={}
static var materials:Dictionary={}
static func tint_ground(root:Node3D)->void:
	# Retain original grass textures and roughness. Suppress dry red/blue cast
	# slightly rather than adding light/emission or repainting water/path assets.
	for node:Node in root.get_children():
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:continue
		var source:ShaderMaterial=node.material_override
		if source.resource_name!="grass":continue
		if not materials.has("ground"):
			var mat:ShaderMaterial=source.duplicate();mat.resource_name="meadow_ground_grass"
			mat.set_shader_parameter("base_color",Color(.82,1.,.78));materials.ground=mat
		node.material_override=materials.ground
static func mesh_subset(source:ArrayMesh,leaves:int)->ArrayMesh:
	if meshes.has(leaves):return meshes[leaves]
	var a:=source.surface_get_arrays(0);var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
	var normals:Array[Vector3]=[];normals.resize(a[Mesh.ARRAY_VERTEX].size());normals.fill(Vector3.ZERO)
	# Area-weighted clockwise physical face normals. Unlike the old upward
	# shading bias, these remain plausible after short nonuniform height scales.
	for k in range(0,leaves*9,3):
		var ia:=indices[k];var ib:=indices[k+1];var ic:=indices[k+2]
		var pa:Vector3=a[Mesh.ARRAY_VERTEX][ia];var pb:Vector3=a[Mesh.ARRAY_VERTEX][ib];var pc:Vector3=a[Mesh.ARRAY_VERTEX][ic]
		var n:=-(pb-pa).cross(pc-pa)
		normals[ia]+=n;normals[ib]+=n;normals[ic]+=n
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(leaves*9):
		var i:=indices[k];var tip_index:=indices[(k/9)*9+8];st.set_uv2(Vector2(0.,a[Mesh.ARRAY_VERTEX][tip_index].y));st.set_uv(a[Mesh.ARRAY_TEX_UV][i]);st.set_normal(normals[i].normalized());st.add_vertex(a[Mesh.ARRAY_VERTEX][i])
	st.index();var mesh:=st.commit();meshes[leaves]=mesh;return mesh
static func density_mask(p:Vector3)->float:
	# Continuous low-frequency density, never a mask of isolated empty islands.
	return .85+.12*sin(p.x*.19+sin(p.z*.13)*2.)*sin(p.z*.27)
static func allowed(p:Vector3,config:Dictionary)->bool:
	if absf(p.x)>141.6 or absf(p.z)>141.6:return false
	for exclusion:Rect2 in config.exclusions:
		if exclusion.grow(.24).has_point(Vector2(p.x,p.z)):return false
	return true
static func allowed_prepared(p:Vector3,exclusions:Array[Rect2])->bool:
	if absf(p.x)>141.6 or absf(p.z)>141.6:return false
	var flat:=Vector2(p.x,p.z)
	for exclusion:Rect2 in exclusions:
		if exclusion.has_point(flat):return false
	return true
static func layer_specs(root:Node3D,config:Dictionary)->Array:
	var radius:=int(config.get("stream_radius",2))
	if not config.has("stream_radius") and root.get_parent()!=null:
		for property:Dictionary in root.get_parent().get_property_list():
			if property.name=="stream_radius":radius=int(root.get_parent().get("stream_radius"));break
	var specs:Array=LAYERS.duplicate(true)
	if config.get("style","")=="verge":
		for i in range(3):specs[i].density=[.2,.6,2.4][i] # sparse cracks, never a roadside meadow
	if radius<=1:
		for i in range(3):specs[i].fade=[Vector2(18,28),Vector2(12,22),Vector2(6,14)][i]
	return specs
static func attach_batch(root:Node3D,layer:Dictionary,layer_id:int,ix:int,iz:int,position:Vector3,mm:MultiMesh,style:String,base_material:ShaderMaterial)->MultiMeshInstance3D:
	var key:String=style+"_"+layer.name+"_"+str(layer.fade.y)
	if not materials.has(key):
		var mat:ShaderMaterial=base_material.duplicate();mat.shader=preload("res://assets/dreamcore/outdoor/wind_meadow.gdshader");mat.set_shader_parameter("fade_start",layer.fade.x);mat.set_shader_parameter("fade_end",layer.fade.y);materials[key]=mat
	var node:=MultiMeshInstance3D.new();node.name="WindMeadow_%s_%d_%d"%[layer.name,ix,iz];node.position=position
	node.multimesh=mm;node.material_override=materials[key];node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Expanded corner radius sqrt(4.9^2*2+1.3^2)<7.1m.
	node.custom_aabb=AABB(Vector3(-4.9,.3,-4.9),Vector3(9.8,1.,9.8));node.visibility_range_end=layer.fade.y+7.1
	node.set_meta("grass_layer",layer_id);node.set_meta("fade_range",layer.fade);node.set_meta("grass_tile",Vector2i(ix,iz));root.add_child(node)
	return node
static func build(root:Node3D,coord:Vector2i,config:Dictionary,source:ArrayMesh,base_material:ShaderMaterial)->void:
	var started:=Time.get_ticks_usec();var mode:String=config.get("recipe_mode","cache")
	var error:="source_forced"
	if mode!="source":
		var layers:=layer_specs(root,config)
		var cached:=Cache.read_recipe(config.style,coord,Cache.signature(config,layers))
		if not cached.has("error"):
			var validation_us:=Time.get_ticks_usec()-started;var audit_us:=0;var upload_us:=0
			for record:Dictionary in cached.records:
				var upload_started:=Time.get_ticks_usec();var layer:Dictionary=layers[record.layer]
				var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_custom_data=true;mm.mesh=mesh_subset(source,layer.leaves);mm.instance_count=record.count;mm.buffer=record.buffer
				var node:=attach_batch(root,layer,record.layer,record.ix,record.iz,Vector3(-12.+record.ix*8.,0,-12.+record.iz*8.),mm,config.style,base_material)
				upload_us+=Time.get_ticks_usec()-upload_started
				if config.get("audit",false):
					var audit_started:=Time.get_ticks_usec();var decoded:=Cache.decode_buffer(record.buffer);node.set_meta("authored_transforms",decoded.transforms);node.set_meta("authored_custom_data",decoded.custom);audit_us+=Time.get_ticks_usec()-audit_started
			root.set_meta("grass_build_stats",{"cache_status":"hit","cache_decode_validate_cpu_us":validation_us,"audit_decode_cpu_us":audit_us,"cache_file_bytes":cached.file_bytes,"candidate_sites":0,"submitted_instances":cached.instances,"batches":cached.records.size(),"logical_instance_bytes":cached.instances*64,"elapsed_cpu_us":Time.get_ticks_usec()-started,"placement_cpu_us":0,"upload_and_node_cpu_us":upload_us,"audit_arrays_retained":config.get("audit",false),"finite_validation":cached.finite_validation})
			return
		error=cached.error
		var warning_key:String=config.style+":"+error
		if not cache_warnings.has(warning_key):
			cache_warnings[warning_key]=true
			push_warning("Grass recipe "+warning_key+": bounded synchronous source fallback; NOT cache fast path. Regenerate with tools/dreamcore/generate_grass_recipes.gd")
	build_source(root,coord,config,source,base_material)
	var stats:Dictionary=root.get_meta("grass_build_stats");stats.cache_status=error;stats.elapsed_with_cache_attempt_us=Time.get_ticks_usec()-started;root.set_meta("grass_build_stats",stats)
static func build_source(root:Node3D,coord:Vector2i,config:Dictionary,source:ArrayMesh,base_material:ShaderMaterial)->void:
	var started:=Time.get_ticks_usec();var candidate_sites:=0;var submitted_instances:=0;var batch_count:=0;var placement_us:=0;var upload_us:=0
	var origin:=Vector3(coord.x*32.,0,coord.y*32.)
	var layers:=layer_specs(root,config)
	for iz in range(4):
		for ix in range(4):
			var tile:=Rect2(origin.x-16.+ix*TILE_SIZE,origin.z-16.+iz*TILE_SIZE,TILE_SIZE,TILE_SIZE)
			var center:=Vector3(tile.get_center().x,0,tile.get_center().y)
			# Prepare masks once per tile, not grow/test every distant rectangle
			# for every root. This preserves identical accepted sites and RNG calls.
			var tile_exclusions:Array[Rect2]=[]
			for exclusion:Rect2 in config.exclusions:
				var expanded:=exclusion.grow(.24)
				if expanded.intersects(tile):tile_exclusions.append(expanded)
			var surfaces:Array=[]
			for surface:AABB in config.patches:
				var rect:=Rect2(surface.position.x+.24,surface.position.z+.24,surface.size.x-.48,surface.size.z-.48).intersection(tile)
				if rect.has_area():surfaces.append({"rect":rect,"height":surface.end.y+.001})
			for layer_id in range(layers.size()):
				var layer:Dictionary=layers[layer_id]
				var transforms:Array[Transform3D]=[];var colors:Array[Color]=[];var occupied:Dictionary={}
				var spacing:=1./sqrt(float(layer.density))
				var rng:=RandomNumberGenerator.new();var placement_started:=Time.get_ticks_usec()
				for surface:Dictionary in surfaces:
					var rect:Rect2=surface.rect
					for gz in range(floori(rect.position.y/spacing),ceili(rect.end.y/spacing)):
						for gx in range(floori(rect.position.x/spacing),ceili(rect.end.x/spacing)):
							candidate_sites+=1
							rng.seed=12347+gx*73856093+gz*19349663+layer_id*83492791
							var p:=Vector3((gx+rng.randf_range(.1,.9))*spacing,surface.height,(gz+rng.randf_range(.1,.9))*spacing)
							if not rect.has_point(Vector2(p.x,p.z)) or not allowed_prepared(p,tile_exclusions):continue
							if rng.randf()>density_mask(p):continue
							var site:=Vector2i(gx,gz)
							if surfaces.size()>1:
								if occupied.has(site):continue # overlapping dry patches are a union, not double grass
								occupied[site]=true
							var h:=rng.randf_range(config.height.x,config.height.y)
							var basis:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(rng.randf_range(.85,1.15),h,rng.randf_range(.85,1.15)))
							transforms.append(Transform3D(basis,p-center));colors.append(Color(rng.randf(),rng.randf(),rng.randf(),1.))
				placement_us+=Time.get_ticks_usec()-placement_started
				if transforms.is_empty():continue
				var upload_started:=Time.get_ticks_usec()
				assert(transforms.size()<=MAX_PER_BATCH,"Meadow tile cap exceeded; do not silently truncate placement")
				var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_custom_data=true;mm.mesh=mesh_subset(source,layer.leaves);mm.instance_count=transforms.size()
				for i in range(transforms.size()):mm.set_instance_transform(i,transforms[i]);mm.set_instance_custom_data(i,colors[i])
				var node:=attach_batch(root,layer,layer_id,ix,iz,center-origin,mm,config.style,base_material)
				if config.get("audit",false):node.set_meta("authored_transforms",transforms);node.set_meta("authored_custom_data",colors)
				submitted_instances+=transforms.size();batch_count+=1;upload_us+=Time.get_ticks_usec()-upload_started
	# Logical packed instance data:3x4 float transform +4 float custom color.
	# Excludes engine/GPU allocator overhead and transient GDScript arrays.
	assert(candidate_sites<=50000,"Authored per-chunk candidate bound exceeded")
	root.set_meta("grass_build_stats",{"candidate_sites":candidate_sites,"submitted_instances":submitted_instances,"batches":batch_count,"logical_instance_bytes":submitted_instances*64,"elapsed_cpu_us":Time.get_ticks_usec()-started,"placement_cpu_us":placement_us,"upload_and_node_cpu_us":upload_us,"audit_arrays_retained":config.get("audit",false)})
