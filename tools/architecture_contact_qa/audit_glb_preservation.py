"""Independently parse exported glTF binary without launching Godot or importing it.
Compare quantized world triangles and every authored collision box to source audit.
"""
import json,struct,pathlib,argparse,hashlib,numpy as np
p=argparse.ArgumentParser();p.add_argument('--input-root',required=True);p.add_argument('--qa-dir',required=True);a=p.parse_args();root=pathlib.Path(a.input_root);out=pathlib.Path(a.qa_dir)
DT={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'};N={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}

def load(path):
 raw=path.read_bytes();magic,ver,length=struct.unpack_from('<III',raw);assert magic==0x46546c67 and ver==2 and length==len(raw);pos=12;chunks={}
 while pos<len(raw):
  ln,typ=struct.unpack_from('<II',raw,pos);pos+=8;chunks[typ]=raw[pos:pos+ln];pos+=ln
 return json.loads(chunks[0x4e4f534a]),chunks[0x004e4942]
def acc(d,b,i):
 a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);dtype=np.dtype(DT[a['componentType']]);n=N[a['type']];stride=v.get('byteStride',n*dtype.itemsize)
 return np.ndarray((a['count'],n),dtype=dtype,buffer=b,offset=offset,strides=(stride,dtype.itemsize)).copy()
def local(n):
 if 'matrix'in n:return np.asarray(n['matrix']).reshape(4,4).T
 m=np.eye(4);x,y,z,w=n.get('rotation',[0,0,0,1]);m[:3,:3]=np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0]);return m
results=[]
for room in ['crescent_court','vaulted_lanes','circular_bath']:
 path=root/'assets/models/poolrooms_wing'/f'{room}.glb';d,b=load(path);source=json.loads((out/f'{room}.json').read_text());tri=[];boxes={};bad=[]
 def visit(i,parent):
  n=d['nodes'][i];mat=parent@local(n);name=n.get('name',str(i));pts=[]
  if 'mesh'in n:
   for pr in d['meshes'][n['mesh']]['primitives']:
    assert pr.get('mode',4)==4;v=acc(d,b,pr['attributes']['POSITION']);v=(np.c_[v,np.ones(len(v))]@mat.T)[:,:3];pts.append(v);idx=acc(d,b,pr['indices']).reshape(-1,3) if 'indices'in pr else np.arange(len(v)).reshape(-1,3)
    if not name.startswith('COLLISION_'):
     q=np.rint(v*10000).astype('int64')
     for f in idx:tri.append(tuple(sorted(tuple(int(c) for c in q[j])for j in f)))
   if name.startswith('COLLISION_'):
    vv=np.concatenate(pts);boxes[name]={'min':vv.min(axis=0).tolist(),'max':vv.max(axis=0).tolist()}
  for c in n.get('children',[]):visit(c,mat)
 for i in d['scenes'][d.get('scene',0)]['nodes']:visit(i,np.eye(4))
 digest=hashlib.sha256(repr(sorted(tri)).encode()).hexdigest();srcboxes={r['object']:r for r in source['collisions']};errors=[]
 for nm,s in srcboxes.items():
  if nm not in boxes:errors.append({'name':nm,'error':'missing'});continue
  b=boxes[nm];e=max(abs(x-y) for x,y in zip(s['bounds_min']+s['bounds_max'],b['min']+b['max']))
  if e>1e-5:errors.append({'name':nm,'max_bounds_error_m':e})
 results.append({'room':room,'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source_visual_triangles':source['visual_triangle_count'],'glb_visual_triangles':len(tri),'source_visual_hash_0_1mm':source['visual_triangle_geometry_sha256_0_1mm'],'glb_visual_hash_0_1mm':digest,'visual_geometry_identical_0_1mm':digest==source['visual_triangle_geometry_sha256_0_1mm'],'collision_names_exact':set(srcboxes)==set(boxes),'collision_bounds_errors':errors,'collision_count':len(boxes)})
 print(json.dumps(results[-1]),flush=True)
(out/'glb_preservation.json').write_text(json.dumps(results,indent=2))
