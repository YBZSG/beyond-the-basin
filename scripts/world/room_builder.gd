class_name PoolRoomBuilder
extends RefCounted
## Native geometry port of engine.ts buildChunk. Dimensions and RNG ordering are source-owned.
const SourceRandom := preload("res://scripts/world/source_random.gd")
const WFC := preload("res://scripts/world/source_wfc.gd")
const Catalog := preload("res://scripts/world/room_catalog.gd")
const ExpansionBuilder := preload("res://scripts/world/expanded_room_builder.gd")
const ArchitectureBatch := preload("res://scripts/world/source_architecture_batch.gd")
const GROUND := -0.78
const AUTHORED := {8:"res://assets/models/quiet-wing-oculus-court.glb",9:"res://assets/models/quiet-wing-vaulted-lap-hall.glb",10:"res://assets/models/quiet-wing-changing-gallery.glb"}
static var imported_scenes: Dictionary = {}
static var imported_shapes: Dictionary = {}
static var notice_fonts: Dictionary = {}
var room: Node3D
var layout: Dictionary
var library: RefCounted
var rng: RefCounted
var solids: Array[AABB] = []
var wfc_grid: Array = []
var physics_body: StaticBody3D
var batch_architecture_enabled: bool = true
var _fallback_materials: Dictionary = {}
var _expansion_builder: RefCounted

func _init(room_root: Node3D, room_layout: Dictionary, material_library: RefCounted) -> void:
	room = room_root
	layout = room_layout
	library = material_library
	rng = SourceRandom.new(layout.coord.x, layout.coord.y, layout.seed)
	physics_body = StaticBody3D.new()
	physics_body.name = "ArchitectureCollision"
	physics_body.collision_layer = 1
	physics_body.collision_mask = 0
	room.add_child(physics_body)

func material(role: String) -> Material:
	var resolved: String = "tile" if role == "wall" else role
	if role == "wall": role = "tile"
	if role in ["tile", "pale"]:
		if layout.daylight: resolved = "daylight_" + role
		elif layout.corrupt >= 2: resolved = "grim_" + role
	if library != null:
		var value: Material = library.get_material(resolved)
		if value != null: return value
	if _fallback_materials.has(resolved):return _fallback_materials[resolved]
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color("aab6b0") if role != "tile" else Color("63899d")
	_fallback_materials[resolved]=fallback
	return fallback

