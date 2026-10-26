extends RefCounted
## Authored tactile station kit. Runtime owns targeting and placement; coarse static collision is authored here.
## Origin = floor; front = +Z. No dynamic bodies, timers, lights, particles or autonomous processing.
const CampaignFont = preload("res://assets/fonts/campaign/PoolCoreCampaignSC.otf")
const BOUNDS := Vector3(1.3, 1.8, .8)
const FRONT_CLEARANCE := 1.2
static var _materials: Dictionary = {}

static func _mat(key: String) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var m := StandardMaterial3D.new()
	var colors := {"enamel":Color("435b60"), "edge":Color("233439"), "brass":Color("b39b64"), "ceramic":Color("d2d6c5"), "dark":Color("121c20"), "red":Color("bd684a"), "blue":Color("60959e"), "amber":Color("e3bc64"), "ready":Color("f4e4bc"), "glass":Color("a7c6c6")}
	m.albedo_color = colors.get(key, Color.WHITE)
	m.roughness = .46 if key in ["brass", "glass"] else .72
	m.metallic = .7 if key in ["brass", "edge"] else .15
	if key in ["ready", "amber"]:
		m.emission_enabled = true; m.emission = m.albedo_color; m.emission_energy_multiplier = .35
	_materials[key] = m
	return m

static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, material: String, node_name: String = "") -> MeshInstance3D:
	var n := MeshInstance3D.new(); n.mesh = mesh; n.position = pos; n.material_override = _mat(material)
	if not node_name.is_empty(): n.name = node_name
	parent.add_child(n)
	return n

static func _box(parent: Node3D, pos: Vector3, size: Vector3, material: String, node_name: String = "") -> MeshInstance3D:
	var m := BoxMesh.new(); m.size = size
	return _mesh(parent,m,pos,material,node_name)

static func _cylinder(parent: Node3D, pos: Vector3, radius: float, depth: float, material: String, node_name: String = "") -> MeshInstance3D:
	var m := CylinderMesh.new(); m.top_radius = radius; m.bottom_radius = radius; m.height = depth; m.radial_segments = 20; m.rings = 1
	var n := _mesh(parent,m,pos,material,node_name); n.rotation.x = PI / 2
	return n

static func _ring(parent: Node3D, pos: Vector3, radius: float, material: String) -> MeshInstance3D:
	var m := TorusMesh.new(); m.inner_radius = radius-.022; m.outer_radius = radius+.022; m.rings = 20; m.ring_segments = 6
	var n := _mesh(parent,m,pos,material); n.rotation.x = PI / 2
	return n

static func _label(parent: Node3D, pos: Vector3, text: String, size: int = 24) -> Label3D:
	var n := Label3D.new(); n.font = CampaignFont; n.text = text; n.position = pos; n.font_size = size; n.pixel_size = .0016
	n.modulate = Color("e0e1cf"); n.outline_size = 0; n.no_depth_test = false; n.shaded = false
	parent.add_child(n)
	return n

static func _pivot(parent: Node3D, pos: Vector3, node_name: String) -> Node3D:
	var n := Node3D.new(); n.name = node_name; n.position = pos; parent.add_child(n); return n

static func _dial(parent: Node3D, pos: Vector3, radius: float, node_name: String) -> void:
	_cylinder(parent,pos,radius,.065,"brass")
	_cylinder(parent,pos+Vector3(0,0,.039),radius*.86,.015,"ceramic")
	for i in 9:
		var a := deg_to_rad(-130.0+i*32.5)
		var tick := _box(parent,pos+Vector3(sin(a)*radius*.69,cos(a)*radius*.69,.053),Vector3(.012,.035,.008),"edge")
		tick.rotation.z = -a
	var needle := _pivot(parent,pos+Vector3(0,0,.064),node_name)
	_box(needle,Vector3(0,radius*.28,0),Vector3(.015,radius*.64,.012),"red")
	_cylinder(needle,Vector3.ZERO,.025,.02,"edge")

