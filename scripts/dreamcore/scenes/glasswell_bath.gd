extends RefCounted
## 浅水深井: .20m walkable water over real 100mm structural glass; 40m dry void.
## All floors/frames/shaft geometry are finite, clipped collision-first by G.
const G=preload("res://scripts/dreamcore/scenes/annex_geometry.gd")
const FX=preload("res://scripts/dreamcore/uncanny/glasswell_bath_effects.gd")
const GLASS=preload("res://shaders/dreamcore/uncanny/glasswell_structural_glass.gdshader")
const RECEIVER=preload("res://shaders/dreamcore/uncanny/glasswell_planar_receiver.gdshader")
# DEPLOY43 candidate: project-relative resources; feature flags require cold-reload.
const N42_OPTIONS=preload("res://scripts/dreamcore/uncanny/glasswell_material_options.gd")
const N42_STEEL_ENABLED=N42_OPTIONS.STEEL_PBR_ENABLED
const N42_BOLTS_ENABLED=N42_OPTIONS.SELECTED_COPPER_BOLTS_ENABLED
const N42_STEEL_SHADER=preload("res://shaders/dreamcore/uncanny/glasswell_coated_steel_pbr.gdshader")
const N42_BOLT_SHADER=preload("res://shaders/dreamcore/uncanny/glasswell_bronze_bolt_oxide.gdshader")
const N42_ASSETS="res://assets/dreamcore/glasswell/coated_steel/"
const PREFIX="glasswell_bath_"
const POOL=Rect2(-15,-20,30,40)
const GLASS_ROUGHNESS=.018
const TOP=.12
const BOTTOM=.02
const WELL_BOTTOM=-40.0
static var _architecture:Array=[]
static func definition()->Dictionary:
 return {"id":"glasswell_bath","title":"浅水深井","subtitle":"水只到脚踝，井一直落到灯下。","goal":"在岸边开启深度回声器，沿玻璃边框确认脚下的真实尺度。","bounds":Rect2i(-1,-1,3,3),"retain_full_finite_scene":true,"spawn":Vector3(0,.42,23),"look_at":Vector3(0,-3,0),"exit":Vector3(24,.4,-30),"exit_station":{"presentation":"authored","readout":false,"interaction_offset":Vector3(-.46,1.12,.08),"interaction_pose":Vector3(24,.42,-28.5),"interaction_alternate_pose":Vector3(24.45,.42,-28.55)},"stations":[{"id":"glasswell_sounder","label":"井深回声器","kind":"sounder","position":Vector3(-20,.4,17),"presentation":"authored","readout":false,"latch_completion":true,"interaction_offset":Vector3(0,1.05,.28),"interaction_pose":Vector3(-20,.42,18.65),"interaction_alternate_pose":Vector3(-19.5,.42,18.65),"state_count":2,"target":1,"value_labels":["待机 / 井底暗灯","测深 / 井底指示"],"action":"发送 / 复位测深","clue":"脚下浅水只深二十厘米。按下回声器，机械指针与井底指示灯会标出四十米的干井。"}],"routes":[[Vector3(0,.42,23),Vector3(-20,.42,27),Vector3(-20,.42,18.65),Vector3(-22,.42,18.65),Vector3(-22,.42,-27),Vector3(20,.42,-27),Vector3(20,.42,27),Vector3(0,.42,23)],[Vector3(0,.42,23),Vector3(0,.28,19.7),Vector3(0,.14,18.8),Vector3(0,.14,0),Vector3(0,.14,-18.8),Vector3(0,.28,-19.7),Vector3(0,.42,-23),Vector3(20,.42,-27),Vector3(24,.42,-28.5)]],"station_approaches":[{"id":"glasswell_sounder","position":Vector3(-20,.42,18.65),"target":Vector3(-20,1.45,17.28)},{"id":"departure","position":Vector3(24,.42,-28.5),"target":Vector3(23.54,1.52,-29.92)}],"route_clearance_m":3.,"pool_floor_y":TOP,"water_surface_y":.32,"pool_depth":.20,"glass_thickness_m":.10,"glass_module_m":2.5,"glass_panel_count":192,"well_bottom_y":WELL_BOTTOM,"cameras":[{"name":"entry","position":Vector3(0,2,23),"target":Vector3(0,-3,0),"fov":62.0},{"name":"mid_shallow_water","position":Vector3(0,1.74,8),"target":Vector3(0,-5,-9),"fov":62.0},{"name":"near_green_edge","position":Vector3(-16,2,21),"target":Vector3(-12.7,-1.2,17.1),"fov":62.0},{"name":"aligned_deep_well","position":Vector3(-16,2,21),"target":Vector3(1,-8,-2),"fov":62.0},{"name":"reverse_structure_truth","position":Vector3(16,2,-16),"target":Vector3(-1,-10,4),"fov":62.0},{"name":"exit_lookback","position":Vector3(24,2,-28.5),"target":Vector3(-3,-2,4),"fov":62.0}],"sky_top":Color("66777c"),"sky_horizon":Color("afbaba"),"ambient":Color("d7e0dd"),"ambient_energy":.26,"sun_color":Color("e1e9e6"),"sun_energy":0.,"sun_rotation":Vector3(-40,-105,0),"sky_shader":"res://shaders/dreamcore/annex_day_sky.gdshader","sky_panorama":"res://assets/dreamcore/annex/day-sky.png","exposure":1.0,"fog":.00022}
