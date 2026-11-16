extends RefCounted
## Explicit room-local optical adapter; no solver/collision/state ownership.
## Integrator applies ONLY to glasswell_bath's own ShaderMaterials after source bind.
const ORIGINAL=preload("res://shaders/dreamcore/uncanny/glasswell_water_source.gdshader")
const REFERENCE=preload("res://shaders/dreamcore/uncanny/glasswell_water_reference.gdshader")
const GEOMETRY_UNIFORMS={"glasswell_origin_xz":Vector2.ZERO,"glasswell_pool_rect":Vector4(-15,-20,15,20),"glasswell_floor_y":.12,"glasswell_glass_bottom_y":.02,"glasswell_module":2.5,"glasswell_cap_width":.065,"glasswell_step_a":Vector4(-1.6,19.4,1.6,20),"glasswell_step_b":Vector4(-1.6,-20,1.6,-19.4),"glasswell_step_top_y":.26}
static func apply(material:ShaderMaterial,reference_requested:bool,reference_waves:RefCounted=null)->void:
 if material==null:return
 var desired:Shader=REFERENCE if reference_requested else ORIGINAL
 if material.shader!=desired:material.shader=desired
 for key:String in GEOMETRY_UNIFORMS:material.set_shader_parameter(key,GEOMETRY_UNIFORMS[key])
 if reference_requested and reference_waves!=null:reference_waves.apply_to(material)
static func exact_floor_y(point:Vector2)->float:
 return .26 if absf(point.x)<1.6 and absf(point.y)>19.4 and absf(point.y)<=20. else .12
static func water_column(point:Vector2,surface_y:float=.32)->float:
 if not Rect2(-15,-20,30,40).has_point(point):return 0.
 return maxf(0.,surface_y-exact_floor_y(point))
static func diagnostics(material:ShaderMaterial)->Dictionary:
 return {"scene":"glasswell_bath","local_shader":material!=null and material.shader in [ORIGINAL,REFERENCE],"shared_shader_replaced":false,"water_surface_y":.32,"glass_top_y":.12,"glass_bottom_y":.02,"dry_well_bottom_y":-40.,"finite_glass_absorption_m":.10,"solver_mutation":false,"collider_mutation":false}
