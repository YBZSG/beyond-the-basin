"""Independent, dependency-free validation of actual exported glTF buffers.
python tools/blender/reference_wing/water_rooms_verify.py
No renderer or Godot display is invoked. JSON is compared with the actual GLB.
"""
import json,struct,math,pathlib,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/models/reference_wing';QA=ROOT/'output/reference_wing/water_rooms'
CTYPE={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'};NCOMP={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def load(path):
 raw=path.read_bytes();magic,version,length=struct.unpack_from('<III',raw)
 assert magic==0x46546c67 and version==2 and length==len(raw)
 off=12;doc=None;binary=None
 while off<len(raw):
  n,t=struct.unpack_from('<II',raw,off);chunk=raw[off+8:off+8+n];off+=8+n
  if t==0x4e4f534a:doc=json.loads(chunk)
  elif t==0x004e4942:binary=chunk
 return doc,binary

def access(doc,binary,idx):
 a=doc['accessors'][idx];bv=doc['bufferViews'][a['bufferView']];fmt='<'+CTYPE[a['componentType']]*NCOMP[a['type']];size=struct.calcsize(fmt);stride=bv.get('byteStride',size);start=bv.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def norm(a):return math.sqrt(dot(a,a))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def check(name):
 path=OUT/(name+'.glb');doc,binary=load(path);contract=json.loads((OUT/(name+'.geometry.json')).read_text());errors=[];meshes={};counts={'visual_primitives':0,'collision_primitives':0,'triangles':0};maxnormal=0;maxtangent=0;densityerrors=0;densitysamples=0
 for node in doc['nodes']:
  if 'mesh' not in node:continue
  nn=node.get('name','');allpos=[];iscoll=nn.startswith('COLLISION_')
  if 'PREVIEW' in nn or 'Water_' in nn:errors.append('Preview/water mesh exported: '+nn)
  if node.get('translation',[0,0,0])!=[0,0,0] or node.get('scale',[1,1,1])!=[1,1,1]:errors.append('Unexpected local transform '+nn)
  for prim in doc['meshes'][node['mesh']]['primitives']:
   counts['collision_primitives' if iscoll else 'visual_primitives']+=1
   att=prim['attributes'];pos=access(doc,binary,att['POSITION']);allpos+=pos
   if iscoll:continue
   required=['NORMAL','TEXCOORD_0','TANGENT']
   for a in required:
    if a not in att:errors.append(nn+' missing '+a)
   if any(a not in att for a in required):continue
   normals=access(doc,binary,att['NORMAL']);uv=access(doc,binary,att['TEXCOORD_0']);tan=access(doc,binary,att['TANGENT'])
   for n,t in zip(normals,tan):
    maxnormal=max(maxnormal,abs(norm(n)-1));maxtangent=max(maxtangent,abs(dot(n,t[:3])),abs(norm(t[:3])-1))
   indices=[i[0] for i in access(doc,binary,prim['indices'])] if 'indices'in prim else range(len(pos))
   for i in range(0,len(indices),3):
    a,b,c=indices[i:i+3];e1=sub(pos[b],pos[a]);e2=sub(pos[c],pos[a]);area=norm(cross(e1,e2));u1=sub(uv[b],uv[a]);u2=sub(uv[c],uv[a]);uarea=abs(u1[0]*u2[1]-u1[1]*u2[0]);counts['triangles']+=1
    if area>1e-5:
     densitysamples+=1
     if abs(uarea/area-1)>.012:densityerrors+=1
  meshes[nn]={'positions':allpos,'bounds':[[min(v[i]for v in allpos)for i in range(3)],[max(v[i]for v in allpos)for i in range(3)]]}
 for proxy in contract['collision_proxies']:
  n=proxy['name']
  if n not in meshes:errors.append('Missing collision node '+n);continue
  b=meshes[n]['bounds']
  if proxy['type']=='BOX':
   target=[[proxy['center'][i]-proxy['size'][i]/2 for i in range(3)],[proxy['center'][i]+proxy['size'][i]/2 for i in range(3)]]
   if max(abs(b[j][i]-target[j][i])for j in range(2)for i in range(3))>1e-5:errors.append('BOX mismatch '+n)
  else:
   expected=proxy['vertices'];actual=list(set(meshes[n]['positions']))
   if any(min(norm(sub(e,a))for a in actual)>2e-5 for e in expected) or any(min(norm(sub(a,e))for e in expected)>2e-5 for a in actual):errors.append('CONVEX exported vertex mismatch '+n)
 for s in contract['support_contacts']:
  ob=meshes[s['object']]['bounds'];su=meshes[s['support']]['bounds'];gap=ob[0][1]-su[1][1]
  if abs(gap)>1e-5:errors.append('Support gap in GLB '+s['object'])
 for mount in contract.get('fixture_mounts',[]):
  fixture=meshes[mount['fixture']]['bounds'];base=meshes[mount['support_object']]['bounds']
  if 'mount_axis' in mount:
   axis='XYZ'.index(mount['mount_axis']);fm=float(mount['fixture_mount_coordinate']);sm=float(mount['support_coordinate'])
   fv=min([fixture[0][axis],fixture[1][axis]],key=lambda x:abs(x-fm));sv=min([base[0][axis],base[1][axis]],key=lambda x:abs(x-sm))
   if max(abs(fv-fm),abs(sv-sm),abs(fv-sv))>1e-5:errors.append('Fixture axis mount gap in GLB '+mount['fixture'])
  elif abs(fixture[0][1]-base[1][1])>1e-5:errors.append('Fixture mount gap in GLB '+mount['fixture'])
 for t in contract['threshold_measurements']:
  floor=meshes[t['threshold_object']]['bounds'];roof=meshes[t['overhead_object']]['bounds'];height=roof[0][1]-floor[1][1]
  if abs(height-t['measured_clear_height_m'])>1e-5:errors.append('Threshold clearance mismatch '+t['portal'])
 if maxnormal>5e-4 or maxtangent>5e-4:errors.append('Non-orthonormal surface basis')
 if densityerrors:errors.append('UV density failures: '+str(densityerrors))
 matnames=[m.get('name')for m in doc.get('materials',[])]
 if doc.get('images'):errors.append('Redundant embedded preview images in runtime GLB')
 result={'name':name,'status':'PASS'if not errors else'FAIL','errors':errors,'actual_glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'counts':counts,'max_normal_unit_error':maxnormal,'max_tangent_orthogonality_or_unit_error':maxtangent,'metric_uv_triangle_samples':densitysamples,'metric_uv_failures':densityerrors,'support_contacts_rechecked_in_glb':len(contract['support_contacts']),'fixture_mounts_rechecked_in_glb':len(contract.get('fixture_mounts',[])),'threshold_clearances_rechecked_in_glb':len(contract['threshold_measurements']),'material_names':matnames,'embedded_image_count':len(doc.get('images',[])),'scope':'Actual glTF vertex/UV/normal/tangent/physics data only; no Godot runtime or GPU visual claim.'}
 return result
results=[check(n)for n in ['colonnade','cyan_corridor','octagonal_bath']];QA.mkdir(parents=True,exist_ok=True);(QA/'glb_independent_audit.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));assert all(r['status']=='PASS'for r in results)