static func layout(coord:Vector2i)->Dictionary:
 return {"coord":coord,"water_enabled":true,"water_floor_y":TOP,"water_rects":G.water_rects(coord,POOL),"solids":[],"spawn_local":Vector3(0,.42,23)}
static func material_specs()->Dictionary:
 var base=G.pbr_specs();var out={}
 for row in [["tile","tile","e3e2d8",4.8],["wall","ivory","c6ccc7",3.2],["well","ivory","566c70",2.4],["well_pier","ivory","8d9b9a",2.4],["well_floor","ivory","34494c",4.0],["pier","ivory","e4e5dc",3.2],["pier_return","ivory","b4c0ba",3.2],["coping","white","d6d9d0",1.0],["steel","metal","79928c",.25],["bronze","metal","82755c",.25],["bronze_cap","metal","f2d3a2",.25]]:
  var spec:Dictionary=base[row[1]].duplicate(true);spec.tint=row[2];spec.period=row[3];spec.roughness_multiplier=.55 if row[0]=="bronze_cap" else .74 if row[0]=="pier" else .88 if row[0]=="wall" else .96 if str(row[0]).begins_with("well") else 1.;out[PREFIX+row[0]]=spec
 return out
static func materials_ready()->void:
 if G._mats.has(PREFIX+"tile"):return
 for key:String in material_specs():
  var spec:Dictionary=material_specs()[key];var m=StandardMaterial3D.new();m.resource_name=key;m.albedo_texture=load(spec.albedo);m.albedo_color=Color(spec.tint);m.normal_enabled=true;m.normal_texture=load(spec.normal);m.normal_scale=spec.strength;m.roughness_texture=load(spec.orm);m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN;m.roughness=spec.get("roughness_multiplier",1.);m.metallic_texture=m.roughness_texture;m.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE;m.metallic=1.;m.ao_enabled=true;m.ao_texture=m.roughness_texture;m.ao_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED;m.uv1_scale=Vector3.ONE/float(spec.period);m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC;m.set_meta("annex_pbr_spec",spec);G._mats[key]=m
 for row in [["joint","64716c",.94,0.],["seal","182b29",.92,0.],["edge","397e69",.14,.05],["edge_seal","57977f",.10,.04],["laminate","81bfa7",.19,0.],["cove","ffe2b8",.35,0.],["warm","ffe2b8",.35,0.],["cool","d8e5df",.4,0.],["dial","e2dfcd",.8,0.],["ink","213432",.84,0.],["frosted","9eaca5",.5,.0]]:
  var m=StandardMaterial3D.new();m.resource_name=PREFIX+row[0];m.albedo_color=Color(row[1]);m.roughness=row[2];m.metallic=row[3]
  if row[0] in ["cove","warm","cool"]:m.emission_enabled=true;m.emission=Color(row[1]);m.emission_energy_multiplier=4.0 if row[0]=="cove" else 2.0 if row[0]=="warm" else 1.1
  G._mats[PREFIX+row[0]]=m
 var glass=ShaderMaterial.new();glass.shader=GLASS;glass.set_shader_parameter("surface_roughness",GLASS_ROUGHNESS);glass.render_priority=-20;glass.resource_name=PREFIX+"glass";G._mats[PREFIX+"glass"]=glass
 # Own-room receiver replacement only; exact original baseline values/textures.
 for key:String in G._mats.keys():
  if not key.begins_with(PREFIX) or not G._mats[key] is StandardMaterial3D:continue
  var source:StandardMaterial3D=G._mats[key];var receiver=ShaderMaterial.new();receiver.shader=RECEIVER;receiver.resource_name=key;receiver.set_shader_parameter("uv1_scale",source.uv1_scale);receiver.set_shader_parameter("uv1_offset",source.uv1_offset);receiver.set_shader_parameter("normal_strength",1.0)
  var spec:Dictionary=material_specs().get(key,{})
  receiver.set_shader_parameter("base_tint",source.albedo_color);receiver.set_shader_parameter("use_textures",not spec.is_empty());receiver.set_shader_parameter("base_roughness",source.roughness);receiver.set_shader_parameter("base_metallic",source.metallic);receiver.set_shader_parameter("base_specular",source.metallic_specular)
  receiver.set_shader_parameter("emission_tint",source.emission if source.emission_enabled else Color(0,0,0));receiver.set_shader_parameter("emission_energy",source.emission_energy_multiplier if source.emission_enabled else 0.0)
  if not spec.is_empty():
   receiver.set_shader_parameter("albedo_tex",source.albedo_texture);receiver.set_shader_parameter("normal_tex",source.normal_texture);receiver.set_shader_parameter("orm_tex",source.roughness_texture);receiver.set_shader_parameter("normal_strength",float(spec.strength));receiver.set_meta("annex_pbr_spec",spec)
  G._mats[key]=receiver

 _n42_bindings()

