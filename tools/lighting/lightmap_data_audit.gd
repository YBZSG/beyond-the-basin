extends RefCounted
## Offline/native-lab validation only. Reads the original HDR samples, not a
## GPU screenshot or a compressed texture that may already have hidden NaNs.
## Never sanitizes, clamps or rewrites invalid baked radiance.

static func inspect_image(source:Image,slices:int=1)->Dictionary:
 if source==null or source.is_empty():return {"pass":false,"error":"Empty HDR image"}
 var image:=source.duplicate() as Image
 # CPU conversion is exact for half-float input, including non-finite values.
 image.convert(Image.FORMAT_RGBF)
 var raw:=image.get_data()
 var count:=raw.size()/4
 var components_per_slice:=count/maxi(slices,1)
 var rows:Array[Dictionary]=[]
 var total_nan:=0;var total_inf:=0;var total_negative:=0
 var finite_min:=INF;var finite_max:=-INF;var finite_count:=0
 for index in maxi(slices,1):
  var nan_count:=0;var inf_count:=0;var negative_count:=0
  for component in range(index*components_per_slice,(index+1)*components_per_slice):
   var value:float=raw.decode_float(component*4)
   if is_nan(value):nan_count+=1
   elif is_inf(value):inf_count+=1
   else:
    finite_count+=1;finite_min=minf(finite_min,value);finite_max=maxf(finite_max,value)
    if value<0.0:negative_count+=1
  total_nan+=nan_count;total_inf+=inf_count;total_negative+=negative_count
  rows.append({"slice":index,"nan_components":nan_count,"infinite_components":inf_count,"negative_components":negative_count})
 return {"pass":total_nan==0 and total_inf==0,"width":image.get_width(),"height":image.get_height(),"slices":rows,"nan_components":total_nan,"infinite_components":total_inf,"negative_components":total_negative,"finite_components":finite_count,"finite_min":finite_min if finite_count>0 else null,"finite_max":finite_max if finite_count>0 else null}

static func inspect_data(data:LightmapGIData)->Dictionary:
 var reports:Array[Dictionary]=[]
 var valid:=data!=null and not data.get_lightmap_textures().is_empty()
 if data==null:return {"pass":false,"error":"No LightmapGIData","textures":reports}
 for texture:TextureLayered in data.get_lightmap_textures():
  var source:=Image.load_from_file(texture.resource_path)
  var result:=inspect_image(source,texture.get_layers())
  result["path"]=texture.resource_path
  reports.append(result)
  valid=valid and bool(result.get("pass",false))
 return {"pass":valid,"textures":reports,"scope":"Original HDR finite-data check; no visual-quality claim"}