static func build_station(spec: Dictionary) -> Node3D:
	var n := Node3D.new(); n.name = "Station_"+str(spec.get("id","fixture")); n.set_meta("label",str(spec.get("label","检修设备")))
	var kind := str(spec.get("kind","power"))
	n.set_meta("kind",kind); n.set_meta("visual_bounds",BOUNDS); n.set_meta("front_clearance",FRONT_CLEARANCE)
	_support(n,kind)
	match kind:
		"power", "breaker", "diagnose": _power(n)
		"pressure", "valve", "balance", "drain", "outlet": _pressure(n)
		"pressure_panel": _pressure_panel(n)
		"sound", "resonator", "listen", "flow_selector": _sound(n)
		"memory", "sequence", "memory_tile": _memory(n)
		"ventilation", "fan", "isolation", "damper", "vent", "motor": _fan(n)
		"light", "mirror": _light(n)
		"shutter": _shutter(n)
		"repair", "departure", "egress": _terminal(n,kind)
		"bell": _bell(n)
		"locker": _locker(n)
		_: _power(n)
	_box(n,Vector3(0,.72,.1),Vector3(.55,.13,.035),"dark")
	_label(n,Vector3(0,.72,.123),str(spec.get("plate",_plate(kind,spec))),20)
	_cylinder(n,Vector3(.28,.85,.14),.035,.04,"amber","Status")
	# Dedicated courtesy diffuser, not the semantic Status lamp. Per-station material
	# prevents arrival emission changes from leaking into other fixtures.
	var conduit := _box(n,Vector3(-.395,1.125,.04),Vector3(.025,.697,.025),"edge")
	conduit.rotation.z=.367
	_box(n,Vector3(-.52,1.45,.07),Vector3(.085,.24,.075),"edge")
	for lamp_index in 3:
		var courtesy := _box(n,Vector3(-.52,1.45+(1-lamp_index)*.066,.115),Vector3(.05,.047,.014),"ceramic","ArrivalLamp%d"%lamp_index)
		var courtesy_material := _mat("ceramic").duplicate() as StandardMaterial3D
		courtesy_material.albedo_color=Color("344345")
		courtesy_material.emission_enabled=true
		courtesy_material.emission=Color("ffe0ab")
		courtesy_material.emission_energy_multiplier=0.0
		courtesy.material_override=courtesy_material
	n.set_meta("arrival_lamp_neutral_energy",0.0)
	# Separate non-objective inspection tag: arrival controller may sway and restore it.
	var vane := _pivot(n,Vector3(-.19,.645,.12),"ArrivalVane")
	_box(vane,Vector3(0,-.045,0),Vector3(.07,.09,.009),"brass")
	n.set_meta("arrival_visual_nodes",[NodePath("ArrivalVane")])
	_add_clues(n,spec)
	_collision(n)
	update_station(n,spec,{})
	return n

static func _power(n: Node3D) -> void:
	_box(n,Vector3(0,1.24,-.04),Vector3(1.02,.76,.18),"enamel")
	_box(n,Vector3(0,1.24,.06),Vector3(.87,.62,.025),"edge")
	for i in 3:
		var x := (i-1)*.27
		_box(n,Vector3(x,1.2,.09),Vector3(.16,.32,.045),"ceramic")
		if i==1:
			var lever := _pivot(n,Vector3(x,1.2,.15),"Lever0")
			_box(lever,Vector3(0,.07,.025),Vector3(.1,.16,.065),"red")
		else:
			_box(n,Vector3(x,1.2,.15),Vector3(.07,.19,.045),"glass")
			for y in [1.1,1.3]: _box(n,Vector3(x,y,.15),Vector3(.08,.035,.055),"brass")
		_label(n,Vector3(x,1.48,.085),["FUSE","SW","FUSE"][i],17)
		_cylinder(n,Vector3(x,1.02,.12),.025,.02,"amber","Lamp%d"%i)
	# Diagram: three explicit circuit traces, not a floating collectible marker.
	for x in [-.39,.39]: _box(n,Vector3(x,1.24,.088),Vector3(.014,.42,.012),"brass")