static func _n42_image(name:String)->ImageTexture:
 var bytes=FileAccess.get_file_as_bytes(N42_ASSETS+name)
 assert(not bytes.is_empty(),"Deploy43 raw PNG payload missing")
 var image=Image.new();var error=image.load_png_from_buffer(bytes)
 assert(error==OK,"Native42 asset load failed")
 assert(image.get_width()==2048 and image.get_height()==2048 and image.get_format()==Image.FORMAT_RGB8,"Native42 unexpected decoded image")
 # In-memory mips only; no import/cache/file write. Must be verified by native gate.
 assert(image.generate_mipmaps()==OK,"Native42 mip generation failed")
 return ImageTexture.create_from_image(image)
static func _n42_bindings()->void:
 if N42_STEEL_ENABLED:
  var m=ShaderMaterial.new();m.shader=N42_STEEL_SHADER;m.resource_name=PREFIX+"steel"
  m.set_shader_parameter("coat_albedo",_n42_image("green_metal_rust_diff_2k.png"))
  m.set_shader_parameter("coat_arm",_n42_image("green_metal_rust_arm_2k.png"))
  m.set_shader_parameter("coat_normal_gl",_n42_image("green_metal_rust_nor_gl_2k_NATIVE_RGB8.png"))
  m.set_shader_parameter("metres_per_repeat",1.);m.set_shader_parameter("normal_depth",1.)
  G._mats[PREFIX+"steel"]=m
 if N42_BOLTS_ENABLED:
  var source:ShaderMaterial=G._mats[PREFIX+"bronze"];var m=ShaderMaterial.new();m.shader=N42_BOLT_SHADER;m.resource_name=PREFIX+"bronze_bolt_oxide"
  for key in ["albedo_tex","normal_tex","orm_tex","base_tint","use_textures","uv1_scale","uv1_offset","normal_strength","base_roughness","base_metallic","base_specular","emission_tint","emission_energy"]:m.set_shader_parameter(key,source.get_shader_parameter(key))
  m.set_shader_parameter("oxide_tint",Color(.28,.145,.065,1.))
  G._mats[PREFIX+"bronze_bolt_oxide"]=m
static func _n42_rod_key(p:Vector3,q:Vector3,r:float,key:String,segments:int)->String:
 if not N42_BOLTS_ENABLED or key!="bronze" or segments!=6 or absf(r-.018)>.000001:return key
 if absf(p.y-.4)>.000001 or absf(q.y-.413)>.000001 or p.x!=q.x or p.z!=q.z:return key
 for center in [Vector3(-15.12,.4,20.0),Vector3(-15.,.4,20.12),Vector3(-14.5,.4,20.12),Vector3(-14.,.4,20.12)]:
  if p.distance_squared_to(center)<.0000000001:return "bronze_bolt_oxide"
 return key

static func _box(a:Array,p:Vector3,s:Vector3,key:String,collision:bool=true)->void:a.append(G.box(p,s,PREFIX+key,collision))
static func _rod(a:Array,p:Vector3,q:Vector3,r:float,key:String,segments:int=12)->void:
 var m=CylinderMesh.new();m.top_radius=r;m.bottom_radius=r;m.height=p.distance_to(q);m.radial_segments=segments;m.rings=0
 var e=G.item(m,(p+q)*.5,PREFIX+_n42_rod_key(p,q,r,key,segments),false);e.transform.basis=Basis(Quaternion(Vector3.UP,(q-p).normalized()));a.append(e)
static func _profile_triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,normal:Vector3)->void:
 var p=[a,b,c]
 if (b-a).cross(c-a).dot(normal)>0.:p=[a,c,b]
 for v:Vector3 in p:st.set_normal(normal.normalized());st.set_uv(Vector2.ZERO);st.add_vertex(v)
static func _profile_run(a:Array,p:Vector3,profile:Array,length:float,key:String,basis:Basis=Basis.IDENTITY)->void:
 # Closed convex folded/stone profile, not bevel shading painted onto a cube.
 # Profile is counterclockwise XY, extruded alongZ; actual surfaces collide.
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);var half=length*.5
 for i in profile.size():
  var j=(i+1)%profile.size();var u:Vector2=profile[i];var v:Vector2=profile[j];var n=Vector3(v.y-u.y,u.x-v.x,0).normalized();var p0=Vector3(u.x,u.y,-half);var p1=Vector3(v.x,v.y,-half);var p2=Vector3(v.x,v.y,half);var p3=Vector3(u.x,u.y,half)
  _profile_triangle(st,p0,p1,p2,n);_profile_triangle(st,p0,p2,p3,n)
 for side in [-1.,1.]:
  var v0:Vector2=profile[0]
  for i in range(1,profile.size()-1):
   var v1:Vector2=profile[i];var v2:Vector2=profile[i+1];_profile_triangle(st,Vector3(v0.x,v0.y,side*half),Vector3(v1.x,v1.y,side*half),Vector3(v2.x,v2.y,side*half),Vector3(0,0,side))
 var item=G.item(st.commit(),p,PREFIX+key,true);item.transform.basis=basis;a.append(item)
