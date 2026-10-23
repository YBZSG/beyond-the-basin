class_name PoolLighting
extends RefCounted

## Notify capture owners after discrete palette changes, never every frame.
signal capture_lighting_changed
## Native Forward+ illumination. A real sun is occluded by actual roofs;
## only authored apertures admit it. No imported Three lightmap is used.

const FORMAL_SUN_ENERGY := 1.45
const FORMAL_EXPOSURE := 1.12
# Accepted actual production-sky mainhall image: production02 exposure-3p2.
# Display exposure only; every other authored room keeps FORMAL_EXPOSURE.
const FORMAL_MAINHALL_EXPOSURE := 3.2
# Native HDR panorama study, 2026-10-21: preserve the existing upper-hemisphere
# horizontal irradiance, not an ambient/exposure lift. See the sky provenance.
const FORMAL_PHYSICAL_SKY_ENERGY := 3.98049270761935
const FORMAL_PHOTON_REFERENCE_HEIGHT := 7.3
const FORMAL_WATER_REFERENCE_HEIGHT := 0.32

const ROOM_CEILINGS: Array[float] = [9.2, 9.2, 9.2, 14.0, 5.8, 9.2, 5.8, 13.0, 14.4, 11.6, 6.4]
const DAYLIGHT_VARIANTS: Array[int] = [3, 5, 6, 8]
const LIGHT_COLORS: Array[Color] = [
	Color("b5dfdc"), Color("b5dfdc"), Color("b5dfdc"), Color("fff5de"),
	Color("b5dfdc"), Color("fff5de"), Color("fff5de"), Color("b5dfdc"),
	Color("e5f4f0"), Color("f8e6c4"), Color("d7eee6")]

var _environment: Environment
var _world_environment: WorldEnvironment
var _mood_tween: Tween
var _room_roots: Array[WeakRef] = []
var _materials := PoolMaterials.new()
var _source_lights:Array[WeakRef]=[]
var _active_formal:=false
var _formal_physical_sky_enabled:=false
# Experimental PC-only quality candidate. No production caller enables it until
# a fixed-camera native comparison and full-game performance acceptance exist.
var _formal_basin_return_distributed_enabled:=false
var _original_sky_material:ProceduralSkyMaterial
var _formal_procedural_sky_material:ProceduralSkyMaterial
var _formal_physical_sky_material:PhysicalSkyMaterial
var _last_coord := Vector2i(2147483647, 2147483647)

func configure_environment(world_environment: WorldEnvironment) -> void:
	var environment := Environment.new()
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.resource_name = "Quiet Wing / native Forward+ environment"
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("91b4c4")
	sky_material.sky_horizon_color = Color("d1ddd8")
	sky_material.ground_horizon_color = Color("acb4a8")
	sky_material.ground_bottom_color = Color("59665f")
	sky_material.sky_curve = 0.18
	sky_material.sun_angle_max = 5.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e9e5df")
	# A small broad fill keeps vaults legible, not an emissive ceiling. Local
	# light and GI still supply most of the separation, color and direction.
	environment.ambient_light_energy = 0.24
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.25
	environment.tonemap_agx_contrast = 1.15
	environment.sdfgi_enabled = forward
	environment.sdfgi_cascades = 6
	environment.sdfgi_min_cell_size = 0.2
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = true
	environment.sdfgi_bounce_feedback = 0.48
	environment.sdfgi_energy = 1.08
	environment.sdfgi_normal_bias = 1.1
	environment.sdfgi_probe_bias = 1.1
	environment.ssao_enabled = forward
	environment.ssao_radius = 0.65
	environment.ssao_intensity = 0.75
	environment.ssao_power = 1.25
	environment.ssao_detail = 0.45
	environment.ssao_light_affect = 0.0
	environment.ssil_enabled = forward
	environment.ssil_radius = 3.5
	environment.ssil_intensity = 0.25
	environment.ssil_normal_rejection = 1.0
	environment.ssr_enabled = forward
	environment.ssr_max_steps = 96
	environment.ssr_depth_tolerance = 0.2
	environment.glow_enabled = true
	environment.glow_bloom = 0.0
	environment.glow_intensity = 0.12
	environment.glow_hdr_threshold = 2.0
	environment.glow_hdr_scale = 1.0
	environment.volumetric_fog_enabled = forward
	environment.volumetric_fog_density = 0.0032
	environment.volumetric_fog_albedo = Color("c3d5cf")
	environment.volumetric_fog_anisotropy = 0.35
	environment.volumetric_fog_length = 96.0
	environment.volumetric_fog_ambient_inject = 0.12
	environment.volumetric_fog_gi_inject = 0.4
	environment.volumetric_fog_emission = Color.BLACK
	environment.fog_enabled = false
	world_environment.environment = environment
	_environment = environment
	_world_environment=world_environment
	if not world_environment.has_node("ApertureSun"):
		var sun := DirectionalLight3D.new()
		sun.name = "ApertureSun"
		sun.rotation_degrees = Vector3(-62.0, -28.0, 0.0)
		sun.light_color = Color("fff2d8")
		sun.light_energy = 1.65
		sun.light_indirect_energy = 0.8
		sun.light_angular_distance = 1.0
		sun.light_bake_mode = Light3D.BAKE_DYNAMIC
		sun.shadow_enabled = true
		sun.shadow_bias = 0.1
		sun.shadow_normal_bias = 2.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 120.0
		sun.directional_shadow_blend_splits = true
		world_environment.add_child(sun)

