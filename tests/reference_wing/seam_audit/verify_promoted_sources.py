"""Read-only evaluated mesh fingerprint comparison, not a surface overlap rescan."""
import bpy,numpy as np,json,pathlib,hashlib,time
ROOT=pathlib.Path(__file__).resolve().parents[3];OUT=ROOT/'output/reference_wing/seam_audit'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fingerprint(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();out=[]
 for ob in sorted([o for o in bpy.context.scene.objects if o.type=='MESH'],key=lambda o:o.name):
  eo=ob.evaluated_get(dg);me=eo.to_mesh();h=hashlib.sha256();meta={'name':ob.name,'hide_render':ob.hide_render,'world_matrix':[list(r)for r in ob.matrix_world],'materials':[m.name if m else None for m in me.materials],'vertices':len(me.vertices),'polygons':len(me.polygons),'loops':len(me.loops),'uv_layers':[u.name for u in me.uv_layers]};h.update(json.dumps(meta,sort_keys=True).encode())
  def feed(collection,field,count,typ):
   a=np.empty(count,dtype=typ);collection.foreach_get(field,a);h.update(a.astype(a.dtype.newbyteorder('<')).tobytes())
  feed(me.vertices,'co',len(me.vertices)*3,np.float32)
  feed(me.loops,'vertex_index',len(me.loops),np.int32)
  for field in ['loop_start','loop_total','material_index']:feed(me.polygons,field,len(me.polygons),np.int32)
  feed(me.polygons,'use_smooth',len(me.polygons),np.bool_)
  for uv in me.uv_layers:feed(uv.data,'uv',len(me.loops)*2,np.float32)
  feed(me.corner_normals,'vector',len(me.corner_normals)*3,np.float32)
  out.append({'name':ob.name,'fingerprint':h.hexdigest(),**{k:meta[k]for k in ['vertices','polygons','loops']}});eo.to_mesh_clear()
 return {'mesh_fingerprint':hashlib.sha256(json.dumps(out,sort_keys=True).encode()).hexdigest(),'objects':out}
rows=[]
for name in ['colonnade','cyan_corridor','octagonal_bath']:
 candidate=ROOT/f'output/reference_wing/water_rooms/joint_repair/{name}/{name}.blend';production=ROOT/f'tools/blender/reference_wing/water_sources/{name}.blend';cb=sha(candidate);pb=sha(production);c=fingerprint(candidate);p=fingerprint(production);co={x['name']:x for x in c['objects']};po={x['name']:x for x in p['objects']};changed=[n for n in co.keys()|po.keys()if co.get(n)!=po.get(n)];rows.append({'scene':name,'candidate_path':str(candidate.relative_to(ROOT)),'production_path':str(production.relative_to(ROOT)),'candidate_sha256':cb,'production_sha256':pb,'inputs_stable':cb==sha(candidate)and pb==sha(production),'candidate_mesh_fingerprint':c['mesh_fingerprint'],'production_mesh_fingerprint':p['mesh_fingerprint'],'exact_mesh_attributes_equal':c['mesh_fingerprint']==p['mesh_fingerprint'],'changed_objects':changed,'mesh_objects':len(co)});print(name,json.dumps(rows[-1]),flush=True)
r={'scope':'Evaluated mesh attributes only: named objects, hide_render, world transforms, vertex coordinates, loop topology, polygon material indices, smooth flags, every UV layer, corner normals and material slot names. No overlap rescan, rendering, GLB import or source edits.','rows':rows,'status':'PASS'if all(x['inputs_stable']and x['exact_mesh_attributes_equal']for x in rows)else'FAIL'};(OUT/'production_source_fingerprints.json').write_text(json.dumps(r,indent=2));assert r['status']=='PASS'
