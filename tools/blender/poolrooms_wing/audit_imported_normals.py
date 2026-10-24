"""Read-only source topology/normal audit. Repairs a temporary BMesh only."""
import bpy,bmesh,json,os,hashlib,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
label=sys.argv[sys.argv.index('--label')+1] if '--label' in sys.argv else 'current'
report={'label':label,'epsilon_metres':.00001,'rooms':{}}
for room in ['crescent_court','vaulted_lanes','circular_bath']:
 bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'tools/blender/poolrooms_wing/source/{room}.blend'))
 rows=[]
 for ob in bpy.context.scene.objects:
  if ob.type!='MESH' or not ob.get('licensed_component'):continue
  bm=bmesh.new();bm.from_mesh(ob.data);bm.normal_update();layer=bm.faces.layers.int.new('audit_original_face_index');original=[]
  for i,f in enumerate(bm.faces):f[layer]=i;original.append(f.normal.copy())
  cloud=sorted(set(tuple(round(c,6) for c in v.co) for v in bm.verts))
  row={'object':ob.name,'source':ob['licensed_component'],'faces':len(bm.faces),'vertices':len(bm.verts),'boundary_edges':sum(e.is_boundary for e in bm.edges),'position_cloud_sha256':hashlib.sha256(json.dumps(cloud).encode()).hexdigest(),'bounds_min':[min(v.co[a] for v in bm.verts) for a in range(3)],'bounds_max':[max(v.co[a] for v in bm.verts) for a in range(3)]}
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.normal_update()
  row.update({'after_weld_vertices':len(bm.verts),'after_weld_faces':len(bm.faces),'after_weld_boundary_edges':sum(e.is_boundary for e in bm.edges),'after_weld_signed_volume':bm.calc_volume(signed=True),'faces_needing_normal_flip':sum(f.normal.dot(original[f[layer]])<-.99 for f in bm.faces),'flat_shading_faces':sum(not f.smooth for f in bm.faces)})
  rows.append(row);bm.free()
 report['rooms'][room]={'components':rows,'total_faces_needing_flip':sum(r['faces_needing_normal_flip'] for r in rows),'total_boundary_edges':sum(r['boundary_edges'] for r in rows),'all_welded_components_closed':all(r['after_weld_boundary_edges']==0 for r in rows),'all_repaired_volumes_positive':all(r['after_weld_signed_volume']>0 for r in rows)}
path=ROOT/f'tools/blender/poolrooms_wing/imported_normals_{label}.json';path.write_text(json.dumps(report,indent=2))
print('IMPORTED_NORMALS',label,{k:{q:v[q] for q in ['total_faces_needing_flip','total_boundary_edges','all_welded_components_closed','all_repaired_volumes_positive']} for k,v in report['rooms'].items()})