func set_source_fog_model(source_mode:bool)->void:
	if _environment==null:return
	var forward:=RenderingServer.get_current_rendering_method()=="forward_plus"
	_environment.ssr_enabled=forward and not source_mode
	_environment.volumetric_fog_enabled=forward and not source_mode
	_environment.fog_enabled=false

func invalidate_active_room() -> void:
	# Coordinates alone do not identify a room after a world or seed rebuild.
	_last_coord = Vector2i(2147483647, 2147483647)

func add_room_lights(room: Node3D, variant: int) -> void:
	if room.has_node("NativeLighting"):return
	var layout:Dictionary=room.get_meta("layout",{})
	var ceiling:float=float(layout.get("ceiling",ROOM_CEILINGS[clampi(variant,0,7)]))
	if layout.get("expanded",false): ceiling=float(layout.get("interior_ceiling",ceiling))
	var rig:=Node3D.new();rig.name="NativeLighting";room.add_child(rig)
	rig.set_meta("variant",variant)
	var fixtures:Array=layout.get("fixtures",[])
	var pc_source := PoolMaterials.use_pc_source_finish() and not bool(layout.get("expanded",false) or layout.get("formal",false))
	for slot in fixtures.size():
		var source:Dictionary=fixtures[slot]
		var at:Vector3=source.position
		var fixture:=PoolFixtureFlicker.new();fixture.name="SourceDoubleTube%d"%slot;fixture.position=at;rig.add_child(fixture)
		var fixture_color: Color = source.color.lerp(Color("eef1eb"),0.42) if pc_source else source.color
		var opal:=_make_opal(fixture_color)
		var alive:=bool(source.get("alive",true))
		if not alive:opal.albedo_color=Color(.14,.17,.18);opal.emission_enabled=false
		var housing:=_materials.get_material("lamp_housing")
		_box(fixture,Vector3(0,.18,0),Vector3(2.85,.18,.52),housing)
		for z in [-.14,.14]:_box(fixture,Vector3(0,.055,z),Vector3(2.55,.11,.095),opal)
		for x in [-1.35,1.35]:_box(fixture,Vector3(x,.09,0),Vector3(.12,.24,.5),housing)
		var cable_height:=maxf(.05,ceiling-.25-at.y-.28)
		for x in [-1.05,1.05]:_box(fixture,Vector3(x,.28+cable_height*.5,0),Vector3(.025,cable_height,.025),housing)
		# Source excludes the lamp's own housing from casting giant shadow wedges.
		for mesh in fixture.find_children("*","MeshInstance3D",true,false):
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.set_meta("source_exclude_optics",true)
		if alive:
			var lamp:=OmniLight3D.new();lamp.name="SourcePointLight";lamp.omni_range=36.0;lamp.omni_attenuation=2.0
			# PC calibrates tube flux and tint for the less veiled ceramic finish.
			# Keep authored positions, relative powers, survival and flicker. Liquid
			# receives the original Three intensity through this explicit conversion.
			var original_power:=float(source.power)
			var power_scale := .115 if pc_source else .07
			_configure_local_light(lamp,fixture_color,original_power*power_scale,.32)
			lamp.set_meta("source_power_per_energy",1.0/power_scale)
			lamp.set_meta("source_shadow_priority",true)
			lamp.set_meta("source_shadow_managed",true)
			lamp.set_meta("source_room_coord",room.get_meta("coord",Vector2i.ZERO))
			_source_lights.append(weakref(lamp))
			fixture.add_child(lamp)
			if source.get("flicker",false):fixture.enable_flicker(float(source.flicker_seed),float(source.flicker_amp),opal)
	if layout.has("exit_light"):
		var exit_lamp:=OmniLight3D.new();exit_lamp.name="SourceExitLight";exit_lamp.position=layout.exit_light;exit_lamp.omni_range=7.0;exit_lamp.omni_attenuation=2.0
		_configure_local_light(exit_lamp,Color("ff4a30"),7.0*.07,.12);exit_lamp.set_meta("source_power_per_energy",1.0/.07);exit_lamp.set_meta("source_shadow_managed",true);exit_lamp.set_meta("source_room_coord",room.get_meta("coord",Vector2i.ZERO));rig.add_child(exit_lamp);_source_lights.append(weakref(exit_lamp))
	_add_reflection_probe(rig,ceiling,false)
	_room_roots.append(weakref(rig))

