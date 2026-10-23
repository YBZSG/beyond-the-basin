class_name SourceCaptureEnvironment
extends RefCounted
## Keep capture illumination current without baking the main view's postprocess
## twice. Sky/resources are shared read-only by capture cameras, not recopied per
## frame. The owner remains the only writer of sky/material palette resources.
const LIVE_PROPERTIES := [
 "sky", "background_mode", "background_color", "background_energy_multiplier", "background_intensity",
 "ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution",
 "fog_enabled", "fog_density", "fog_light_color",
 "volumetric_fog_enabled", "volumetric_fog_density", "volumetric_fog_albedo",
 "sdfgi_bounce_feedback", "sdfgi_energy", "ssao_intensity", "ssao_power",
]

static func create(source: Environment) -> Environment:
 var capture:=source.duplicate(false) as Environment
 _enforce_linear(capture)
 return capture

static func _is_lighting(name: String) -> bool:
 # These disabled capture-only postprocessing groups cannot affect illumination.
 return not (name.begins_with("pathtracing_") or name.begins_with("tonemap_") or name.begins_with("glow_") or name.begins_with("adjustment_") or name.begins_with("resource_") or name=="script")

static func synchronize(source: Environment, capture: Environment) -> bool:
 if source==null or capture==null: return false
 var changed:=false
 for property in source.get_property_list():
  var name:=str(property.name)
  if not int(property.usage)&PROPERTY_USAGE_STORAGE or not _is_lighting(name): continue
  var value:Variant=source.get(name)
  if capture.get(name)!=value:
   capture.set(name,value)
   changed=true
 _enforce_linear(capture)
 return changed

static func synchronize_live(source: Environment, capture: Environment) -> bool:
 if source==null or capture==null: return false
 var changed:=false
 # PoolLighting's bounded mood/energy tweens and room palette switches only.
 # No duplicate(), property-list allocation or write for unchanged values.
 for name in LIVE_PROPERTIES:
  var value:Variant=source.get(name)
  if capture.get(name)!=value:
   capture.set(name,value)
   changed=true
 return changed

static func _enforce_linear(capture: Environment) -> void:
 if capture.has_method("set_pathtracing_enabled"): capture.set("pathtracing_enabled",false)
 if capture.tonemap_mode!=Environment.TONE_MAPPER_LINEAR: capture.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 if capture.tonemap_exposure!=1.0: capture.tonemap_exposure=1.0
 if capture.glow_enabled: capture.glow_enabled=false
 if capture.adjustment_enabled: capture.adjustment_enabled=false
