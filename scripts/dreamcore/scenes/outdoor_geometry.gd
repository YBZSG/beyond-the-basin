extends RefCounted
## Original dimensioned architecture. Global design specifications are clipped to
## centered 32 m cells for collision, while distant architecture renders once.
static var cache: Dictionary = {}
static func mat(role:String)->Material:
	if cache.has(role): return cache[role]
	var kinds={"grass":1.,"track":2.,"asphalt":3.,"tile":4.,"metal":5.,"wood":5.,"rust":5.}
	var m:=ShaderMaterial.new();m.shader=preload("res://assets/dreamcore/outdoor/weathered.gdshader")
	m.resource_name=role
	m.set_shader_parameter("base_color",Color.WHITE)
	for channel in ["albedo","normal","roughness"]:m.set_shader_parameter(channel+"_map",load("res://assets/dreamcore/outdoor/textures/"+role+"_"+channel+".png"))
	m.set_shader_parameter("surface_kind",kinds.get(role,0.))
	m.set_shader_parameter("wetness",.95 if role in ["asphalt","tile"] else .0)
	cache[role]=m;return m
static func plain(color:Color,emission:float=0.)->Material:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.8
	if emission>0.:m.emission_enabled=true;m.emission=color;m.emission_energy_multiplier=emission
	return m
static func box(root:Node3D,p:Vector3,s:Vector3,role:String="concrete",collision:bool=false)->MeshInstance3D:
	var n:=MeshInstance3D.new();var primitive:=BoxMesh.new();primitive.size=s
	var arrays:=primitive.get_mesh_arrays();var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var uvs:=PackedVector2Array();var uv2:=PackedVector2Array()
	for i in range(vertices.size()):
		var w:=root.to_global(p+vertices[i]);var normal:Vector3=root.global_basis*normals[i]
		uvs.append((Vector2(w.x,w.z) if abs(normal.y)>.7 else (Vector2(w.z,w.y) if abs(normal.x)>.7 else Vector2(w.x,w.y)))*.25)
		uv2.append(Vector2(w.x,w.z)/288.+Vector2(.5,.5))
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_TEX_UV2]=uv2;var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var tool:=SurfaceTool.new();tool.create_from(mesh,0);tool.generate_tangents();n.mesh=tool.commit();n.position=p;n.material_override=mat(role);root.add_child(n)
	if collision:collider(root,AABB(p-s*.5,s))
	return n
static func collider(root:Node3D,a:AABB)->void:
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	var c:=CollisionShape3D.new();var s:=BoxShape3D.new();s.size=a.size;c.shape=s;c.position=a.get_center();body.add_child(c);root.add_child(body)
static func rod(root:Node3D,a:Vector3,b:Vector3,r:float=.045,role:String="metal")->void:
	var n:=MeshInstance3D.new();var m:=CylinderMesh.new();m.top_radius=r;m.bottom_radius=r;m.height=a.distance_to(b);m.radial_segments=8;m.rings=0;n.mesh=m;n.position=(a+b)*.5;n.quaternion=Quaternion(Vector3.UP,(b-a).normalized());n.material_override=mat(role);root.add_child(n)
static func clipped(a:AABB,coord:Vector2i)->AABB:
	var origin:=Vector3(coord.x*32.,0.,coord.y*32.)
	var b:=a.intersection(AABB(origin+Vector3(-16,-100,-16),Vector3(32,400,32)))
	return AABB(b.position-origin,b.size)
static func solids(specs:Array,coord:Vector2i)->Array[AABB]:
	var out:Array[AABB]=[]
	for a:AABB in specs:
		var c:=clipped(a,coord)
		if c.size.x>.001 and c.size.y>.001 and c.size.z>.001:out.append(c)
	return out
static func shell(root:Node3D,data:Dictionary)->void:
	for a:AABB in data.solids:collider(root,a)
static func floor_patch(root:Node3D,coord:Vector2i,a:AABB,role:String)->void:
	var c:=clipped(a,coord)
	if c.size.x>.001 and c.size.z>.001:box(root,c.get_center(),c.size,role)
static func bench(root:Node3D,p:Vector3)->void:
	for i in range(4):box(root,p+Vector3(0,.55,float(i)*.12),Vector3(2.2,.075,.1),"wood")
	for i in range(3):box(root,p+Vector3(0,.78+float(i)*.13,.43),Vector3(2.2,.085,.065),"wood")
	for x in [-.85,.85]:
		rod(root,p+Vector3(x,0,0),p+Vector3(x,.57,0),.035);rod(root,p+Vector3(x,0,.4),p+Vector3(x,1.1,.4),.035)
static func door(root:Node3D,p:Vector3,angle:float=0.)->void:
	var r:=Node3D.new();r.position=p;r.rotation.y=angle;root.add_child(r)
	box(r,Vector3(0,1.15,0),Vector3(1.15,2.3,.12),"metal")
	for x in [-.63,.63]:box(r,Vector3(x,1.2,.05),Vector3(.12,2.4,.22),"pale")
	box(r,Vector3(0,2.42,.05),Vector3(1.38,.13,.22),"pale")
	box(r,Vector3(.38,1.1,.14),Vector3(.16,.035,.04),"rust")
static func boundaries()->Array:
	return [AABB(Vector3(-144,-1,-144),Vector3(2,5,288)),AABB(Vector3(142,-1,-144),Vector3(2,5,288)),AABB(Vector3(-144,-1,-144),Vector3(288,5,2)),AABB(Vector3(-144,-1,142),Vector3(288,5,2))]
static func boundary_visual(root:Node3D,role:String="concrete")->void:
	for a:AABB in boundaries():box(root,a.get_center(),a.size,role)