func update_source_view(camera:Camera3D)->void:
	if _active_formal or not is_instance_valid(camera):return
	var tubes:Array=[];var rest:Array=[];var alive:Array[WeakRef]=[]
	var focus:=camera.global_position;var direction:=-camera.global_basis.z
	for reference:WeakRef in _source_lights:
		var light:=reference.get_ref() as OmniLight3D
		if not is_instance_valid(light):continue
		alive.append(reference)
		var coord:Vector2i=light.get_meta("source_room_coord",Vector2i.ZERO)
		var delta:=coord-_last_coord
		light.visible=maxi(absi(delta.x),absi(delta.y))<=1
		if not light.visible:light.shadow_enabled=false;continue
		if coord==_last_coord and light.get_meta("source_shadow_priority",false):tubes.append(light)
		else:
			var relative:=light.global_position-focus;var along:=relative.dot(direction)
			rest.append({"light":light,"score":relative.length_squared()-along*along+(2500.0 if along<0 else 0.0)})
	rest.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.score<b.score)
	var selected:Array=tubes
	for entry:Dictionary in rest:selected.append(entry.light)
	for i in selected.size():
		var light:OmniLight3D=selected[i]
		light.visible=i<27
		light.shadow_enabled=i<4 and bool(light.get_meta("source_shadows_allowed",true))
	_source_lights=alive

static func display_exposure_for_room(coord: Vector2i, formal: bool) -> float:
	if not formal:return 1.25
	return FORMAL_MAINHALL_EXPOSURE if coord == Vector2i(-1,-1) else FORMAL_EXPOSURE

