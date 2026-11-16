extends RefCounted
## Only the existing Soffit FAR proxy; near shader and all old14 stay exact.
const SOURCE=preload("res://shaders/source_water_surface.gdshader")
const SOURCE_REFERENCE=preload("res://shaders/reference_wing/reference_water_surface.gdshader")
const FAR=preload("res://shaders/dreamcore/uncanny/soffit_far_source.gdshader")
const FAR_REFERENCE=preload("res://shaders/dreamcore/uncanny/soffit_far_reference.gdshader")
const ORIGINAL_FAR=preload("res://shaders/dreamcore/distant_calm_water.gdshader")
const PUBLISHED=["absorptionOn", "absorptionStrength", "causticGain", "causticsScale", "causticsSpeed", "debugView", "detailCell", "distortionScale", "domain_origin", "foamOn", "foamStrength", "fresnelOn", "fresnelStrength", "microOn", "microOrigin", "microStrength", "mirrorSampler", "normalBoost", "pcNearfieldOn", "pcNearfieldStrength", "poolCaustics", "poolCell", "poolDepth", "poolDetail", "poolSurface", "poolTime", "referenceWaveModes", "referenceWavesActive", "reflectionOn", "reflectionReady", "reflectionSize", "refractionOn", "refractionStrength", "rippleGain", "ripplesOn", "sceneReady", "simulationOn", "sourceFogColor", "sourceFogDensity", "sourceFogEnabled", "sunColor", "sunDirection", "textureMatrix", "waterColor", "waterlineOn", "waveHeight", "windModes", "windOpticsActive"]
const SOURCE_PUBLISHED=["absorptionOn", "absorptionStrength", "causticGain", "causticsScale", "causticsSpeed", "debugView", "detailCell", "distortionScale", "domain_origin", "foamOn", "foamStrength", "fresnelOn", "fresnelStrength", "microOn", "microOrigin", "microStrength", "mirrorSampler", "normalBoost", "pcNearfieldOn", "pcNearfieldStrength", "poolCaustics", "poolCell", "poolDepth", "poolDetail", "poolSurface", "poolTime", "reflectionOn", "reflectionReady", "reflectionSize", "refractionOn", "refractionStrength", "rippleGain", "ripplesOn", "sceneReady", "simulationOn", "sourceFogColor", "sourceFogDensity", "sourceFogEnabled", "sunColor", "sunDirection", "textureMatrix", "waterColor", "waterlineOn", "waveHeight", "windModes", "windOpticsActive"]
const TEXTURE_ALIASES=["mirrorSampler", "poolCaustics", "poolDepth", "poolDetail", "poolSurface"]
const MAX_SAFE_FLOAT32=3.4028233e38
static func finite(value:Variant)->bool:
 match typeof(value):
  TYPE_NIL,TYPE_BOOL,TYPE_INT:return true
  TYPE_FLOAT:return is_finite(value) and absf(value)<=MAX_SAFE_FLOAT32
  TYPE_VECTOR2:return finite(value.x) and finite(value.y)
  TYPE_VECTOR3:return finite(value.x) and finite(value.y) and finite(value.z)
  TYPE_VECTOR4:return finite(value.x) and finite(value.y) and finite(value.z) and finite(value.w)
  TYPE_COLOR:return finite(value.r) and finite(value.g) and finite(value.b) and finite(value.a)
  TYPE_PROJECTION:
   for column in 4:
    if not finite(value[column]):return false
   return true
  TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_VECTOR4_ARRAY:
   for entry in value:
    if not finite(entry):return false
   return true
  TYPE_OBJECT:return value is Texture2D
 return false
static func apply(source:ShaderMaterial,target:ShaderMaterial)->bool:
 if source==null or target==null:return false
 # Preserve unrelated diagnostics/experimental resources, never overwrite them.
 if source.shader not in [SOURCE,SOURCE_REFERENCE] or target.shader not in [ORIGINAL_FAR,FAR,FAR_REFERENCE]:return false
 target.shader=FAR_REFERENCE if source.shader==SOURCE_REFERENCE else FAR
 var keys:Array=PUBLISHED if source.shader==SOURCE_REFERENCE else SOURCE_PUBLISHED
 for key:String in keys:
  var value:Variant=source.get_shader_parameter(key)
  # Null clears an override to the IDENTICAL generated source default.
  # Reject nonfinite/float32-overflow publications without touching source.
  target.set_shader_parameter(key,value if finite(value) else null)
 return true
static func detach(target:ShaderMaterial)->void:
 if target==null:return
 for key:String in TEXTURE_ALIASES:target.set_shader_parameter(key,null)
static func diagnostics(source:ShaderMaterial,target:ShaderMaterial)->Dictionary:
 return {"scene":"soffit_reservoir","near_unchanged":source!=null and source.shader in [SOURCE,SOURCE_REFERENCE],"far_optical":target!=null and target.shader in [FAR,FAR_REFERENCE],"domain_enlarged":false,"solver_mutation":false,"extra_clock":false,"opaque_depth_law":"unchanged_source_view_depth","height_fade_m":8.0}