static func _pressure(n: Node3D) -> void:
	_box(n,Vector3(0,1.04,-.05),Vector3(.91,.17,.17),"enamel")
	for x in [-.4,.4]: _cylinder(n,Vector3(x,1.04,.05),.13,.06,"brass")
	_dial(n,Vector3(0,1.48,.0),.2,"Needle")
	var wheel := _pivot(n,Vector3(0,1.02,.24),"Wheel")
	_ring(wheel,Vector3.ZERO,.27,"red")
	for i in 4:
		var spoke := _box(wheel,Vector3.ZERO,Vector3(.032,.51,.035),"red"); spoke.rotation.z=i*PI/4
	_cylinder(wheel,Vector3.ZERO,.065,.09,"brass")
	_label(n,Vector3(.37,1.36,.13),"−  +",25)

static func _sound(n: Node3D) -> void:
	_box(n,Vector3(0,1.12,-.06),Vector3(.78,.49,.25),"enamel")
	var horn := _pivot(n,Vector3(0,1.4,.1),"Horn")
	var cone := CylinderMesh.new(); cone.top_radius=.3; cone.bottom_radius=.07; cone.height=.27; cone.radial_segments=24
	var bell := _mesh(horn,cone,Vector3(0,0,.06),"brass"); bell.rotation.x=PI/2
	_cylinder(horn,Vector3(0,0,.205),.255,.015,"dark")
	_ring(horn,Vector3(0,0,.22),.275,"brass")
	for i in 5: _box(horn,Vector3((i-2)*.065,0,.224),Vector3(.012,.36-abs(i-2)*.06,.012),"edge")
	var selector := _pivot(n,Vector3(0,1.04,.14),"Selector")
	_cylinder(selector,Vector3.ZERO,.1,.08,"brass")
	_box(selector,Vector3(0,.048,.06),Vector3(.018,.07,.015),"ceramic")
	_label(n,Vector3(0,.91,.15),"·   · ·   · · ·",20)

static func _memory(n: Node3D) -> void:
	_box(n,Vector3(0,1.15,-.04),Vector3(1.2,.58,.2),"enamel")
	for row in [1.0,1.3]: _box(n,Vector3(0,row,.1),Vector3(1.1,.025,.035),"brass")
	for i in 5:
		var tile := _pivot(n,Vector3((i-2)*.21,1.15,.14),"Tile%d"%i)
		_box(tile,Vector3.ZERO,Vector3(.18,.25,.065),"ceramic")
		for mark in i+1: _box(tile,Vector3((mark-i*.5)*.025,0,.037),Vector3(.011,.09,.008),"enamel")
	_label(n,Vector3(0,1.55,.03),"I     II     III     IV     V",22)

static func _fan(n: Node3D) -> void:
	_box(n,Vector3(0,1.27,-.04),Vector3(.86,.74,.23),"enamel")
	_cylinder(n,Vector3(0,1.29,.1),.3,.03,"dark")
	var fan := _pivot(n,Vector3(0,1.29,.14),"Fan")
	for i in 4:
		var blade := _pivot(fan,Vector3.ZERO,"Blade%d"%i); blade.rotation.z=i*PI/2
		var fin := _box(blade,Vector3(.08,.12,0),Vector3(.13,.24,.02),"brass"); fin.rotation.z=.4
	_cylinder(fan,Vector3.ZERO,.065,.04,"edge")
	_ring(n,Vector3(0,1.29,.18),.31,"edge")
	for i in 5: _box(n,Vector3((i-2)*.1,1.29,.2),Vector3(.012,.52,.015),"edge")
	var shutter := _pivot(n,Vector3(0,1.29,.23),"Shutter")
	for i in 3: _box(shutter,Vector3(0,(i-1)*.17,0),Vector3(.58,.045,.025),"ceramic")
	_label(n,Vector3(0,.94,.14),"AIR  /  ISOLATE",18)

