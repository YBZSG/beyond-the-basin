extends RefCounted
const Form = preload("res://scripts/dreamcore/scenes/crossing_channels.gd")
const G = preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind): return _materials[kind]
	var m := StandardMaterial3D.new()
	m.resource_name = "Maintenance gate / "+kind
	m.cull_mode = BaseMaterial3D.CULL_BACK
	if kind == "steel":
		m = G.mat("metal").duplicate() as StandardMaterial3D
		m.resource_name = "Maintenance gate / existing brushed steel PBR"
		m.metallic = 1.0
		m.roughness = .9
		m.normal_scale = .22
	elif kind in ["paint","frame"]:
		m.albedo_color = Color("52645d") if kind == "paint" else Color("66716a")
		m.metallic = 0.0 # Opaque paint is a dielectric, not grey half-metal.
		m.roughness = .55 if kind == "paint" else .59
		m.normal_enabled = true
		m.normal_texture = load("res://assets/materials/art_pass/textures/steel_normal_gl_512.png")
		m.normal_scale = .055
		m.uv1_scale = Vector3.ONE*4.0
	elif kind == "rubber":
		m.albedo_color = Color("242b27")
		m.metallic = 0.0
		m.roughness = .94
	elif kind == "bearing":
		m.albedo_color = Color("303934")
		m.metallic = 0.0 # Thin dark lubricant film on thrust washers, not rust.
		m.roughness = .32
	_materials[kind] = m
	return m

