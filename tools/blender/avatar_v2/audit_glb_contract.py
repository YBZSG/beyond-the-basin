"""No Godot/GPU: validate exported V2 skin and preserved animation contract."""
from pathlib import Path
import json,struct,hashlib,math
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/models/avatar_v2'
FINGERS=[f+str(n)+'_'+s for s in ['L','R'] for f in ['Index','Middle','Ring','Little','Thumb'] for n in [1,2]]
class GLB:
 def __init__(self,p):
  self.path=p;self.raw=p.read_bytes();n=struct.unpack_from('<I',self.raw,12)[0];self.j=json.loads(self.raw[20:20+n]);self.data=self.raw[28+n:]
 def acc(self,i):
  a=self.j['accessors'][i];v=self.j['bufferViews'][a['bufferView']];dt={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']];cols={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];size=np.dtype(dt).itemsize
  x=np.ndarray((a['count'],cols),dtype=dt,buffer=self.data,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',size*cols),size)).copy()
  if a.get('normalized') and a['componentType']!=5126:x=x.astype(float)/np.iinfo(np.dtype(dt)).max
  return x
 def channels(self):
  out={}
  for a in self.j['animations']:
   for c in a['channels']:
    s=a['samplers'][c['sampler']];name=self.j['nodes'][c['target']['node']]['name'];key=(a['name'],name,c['target']['path'])
    out[key]=(self.acc(s['input']),self.acc(s['output']),s.get('interpolation','LINEAR'))
  return out
 def joint_matrices(self):
  s=self.j['skins'][0];ib=self.acc(s['inverseBindMatrices']);return {self.j['nodes'][n]['name']:ib[i] for i,n in enumerate(s['joints'])}
base=GLB(ROOT/'assets/models/avatar/pool_explorer.glb');v2=GLB(OUT/'pool_explorer_v2.glb')
bc=base.channels();vc=v2.channels();assert set(bc)==set(vc)
results={'glb_sha256':hashlib.sha256(v2.raw).hexdigest(),'bone_count':len(v2.j['skins'][0]['joints']),'animations':{},'skin':{},'nonfinger_channels_exact':True,'changed_finger_channels':0,'max_nonfinger_sample_error':0.,'inverse_bind_max_error':0.}
bj=base.joint_matrices();vj=v2.joint_matrices();assert set(bj)==set(vj);assert len(bj)==42
for name in bj:results['inverse_bind_max_error']=max(results['inverse_bind_max_error'],float(np.max(np.abs(bj[name]-vj[name]))))
assert results['inverse_bind_max_error']<1e-7
for key,(bt,bv,bi) in bc.items():
 vt,vv,vi=vc[key];assert np.array_equal(bt,vt),(key,'timing changed');assert bi==vi
 assert bv.shape==vv.shape,(key,bv.shape,vv.shape)
 err=float(np.max(np.abs(bv-vv)))
 if key[1] not in FINGERS:
  results['max_nonfinger_sample_error']=max(results['max_nonfinger_sample_error'],err)
  if err>0:results['nonfinger_channels_exact']=False
  assert err<1e-6,(key,err)
 else:results['changed_finger_channels']+=int(err>1e-6)
 results['animations'].setdefault(key[0],{'start':float(vt[0,0]),'end':float(vt[-1,0]),'channels':0})['channels']+=1
for node in v2.j['nodes']:
 if 'mesh' not in node:continue
 m=v2.j['meshes'][node['mesh']];tris=0;vertices=0;minw=1.;maxw=1.;maxinf=0
 for p in m['primitives']:
  at=p['attributes'];pos=v2.acc(at['POSITION']);ws=v2.acc(at['WEIGHTS_0']);js=v2.acc(at['JOINTS_0'])
  assert np.isfinite(pos).all();assert np.isfinite(ws).all();assert np.max(js)<42
  sums=ws.sum(axis=1);minw=min(minw,float(sums.min()));maxw=max(maxw,float(sums.max()));assert np.max(np.abs(sums-1))<1e-5
  maxinf=max(maxinf,int((ws>0).sum(axis=1).max()));tris+=len(v2.acc(p['indices']))//3;vertices+=len(pos)
  if 'COLOR_0' in at:
   colors=v2.acc(at['COLOR_0']);assert np.isfinite(colors).all()
   material=v2.j['materials'][p['material']]['name']
   if 'anatomical skin' not in material:assert np.min(colors)>.999,(material,'Unexpected tint')
 results['skin'][node['name']]={'primitives':len(m['primitives']),'triangles':tris,'exported_vertices':vertices,'weight_min':minw,'weight_max':maxw,'max_influences':maxinf}
assert sum(x['triangles'] for x in results['skin'].values())<55000
results['passed']=True
(HERE/'audit/glb_contract.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