static func arch(root:Node3D,center:Vector3,radius:float,width:float,depth:float)->void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1)
	for i in range(128):
		var a:=TAU*float(i)/128.;var b:=TAU*float(i+1)/128.
		var pts:Array[Vector3]=[]
		for z in [-depth*.5,depth*.5]:
			for r in [radius-width*.5,radius+width*.5]:
				pts.append(center+Vector3(cos(a)*r,sin(a)*r,z));pts.append(center+Vector3(cos(b)*r,sin(b)*r,z))
		var quads:=[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3]]
		for qi in range(4):
			var q:Array=quads[qi]
			for j in [0,1,2,0,2,3]:
				var index:int=q[j];var p:Vector3=pts[index]
				st.set_uv((Vector2(p.x,p.y) if qi<2 else Vector2((a if index%2==0 else b)*radius,p.z))*.25);st.add_vertex(p)
	st.generate_normals();st.generate_tangents();var n:=MeshInstance3D.new();n.mesh=st.commit();n.material_override=mat("pale");root.add_child(n)
static func grass_tufts(root:Node3D,coord:Vector2i,patches:Array,count:int=420)->void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1)
	var vertices:=0
	var rng:=RandomNumberGenerator.new();rng.seed=abs(coord.x*92821+coord.y*68917)+4527
	var o:=Vector3(coord.x*32.,0,coord.y*32.)
	for i in range(count):
		var p:=Vector3(rng.randf_range(-16,16),.4,rng.randf_range(-16,16));var inside:=false
		for patch:AABB in patches:
			if patch.grow(.001).has_point(p+o):inside=true;break
		if not inside:continue
		vertices+=9
		var h:=rng.randf_range(.04,.12)
		for angle in [0.,1.047,2.094]:
			var d:=Vector3(cos(angle),0,sin(angle))*.003
			for v in [p-d,p+d,p+Vector3(.008,h,.006)]:
				st.set_uv(Vector2(v.x+o.x,v.z+o.z)*.25);st.add_vertex(v)
	if vertices==0:return
	st.generate_normals();var n:=MeshInstance3D.new();n.mesh=st.commit();n.material_override=mat("grass");n.visibility_range_end=75.;n.visibility_range_end_margin=10.;root.add_child(n)
static func batch_static(root:Node3D)->void:
	# Persistent horizon is visual-only; all reachable collision remains in
	# chunk shells. Preserve actual vertex attributes, not an impostor image.
	var groups:Dictionary={};var sources:Array[MeshInstance3D]=[]
	var before_bounds:=AABB();var have_bounds:=false;var before_draws:=0;var before_triangles:=0
	for object in root.find_children("*","MeshInstance3D",true,false):
		var source:=object as MeshInstance3D
		if source.mesh==null:continue
		sources.append(source)
		var transform:Transform3D=root.global_transform.affine_inverse()*source.global_transform
		var normal_basis:Basis=transform.basis.inverse().transposed()
		var bounds:AABB=transform*source.mesh.get_aabb();before_bounds=before_bounds.merge(bounds) if have_bounds else bounds;have_bounds=true
		before_draws+=source.mesh.get_surface_count()
		for surface in range(source.mesh.get_surface_count()):
			var material:Material=source.material_override if source.material_override!=null else source.mesh.surface_get_material(surface)
			if not groups.has(material):
				var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);groups[material]=tool
			var tool:SurfaceTool=groups[material];var arrays:Array=source.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			if indices.is_empty():
				for i in range(vertices.size()):indices.append(i)
			before_triangles+=indices.size()/3
			for i:int in indices:
				var normal:Vector3=arrays[Mesh.ARRAY_NORMAL][i] if arrays[Mesh.ARRAY_NORMAL]!=null and arrays[Mesh.ARRAY_NORMAL].size()>i else Vector3.UP
				tool.set_normal((normal_basis*normal).normalized())
				tool.set_uv(arrays[Mesh.ARRAY_TEX_UV][i] if arrays[Mesh.ARRAY_TEX_UV]!=null and arrays[Mesh.ARRAY_TEX_UV].size()>i else Vector2.ZERO)
				tool.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][i] if arrays[Mesh.ARRAY_TEX_UV2]!=null and arrays[Mesh.ARRAY_TEX_UV2].size()>i else Vector2.ZERO)
				if arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_TANGENT].size()>i*4+3:
					var t:Vector3=transform.basis*Vector3(arrays[Mesh.ARRAY_TANGENT][i*4],arrays[Mesh.ARRAY_TANGENT][i*4+1],arrays[Mesh.ARRAY_TANGENT][i*4+2])
					tool.set_tangent(Plane(t.normalized(),arrays[Mesh.ARRAY_TANGENT][i*4+3]))
				else:tool.set_tangent(Plane(Vector3.RIGHT,1.))
				tool.add_vertex(transform*vertices[i])
	for source:MeshInstance3D in sources:source.free()
	var after_bounds:=AABB();var after_have:=false
	for material:Material in groups:
		var tool:SurfaceTool=groups[material];tool.index();var mesh:=MeshInstance3D.new();mesh.name="HorizonBatch_"+str(root.get_child_count());mesh.mesh=tool.commit();mesh.material_override=material;root.add_child(mesh)
		var bounds:AABB=mesh.mesh.get_aabb();after_bounds=after_bounds.merge(bounds) if after_have else bounds;after_have=true
	root.set_meta("horizon_batch_report",{"before_draw_surfaces":before_draws,"after_draw_surfaces":groups.size(),"triangles":before_triangles,"bounds_error":before_bounds.position.distance_to(after_bounds.position)+before_bounds.size.distance_to(after_bounds.size),"before_bounds":before_bounds,"after_bounds":after_bounds})