static func metric_mesh(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for n in (indices.size() if not indices.is_empty() else vertices.size()):
			var i: int = indices[n] if not indices.is_empty() else n
			st.set_normal(normals[i])
			st.set_uv(G.metric_uv(vertices[i],normals[i]))
			st.add_vertex(vertices[i])
	st.generate_tangents()
	return st.commit()

static func bevel_box(size: Vector3, bevel: float) -> Mesh:
	var key := "box/"+str(size)+"/"+str(bevel)
	if not _meshes.has(key): _meshes[key] = metric_mesh(Form.chamfer_mesh(size,bevel))
	return _meshes[key]

static func append_mesh(st: SurfaceTool, mesh: Mesh, center: Vector3) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	for n in (indices.size() if not indices.is_empty() else vertices.size()):
		var i: int = indices[n] if not indices.is_empty() else n
		var point := vertices[i]+center
		st.set_normal(normals[i])
		st.set_uv(G.metric_uv(point,normals[i]))
		st.add_vertex(point)

static func pressed_leaf() -> Mesh:
	if _meshes.has("pressed_leaf"): return _meshes.pressed_leaf
	var specs: Array = []
	# Exact outer envelope stays 0.12 x 2.55 x 2.20; centre skins sit 4mm inward.
	specs.append([Vector3(0,1.295,1.10),Vector3(.112,2.42,2.07),.0015])
	for y in [.0525,2.5375]: specs.append([Vector3(0,y,1.10),Vector3(.12,.065,2.20),.0015])
	specs.append([Vector3(0,1.295,2.1675),Vector3(.12,2.42,.065),.0015])
	var previous := .085
	for y in [.35,1.35,2.35]:
		var low: float = y-.095
		if low > previous: specs.append([Vector3(0,(previous+low)*.5,.0325),Vector3(.12,low-previous,.065),.0015])
		# Real hollow hinge-edge pockets: two 4mm skins, not a solid block through the pin.
		for x in [-.058,.058]: specs.append([Vector3(x,y,.0325),Vector3(.004,.19,.065),.0004])
		previous = y+.095
	if previous < 2.505: specs.append([Vector3(0,(previous+2.505)*.5,.0325),Vector3(.12,2.505-previous,.065),.0015])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: Array in specs: append_mesh(st,bevel_box(row[1],row[2]),row[0]-Vector3(0,1.295,1.10))
	st.generate_tangents()
	_meshes.pressed_leaf = st.commit()
	return _meshes.pressed_leaf

static func _quad(st: SurfaceTool, points: Array, normal: Vector3) -> void:
	Form._quad(st,points,normal)

static func _smooth_quad(st: SurfaceTool, points: Array, normals: Array) -> void:
	Form._smooth_tri(st,points[0],points[1],points[2],normals[0],normals[1],normals[2])
	Form._smooth_tri(st,points[0],points[2],points[3],normals[0],normals[2],normals[3])

static func tube(outer: float, inner: float, height: float, bevel := .001, segments := 48) -> Mesh:
	var key := "tube/%s/%s/%s/%s/%s" % [outer,inner,height,bevel,segments]
	if _meshes.has(key): return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profiles: Array[Vector2] = [Vector2(-height*.5,outer-bevel),Vector2(-height*.5+bevel,outer),Vector2(height*.5-bevel,outer),Vector2(height*.5,outer-bevel)]
	for i in segments:
		var a := TAU*i/segments
		var b := TAU*(i+1)/segments
		var na := Vector3(cos(a),0,sin(a))
		var nb := Vector3(cos(b),0,sin(b))
		for j in range(profiles.size()-1):
			var low: Vector2 = profiles[j]
			var high: Vector2 = profiles[j+1]
			var vertical := Vector3.DOWN if j == 0 else Vector3.UP if j == 2 else Vector3.ZERO
			var normal_a := (na+vertical).normalized()
			var normal_b := (nb+vertical).normalized()
			_smooth_quad(st,[na*low.y+Vector3.UP*low.x,nb*low.y+Vector3.UP*low.x,nb*high.y+Vector3.UP*high.x,na*high.y+Vector3.UP*high.x],[normal_a,normal_b,normal_b,normal_a])
		for side in [-1.0,1.0]:
			var y: Vector3 = Vector3.UP*side*height*.5
			_quad(st,[na*(outer-bevel)+y,nb*(outer-bevel)+y,nb*inner+y,na*inner+y],Vector3.UP*side)
		_smooth_quad(st,[na*inner-Vector3.UP*height*.5,nb*inner-Vector3.UP*height*.5,nb*inner+Vector3.UP*height*.5,na*inner+Vector3.UP*height*.5],[-na,-nb,-nb,-na])
	_meshes[key] = metric_mesh(st.commit())
	return _meshes[key]

static func socket_head(radius: float, depth: float) -> Mesh:
	# Hex head and recessed hex socket; no painted screw slot or coplanar decal.
	var key := "socket/%s/%s" % [radius,depth]
	if _meshes.has(key): return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a := TAU*i/6.0
		var b := TAU*(i+1)/6.0
		var na := Vector3(cos(a),0,sin(a))
		var nb := Vector3(cos(b),0,sin(b))
		var top := Vector3.UP*depth
		var bottom := Vector3.UP*depth*.25
		_quad(st,[na*radius,nb*radius,nb*radius+top,na*radius+top],(na+nb).normalized())
		_quad(st,[na*radius+top,nb*radius+top,nb*radius*.40+top,na*radius*.40+top],Vector3.UP)
		_quad(st,[na*radius*.40+top,nb*radius*.40+top,nb*radius*.40+bottom,na*radius*.40+bottom],-(na+nb).normalized())
		Form._tri(st,bottom,na*radius*.40+bottom,nb*radius*.40+bottom,Vector3.UP)
	_meshes[key] = metric_mesh(st.commit())
	return _meshes[key]

static func embedded_jamb(size: Vector3, bevel: float, contact_sign: float) -> Mesh:
	# Only omit the two flat contact-plane triangles buried against the continuous wall.
	# Adjacent bevels, outer envelope, normals, material and physical shape are retained.
	var key := "embedded_jamb/%s/%s/%s" % [size,bevel,contact_sign]
	if _meshes.has(key): return _meshes[key]
	var source: Mesh = bevel_box(size,bevel)
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(0,vertices.size(),3):
		var contact := true
		for j in 3:
			if absf(vertices[index+j].z-contact_sign*size.z*.5) > .000001: contact = false
		if contact: continue
		for j in 3:
			st.set_normal(normals[index+j])
			st.set_uv(uv[index+j])
			st.add_vertex(vertices[index+j])
	st.generate_tangents()
	_meshes[key] = st.commit()
	return _meshes[key]