func update_active_room(coord: Vector2i, layout: Dictionary) -> void:
	if coord == _last_coord:
		return
	_last_coord = coord
	var variant := int(layout.get("variant",0))
	# Authored variants have explicit daylight because the later room indices
	# are not entries in the original procedural-room variant table.
	var daylit := bool(layout.get("daylight",variant in DAYLIGHT_VARIANTS))
	var formal := bool(layout.get("formal",false))
	var expanded := bool(layout.get("expanded",false))
	var authored := formal or expanded
	_active_formal=formal
	set_source_fog_model(not authored)
	if _environment:
		# Source exploration decay eases fog, background and daylight targets.
		# Native volumetric density is not numerically the Three exponential fog.
		var decay:=clampi(int(layout.get("corrupt",0)),0,3)
		var density:float=(0.0025 if daylit else 0.0035)+[0.0,0.0007,0.0017,0.0030][decay]
		if expanded: density = .0012 if daylit else .0016
		var fog_target:=Color("c3d5cf").lerp(Color(str(layout.get("fog_color","#22343d"))) if decay<2 else Color("22343d"),0.3+0.12*decay)
		if is_instance_valid(_mood_tween):_mood_tween.kill()
		_mood_tween=_world_environment.create_tween().set_parallel(true)
		if RenderingServer.get_current_rendering_method() == "forward_plus":
			_mood_tween.tween_property(_environment,"volumetric_fog_density",density,1.6)
			_mood_tween.tween_property(_environment,"volumetric_fog_albedo",fog_target,1.6)
		else:
			# Mobile has no volumetric fog, but still retains exploration decay.
			_mood_tween.tween_property(_environment,"fog_density",density,1.6)
			_mood_tween.tween_property(_environment,"fog_light_color",fog_target,1.6)
		_mood_tween.tween_property(_environment,"background_energy_multiplier",[1.0,0.85,0.55,0.3][decay],1.6)
		# Preserve headroom on pale sunlit ceramic, without crushing the unlit
		# bays. This is room-scoped, so legacy-room exposure remains unchanged.
		_mood_tween.tween_property(_environment,"tonemap_exposure",(1.4 if expanded else display_exposure_for_room(coord, formal)),0.6)
		_environment.background_mode=Environment.BG_SKY if authored else Environment.BG_COLOR
		_environment.background_color=Color(["14262f","101f28","0c181f","080f14"][decay])
		_set_formal_daylight_palette(authored)
		_environment.ambient_light_color=Color("e9eded") if authored else (Color("b7c6ca") if PoolMaterials.use_pc_source_finish() else Color("9dbacb"))
		_mood_tween.tween_property(_environment,"ambient_light_energy",(0.15 if expanded else (0.18 if formal else .095)),0.6)
		var sun:=_world_environment.get_node_or_null("ApertureSun") as DirectionalLight3D
		if sun:_mood_tween.tween_property(sun,"light_energy",FORMAL_SUN_ENERGY if authored and daylit and decay<2 else 0.0,0.6)
		# Immediate sky/palette state and eventual tween targets are two distinct
		# valid snapshots. Capture owners retain their linear HDR postprocessing.
		capture_lighting_changed.emit()
		_mood_tween.finished.connect(_on_mood_lighting_finished,CONNECT_ONE_SHOT)
	var alive: Array[WeakRef] = []
	for reference in _room_roots:
		var node := reference.get_ref() as Node3D
		if is_instance_valid(node):
			alive.append(reference)
	_room_roots = alive

func _on_mood_lighting_finished() -> void:
	capture_lighting_changed.emit()

static func create_formal_physical_sky() -> PhysicalSkyMaterial:
	var material:=PhysicalSkyMaterial.new()
	material.resource_name="Formal / native energy-matched atmospheric sky candidate"
	material.turbidity=2.5
	material.ground_color=Color(.2,.21,.21)
	material.energy_multiplier=FORMAL_PHYSICAL_SKY_ENERGY
	return material

func set_formal_physical_sky_enabled(enabled:bool) -> void:
	# Explicit candidate switch. Original-room sky/palette is never replaced.
	if _formal_physical_sky_enabled==enabled:return
	_formal_physical_sky_enabled=enabled
	if _active_formal and _environment:
		_set_formal_daylight_palette(true)
		capture_lighting_changed.emit()