static func _light(n: Node3D) -> void:
	_box(n,Vector3(0,1.2,-.08),Vector3(.11,.65,.14),"brass")
	var mirror := _pivot(n,Vector3(0,1.37,.02),"Mirror")
	_cylinder(mirror,Vector3.ZERO,.33,.07,"brass")
	_cylinder(mirror,Vector3(0,0,.042),.285,.025,"glass")
	_box(mirror,Vector3(0,0,.06),Vector3(.015,.55,.01),"ceramic")
	_box(mirror,Vector3(0,0,.06),Vector3(.55,.015,.01),"ceramic")
	for x in [-.39,.39]: _box(n,Vector3(x,1.32,0),Vector3(.055,.35,.09),"enamel")
	_box(n,Vector3(0,1.14,0),Vector3(.81,.055,.09),"enamel")
	_dial(n,Vector3(0,.97,.14),.12,"Needle")

static func update_station(n: Node3D, spec: Dictionary, view: Dictionary) -> void:
	if not is_instance_valid(n): return
	# Stable stations must not resubmit materials/transforms to the renderer each frame.
	if n.get_meta("campaign_view", {}) == view: return
	n.set_meta("campaign_view", view.duplicate(true))
	var done := bool(view.get("solved",view.get("completed",false)))
	var active := bool(view.get("active",false))
	var kind := str(spec.get("kind",n.get_meta("kind","breaker")))
	var value := clampf(float(view.get("value",view.get("stage",0))),0.0,5.0)
	var status := n.get_node_or_null("Status") as MeshInstance3D
	if status: status.material_override=_mat("ready" if done or active else "amber")
	for i in 3:
		var lever := n.get_node_or_null("Lever%d"%i) as Node3D
		if lever: lever.rotation.x= -.6 if active else .55
		var lamp := n.get_node_or_null("Lamp%d"%i) as MeshInstance3D
		if lamp: lamp.material_override=_mat("ready" if active else "amber")
	var needle := n.get_node_or_null("Needle") as Node3D
	if needle: needle.rotation.z = lerpf(2.2,-2.2,value/3.0)
	if kind=="shutter" and needle: needle.rotation.z=lerpf(2.2,-2.2,clampf(float(view.get("stable",0.0))/12.0,0.0,1.0))
	var readings: Array = view.get("readings",[0,0,0])
	for i in 3:
		var gauge := n.get_node_or_null("Gauge%d"%i) as Node3D
		if gauge and readings.size()>i: gauge.rotation.z=lerpf(2.2,-2.2,clampf(float(readings[i])/6.0,0.0,1.0))
	var wheel := n.get_node_or_null("Wheel") as Node3D
	if wheel: wheel.rotation.z=value*PI/3.0
	var selector := n.get_node_or_null("Selector") as Node3D
	if selector: selector.rotation.z=value*TAU/3.0
	var horn := n.get_node_or_null("Horn") as Node3D
	if horn: horn.rotation.y=sin(value*TAU/3.0)*.16
	for i in 5:
		var tile := n.get_node_or_null("Tile%d"%i) as Node3D
		if tile:
			tile.position.y=1.15+(.045 if active else 0.0)
			tile.rotation.z=0.0 if active else deg_to_rad(float((i%3)-1)*8.0)
	var shutter := n.get_node_or_null("Shutter") as Node3D
	if shutter: shutter.rotation.x = (.95 if not active else 0.0) if kind=="damper" else (.95 if active else 0.0)
	var fan := n.get_node_or_null("Fan") as Node3D
	if fan: fan.rotation.z=value*.45
	var mirror := n.get_node_or_null("Mirror") as Node3D
	if mirror: mirror.rotation.y = (value-1.0)*.48
	var door := n.get_node_or_null("Door") as Node3D
	if door: door.rotation.y = -1.15 if active else 0.0
	var clapper := n.get_node_or_null("Clapper") as Node3D
	if clapper: clapper.rotation.z = .45 if active else -.1
	var readout := n.get_node_or_null("Readout") as Label3D
	if readout: readout.text = str(int(value))
	n.set_meta("visual_completed",done)
	n.set_meta("visual_value",value)