func box(x: float,y: float,z: float,w: float,h: float,d: float,role: String = "tile",solid: bool = true,rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var object := MeshInstance3D.new()
	object.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var shape := BoxMesh.new()
	shape.size = Vector3(w,h,d)
	object.mesh = shape
	object.material_override = material(role)
	object.set_meta("source_role", role)
	if role in ["skylight","skylight_dim","glow","exit_glow"]:object.set_meta("source_exclude_optics",true)
	object.position = Vector3(x,y,z)
	object.rotation = rotation
	room.add_child(object)
	if solid:
		var collision := BoxShape3D.new()
		collision.size = shape.size
		add_shape(collision, object.transform)
		if rotation == Vector3.ZERO: solids.append(AABB(object.position-shape.size*.5,shape.size))
	return object

func add_shape(shape: Shape3D, transform: Transform3D, target: StaticBody3D = null) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = transform
	(target if target != null else physics_body).add_child(collision)

func cylinder(x: float,y: float,z: float,radius: float,height: float,role: String = "tile",tilt: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var object := MeshInstance3D.new()
	object.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	mesh.rings = 0
	object.mesh = mesh
	object.position = Vector3(x,y,z)
	object.rotation = tilt
	object.material_override = material(role)
	object.set_meta("source_role", role)
	if role in ["skylight","skylight_dim","glow","exit_glow"]:object.set_meta("source_exclude_optics",true)
	room.add_child(object)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	# Source keeps lean-decorated columns' collision vertical intentionally.
	add_shape(shape, Transform3D(Basis.IDENTITY, object.position))
	solids.append(AABB(object.position-Vector3(radius,height*.5,radius),Vector3(radius*2,height,radius*2)))
	return object

func sphere(x: float,y: float,z: float,radius: float,role: String) -> void:
	var object := MeshInstance3D.new()
	object.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 11
	object.mesh = mesh
	object.position = Vector3(x,y,z)
	object.material_override = material(role)
	object.set_meta("source_role", role)
	if role in ["skylight","skylight_dim","glow","exit_glow"]:object.set_meta("source_exclude_optics",true)
	room.add_child(object)
	var shape := SphereShape3D.new()
	shape.radius = radius
	add_shape(shape, object.transform)

func rod(a: Vector3,b: Vector3,radius: float = .035,collision: bool = true) -> void:
	var delta: Vector3 = b-a
	var object := MeshInstance3D.new()
	object.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=delta.length()
	mesh.radial_segments=32
	mesh.rings=0
	object.mesh=mesh
	object.position=(a+b)*.5
	object.quaternion=Quaternion(Vector3.UP,delta.normalized())
	object.material_override=material("metal")
	object.set_meta("source_role", "metal")
	object.set_meta("source_rod", true)
	room.add_child(object)
	if collision:
		var shape:=CylinderShape3D.new()
		shape.radius=radius
		shape.height=delta.length()
		add_shape(shape,object.transform)

func rail(x: float,y: float,z: float,length: float,along_x: bool = true) -> void:
	var a:=Vector3(x,y,z)
	var direction:=Vector3.RIGHT if along_x else Vector3.BACK
	rod(a+Vector3.UP,a+Vector3.UP+direction*length)
	rod(a+Vector3.UP*.48,a+Vector3.UP*.48+direction*length)
	var count: int = int(ceil(length/1.8))
	for i in count+1:
		var p:=a+direction*(float(i)/count*length)
		rod(p,p+Vector3.UP)

func sign_board(x: float,y: float,z: float,text_value: String,angle: float = 0.0,dark: bool = false) -> void:
	# Original canvas is 256 x 320 pixels mapped to a 0.72 x 0.9 m plane.
	# Keep its frame, two/three-line notice and separate small footer, not an
	# oversized uniform Label3D that replaces the source sign composition.
	var sign_root:=Node3D.new()
	sign_root.name="SourceNotice"
	sign_root.position=Vector3(x,y,z)
	sign_root.rotation.y=angle
	sign_root.set_meta("source_sign",{"position":Vector3(x,y,z),"text":text_value,"angle":angle,"dark":dark})
	room.add_child(sign_root)
	var board:=MeshInstance3D.new()
	var plane:=QuadMesh.new()
	plane.size=Vector2(.72,.9)
	board.mesh=plane
	board.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var board_material:=StandardMaterial3D.new()
	board_material.albedo_color=Color("17252b") if dark else Color("c4c8bd")
	board_material.roughness=.7
	board.material_override=board_material
	sign_root.add_child(board)
	var border_material:=StandardMaterial3D.new()
	border_material.albedo_color=Color("7c8063") if dark else Color("873e32")
	border_material.roughness=.7
	const TEXEL:float=.72/256.0
	for side in [-1,1]:
		for horizontal in [true,false]:
			var border:=MeshInstance3D.new()
			var strip:=QuadMesh.new()
			strip.size=Vector2(236*TEXEL,5*TEXEL) if horizontal else Vector2(5*TEXEL,300*TEXEL)
			border.mesh=strip
			border.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			border.material_override=border_material
			border.position=Vector3(0,side*150*TEXEL,.001) if horizontal else Vector3(side*118*TEXEL,0,.001)
			sign_root.add_child(border)
	if notice_fonts.is_empty():
		var heading_font:=SystemFont.new()
		heading_font.font_names=PackedStringArray(["Noto Serif CJK SC","Noto Serif","serif"])
		heading_font.font_weight=700
		var footer_font:=SystemFont.new()
		footer_font.font_names=PackedStringArray(["Noto Sans Mono","monospace"])
		notice_fonts={"heading":heading_font,"footer":footer_font}
	var lines:=text_value.split("\n")
	for index in lines.size()+1:
		var footer:bool=index==lines.size()
		var label:=Label3D.new()
		label.text="POOL  /  1.2 M" if footer else lines[index]
		label.font_size=16 if footer else 44
		label.font=notice_fonts.footer if footer else notice_fonts.heading
		label.pixel_size=TEXEL
		label.modulate=Color("b4ac78") if dark else Color("973f30")
		label.outline_size=0
		label.shaded=true
		label.position=Vector3(0,.45-(278.0 if footer else 51.0+index*58.0)*TEXEL,.002)
		sign_root.add_child(label)

func decay_text(pristine: String) -> String:
	if layout.corrupt < 2: return pristine
	var pool: Array = ["请勿\n逗留","水位\n上升","此处\n无人"] if layout.corrupt >= 3 else ["本区\n已停用","维护\n中","暂不\n开放"]
	return pool[int(floor(rng.next()*pool.size()))]

func ladder(x: float,z: float,height: float,exit_z: float = NAN,visual: bool = true) -> void:
	if is_nan(exit_z): exit_z=z-.65
	if visual:
		for dx in [-.43,.43]: rod(Vector3(x+dx,-.78,z+.7),Vector3(x+dx,height+1,z),.035,false)
		var y: float = .3
		while y < height+.5:
			var rz: float = z+.7*(1-y/(height+1))
			rod(Vector3(x-.43,y,rz),Vector3(x+.43,y,rz),.027,false)
			y+=.34
	var anchor:=Node3D.new()
	anchor.name="ClimbableLadder"
	room.add_child(anchor)
	anchor.add_to_group("pool_ladders")
	var local_base:=Vector3(x,-.15,z+1.1)
	var local_top:=Vector3(x,height+.16,z+.45)
	var local_exit:=Vector3(x,height+.16,exit_z)
	anchor.set_meta("base",room.to_global(local_base))
	anchor.set_meta("top",room.to_global(local_top))
	anchor.set_meta("exit",room.to_global(local_exit))
	anchor.set_meta("local_base",local_base)
	anchor.set_meta("local_top",local_top)
	anchor.set_meta("local_exit",local_exit)

func tower(x: float,z: float) -> void:
	box(x,2.06,z,.85,5.68,1.1,"pale")
	for y in [2.5,5.0]:
		box(x-.6,y,z,2.8,.22,2.4,"pale")
		rail(x-2,y+.12,z-1.05,2.8)
		rail(x-2,y+.12,z-1.05,2.1,false)
		rail(x-2,y+.12,z+1.05,1.7)
		ladder(x+.55+(-.9 if y==5 else 0),z+1.55,y,z+.75)
	sign_board(x-.65,3.6,z+.57,"禁止\n跳水")

func _adjacent_layout(coord: Vector2i) -> Dictionary:
	# Only the selected wing substitutes its three anchors; neighboring random
	# shells must seal against that actual ceiling, not the old anchor catalog.
	if layout.get("poolrooms_mode", false):
		var wing = preload("res://scripts/poolrooms_wing/poolrooms_catalog.gd")
		if wing.ANCHORS.has(coord): return wing.room_layout(coord, layout.seed)
	return Catalog.room_layout(coord, layout.seed, layout.get("expanded_mode", false))

func build_shell() -> void:
	if layout.get("expanded", false):
		_expansion_builder=ExpansionBuilder.new(self)
		_expansion_builder.build_shell()
		# Keep shared upper boundaries sealed when an adjacent original room is lower.
		for offset in [Vector2i.RIGHT,Vector2i.DOWN]:
			var adjacent: Dictionary=_adjacent_layout(layout.coord+offset)
			var top: float=adjacent.ceiling
			if float(layout.ceiling)>top:
				box(offset.x*16,(float(layout.ceiling)+top)*.5,offset.y*16,.6 if offset.x else 32.0,float(layout.ceiling)-top,32.0 if offset.x else .6,"formal_plaster")
		return
	var ceiling: float = layout.ceiling
	box(0,-.995,0,32,.55,32).name="ContinuousBasinFloor"
	if layout.daylight:
		box(-11,ceiling,0,10,.6,32,"pale")
		box(11,ceiling,0,10,.6,32,"pale")
		box(0,ceiling,-11,12,.6,10,"pale")
		box(0,ceiling,11,12,.6,10,"pale")
		var sky:=box(0,ceiling+1.2,0,12,.12,12,"skylight_dim" if layout.corrupt>=2 else "skylight",false)
		sky.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		for dx in [-6,6]: box(dx,ceiling+.5,0,.25,1.4,12,"pale")
		for dz in [-6,6]: box(0,ceiling+.5,dz,12,1.4,.25,"pale")
		for offset in [-6,-3,0,3,6]:
			box(offset,ceiling+1.08,0,.12,.16,12,"lamp_housing")
			box(0,ceiling+1.08,offset,12,.16,.12,"lamp_housing")
	else: box(0,ceiling,0,32,.6,32,"pale")
	# Every room owns north and west boundaries, exactly as in Three.js.
	for side in [-1,1]:
		box(side*10,(ceiling+GROUND)/2,-16,12,ceiling-GROUND,.6,"wall")
		box(-16,(ceiling+GROUND)/2,side*10,.6,ceiling-GROUND,12,"wall")
	box(0,(ceiling+5.4)/2,-16,8,ceiling-5.4,.6,"wall")
	box(-16,(ceiling+5.4)/2,0,.6,ceiling-5.4,8,"wall")
	for offset in [Vector2i(1,0),Vector2i(0,1)]:
		var adjacent: Dictionary = _adjacent_layout(layout.coord+offset)
		var top: float = adjacent.ceiling
		if ceiling>top: box(offset.x*16,(ceiling+top)/2,offset.y*16,.6 if offset.x else 32.0,ceiling-top,32.0 if offset.x else .6,"pale")

	# Incremental startup renders these shells before their interiors arrive.
	# Batch now, then merge the same shell geometry with interior groups later.
	if batch_architecture_enabled: ArchitectureBatch.batch(room)

func build_interior() -> void:
	if _expansion_builder!=null:
		_expansion_builder.build_interior()
		return
	match int(layout.variant):
		0,1,2: _old_pool()
		3: _high_arcades()
		4,6: _connected_baths()
		5: _high_gallery()
		7: _pillar_hall()
		8,9,10: _authored_wing()
	_prepare_fixtures_and_props()
	var exclusions: Array[AABB] = []
	for solid in solids:
		if solid.position.y < .32 and solid.end.y > .32: exclusions.append(solid)
	layout.water_exclusions=exclusions
	layout.solids=solids
	layout.wfc_grid=wfc_grid
	room.set_meta("layout",layout)
	if batch_architecture_enabled: ArchitectureBatch.batch(room)
	room.set_meta("complete",true)

func _old_pool() -> void:
	for dx in [-10,-3,4,11]:
		box(dx,(6+GROUND)/2,-9,1,6-GROUND,1)
		box(dx,7.45,-9,.65,2.9,.65)
	box(0,5.85,-11.7,31,.35,5.5)
	box(0,5.5,-9,31,.6,.55)
	rail(-15,6.05,-9,30)
	ladder(-12,-8.4,6.04,-10.1)
	for dx in [-14,-7,0,7,14]: box(dx,8.65,0,.32,.6,31)
	for dz in [-5,6]: box(0,8.65,dz,31,.6,.4)
	sign_board(-3,3.4,-8.48,"禁止\n跳水")
	sign_board(10,3.4,-15.68,decay_text("泳池\n须知"),0,true)
	if layout.variant!=2: tower(6,-6)
	else:
		for dx in [-7,7]: box(dx,(4.8+GROUND)/2,0,1.1,4.8-GROUND,1.1,"pale")
		rng.next()
		box(-12.75,.08,-6,5.9,1.72,4,"pale")
		for i in 5:
			var top: float = .94-(i+1)*.28
			box(-9.5+i*.62,(GROUND+top)/2,-6,.64,top-GROUND,3.2,"pale")
		rail(-15.6,.94,-8,5.6)
	for dx in [-.65,.65]:
		for dz in [-.6,.6]: rod(Vector3(12+dx,GROUND,-7+dz),Vector3(12+dx*.65,2.8,-7+dz*.65),.045)
	box(12,2.45,-7,1,.13,.9,"pale")
	box(12,2.95,-7.4,1,.9,.1,"pale")
	ladder(12,-6.6,2.2)
	for dz in [-3,5]:
		box(-13,.72,dz,2.4,.12,.65,"pale")
		for dx in [-.8,.8]: rod(Vector3(-13+dx,GROUND,dz),Vector3(-13+dx,.7,dz))
	for dz in [1,9]:
		var tilt:=Vector3.ZERO
		if layout.corrupt>=2:
			tilt.z=(rng.next()-.5)*.15
			tilt.x=(rng.next()-.5)*.15
		cylinder(-8,(8.9+GROUND)/2,dz,.65,8.9-GROUND,"tile",tilt)
	var slide_start:=Vector3(10,3.3,2)
	var slide_end:=Vector3(10,GROUND,8)
	var midpoint: Vector3 = (slide_start+slide_end)*.5
	var slope: float = atan2(slide_start.y-slide_end.y,slide_end.z-slide_start.z)
	var slide:=box(midpoint.x,midpoint.y,midpoint.z,1.65,.16,slide_start.distance_to(slide_end),"red",false,Vector3(slope,0,0))
	slide.name="WalkableSlide"
	var body:=StaticBody3D.new()
	body.name="SlideCollision"
	body.collision_layer=1
	body.collision_mask=0
	body.add_to_group("pool_slides")
	body.set_meta("pool_slide",true)
	room.add_child(body)
	var shape:=BoxShape3D.new()
	shape.size=Vector3(1.65,.16,slide_start.distance_to(slide_end))
	add_shape(shape,slide.transform,body)
	for side in [-1,1]: rod(slide_start+Vector3(side*.86,.3,0),slide_end+Vector3(side*.86,.3,0),.075)
	box(10,3.22,1.1,2,.16,1.8,"pale")
	ladder(10,-.15,3.3,.65)
	box(-5,.21,7,1.5,1.98,1.5,"pale")
	sphere(-5,1.9,7,.8,"chrome")
	for dx in [-.8,.8]: box(3+dx,1.11,8,.15,3.78,.25,"metal")
	box(3,3,8,1.75,.16,.25,"metal")
	sign_board(3,2.55,8.14,"出口\n不存在",0,true)
	if layout.variant==1: sphere(-3,.87,0,1.6,"yellow")

func _high_arcades() -> void:
	for dx in [-8,8]:
		for dz in [-9,3]:
			# Exact 4.6m/3.5m semicircular ring, spring line at y=GROUND+5.3.
			for side in [-1,1]:
				box(dx+side*4.05,GROUND+2.65,dz+.4,1.1,5.3,.8,"pale",false)
				# The original extrusion is based at GROUND but its explicit
				# navigation/prop-rejection solid reaches world y=5.3.
				var pier:=AABB(Vector3(dx+side*4.05-.55,GROUND,dz),Vector3(1.1,5.3-GROUND,.8))
				solids.append(pier)
				var collision:=BoxShape3D.new()
				collision.size=pier.size
				add_shape(collision,Transform3D(Basis.IDENTITY,pier.get_center()))
			_arch_ring(Vector3(dx,GROUND+5.3,dz+.4),3.5,4.6,.8,64)
	for i in 5: box(-12,GROUND+(i+1)*.16,10-i*.65,5,(i+1)*.32,.68,"pale")
	rail(-14,1,7,4)
	sign_board(12,3,-15.65,decay_text("静水\n回廊"))

func _arch_ring(center: Vector3,inner: float,outer: float,depth: float,segments: int) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in segments:
		var a: float = float(i)/segments*PI
		var b: float = float(i+1)/segments*PI
		var points: Array[Vector3] = []
		for z in [-depth*.5,depth*.5]:
			points.append(Vector3(cos(a)*inner,sin(a)*inner,z)+center)
			points.append(Vector3(cos(b)*inner,sin(b)*inner,z)+center)
			points.append(Vector3(cos(b)*outer,sin(b)*outer,z)+center)
			points.append(Vector3(cos(a)*outer,sin(a)*outer,z)+center)
		for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[3,7,6,2]]:
			for j in [0,1,2,0,2,3]: st.add_vertex(points[face[j]])
	st.generate_normals()
	var object:=MeshInstance3D.new()
	object.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	object.mesh=st.commit()
	object.material_override=material("pale")
	object.set_meta("source_role", "pale")
	object.set_meta("source_arch", {"position":center,"inner":inner,"outer":outer,"depth":depth})
	room.add_child(object)
	add_shape(object.mesh.create_trimesh_shape(),Transform3D.IDENTITY)

func _connected_baths() -> void:
	for dx in [-10,0,10]:
		for dz in [-9,3]:
			box(dx,2.5,dz,1.25,6.56,1.25,"pale")
			box(dx,-.07,dz,5.8,1.42,5.8,"pale")
			for i in 3: box(dx,-.58+(2-i)*.18,dz+3.1+i*.5,3,.28,.52,"pale")
	for dz in [-9,3]: box(0,.59,dz,26,.12,1.5,"pale")
	sign_board(10,3,-15.65,decay_text("夜间\n浴场"))

func _high_gallery() -> void:
	for dx in [-10,10]:
		for dz in [-10,-3,4,11]:
			box(dx,4.1,dz,1.5,9.76,1.5,"pale")
			box(dx,5.5,dz,4,.3,3,"pale")
	box(0,5.5,-12,28,.35,3,"pale")
	rail(-14,5.7,-10.6,28)
	ladder(12,-9.8,5.7,-11.4)
	tower(-10,2)
	sign_board(8,3,-15.65,decay_text("午后\n无人"))

func _pillar_hall() -> void:
	wfc_grid=WFC.collapse_interior(SourceRandom.new(layout.coord.x,layout.coord.y,layout.seed+911),12,1+layout.corrupt*.55)
	var pillars: Array[Vector2i] = []
	for j in 12:
		for i in 12:
			if wfc_grid[j][i]=="P": pillars.append(Vector2i(i,j))
	var stair:=Vector2i(-1,-1)
	var nearest: float = INF
	for pillar in pillars:
		var distance: float = Vector2(pillar).distance_to(Vector2(5.5,5.5))
		if distance<nearest:
			stair=pillar
			nearest=distance
	for j in 12:
		for i in 12:
			var x: float = (i-5.5)*2.2
			var z: float = (j-5.5)*2.2
			if wfc_grid[j][i]=="P":
				var tilt:=Vector3.ZERO
				if layout.corrupt>=2 and stair!=Vector2i(i,j):
					tilt.z=(rng.next()-.5)*.15
					tilt.x=(rng.next()-.5)*.15
				cylinder(x,(layout.ceiling+GROUND)/2,z,.65,layout.ceiling-GROUND,"tile",tilt)
			elif wfc_grid[j][i]=="S" and (layout.corrupt<3 or rng.next()>=.3): box(x,(.64+GROUND)/2,z,2.25,.64-GROUND,2.25,"pale")
	if stair.x>=0 and layout.corrupt<3:
		var sx: float = (stair.x-5.5)*2.2
		var sz: float = (stair.y-5.5)*2.2
		var theta0: float = atan2(-sz,-sx)
		for s in 32:
			var theta: float = theta0+s*PI/6
			box(sx+cos(theta)*1.05,GROUND+.045+s*.3,sz+sin(theta)*1.05,.95,.09,1.04,"pale",true,Vector3(0,-theta,0))
		var end: float = theta0+32*PI/6
		var ox: float = cos(end)
		var oz: float = sin(end)
		var px: float = sx-ox*.9
		var pz: float = sz-oz*.9
		box(px,8.96,pz,2.6,.12,2.6,"pale")
		var opening:=Vector2i(int(signf(ox)),0) if absf(ox)>absf(oz) else Vector2i(0,int(signf(oz)))
		for side in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
			if side==opening: continue
			box(px+side.x*1.3,9.55,pz+side.y*1.3,.12 if side.x else 2.6,.7,.12 if side.y else 2.6,"pale")
		box(px+ox*1.22,9.32,pz+oz*1.22,.16 if absf(ox)>.5 else .42,.52,.42 if absf(ox)>.5 else .16,"exit_glow",false)
		layout.exit_light=Vector3(px+ox*1.05,9.4,pz+oz*1.05)
		sign_board(px-opening.x*1.22,9.62,pz-opening.y*1.22,"上方\n禁止\n停留" if layout.corrupt>=2 else "柱顶\n观察间",atan2(opening.x,opening.y))
	for dx in [-14,-7,0,7,14]: box(dx,12.4,0,.32,.6,31)
	sign_board(8,3,-15.65,decay_text("柱影\n重重"))

func _authored_wing() -> void:
	var path: String = AUTHORED[int(layout.variant)]
	if not imported_scenes.has(path): imported_scenes[path]=load(path)
	var packed: PackedScene = imported_scenes[path]
	if packed==null:
		push_error("Authored room could not be loaded: "+path)
		return
	var root: Node3D = packed.instantiate()
	root.name="AuthoredQuietWing"
	room.add_child(root)
	if library!=null: library.apply_to_imported(root)
	var triangles:=PackedVector3Array()
	_collect_imported(root,Transform3D.IDENTITY,triangles,not imported_shapes.has(path))
	if not imported_shapes.has(path):
		var shape:=ConcavePolygonShape3D.new()
		shape.set_faces(triangles)
		imported_shapes[path]=shape
	add_shape(imported_shapes[path],Transform3D.IDENTITY)
	if layout.variant==8: ladder(-12.1,-8.3,.52,-9.2,false)
	if layout.variant==9: ladder(13.1,-5.4,.52,-6.2,false)

func _collect_imported(node: Node, parent_transform: Transform3D, triangles: PackedVector3Array, collect_faces: bool) -> void:
	var transform: Transform3D = parent_transform * node.transform if node is Node3D else parent_transform
	if node is MeshInstance3D and node.mesh!=null:
		var extras: Dictionary = node.get_meta("extras",{})
		var solid: bool = node.get_meta("solid",extras.get("solid",true))
		var label: String = node.get_meta("label",extras.get("label",""))
		if not label.is_empty():
			solid=false
			var sign_text:=Label3D.new()
			sign_text.text=label+"\nPOOL / 1.2 M"
			sign_text.font_size=38
			sign_text.pixel_size=.0055
			sign_text.outline_size=0
			sign_text.position.z=.012
			sign_text.modulate=Color("9c5443")
			node.add_child(sign_text)
		if solid:
			var bounds: AABB = transform * node.mesh.get_aabb()
			var explicit_solid: bool = node.get_meta("solid",extras.get("solid",false))
			if explicit_solid and not String(node.name).begins_with("Metal tubular support"):
				solids.append(bounds)
			if collect_faces:
				for point in node.mesh.get_faces(): triangles.append(transform*point)
	for child in node.get_children():
		if child is Label3D: continue
		_collect_imported(child,transform,triangles,collect_faces)

func _prepare_fixtures_and_props() -> void:
	var corrupt: int = layout.corrupt
	var survival: float = [1.0,1.0,.6,.28][corrupt]
	var power_scale: float = [1.0,.78,.52,.32][corrupt]
	var chance: float = [0.0,.5,.8,1.0][corrupt]
	var amplitude: float = [0.0,.35,.6,.85][corrupt]
	var alive: Array[bool] = [rng.next()<survival,rng.next()<survival]
	if not alive[0] and not alive[1]: alive[0 if rng.next()<.5 else 1]=true
	var fixtures: Array[Dictionary] = []
	for slot in 2:
		var vote: float = rng.next()
		var flicker_seed: float = rng.next()*37
		fixtures.append({"alive":alive[slot],"position":Vector3(-9 if slot==0 else 8,minf(7.3,layout.ceiling-.7),-5),"color":Color(layout.light_color if slot==0 else ("#fff5de" if layout.daylight else "#eee9d5")),"power":layout.light_power*power_scale,"power_scale":power_scale,"flicker":alive[slot] and vote<chance,"flicker_seed":flicker_seed,"flicker_amp":amplitude})
	layout.fixtures=fixtures
	var duck_count: int = 2 if layout.variant>=8 else (int(ceil(layout.ducks/2.0)) if corrupt>=3 else int(layout.ducks))
	var ball_draw: float = rng.next()
	var ball_count: int = (1 if ball_draw>.8 else 0) if layout.variant>=8 else int(floor(ball_draw*2.4))
	var empty_cells: Array[Vector2i] = []
	if not wfc_grid.is_empty():
		for j in 12:
			for i in 12:
				if wfc_grid[j][i]=="E": empty_cells.append(Vector2i(i,j))
	var spawns: Array[Dictionary] = []
	for i in (duck_count if not wfc_grid.is_empty() else duck_count*2)+ball_count:
		var amount: int = duck_count if not wfc_grid.is_empty() else duck_count*2
		var kind: String = ("egg" if i%3!=0 else "duck") if i<amount else "ball"
		var pos:=Vector3.ZERO
		if not empty_cells.is_empty():
			var cell: Vector2i = empty_cells[int(floor(rng.next()*empty_cells.size()))]
			pos.x=(cell.x-5.5)*2.2+(rng.next()-.5)*1.1
			pos.z=(cell.y-5.5)*2.2+(rng.next()-.5)*1.1
		else:
			pos.x=(rng.next()-.5)*28
			pos.z=(rng.next()-.5)*27
		var yaw: float = rng.next()*TAU
		var blocked: bool = false
		for bounds in solids:
			if bounds.position.y<1.7 and bounds.end.y>.65 and pos.x>bounds.position.x-.28 and pos.x<bounds.end.x+.28 and pos.z>bounds.position.z-.28 and pos.z<bounds.end.z+.28:
				blocked=true
				break
		if not blocked:
			pos.y=.445 if kind=="duck" else .32
			spawns.append({"position":pos,"yaw":yaw,"kind":kind})
	layout.prop_spawns=spawns
