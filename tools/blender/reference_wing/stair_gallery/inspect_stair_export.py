"""Read the actual GLB buffers and geometry sidecar. No Godot/display required."""
import struct, json, math, os
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'))
OUT=os.path.join(ROOT,'assets/models/reference_wing');QA=os.path.join(ROOT,'output/reference_wing/stair')
data=open(os.path.join(OUT,'stair_gallery.glb'),'rb').read();magic,version,length=struct.unpack_from('<III',data)
assert magic==0x46546c67 and version==2 and length==len(data)
jslen,jstype=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+jslen]);off=20+jslen;binlen,bintype=struct.unpack_from('<II',data,off);blob=data[off+8:off+8+binlen]
TYPES={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16};FMTS={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}
def acc(i):
 a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];n=TYPES[a['type']];fmt='<'+FMTS[a['componentType']]*n;size=struct.calcsize(fmt);stride=v.get('byteStride',size);base=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from(fmt,blob,base+j*stride) for j in range(a['count'])]
C=json.load(open(os.path.join(OUT,'stair_gallery.geometry.json')));out={'schema':'poolcore-glb-export-checks-v1','source':'Actual binary GLB attribute buffers and geometry sidecar','tangent_normal_dot_tolerance':.001,'tolerance_note':'MikkTSpace/export floating-point tangent orthogonality tolerance: <0.0573 degrees; measured maximum retained in report.','failure_count':0,'failures':[],'runtime_visible_mesh_nodes':0,'runtime_collision_nodes':0,'visible_triangles':0,'mesh_primitives':[]};allpos=[]
for node in doc['nodes']:
 if 'mesh' not in node:continue
 collision=node.get('name','').startswith('COLLISION_')
 out['runtime_collision_nodes' if collision else 'runtime_visible_mesh_nodes']+=1
 for primitive in doc['meshes'][node['mesh']]['primitives']:
  attr=primitive['attributes'];pos=acc(attr['POSITION']);norm=acc(attr['NORMAL']);uv=acc(attr['TEXCOORD_0']);tan=acc(attr['TANGENT']) if 'TANGENT' in attr else []
  maxunit=max(abs(math.sqrt(sum(x*x for x in n))-1) for n in norm);maxdot=max((abs(sum(n[i]*t[i] for i in range(3))) for n,t in zip(norm,tan)),default=None)
  rec={'name':node.get('name'),'collision':collision,'vertices':len(pos),'triangles':len(acc(primitive['indices']))//3,'attributes':sorted(attr),'normal_unit_error':maxunit,'tangent_normal_dot_abs_max':maxdot,'tangent_count':len(tan),'finite':all(math.isfinite(x) for a in [pos,norm,uv,tan] for row in a for x in row)}
  if not collision:
   out['visible_triangles']+=rec['triangles'];allpos.extend(pos)
   if len(tan)!=len(pos) or maxunit>1e-4 or maxdot is None or maxdot>1e-3 or not rec['finite']:out['failures'].append(rec)
  out['mesh_primitives'].append(rec)
out['embedded_image_count']=len(doc.get('images',[]));out['embedded_texture_count']=len(doc.get('textures',[]));out['texture_free_runtime_export']=not doc.get('images') and not doc.get('textures')
if not out['texture_free_runtime_export']:out['failures'].append('Runtime GLB contains preview textures')
actual_min=[min(v[i] for v in allpos) for i in range(3)];actual_max=[max(v[i] for v in allpos) for i in range(3)]
out['actual_godot_bounds']={'min':actual_min,'max':actual_max};out['bounds_match_sidecar']=max(abs(actual_min[i]-C['bounds_min'][i]) for i in range(3))<1e-4 and max(abs(actual_max[i]-C['bounds_max'][i]) for i in range(3))<1e-4
if not out['bounds_match_sidecar']:out['failures'].append('GLB coordinates/bounds do not match Godot Y-up sidecar')
proxy_names={n['name'] for n in doc['nodes'] if n.get('name','').startswith('COLLISION_')};contract_names={p['name'] for p in C['collision_proxies']};out['collision_names_exact']=proxy_names==contract_names
if proxy_names!=contract_names:out['failures'].append({'collision_name_difference':sorted(proxy_names^contract_names)})
out['stair_rise_total']=round(C['upper_floor_y']-C['deck_top'],6);out['step_count']=len(C['steps']);out['tread_depth']=C['steps'][0]['tread_depth'];out['dry_only']=C['water_regions']==[];out['closed_boundaries']=C['boundaries'];out['north_portal']=C['portal_contracts'][0]
out['failure_count']=len(out['failures']);C['runtime_export_summary']={k:out[k] for k in ['runtime_visible_mesh_nodes','runtime_collision_nodes','visible_triangles','bounds_match_sidecar','collision_names_exact','embedded_image_count','embedded_texture_count','texture_free_runtime_export','failure_count']}
json.dump(out,open(os.path.join(QA,'stair_export_checks.json'),'w'),indent=2);json.dump(C,open(os.path.join(OUT,'stair_gallery.geometry.json'),'w'),indent=2)
print(json.dumps(C['runtime_export_summary'],indent=2))
assert out['failure_count']==0, out['failures']