static func _pier_facing(a:Array,p:Vector3,basis:Basis)->void:
 _profile_run(a,p,[Vector2(-.675,0),Vector2(.675,0),Vector2(.675,.21),Vector2(.585,.30),Vector2(-.585,.30),Vector2(-.675,.21)],1.984,"pier",basis)
static func _formed_cap(a:Array,p:Vector3,length:float,across_z:bool=false)->void:
 # Maximum top remains EXACTLY.40; footprint and .388 bearing unchanged.
 # Real12mm top chamfers face UP into hall/cove light, not hidden undercuts.
 _profile_run(a,p,[Vector2(-.10,.388),Vector2(.10,.388),Vector2(.088,.40),Vector2(-.088,.40)],length,"bronze_cap",Basis(Vector3.UP,PI*.5) if across_z else Basis.IDENTITY)
static func _hall(a:Array)->void:
 # Actual four-piece annular deck: there is no opaque/invisible slab across well.
 for r in [Rect2(-32,-40,17,80),Rect2(15,-40,17,80),Rect2(-15,-40,30,20),Rect2(-15,20,30,20)]:_box(a,Vector3(r.get_center().x,-.19,r.get_center().y),Vector3(r.size.x,.82,r.size.y),"tile")
 # The top floor OWNS only the area outside the coping+drain outer rectangle.
 # The continuous lower structural annulus ends atY.22, below the real trough.
 for r in [Rect2(-32,-40,16.62,80),Rect2(15.38,-40,16.62,80),Rect2(-15.38,-40,30.76,19.62),Rect2(-15.38,20.38,30.76,19.62)]:_box(a,Vector3(r.get_center().x,.31,r.get_center().y),Vector3(r.size.x,.18,r.size.y),"tile")
 # 64x80x32m closed hall. Actual mineral backing and 40mm facing panels
 # have 16mm recessed joints; not black sticks painted across a flat wall.
 for x in [-32.4,32.4]:_box(a,Vector3(x,16,0),Vector3(.8,32,80.8),"joint")
 for z in [-40.4,40.4]:_box(a,Vector3(0,16,z),Vector3(64,.0+32,.8),"joint")
 _box(a,Vector3(0,32.35,0),Vector3(64.8,.7,80.8),"wall",false)
 for side in [-1.,1.]:
  for iy in 16:
   for iz in 40:_box(a,Vector3(side*31.98,1.+iy*2.,-39.+iz*2.),Vector3(.04,1.984,1.984),"wall")
   for ix in 32:_box(a,Vector3(-31.+ix*2.,1.+iy*2.,side*39.98),Vector3(1.984,1.984,.04),"wall")
  for z in range(-32,33,8):
   _box(a,Vector3(side*31.5,16,z),Vector3(1.,32,1.35),"pier_return")
   for iy in 16:_pier_facing(a,Vector3(side*31.0,1.+iy*2.,z),Basis(Vector3.UP,-side*PI*.5)*Basis(Vector3.RIGHT,PI*.5))
   _box(a,Vector3(side*30.66,.57,z),Vector3(.018,.085,1.2),"cove",false)
  for x in range(-24,25,8):
   _box(a,Vector3(x,16,side*39.5),Vector3(1.35,32,1.),"pier_return")
   for iy in 16:_pier_facing(a,Vector3(x,1.+iy*2.,side*39.0),Basis(Vector3.UP,PI if side>0 else 0.)*Basis(Vector3.RIGHT,PI*.5))
   _box(a,Vector3(x,.57,side*38.66),Vector3(1.2,.085,.018),"cove",false)
 # Continuous low wall cove behind pilasters; warm mounting is real geometry,
 # with a metal channel and opal strip. No unsupported invisible spotlight.
 for side in [-1.,1.]:
  _box(a,Vector3(side*31.955,.55,0),Vector3(.045,.12,79.0),"steel",false)
  _box(a,Vector3(side*31.925,.555,0),Vector3(.018,.085,78.8),"cove",false)
  _box(a,Vector3(0,.55,side*39.955),Vector3(63.0,.12,.045),"steel",false)
  _box(a,Vector3(0,.555,side*39.925),Vector3(62.8,.085,.018),"cove",false)
 # Far human-scale recessed maintenance bays: closed inset panels, not fake routes.
 for x in [-20.,0.,20.]:
  _box(a,Vector3(x,1.6,-39.96),Vector3(2.7,2.4,.06),"seal",false)
  for dx in [-1.4,1.4]:_box(a,Vector3(x+dx,1.6,-39.89),Vector3(.065,2.5,.1),"steel",false)
  _box(a,Vector3(x,2.87,-39.88),Vector3(2.85,.07,.1),"steel",false)
 # Two real low-mounted, guarded wall-wash fixtures replace two far hall
 # omni practicals. Their lenses sit above the housings and aim up the relief.
 for x in [-16.,16.]:
  _box(a,Vector3(x,.41,-38.4),Vector3(.70,.02,.52),"steel")
  for dx in [-.23,.23]:_box(a,Vector3(x+dx,.445,-38.4),Vector3(.08,.05,.32),"bronze")
  _box(a,Vector3(x,.50,-38.4),Vector3(.62,.06,.46),"steel")
  _box(a,Vector3(x,.536,-38.4),Vector3(.48,.012,.32),"warm",false)
  for dx in [-.29,.29]:_box(a,Vector3(x+dx,.55,-38.4),Vector3(.025,.12,.46),"bronze",false)
 # Four shallow ceiling-cornice housings touch the real ceiling undersideY32.
 # BackplateY31.96..32; framed opening1.10m; lensY31.86..31.88.
 # The lamp originY31.84 is BELOW its lens, never behind opaque ceiling.
 for x in [-16.,16.]:
  for z in [-20.,20.]:
   _box(a,Vector3(x,31.98,z),Vector3(1.4,.04,1.4),"steel",false)
   for side in [-1.,1.]:
    _box(a,Vector3(x+side*.625,31.89,z),Vector3(.15,.14,1.4),"bronze",false)
    _box(a,Vector3(x,31.89,z+side*.625),Vector3(1.10,.14,.15),"bronze",false)
   _box(a,Vector3(x,31.92,z),Vector3(1.10,.08,1.10),"steel",false)
   _box(a,Vector3(x,31.87,z),Vector3(1.02,.02,1.02),"warm",false)
