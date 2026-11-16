extends RefCounted
## Furniture only: a quiet three-pad waiting bench in the memory vestibule.
## Presentation layers follow the owning stage. No animation/state/collision code.
const M=preload("res://scripts/world/code_seating_geometry.gd")
static func build(stage:Node3D,metal:Material,layer:int)->void:
 var fabric=StandardMaterial3D.new();fabric.resource_name="Memory / muted olive upholstery";fabric.albedo_color=Color("788478");fabric.roughness=.86
 var piping=fabric.duplicate();piping.resource_name="Memory / recessed upholstery welt";piping.albedo_color=Color("626e63")
 var frame=metal.duplicate();frame.resource_name="Memory / local brushed support"
 # Existing bench footprint x[-2.3,-1.5], z[-2.9,-.7] is retained.
 _part(stage,"MemorySeatUnderside",Vector3(-1.9,.377,-1.8),Vector3(.66,.035,2.08),.014,frame,layer)
 for z in [-2.46,-1.8,-1.14]:
  _part(stage,"MemorySeatWelt",Vector3(-1.9,.405,z),Vector3(.690,.018,.656),.009,piping,layer)
  _part(stage,"MemorySeatPad",Vector3(-1.9,.42,z),Vector3(.68,.08,.65),.035,fabric,layer)
  _part(stage,"MemoryBackPad",Vector3(-2.2,.685,z),Vector3(.10,.39,.65),.043,fabric,layer)
 for x in [-2.13,-1.67]:
  for z in [-2.60,-1.0]:_part(stage,"MemoryBenchFoot",Vector3(x,.185,z),Vector3(.045,.37,.045),.009,frame,layer)
 for z in [-2.60,-1.0]:
  _part(stage,"MemoryBackSupport",Vector3(-2.2,.56,z),Vector3(.035,.52,.035),.008,frame,layer)
  _part(stage,"MemorySeatCrossrail",Vector3(-1.9,.345,z),Vector3(.50,.035,.04),.008,frame,layer)
static func _part(stage:Node3D,label:String,p:Vector3,size:Vector3,r:float,material:Material,layer:int)->void:
 var n=M.node(stage,label,M.rounded_box(size,r),p,material);n.layers=layer;n.set_meta("seating_part",true)