static func _plate(kind: String, spec: Dictionary) -> String:
	var index := int(spec.get("index",0))
	match kind:
		"breaker": return "FEED" if index==0 else ("NIGHT / ISOLATE" if index==4 else "CIRCUIT %02d"%index)
		"valve": return ["BYPASS A", "RETURN B", "FILL C"][clampi(index,0,2)]
		"flow_selector": return "OUTER / 2" if index==0 else "RETURN / 1"
		"memory_tile": return ["STAIR", "COLUMN", "WINDOW", "OCTAGON", "CONFIRM"][clampi(index,0,4)]
		"damper": return "1 / ISOLATE"
		"vent": return "2 / OPEN"
		"motor": return "3 / START"
		"mirror": return "EAST / 1" if index==1 else "DOWN / 2"
		"repair": return "EMERGENCY RESET"
		"departure", "egress": return "RELEASE / EXIT"
	return kind.to_upper().replace("_"," ")

static func _add_clues(n: Node3D, spec: Dictionary) -> void:
	var kind := str(spec.get("kind","breaker"))
	var index := int(spec.get("index",0))
	if kind == "breaker":
		# Insulation scorch marks are localized to the actually faulty branch.
		if index==4:
			for i in 4:
				var scar := _box(n,Vector3(-.2+i*.11,1.57,.062),Vector3(.035,.08+(i%2)*.04,.012),"dark")
				scar.rotation.z=.3
			_label(n,Vector3(0,1.67,.07),"!  LEAK / ISOLATE",22)
		else: _label(n,Vector3(0,1.67,.07),"ON  /  OFF",22)
	elif kind in ["valve", "drain", "outlet"]:
		_label(n,Vector3(0,1.73,.04),"0   1   2   3" if kind=="valve" else "CLOSE / OPEN",21)
		var readout := _label(n,Vector3(.36,1.56,.09),"0",32); readout.name="Readout"
	elif kind=="flow_selector":
		# Pipe shapes distinguish curved outer route from paired return channels.
		if index==0:
			_ring(n,Vector3(.46,1.25,.04),.13,"brass")
			_box(n,Vector3(.46,1.08,.04),Vector3(.025,.13,.025),"brass")
		else:
			for x in [.42,.5]: _box(n,Vector3(x,1.25,.04),Vector3(.025,.34,.025),"brass")
		var readout := _label(n,Vector3(-.3,1.04,.14),"0",28); readout.name="Readout"
	elif kind=="memory_tile":
		# A station is one spatial note, not five interchangeable pickups.
		for i in 5:
			var tile := n.get_node("Tile%d"%i) as Node3D
			if i!=clampi(index,0,4): tile.free()
			else: tile.position.x=0.0
		if index==0:
			_label(n,Vector3(0,1.57,.05),"STAIR > WINDOW\nCOLUMN > OCTAGON",19)
		for child in n.get_children():
			if child is Label3D and child.text.begins_with("I     II"): child.free()
		_symbol(n,index)
	elif kind in ["damper","vent","motor"]:
		_label(n,Vector3(0,1.73,.08),"ISOLATE > OPEN > START",17)
	elif kind=="mirror":
		_label(n,Vector3(0,1.77,.02),"0    1    2",23)
		# Fixed brass notch is the desired aiming detent; mirror is independently movable.
		var notch := _box(n,Vector3(.37 if index==1 else -.37,1.58,.08),Vector3(.045,.12,.04),"brass")
		notch.rotation.z = .4 if index==1 else -.4