static func _well(a:Array)->void:
 # Real dry enclosure: four thick walls and a finite bottom at -40m.
 for x in [-15.5,15.5]:_box(a,Vector3(x,-19.94,0),Vector3(1.,40.12,42.),"well")
 for z in [-20.5,20.5]:_box(a,Vector3(0,-19.94,z),Vector3(30,40.12,1.),"well")
 _box(a,Vector3(0,-40.45,0),Vector3(32,.9,42),"well_floor")
 # Deep vertical pier returns and ledges ground the shaft rather than faking infinity.
 for side in [-1.,1.]:
  for z in [-10.,0.,10.]:_box(a,Vector3(side*14.45,-20.985,z),Vector3(1.10,38.03,1.50),"well_pier")
  _box(a,Vector3(side*14.4,-1.72,0),Vector3(1.2,.5,40),"well_pier")
  for x in [-7.5,7.5]:_box(a,Vector3(x,-20.985,side*19.45),Vector3(1.60,38.03,1.10),"well_pier")
  # End capitals butt between the X capital runs; real bearings touch the
  # end girder underside without overlapping coplanar ledge tops.
  _box(a,Vector3(0,-1.72,side*19.4),Vector3(27.6,.5,1.2),"well_pier")
  for x in [-7.5,7.5]:_box(a,Vector3(x,-1.44,side*19.87),Vector3(.8,.06,.26),"bronze",false)
  # Legible cast-panel courses extend down the true shaft, not a depth poster.
  for y in range(-2,-40,-2):
   _box(a,Vector3(side*14.992,y,0),Vector3(.016,.018,39.85),"seal",false)
   _box(a,Vector3(0,y,side*19.992),Vector3(29.85,.018,.016),"seal",false)
  for z in range(-20,21,2):_box(a,Vector3(side*14.992,-20,z),Vector3(.016,39.7,.025),"seal",false)
  for x in range(-15,16,2):_box(a,Vector3(x,-20,side*19.992),Vector3(.025,39.7,.016),"seal",false)
  # Two sparse, visibly mounted inspection strips illuminate the DRY wall.
  # Two retained inspection lamps; the four new ceiling spots never reach the bottom.
  _box(a,Vector3(side*14.95,-5.4,side*8),Vector3(.10,.20,.84),"steel",false)
  _box(a,Vector3(side*14.89,-5.4,side*8),Vector3(.018,.075,.65),"cool",false)
 # Real I-section cross-girders every10m. Each terminates on concrete wall bearing.
 for z in [-20.,-10.,0.,10.,20.]:
  _box(a,Vector3(0,-.83,z),Vector3(30,.98,.095),"steel",false)
  for y in [-.295,-1.365]:_box(a,Vector3(0,y,z),Vector3(30,.09,.40),"steel",false)
  for side in [-1.,1.]:
   _box(a,Vector3(side*14.62,-1.44,z),Vector3(.7,.06,.65),"bronze",false)
   for dz in [-.20,.20]:_rod(a,Vector3(side*14.62,-1.47,z+dz),Vector3(side*14.62,-1.37,z+dz),.035,"steel",6)
 # Bottom is almost empty; only a small maintenance door and lamp at real depth.
 _box(a,Vector3(0,-38.85,-19.965),Vector3(1.15,2.25,.07),"seal",false)
 for x in [-.63,.63]:_box(a,Vector3(x,-38.83,-19.90),Vector3(.07,2.35,.09),"steel",false)
 _box(a,Vector3(0,-37.60,-19.90),Vector3(1.35,.08,.10),"steel",false)
 _box(a,Vector3(0,-37.25,-19.86),Vector3(.7,.09,.08),"warm",false)
 _box(a,Vector3(-14.86,-38.4,7),Vector3(.08,.11,.65),"warm",false)
