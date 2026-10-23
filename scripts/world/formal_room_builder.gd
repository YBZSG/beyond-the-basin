extends RefCounted
const Catalog=preload("res://scripts/world/formal_rooms.gd")
var room:Node3D
var layout:Dictionary
var library:RefCounted
var body:StaticBody3D
func _init(root:Node3D,data:Dictionary,materials:RefCounted):
 room=root;layout=data;library=materials
func build_shell():
 var asset_path:String=layout.get("geometry_path",Catalog.PATHS.get(layout.coord,""))
 var packed:PackedScene=load(asset_path) if not asset_path.is_empty() else null
 if packed==null:
  push_error("Formal room GLB missing: "+str(layout.coord));return
 var geometry:Node3D=packed.instantiate()
 geometry.name="FormalAuthoredArchitecture"
 room.add_child(geometry)
 body=StaticBody3D.new();body.name="ArchitectureCollision";body.collision_layer=1;body.collision_mask=0;room.add_child(body)
 _visit(geometry)
func _visit(node:Node):
 if node is MeshInstance3D:
  var mesh_node:=node as MeshInstance3D
  if String(node.name).begins_with("COLLISION_"):
   if mesh_node.mesh:
    var collider:=CollisionShape3D.new()
    # Disabling simplification is required for thin precise coping/stair proxies.
    collider.shape=mesh_node.mesh.create_convex_shape(true,false)
    collider.transform=room.global_transform.affine_inverse()*mesh_node.global_transform
    body.add_child(collider)
    var local_box:AABB=collider.transform*mesh_node.mesh.get_aabb()
    layout.solids.append(local_box)
   mesh_node.hide()
  else:
   mesh_node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
   mesh_node.layers=1
   if mesh_node.mesh:
    for index in mesh_node.mesh.get_surface_count():
     var old:Material=mesh_node.get_active_material(index)
     if old:
      var role:=old.resource_name.trim_prefix("Formal_").to_lower()
      var mapped:String=_material_role(String(node.name),role)
      mesh_node.set_surface_override_material(index,library.get_material(mapped))
      if role=="glazing":
       # These are actual apertures, not luminous white panels. Native shadow
       # maps, SDFGI and the source-water triangle BVH must all admit daylight.
       # The separately authored mullions, curbs and reveals remain opaque.
       mesh_node.set_meta("source_transmissive",true)
       mesh_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
       mesh_node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
 for child in node.get_children():_visit(child)
func _material_role(node_name:String,source_role:String)->String:
 if node_name.begins_with("Main_") or node_name.begins_with("Terrace_") or node_name.begins_with("Bath_"):
  if source_role=="coping":return "formal_coping"
  if source_role=="ceramic":
   if "_Deck" in node_name or node_name.ends_with("Vestibule"):
    return "formal_dry_deck"
   if "_Basin" in node_name or "_Stair" in node_name:
    return "formal_basin"
   # Includes the real TileWainscot and CeramicFoot meshes, not an overlay.
   return "formal_wainscot"
 return {"ceramic":"formal_arcade_tile","plaster":"formal_plaster","coping":"formal_arcade_coping","metal":"brushed stainless","drain":"black","glazing":"formal_glazing"}.get(source_role,"pale")
func build_interior():
 room.set_meta("layout",layout)
 room.set_meta("complete",true)