static func _symbol(n: Node3D, index: int) -> void:
	var center := Vector3(0,1.15,.205)
	match index:
		0:
			for i in 3: _box(n,center+Vector3((i-1)*.045,(i-1)*.04,0),Vector3(.05,.014,.014),"brass")
		1:
			_box(n,center,Vector3(.035,.14,.014),"brass")
			for y in [-.07,.07]: _box(n,center+Vector3(0,y,0),Vector3(.1,.02,.014),"brass")
		2:
			_box(n,center,Vector3(.11,.14,.014),"blue")
			_box(n,center+Vector3(0,0,.012),Vector3(.012,.14,.012),"ceramic")
		3:
			var m := CylinderMesh.new(); m.top_radius=.07; m.bottom_radius=.07; m.height=.012; m.radial_segments=8
			var icon := _mesh(n,m,center,"brass"); icon.rotation.x=PI/2
		4: _ring(n,center,.065,"brass")

static func _pressure_panel(n: Node3D) -> void:
	_box(n,Vector3(0,1.25,-.02),Vector3(1.16,.65,.22),"enamel")
	for i in 3:
		_dial(n,Vector3((i-1)*.34,1.34,.13),.14,"Gauge%d"%i)
		_label(n,Vector3((i-1)*.34,1.08,.1),["A+B=3","B+C=4","A+C=5"][i],19)
	var lever := _pivot(n,Vector3(0,.93,.16),"Lever0")
	_box(lever,Vector3(0,.035,.045),Vector3(.16,.09,.08),"brass")

static func _shutter(n: Node3D) -> void:
	_box(n,Vector3(0,1.28,-.04),Vector3(.85,.7,.22),"enamel")
	_box(n,Vector3(0,1.33,.08),Vector3(.65,.43,.015),"dark")
	var shutter := _pivot(n,Vector3(0,1.33,.14),"Shutter")
	for i in 4: _box(shutter,Vector3(0,(i-1.5)*.1,0),Vector3(.63,.07,.025),"brass")
	_dial(n,Vector3(0,.95,.16),.11,"Needle")
	_label(n,Vector3(0,1.72,.1),"ALIGN > OPEN > CHARGE",17)

static func _terminal(n: Node3D, kind: String) -> void:
	_box(n,Vector3(0,1.23,-.04),Vector3(.76,.68,.24),"enamel")
	_box(n,Vector3(0,1.31,.09),Vector3(.59,.32,.025),"dark")
	_label(n,Vector3(0,1.34,.11),"RESET\nLOCAL SYSTEM" if kind=="repair" else "EXIT\nSYSTEM RELEASE",23)
	var lever := _pivot(n,Vector3(0,1.02,.16),"Lever0")
	_box(lever,Vector3(0,.04,.02),Vector3(.28,.08,.08),"red" if kind=="repair" else "brass")
	for x in [-.23,.23]: _box(n,Vector3(x,1.03,.19),Vector3(.035,.2,.12),"edge")

static func _bell(n: Node3D) -> void:
	_box(n,Vector3(0,.98,0),Vector3(.66,.1,.4),"enamel")
	var shell := SphereMesh.new(); shell.radius=.21; shell.height=.23; shell.is_hemisphere=true; shell.radial_segments=20; shell.rings=8
	_mesh(n,shell,Vector3(0,1.06,0),"brass")
	var clapper := _pivot(n,Vector3(0,1.28,0),"Clapper")
	_box(clapper,Vector3(0,.06,0),Vector3(.035,.14,.035),"brass")
	_label(n,Vector3(0,1.5,.08),"SERVICE BELL",22)