static func _glazing(a:Array)->void:
 # 12x16 independent thick panes; each open-looking area has its own visual solid
 # and EXACT identical collision mesh. 65mm joint bands are fully framed/sealed.
 for iz in 16:
  for ix in 12:
   var x=-13.75+ix*2.5;var z=-18.75+iz*2.5
   _box(a,Vector3(x,.07,z),Vector3(2.435,.10,2.435),"glass")
   # The100mm protected laminated edges carry a thin visible green edge seal.
   # This side-only coating does not cover the clear top face or fake a floor.
   for side in [-1.,1.]:
    _box(a,Vector3(x+side*1.2177,.07,z),Vector3(.003,.096,2.435),"edge_seal",false)
    _box(a,Vector3(x,.07,z+side*1.2177),Vector3(2.435,.096,.003),"edge_seal",false)
   # Three visible lamination strata remain readable in near-field edge views.
   for side in [-1.,1.]:
    for y in [.031,.060,.089]:
     _box(a,Vector3(x+side*1.214,y,z),Vector3(.007,.008,2.426),"edge",false)
     _box(a,Vector3(x,y,z+side*1.214),Vector3(2.426,.008,.007),"edge",false)
 # X runs own every crossing. Z members are between-run pieces, not
 # coplanar/interpenetrating crosses or epsilon-offset covers. Floor classification
 # remains the exact65mm grid; rails, stems and gasket corners are butt-jointed.
 for ix in 13:
  var x=-15.+ix*2.5
  _box(a,Vector3(x,.103,0),Vector3(.065,.034,40.065),"bronze")
  _box(a,Vector3(x,-.142,0),Vector3(.08,.30,40.08),"steel",false)
  _box(a,Vector3(x,.047,0),Vector3(.022,.078,40.022),"steel",false)
  for side in [-1.,1.]:_box(a,Vector3(x+side*.037,.014,0),Vector3(.010,.012,40.084),"seal",false)
 for iz in 17:
  var z=-20.+iz*2.5
  for ix in 12:
   var x=-13.75+ix*2.5
   _box(a,Vector3(x,.103,z),Vector3(2.435,.034,.065),"bronze")
   _box(a,Vector3(x,-.142,z),Vector3(2.420,.30,.08),"steel",false)
   _box(a,Vector3(x,.047,z),Vector3(2.478,.078,.022),"steel",false)
   for side in [-1.,1.]:_box(a,Vector3(x,.014,z+side*.037),Vector3(2.416,.012,.010),"seal",false)
 # Flush small compression-cap screws; no unconnected floating cover strips.
 for iz in 17:
  for ix in 13:_rod(a,Vector3(-14.976+ix*2.5,.1202,-19.976+iz*2.5),Vector3(-14.976+ix*2.5,.125,-19.976+iz*2.5),.008,"steel",6)
 # Perimeter anchor heads sit ABOVE coping top.4, never buried inside it.
 for side in [-1.,1.]:
  for i in 81:_rod(a,Vector3(side*15.12,.4,-20+i*.5),Vector3(side*15.12,.413,-20+i*.5),.018,"bronze",6)
  for i in 61:_rod(a,Vector3(-15+i*.5,.4,side*20.12),Vector3(-15+i*.5,.413,side*20.12),.018,"bronze",6)
static func _drain_piece(a:Array,p:Vector3,u:float,y:float,v:float,across:float,height:float,length:float,along_z:bool,key:String)->void:
 var offset=Vector3(u,y,v) if along_z else Vector3(v,y,u)
 var size=Vector3(across,height,length) if along_z else Vector3(length,height,across)
 _box(a,p+offset,size,key)
static func _drain_strip(a:Array,p:Vector3,length:float,along_z:bool)->void:
 # Closed180mm trough: real70mm clear-top recess,16mm pan atY.314-.33,
 # continuous side/end supports down to the lower annulusY.22. The pan is
 # above pool waterY.32; the dry drain never becomes a false source-water cell.
 # Flush18mm grating has individual real collisions, never a hidden cover.
 # Side runs own corners; end pieces butt between them without coplanar overlap.
 _drain_piece(a,p,0,.322,0,.18,.016,length,along_z,"seal")
 for side in [-1.,1.]:
  _drain_piece(a,p,side*.082,.301,0,.016,.162,length,along_z,"steel")
  _drain_piece(a,p,side*.082,.391,0,.016,.018,length,along_z,"bronze")
  _drain_piece(a,p,0,.301,side*(length*.5-.008),.148,.162,.016,along_z,"steel")
  _drain_piece(a,p,0,.391,side*(length*.5-.008),.148,.018,.016,along_z,"bronze")
 var clear_length=length-.032;var count=ceili(clear_length/.08);var pitch=clear_length/float(count)
 for i in count:_drain_piece(a,p,0,.391,-clear_length*.5+(i+.5)*pitch,.148,.018,.018,along_z,"bronze")