func _set_formal_daylight_palette(formal: bool) -> void:
	# Keep the original scene's atmosphere exactly separate. The authored hall
	# has neutral mineral surfaces under sky and near-neutral direct daylight,
	# not a green ground hemisphere multiplied by yellow sun and cream paint.
	if _environment == null:
		return
	if _original_sky_material==null:
		_original_sky_material=_environment.sky.sky_material as ProceduralSkyMaterial
		_formal_procedural_sky_material=_original_sky_material.duplicate() as ProceduralSkyMaterial
	# Separate material instances prevent a formal candidate from mutating the
	# source-room palette even while captures retain the shared Sky resource.
	if formal:
		_formal_procedural_sky_material.sky_top_color=Color("7faec9")
		_formal_procedural_sky_material.sky_horizon_color=Color("c9dfe9")
		_formal_procedural_sky_material.ground_horizon_color=Color("b4b9b7")
		_formal_procedural_sky_material.ground_bottom_color=Color("6a7473")
		_formal_procedural_sky_material.sky_curve=0.35
		if _formal_physical_sky_enabled:
			if _formal_physical_sky_material==null:_formal_physical_sky_material=create_formal_physical_sky()
			_environment.sky.sky_material=_formal_physical_sky_material
		else:_environment.sky.sky_material=_formal_procedural_sky_material
	else:_environment.sky.sky_material=_original_sky_material
	_environment.tonemap_agx_contrast = 1.05 if formal else 1.15
	_environment.sdfgi_bounce_feedback = 0.65 if formal else 0.48
	_environment.sdfgi_energy = 1.0 if formal else 1.08
	_environment.ssao_intensity = 0.48 if formal else 0.75
	_environment.ssao_power = 1.0 if formal else 1.25
	var sun := _world_environment.get_node_or_null("ApertureSun") as DirectionalLight3D
	if sun:
		sun.light_color = Color("fff9ee") if formal else Color("fff2d8")

func _add_suspended_fixture(parent: Node3D, at: Vector3, mount_y: float, color: Color, energy: float, slot: int, source: Dictionary) -> void:
	var fixture := PoolFixtureFlicker.new()
	fixture.name = "SourceDoubleTube%d" % slot
	fixture.position = at
	parent.add_child(fixture)
	var housing := _materials.get_material("lamp_housing")
	var opal := _make_opal(color)
	var alive := bool(source.get("alive",true))
	if not alive:
		opal.albedo_color = Color("303a3c")
		opal.emission_enabled = false
	_box(fixture, Vector3(0,0.18,0), Vector3(2.85,0.18,0.52), housing)
	for z in [-0.14,0.14]:
		_box(fixture, Vector3(0,0.055,z), Vector3(2.55,0.11,0.095), opal)
	for x in [-1.35,1.35]:
		_box(fixture, Vector3(x,0.09,0), Vector3(0.12,0.24,0.50), housing)
	var cable_height := maxf(0.05, mount_y-at.y-0.28)
	for x in [-1.05,1.05]:
		_box(fixture, Vector3(x,0.28+cable_height*0.5,0), Vector3(0.025,cable_height,0.025), housing)
	if not alive:
		return
	# Godot has no real-time rectangular area light. Two wide shadowed spots
	# distribute each tube's emission rather than pretending one hot dot is LTC.
	for x in [-0.68,0.68]:
		var spot := SpotLight3D.new()
		spot.name = "TubeDiffuse_%s" % str(x)
		spot.position = Vector3(x,-0.04,0)
		spot.rotation_degrees.x = -90.0
		spot.spot_angle = 78.0
		spot.spot_angle_attenuation = 0.25
		spot.spot_range = 27.0
		spot.spot_attenuation = 1.0
		_configure_local_light(spot, color, energy*0.5, 0.45)
		# The two spots approximate diffuse tube flux, not two spherical
		# emitters. Specular must come from the actual elongated opal meshes.
		spot.light_specular = 0.0
		fixture.add_child(spot)
	# The opal tube radiates a weaker upward component. It originates at the
	# same physical fixture, not in a ceiling that has no opening.
	var upward := OmniLight3D.new()
	upward.name = "TubeOpalScatter"
	upward.position = Vector3(0,0.04,0)
	upward.omni_range = 17.5
	upward.omni_attenuation = 1.15
	_configure_local_light(upward, color, energy*0.16, 0.32)
	upward.light_specular = 0.0
	fixture.add_child(upward)
	if bool(source.get("flicker",false)):
		fixture.enable_flicker(float(source.get("flicker_seed",0.0)), float(source.get("flicker_amp",0.0)), opal)