static func _locker(n: Node3D) -> void:
	_box(n,Vector3(0,1.2,-.06),Vector3(.7,.7,.27),"edge")
	var door := _pivot(n,Vector3(-.34,1.2,.09),"Door")
	_box(door,Vector3(.34,0,0),Vector3(.68,.68,.05),"enamel")
	_box(door,Vector3(.59,0,.05),Vector3(.025,.16,.04),"brass")
	for i in 4: _box(door,Vector3(.34,.13+i*.035,.028),Vector3(.3,.012,.01),"dark")
	_label(n,Vector3(0,1.7,.08),"LOST & FOUND",21)

static func _collision(n: Node3D) -> void:
	var body := StaticBody3D.new(); body.name="StationBody"; body.collision_layer=1; body.collision_mask=0
	n.add_child(body)
	# A continuous simplified envelope avoids decorative snag points and hidden physics.
	for part in [ [Vector3(0,.06,0),Vector3(.82,.12,.58)], [Vector3(0,.5,-.08),Vector3(.2,.88,.2)], [Vector3(0,1.24,.04),Vector3(1.2,.84,.58)] ]:
		var shape := BoxShape3D.new(); shape.size=part[1]
		var collider := CollisionShape3D.new(); collider.shape=shape; collider.position=part[0]; body.add_child(collider)


static func _support(n: Node3D, kind: String) -> void:
	match kind:
		"valve", "pressure", "drain", "outlet":
			for x in [-.38,.38]:
				_box(n,Vector3(x,.045,0),Vector3(.25,.09,.42),"edge")
				var pipe := _cylinder(n,Vector3(x,.53,-.05),.075,.92,"enamel"); pipe.rotation.x=0.0
				var collar := _cylinder(n,Vector3(x,.17,-.05),.105,.09,"brass"); collar.rotation.x=0.0
		"memory_tile", "memory", "pressure_panel", "bell":
			for x in [-.34,.34]:
				_box(n,Vector3(x,.4,-.04),Vector3(.055,.8,.08),"enamel")
				_box(n,Vector3(x,.035,0),Vector3(.13,.07,.52),"edge")
			_box(n,Vector3(0,.84,-.04),Vector3(.79,.08,.37),"brass")
			_box(n,Vector3(0,.24,-.08),Vector3(.7,.035,.04),"enamel")
		"mirror", "light":
			_box(n,Vector3(0,.48,-.08),Vector3(.1,.96,.1),"brass")
			for i in 3:
				var foot := _pivot(n,Vector3(0,.13,-.05),"Foot%d"%i);foot.rotation.y=i*TAU/3.0
				var leg := _box(foot,Vector3(0,0,.18),Vector3(.08,.08,.47),"edge");leg.rotation.x=.3
		"vent", "motor", "damper", "fan":
			for x in [-.31,.31]:
				_box(n,Vector3(x,.43,-.05),Vector3(.07,.86,.13),"enamel")
				_box(n,Vector3(x,.045,0),Vector3(.18,.09,.55),"edge")
			_box(n,Vector3(0,.32,-.08),Vector3(.65,.08,.08),"edge")
		_:
			_box(n,Vector3(0,.06,0),Vector3(.82,.12,.58),"edge")
			_box(n,Vector3(0,.47,-.08),Vector3(.17,.84,.17),"enamel")
			_box(n,Vector3(0,.84,-.08),Vector3(.66,.1,.28),"brass")


static func pulse_station(n: Node3D) -> void:
	## Optional single ease-out interaction acknowledgment. No blink or light change.
	## Only invoke on a player action, never per-frame. Prior tween is replaced.
	if not is_instance_valid(n) or not n.is_inside_tree(): return
	var lens := n.get_node_or_null("Status") as Node3D
	if not lens: return
	var previous: Variant = n.get_meta("feedback_tween") if n.has_meta("feedback_tween") else null
	if previous is Tween and previous.is_valid(): previous.kill()
	lens.scale=Vector3.ONE
	var tween := n.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(lens,"scale",Vector3.ONE*1.2,.12)
	tween.tween_property(lens,"scale",Vector3.ONE,.24)
	n.set_meta("feedback_tween",tween)