static func _banks(a:Array)->void:
 # Coping owns its footprint, with no intact floor hiding below its top face.
 # X coping/drain runs own the rectangle corners; Z runs butt against those.
 for side in [-1.,1.]:
  _box(a,Vector3(side*15.10,.254,0),Vector3(.20,.268,40.4),"coping")
  _formed_cap(a,Vector3(side*15.10,0,0),40.4)
  _drain_strip(a,Vector3(side*15.29,0,0),40.76,true)
  for x in [-8.3,8.3]:
   _box(a,Vector3(x,.254,side*20.10),Vector3(13.4,.268,.20),"coping")
   _formed_cap(a,Vector3(x,0,side*20.10),13.4,true)
  # Same exact14cm entry risers: dry landing.40 -> submerged step.26 -> glass.12.
  _box(a,Vector3(0,.31,side*20.10),Vector3(3.2,.18,.20),"tile")
  _box(a,Vector3(0,.19,side*19.703),Vector3(3.2,.14,.594),"coping")
  # Actual6mm vertical nosing owns the removed front slice. Combined step
  # bounds remain EXACTLYZ[19.4,20]/[-20,-19.4],Y[.12,.26].
  _box(a,Vector3(0,.19,side*19.403),Vector3(3.2,.14,.006),"bronze")
  _drain_strip(a,Vector3(0,0,side*20.29),30.40,false)
static func _dial_digit(a:Array,p:Vector3,height:float,digit:int)->void:
 var width=height*.5;var stroke=height*.085
 var segments={"a":[Vector2(0,.5),Vector2(.86,0)],"b":[Vector2(.5,.25),Vector2(0,.42)],"c":[Vector2(.5,-.25),Vector2(0,.42)],"d":[Vector2(0,-.5),Vector2(.86,0)],"e":[Vector2(-.5,-.25),Vector2(0,.42)],"f":[Vector2(-.5,.25),Vector2(0,.42)],"g":[Vector2(0,0),Vector2(.86,0)]}
 var code:String={0:"abcdef",2:"abdeg",4:"bcfg"}.get(digit,"")
 for i in code.length():
  var key=code.substr(i,1);var item:Array=segments[key];var q:Vector2=item[0];var size:Vector2=item[1];_box(a,p+Vector3(q.x*width,q.y*height,0),Vector3(maxf(stroke,size.x*width),maxf(stroke,size.y*height),.003),"ink",false)
static func _device_and_exit(a:Array)->void:
 # Enclosed mechanical sounder: narrow stem, readable circular dial, guarded key.
 _box(a,Vector3(-20,.45,17),Vector3(.75,.10,.65),"steel")
 _box(a,Vector3(-20,.91,17),Vector3(.24,.82,.24),"bronze")
 _box(a,Vector3(-20,1.45,17),Vector3(.62,.50,.46),"steel")
 _rod(a,Vector3(-20,1.48,17.236),Vector3(-20,1.48,17.250),.205,"dial",64)
 for i in 9:
  var t=deg_to_rad(-135.+i*270./8.);var p=Vector3(-20+sin(t)*.177,1.48+cos(t)*.177,17.258)
  _rod(a,p,p+Vector3(0,0,.006),.008 if i%2 else .011,"ink",8)
 # Geometric engraved0/20/40 calibration; the visual pointer conveys depth
 # without requiring sound, transient UI text, a timer or reading tiny captions.
 _dial_digit(a,Vector3(-20.137,1.35,17.26),.036,0)
 _dial_digit(a,Vector3(-20.017,1.647,17.26),.036,2);_dial_digit(a,Vector3(-19.988,1.647,17.26),.036,0)
 _dial_digit(a,Vector3(-19.879,1.35,17.26),.036,4);_dial_digit(a,Vector3(-19.850,1.35,17.26),.036,0)
 _box(a,Vector3(-19.78,1.26,17.238),Vector3(.08,.07,.032),"bronze",false)
 # Dedicated cable descends through a sealed shore gland, with no trip wire.
 _rod(a,Vector3(-20,.57,16.9),Vector3(-20,.42,16.9),.025,"seal")
 # A sealed service conduit runs under the dry shore, emerges inside the
 # real well and descends to the actual indicator; clamps show its fixed scale.
 _rod(a,Vector3(-14.88,-.34,16.9),Vector3(-14.88,-38.4,16.9),.024,"steel",16)
 _rod(a,Vector3(-14.88,-38.4,16.9),Vector3(-14.88,-38.4,7.32),.024,"steel",16)
 for y in [-2.,-6.,-10.,-14.,-18.,-22.,-26.,-30.,-34.,-38.]:
  _box(a,Vector3(-14.95,y,16.9),Vector3(.1,.09,.12),"bronze",false)
 # Far-bank frosted acoustic vestibule: real1.8m opening, return walls, human handle.
 for x in [22.95,25.05]:_box(a,Vector3(x,1.7,-31.5),Vector3(.30,2.6,3.8),"frosted")
 _box(a,Vector3(24,3.10,-31.5),Vector3(2.4,.20,3.8),"frosted")
 _box(a,Vector3(24,1.6,-33.3),Vector3(1.8,2.4,.08),"frosted")
 # The authored departure surface is the near complete door leaf, not a console.
 _box(a,Vector3(24,1.6,-30.08),Vector3(1.8,2.4,.08),"frosted")
 for x in [23.06,24.94]:_box(a,Vector3(x,1.62,-30),Vector3(.07,2.48,.12),"steel",false)
 _box(a,Vector3(24,2.87,-30),Vector3(1.95,.07,.12),"steel",false)
 for y in [.8,2.4]:_box(a,Vector3(24.86,y,-29.99),Vector3(.10,.17,.05),"bronze",false)
 _rod(a,Vector3(23.54,1.40,-29.92),Vector3(23.54,1.64,-29.92),.018,"bronze",20)
 for y in [1.4,1.64]:_rod(a,Vector3(23.54,y,-29.92),Vector3(23.54,y,-30.042),.012,"bronze",16)