func _add_wall_fixture(parent: Node3D, at: Vector3, color: Color, side: float, energy: float) -> void:
	var fixture := Node3D.new()
	fixture.name = "WallOpal_%s_%s" % [str(at.x),str(side)]
	fixture.position = at
	parent.add_child(fixture)
	_box(fixture, Vector3.ZERO, Vector3(0.26,0.74,0.10), _materials.get_material("lamp_housing"))
	_box(fixture, Vector3(0,0,-side*0.075), Vector3(0.16,0.56,0.08), _make_opal(color))
	var lamp := OmniLight3D.new()
	lamp.name = "WallOpalLight"
	lamp.position.z = -side*0.22
	lamp.omni_range = 15.5
	lamp.omni_attenuation = 1.25
	_configure_local_light(lamp, color, energy, 0.18)
	lamp.light_specular = 0.55
	fixture.add_child(lamp)

func _configure_local_light(light: Light3D, color: Color, energy: float, emitter_size: float) -> void:
	light.light_color = color
	light.light_energy = energy
	light.light_indirect_energy = 0.8
	light.light_size = emitter_size
	light.light_bake_mode = Light3D.BAKE_DYNAMIC
	light.light_volumetric_fog_energy = 0.5
	light.shadow_enabled = true
	# Native defaults are essential at grazing angles on the 4 m arches.
	# The earlier Three-sized biases caused confirmed shadow-map acne:
	# it survived SDFGI-off and vanished only with direct shadows disabled.
	light.shadow_bias = 0.12
	light.shadow_normal_bias = 2.0
	light.shadow_blur = 1.0

func _add_reflection_probe(parent: Node3D, ceiling: float, daylit: bool) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "RoomReflection"
	probe.position = Vector3(0,(ceiling-0.78)*0.5,0)
	probe.size = Vector3(32.0,ceiling+0.78,32.0)
	probe.origin_offset = Vector3(0,2.4-probe.position.y,0)
	probe.max_distance = 48.0
	probe.box_projection = true
	probe.interior = not daylit
	probe.enable_shadows = true
	probe.blend_distance = 1.4
	probe.intensity = 0.8
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	# Architecture is layer 1. Water (layer 2) receives but is not captured.
	probe.cull_mask = 1
	probe.reflection_mask = 1048575
	parent.add_child(probe)

