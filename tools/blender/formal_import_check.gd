extends SceneTree
var failed := false
var counts := {}
func _initialize():
 for asset in ['formal_arch','formal_mainhall','formal_arcade','formal_sidepool','formal_terrace','formal_bath']:
  var packed = load('res://assets/models/formal/'+asset+'.glb') as PackedScene
  if packed == null:
   push_error('Missing import '+asset);failed=true;continue
  var node=packed.instantiate()
  counts={'visible':0,'collision':0,'uv0':0,'uv2':0,'surfaces':0,'triangles':0}
  check_node(node)
  print('FORMAL_IMPORT ',asset,' ',counts)
  if counts.visible < 1 or counts.collision < 1 or counts.uv0 < counts.visible or counts.uv2 < counts.visible: failed=true
  node.free()
 print('FORMAL_IMPORT_RESULT ', 'FAIL' if failed else 'PASS')
 quit(1 if failed else 0)
func check_node(n: Node):
 if n is Node3D and not n.transform.is_finite():
  push_error('Nonfinite transform '+str(n.name));failed=true
 if n is MeshInstance3D and n.mesh:
  var collision=str(n.name).begins_with('COLLISION_')
  counts['collision' if collision else 'visible']+=1
  var got_uv0=false
  var got_uv2=false
  for i in range(n.mesh.get_surface_count()):
   var arrays=n.mesh.surface_get_arrays(i)
   counts.surfaces+=1
   var indices=arrays[Mesh.ARRAY_INDEX]
   counts.triangles+=indices.size()/3 if indices else arrays[Mesh.ARRAY_VERTEX].size()/3
   if arrays[Mesh.ARRAY_TEX_UV] and arrays[Mesh.ARRAY_TEX_UV].size()>0:got_uv0=true
   if arrays[Mesh.ARRAY_TEX_UV2] and arrays[Mesh.ARRAY_TEX_UV2].size()>0:got_uv2=true
   var material=n.mesh.surface_get_material(i)
   if material == null or not material.resource_name.begins_with('Formal_'):
    push_error('Unexpected material '+str(n.name));failed=true
  if not collision:
   if got_uv0:counts.uv0+=1
   if got_uv2:counts.uv2+=1
  else:
   var shape=n.mesh.create_convex_shape(true,false)
   if shape == null:push_error('Invalid collision '+str(n.name));failed=true
   if str(n.name).begins_with('COLLISION_Main_Stair') and str(n.name).trim_prefix('COLLISION_Main_Stair').is_valid_int():
    var aabb=n.mesh.get_aabb();var top=n.transform*(aabb.position+Vector3(0,aabb.size.y,0))
    print('EXACT_STAIR ',n.name,' top_y=',top.y)
    var stair_index:=str(n.name).trim_prefix('COLLISION_Main_Stair').to_int()
    if stair_index<0 or stair_index>3 or absf(top.y-(.38-.14*stair_index))>.00001:
     push_error('Unexpected preserved stair height '+str(n.name));failed=true
 for c in n.get_children():check_node(c)
