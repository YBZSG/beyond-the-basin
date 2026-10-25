"""Shared author-only exact join termination for the three water rooms.
Called by the reproducible generator and source-preserving repair tool.
"""
import bpy,bmesh,json
from pathlib import Path

def apply_manifest(G,OB,runtime,box,uv_metric,bbox):
 manifest=json.loads(Path(__file__).with_name('water_rooms_joint_manifest.json').read_text());ops=manifest['rooms'].get(G['name'],[]);order={c['name']:i for i,c in enumerate(G['collision_proxies'])};changed=[]
 for op in ops:
  name=op['object'];old=next(c for c in G['collision_proxies']if c['source_object']==name);assert old['type']=='BOX'
  lo=[old['center'][i]-old['size'][i]/2 for i in range(3)];hi=[old['center'][i]+old['size'][i]/2 for i in range(3)];nlo=[op['center'][i]-op['size'][i]/2 for i in range(3)];nhi=[op['center'][i]+op['size'][i]/2 for i in range(3)];assert all(lo[i]-1e-6<=nlo[i]<=nhi[i]<=hi[i]+1e-6 for i in range(3)),(name,lo,hi,nlo,nhi)
  mat=OB[name].data.materials[0].name
  for key in[name,'COLLISION_'+name]:bpy.data.objects.remove(OB[key],do_unlink=True);del OB[key]
  G['collision_proxies']=[c for c in G['collision_proxies']if c['source_object']!=name]
  ob=box(name,op['center'],op['size'],mat,True,0)
  if '_Roof_'not in name:
   me=ob.data;attribute=me.attributes.new('bevel_weight_edge','FLOAT','EDGE')
   for edge in me.edges:
    vv=[me.vertices[i].co for i in edge.vertices];godot=[(v.x,v.z,-v.y)for v in vv]
    buried=any(all(abs(v[axis]-value)<1e-5 for v in godot)for axis,value in op['join_planes']);attribute.data[edge.index].value=0.0 if buried else 1.0
   mod=ob.modifiers.new('Metric bevel on exposed edges only','BEVEL');mod.limit_method='WEIGHT';mod.width=min(.004,min(op['size'])/4);mod.segments=2
   bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
   bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);ng=[f for f in bm.faces if len(f.verts)>4]
   if ng:bmesh.ops.triangulate(bm,faces=ng)
   bm.to_mesh(me);bm.free();me.update();uv_metric(me)
  changed.append(name)
 G['collision_proxies'].sort(key=lambda c:order[c['name']])
 for row in G['support_contacts']:
  a,b=bbox(OB[row['object']]),bbox(OB[row['support']]);row.update(object_bottom_y=round(a[0][1],6),support_top_y=round(b[1][1],6),gap=round(a[0][1]-b[1][1],6),footprint_overlap_xz=[round(min(a[1][i],b[1][i])-max(a[0][i],b[0][i]),6)for i in[0,2]])
  assert abs(row['gap'])<1e-5 and min(row['footprint_overlap_xz'])>0,row
 G['joint_termination_revision']=manifest['revision']
 if G['name']=='octagonal_bath':G['cap_termination_revision']=1
 return changed