static func geometry()->Array:
 if not _architecture.is_empty():return _architecture
 materials_ready();var a:Array=[];_hall(a);_well(a);_glazing(a);_banks(a);_device_and_exit(a);_architecture=a;return a
static func _mark_glass(room:Node3D)->void:
 for n in room.get_children():
  if n is MeshInstance3D and n.material_override==G._mats[PREFIX+"glass"]:n.set_meta("source_transmissive",true);n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;n.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
static func build_shell(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 # Pane collision uses the exact visual BoxMesh bounds, not a separate floor.
 # Analytic boxes avoid rare coplanar triangle-edge ray misses at glazing seams.
 # These SAME actual shapes feed the unchanged source terrain collector directly.
 var opaque:Array=[];var panes:Array=[];var c:Vector2i=data.coord;var offset=Vector3(c.x*32.,0,c.y*32.)
 var body=StaticBody3D.new();body.name="StructuralGlassExactPanelCollision";body.set_meta("dream_observation_transparent",true);room.add_child(body)
 for e:Dictionary in geometry():
  if e.material!=PREFIX+"glass":opaque.append(e);continue
  var visual:Dictionary=e.duplicate();visual.collision=false;panes.append(visual)
  var box:AABB=e.transform*e.mesh.get_aabb()
  var low=Vector3(maxf(box.position.x,offset.x-16),box.position.y,maxf(box.position.z,offset.z-16));var high=Vector3(minf(box.end.x,offset.x+16),box.end.y,minf(box.end.z,offset.z+16))
  if high.x<=low.x or high.z<=low.z:continue
  var shape=BoxShape3D.new();shape.size=high-low;var cs=CollisionShape3D.new();cs.name="ExactVisualPane";cs.shape=shape;cs.position=(low+high)*.5-offset;body.add_child(cs);data.solids.append(AABB(low-offset,high-low))
 G.build(room,data,opaque,true);G.build(room,data,panes,false);_mark_glass(room)
static func build_detail(room:Node3D,data:Dictionary,_materials:RefCounted)->void:
 var detail:Array=[]
 for e:Dictionary in geometry():
  if e.material!=PREFIX+"glass":detail.append(e)
 G.build(room,data,detail,false)
 for p in [Vector3(-30.65,.74,24),Vector3(30.65,.74,24)]:G.lamp(room,data,p,Color("f2e5cf"),1.10,33.)
 for x in [-16.,16.]:_wall_wash(room,data,Vector3(x,.59,-38.4),Vector3(x,4,-38.70))
 for side in [-1.,1.]:G.lamp(room,data,Vector3(side*14.65,-5.35,side*8),Color("c7dad4"),.65,32.)
 G.lamp(room,data,Vector3(0,-37.15,-19.45),Color("ffe2b8"),.25,9.)
 for x in [-16.,16.]:
  for z in [-20.,20.]:_ceiling_wash(room,data,Vector3(x,31.84,z))
static func _wall_wash(room:Node3D,data:Dictionary,point:Vector3,target:Vector3)->void:
 var c:Vector2i=data.coord
 if Vector2i(floori((point.x+16.)/32.),floori((point.z+16.)/32.))!=c:return
 var light=SpotLight3D.new();light.name="GlasswellBoundedWallWash";light.position=point-Vector3(c.x*32.,0,c.y*32.);light.basis=Basis.looking_at(target-point,Vector3.FORWARD)
 light.light_color=Color("f2e5cf");light.light_energy=12.;light.light_specular=.25;light.spot_range=36.;light.spot_angle=14.;light.spot_angle_attenuation=1.5;light.spot_attenuation=1.;light.shadow_enabled=true;light.shadow_bias=.025;light.shadow_normal_bias=.20;room.add_child(light)
static func _ceiling_wash(room:Node3D,data:Dictionary,point:Vector3)->void:
 var c:Vector2i=data.coord
 if Vector2i(floori((point.x+16.)/32.),floori((point.z+16.)/32.))!=c:return
 var light=SpotLight3D.new();light.name="GlasswellCeilingCorniceSpot";light.position=point-Vector3(c.x*32.,0,c.y*32.);light.rotation_degrees=Vector3(-90,0,0)
 light.light_color=Color("f2e5cf");light.light_energy=60.;light.light_specular=.25;light.spot_range=44.;light.spot_angle=38.;light.spot_angle_attenuation=1.5;light.spot_attenuation=1.;light.shadow_enabled=true;light.shadow_bias=.025;light.shadow_normal_bias=.20;room.add_child(light)
static func build_horizon(root:Node3D,_materials:RefCounted)->void:
 materials_ready();var actor=FX.new();actor.name="GlasswellDepthSounder";root.add_child(actor)