func _make_opal(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Physical opal emitter"
	material.albedo_color = color
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.8
	return material

func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	# Matches the source: tiny luminaire pieces must not project giant
	# self-shadow wedges from their deliberately extended light proxies.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(instance)

static func formal_fixture_power_at_height(emitter_height:float)->float:
	# Author the effective source fixture input, not the source algorithm.
	# Preserve the normal-room on-axis P/(distance^2+1) at flat water y=.32
	# when an aperture sample is lower than the original y=7.3 tube light.
	# This is not whole-field equivalence: horizontal offsets, focusing and
	# visibility remain governed by the unchanged source photon transport.
	var distance:=emitter_height-FORMAL_WATER_REFERENCE_HEIGHT
	var reference:=FORMAL_PHOTON_REFERENCE_HEIGHT-FORMAL_WATER_REFERENCE_HEIGHT
	return 20.0*(distance*distance+1.0)/(reference*reference+1.0)

func add_formal_lights(room:Node3D,layout:Dictionary)->void:
	if room.has_node("NativeLighting"):
		return
	var index:int=preload("res://scripts/world/formal_rooms.gd").COORDS.find(layout.coord)
	var terrace:bool=layout.coord==Vector2i(0,-2)
	var bath:bool=layout.coord==Vector2i(-1,-2)
	var fixtures: Array=[]
	var root:=Node3D.new();root.name="NativeLighting";room.add_child(root)
	var positions:Array[Vector3]=[]
	if terrace:
		# Both effective source positions sit within the 12 x 9 m open-sky
		# rectangle, not under a solid pergola bay or inside the connecting hall.
		positions=[Vector3(-4.6,4.05,-1.8),Vector3(4.6,4.05,1.8)]
	elif bath:
		# The 3.6 m oculus is the sole top-light opening. Keep its sampling pair
		# inside the real aperture and below its glazing at y = 6.025 m.
		positions=[Vector3(-0.8,5.72,0),Vector3(0.8,5.72,0)]
	elif index==0:
		# Keep the two authored effective water emitters, in the same order and
		# at the same positions. Six identical whole-room omnis previously
		# washed out every arch and also consumed six redundant shadow maps.
		positions=[Vector3(-10.3,3.78,-6.6),Vector3(10.3,3.78,-6.6)]
	elif index==1:
		positions=[Vector3(10.5,3.2,0),Vector3(-7.0,3.2,0)]
	else:positions=[Vector3(0,3.2,5.7),Vector3(-5.5,3.1,-1)]
	for i in positions.size():
		var light:=OmniLight3D.new()
		light.name="FormalSourceFill%d" % i
		light.position=positions[i]
		light.omni_range=12.0 if index==0 else 16.0
		light.omni_attenuation=1.15 if index==0 else 1.0
		_configure_local_light(light,Color("e7eeea") if index==0 else Color("fff4e5"),0.60 if index==0 else 2.0,1.15)
		if terrace or bath:
			light.omni_range=12.0 if terrace else 14.0
			_configure_local_light(light,Color("eaf3f3"),0.38 if terrace else 0.50,1.4 if terrace else 1.0)
		light.light_specular=0.0
		light.light_volumetric_fog_energy=0.12
		root.add_child(light)
		fixtures.append({"position":positions[i],"power":formal_fixture_power_at_height(positions[i].y)})
		light.set_meta("source_shadow_priority",true)
	if index==0:
		# A weak diffuse component at the actual roof slot, not more omnidirectional
		# lamps in the room. The directional sun remains the key and the masonry
		# still occludes these broad, shadowed aperture samples.
		for z in [-6.6,0.0,6.6]:
			var aperture:=SpotLight3D.new()
			aperture.name="FormalRoofFill_%s" % str(z)
			aperture.position=Vector3(0.0,4.72,z)
			aperture.rotation_degrees.x=-90.0
			aperture.spot_angle=74.0
			aperture.spot_range=11.0
			aperture.spot_attenuation=1.0
			aperture.spot_angle_attenuation=0.45
			_configure_local_light(aperture,Color("e3eeed"),0.65,1.2)
			aperture.light_specular=0.0
			aperture.light_volumetric_fog_energy=0.08
			root.add_child(aperture)
		# SDFGI's short diffuse feedback underestimates the bright basin's broad
		# return onto the vault. This explicitly authored bounce proxy is aimed
		# upward from the sunlit water footprint; it is not a luminous ceiling or
		# an additional caustic emitter. This is an approximate broad indirect
		# return, not a point source: a single hard shadow creates the disproven
		# roof stripe. Real sunlight/local-light shadows and SSAO remain active.
		var bounce:=SpotLight3D.new()
		bounce.name="FormalSunlitBasinBounce"
		bounce.position=Vector3(1.2,0.48,0.0)
		bounce.rotation_degrees.x=90.0
		bounce.spot_angle=80.0
		bounce.spot_range=10.0
		bounce.spot_attenuation=0.7
		bounce.spot_angle_attenuation=0.25
		_configure_local_light(bounce,Color("ece9dc"),1.0,2.0)
		bounce.shadow_enabled=false
		bounce.set_meta("desktop_authored_shadow",false)
		bounce.light_specular=0.0
		bounce.light_indirect_energy=0.0
		bounce.light_volumetric_fog_energy=0.0
		root.add_child(bounce)
		if _formal_basin_return_distributed_enabled:
			_sync_formal_basin_return_distribution(root)
	elif terrace:
		# One broad downward sky contribution for the courtyard. There is no
		# upward fill: most of this room is truly open to the sky.
		_add_formal_aperture_spot(root,"TerraceOpenSky",Vector3(0,4.05,0),false,0.55,78.0,14.0,2.5,Color("eaf3f3"))
	elif bath:
		_add_formal_aperture_spot(root,"BathOculusSky",Vector3(0,5.72,0),false,0.65,73.0,13.0,1.4,Color("eaf3f3"))
		# A bounded diffuse approximation of the pale, sunlit circular basin's
		# return. It does not emit caustics, specular light or volumetric haze.
		_add_formal_aperture_spot(root,"BathBasinReturn",Vector3(0,0.45,0),true,0.55,84.0,12.0,3.2,Color("e4ece8"))
		# The broad basin return must not cast a second hard upward rail shadow.
		var basin_return := root.get_node("BathBasinReturn") as SpotLight3D
		basin_return.shadow_enabled = false
		basin_return.set_meta("desktop_authored_shadow", false)
	layout.fixtures=fixtures
	var probe:=ReflectionProbe.new();probe.name="FormalReflectionFallback";probe.size=Vector3(27,8,27);probe.position.y=2.0;probe.interior=not bool(layout.get("daylight",false));probe.box_projection=true;probe.cull_mask=1;probe.enable_shadows=true
	probe.ambient_mode=ReflectionProbe.AMBIENT_DISABLED
	probe.intensity=0.85
	probe.update_mode=ReflectionProbe.UPDATE_ONCE
	if terrace or bath:
		probe.size=Vector3(24.0,7.5,23.0) if terrace else Vector3(20.0,8.0,20.0)
		probe.position.y=3.0
		probe.origin_offset=Vector3(0,-0.6,0)
		probe.max_distance=40.0
		probe.blend_distance=1.4
	root.add_child(probe)
	_room_roots.append(weakref(root))

func set_formal_basin_return_distribution_enabled(enabled:bool)->void:
	if _formal_basin_return_distributed_enabled==enabled:return
	_formal_basin_return_distributed_enabled=enabled
	for reference:WeakRef in _room_roots:
		var rig:=reference.get_ref() as Node3D
		if is_instance_valid(rig):_sync_formal_basin_return_distribution(rig)
	capture_lighting_changed.emit()

func _sync_formal_basin_return_distribution(rig:Node3D)->void:
	var center:=rig.get_node_or_null("FormalSunlitBasinBounce") as SpotLight3D
	if center==null:return # Original rooms and the other four formal rooms.
	# Equal-area quadrature of the 12 m long sunlit basin strip. The fixed sun
	# projects the narrow roof slot roughly +1.1 m in X at the water plane; the
	# existing x=1.2 m, y=0.48 m effective return origin is preserved. Three 4 m
	# longitudinal strips are sampled at their centers, not at arbitrary lamps.
	# All three keep real occlusion. The sum of their authored energies is 1.0,
	# not three times the prior return. This redistributes a diffuse approximation;
	# it is not a photon emitter, an exact area-light integrator, or more GI gain.
	center.light_energy=1.0/3.0 if _formal_basin_return_distributed_enabled else 1.0
	# Preserve the old explicit distributed-light diagnostic when requested;
	# the normal single broad-return proxy does not cast a point-source stripe.
	center.shadow_enabled=_formal_basin_return_distributed_enabled
	center.set_meta("desktop_authored_shadow",_formal_basin_return_distributed_enabled)
	for z:float in [-4.0,4.0]:
		var label:="FormalSunlitBasinBounce_%s" % ("North" if z<0 else "South")
		var sample:=rig.get_node_or_null(label) as SpotLight3D
		if not _formal_basin_return_distributed_enabled:
			if sample!=null:
				rig.remove_child(sample)
				sample.free()
			continue
		if sample==null:
			# Duplicate all cone/shadow/attenuation properties of the preserved
			# reference, rather than introducing independently drifting defaults.
			sample=center.duplicate() as SpotLight3D
			sample.name=label
			rig.add_child(sample)
		sample.position=Vector3(1.2,0.48,z)
		sample.light_energy=1.0/3.0

func _add_formal_aperture_spot(parent:Node3D,label:String,at:Vector3,upward:bool,energy:float,angle:float,distance:float,emitter_size:float,color:Color)->void:
	var light:=SpotLight3D.new()
	light.name=label
	light.position=at
	light.rotation_degrees.x=90.0 if upward else -90.0
	light.spot_angle=angle
	light.spot_range=distance
	light.spot_attenuation=0.8 if upward else 1.0
	light.spot_angle_attenuation=0.3
	_configure_local_light(light,color,energy,emitter_size)
	light.light_specular=0.0
	light.light_indirect_energy=0.0 if upward else 0.8
	light.light_volumetric_fog_energy=0.0
	parent.add_child(light)
