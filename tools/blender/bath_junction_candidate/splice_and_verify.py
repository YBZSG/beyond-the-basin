#!/usr/bin/env python3
"""Replace only two visual node references; preserve original unrelated GLB bytes.
The inserted mesh is the Blender-generated source export, never synthetic mesh
bytes. Production files are read-only. All checks fail closed before publication.
"""
import collections,copy,hashlib,json,math,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tests'))
from formal_architectural_junctions import GLB
from formal_mesh_qa import area,uv_overlap_check,intersection_area
DIR=ROOT/'assets/models/bath_junction_candidate'
DOC=ROOT/'docs/bath-junction-candidate'
TARGETS={'Bath_Wall','Bath_UpperDrum'}

def accessor_bytes(g,index):
 a=g.doc['accessors'][index];v=g.doc['bufferViews'][a['bufferView']]
 size={5126:4,5125:4,5123:2,5121:1}[a['componentType']]*{'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
 return b''.join(g.binary[start+i*stride:start+i*stride+size] for i in range(a['count']))

def primitive_signature(g,name):
 row=[]
 for p in g.primitives(name):
  row.append({'attributes':{n:hashlib.sha256(accessor_bytes(g,i)).hexdigest() for n,i in p['attributes'].items()},
              'indices':hashlib.sha256(accessor_bytes(g,p['indices'])).hexdigest(),
              'material':g.doc['materials'][p['material']]})
 return row

def write_glb(doc,binary,path):
 binary=bytes(binary)+b'\0'*((-len(binary))%4);doc['buffers']=[{'byteLength':len(binary)}]
 js=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();js+=b' '*((-len(js))%4)
 raw=struct.pack('<III',0x46546C67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4E4F534A)+js+struct.pack('<II',len(binary),0x004E4942)+binary
 path.write_bytes(raw)

def triangles(g,name):
 out=[]
 for pr in g.primitives(name):
  vs=g.accessor(pr['attributes']['POSITION']);ids=[x[0] for x in g.accessor(pr['indices'])]
  out.extend([[vs[k] for k in ids[i:i+3]] for i in range(0,len(ids),3)])
 return out

def ray_hit(tris,origin,direction):
 def sub(a,b):return tuple(a[i]-b[i] for i in range(3))
 def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
 def dot(a,b):return sum(x*y for x,y in zip(a,b))
 hits=[]
 for a,b,c in tris:
  e1=sub(b,a);e2=sub(c,a);h=cross(direction,e2);det=dot(e1,h)
  if abs(det)<1e-10:continue
  f=1/det;s=sub(origin,a);u=f*dot(s,h)
  if u < -1e-7 or u > 1+1e-7:continue
  q=cross(s,e1);v=f*dot(direction,q)
  if v < -1e-7 or u+v>1+1e-7:continue
  t=f*dot(e2,q)
  if t>1e-7:hits.append(t)
 return min(hits) if hits else None

def main():
 original=GLB(ROOT/'assets/models/formal/formal_bath.glb')
 source=GLB(DIR/'formal_bath_full_source_export.glb')
 doc=copy.deepcopy(original.doc);binary=bytearray(original.binary)
 # Validate the full editable-scene export before doing the byte-preserving merge.
 untouched=sorted(set(original.nodes)-TARGETS)
 differences=[n for n in untouched if primitive_signature(original,n)!=primitive_signature(source,n)]
 assert not differences,('Unrelated source-export attribute bytes changed',differences)
 original_node={n['name']:n for n in original.doc['nodes']}
 source_node={n['name']:n for n in source.doc['nodes']}
 source_mesh=source.doc['meshes'][source_node['Bath_Wall']['mesh']]
 new_mesh=copy.deepcopy(source_mesh)
 accmap={};viewmap={}
 def append_accessor(idx):
  if idx in accmap:return accmap[idx]
  a=copy.deepcopy(source.doc['accessors'][idx]);view_idx=a['bufferView']
  if view_idx not in viewmap:
   old=source.doc['bufferViews'][view_idx];new=copy.deepcopy(old)
   binary.extend(b'\0'*((-len(binary))%4));start=len(binary)
   binary.extend(source.binary[old.get('byteOffset',0):old.get('byteOffset',0)+old['byteLength']])
   new['buffer']=0;new['byteOffset']=start;viewmap[view_idx]=len(doc['bufferViews']);doc['bufferViews'].append(new)
  a['bufferView']=viewmap[view_idx];accmap[idx]=len(doc['accessors']);doc['accessors'].append(a);return accmap[idx]
 for p in new_mesh['primitives']:
  p['attributes']={k:append_accessor(v) for k,v in p['attributes'].items()};p['indices']=append_accessor(p['indices'])
  mat=source.doc['materials'][p['material']];p['material']=original.doc['materials'].index(mat)
 new_mesh['name']='Bath_Wall_Continuous'
 node_index=next(i for i,n in enumerate(doc['nodes']) if n['name']=='Bath_Wall')
 mesh_index=doc['nodes'][node_index]['mesh'];doc['meshes'][mesh_index]=new_mesh
 doc['nodes'][node_index]['extras']=source_node['Bath_Wall']['extras']
 drum_index=next(i for i,n in enumerate(doc['nodes']) if n['name']=='Bath_UpperDrum')
 doc['nodes'][drum_index].pop('mesh')
 doc['nodes'][drum_index]['extras']=source_node['Bath_UpperDrum']['extras']
 path=DIR/'formal_bath_continuous_wall.glb';write_glb(doc,binary,path);candidate=GLB(path)
 assert candidate.binary[:len(original.binary)]==original.binary
 assert candidate.doc['materials']==original.doc['materials']
 changed_nodes=[]
 for old,new in zip(original.doc['nodes'],candidate.doc['nodes']):
  if old!=new:changed_nodes.append(old['name'])
 assert set(changed_nodes)==TARGETS
 assert all(primitive_signature(original,n)==primitive_signature(candidate,n) for n in untouched)
 assert primitive_signature(candidate,'Bath_Wall')==primitive_signature(source,'Bath_Wall')
 assert original.collision_hash()==candidate.collision_hash()
 tris=triangles(candidate,'Bath_Wall');edges=collections.Counter()
 for t in tris:
  keys=[tuple(round(x,6) for x in v) for v in t]
  assert len(set(keys))==3
  for a,b in ((0,1),(1,2),(2,0)):edges[tuple(sorted((keys[a],keys[b])))]+=1
 assert all(n==2 for n in edges.values()),collections.Counter(edges.values())
 normals=0;uv2tris=[];metric=0
 for p in candidate.primitives('Bath_Wall'):
  attrs=p['attributes'];ns=candidate.accessor(attrs['NORMAL']);vs=candidate.accessor(attrs['POSITION']);uv0=candidate.accessor(attrs['TEXCOORD_0']);uv2=candidate.accessor(attrs['TEXCOORD_1'])
  for n in ns:assert all(math.isfinite(x) for x in n) and abs(sum(x*x for x in n)-1)<1e-4;normals+=1
  for uv in uv2:assert all(math.isfinite(x) and -1e-6<=x<=1+1e-6 for x in uv)
  ids=[x[0] for x in candidate.accessor(p['indices'])]
  for i in range(0,len(ids),3):
   t=[uv2[k] for k in ids[i:i+3]];assert area(t)>1e-13;uv2tris.append(t)
  # For every original un-beveled vertical shell point, UV V retains metres.
  for v,n,uv in zip(vs,ns,uv0):
   if abs(n[1])<1e-4 and any(abs(v[1]-y)<2e-5 for y in (1.488,3.2,4.592)):
    assert abs(uv[1]-(1-v[1]))<2e-5;(metric:=metric+1)
 overlap_pairs=uv_overlap_check(uv2tris)
 assert metric>100
 portal_probes=[]
 for axis in [(1,0,0),(0,0,1)]:
  for y in [1.55,2.4,3.18]:
   hit=ray_hit(tris,(0,y,0),axis);assert hit is None;portal_probes.append({'direction':axis,'y':y,'hit':hit})
  hit=ray_hit(tris,(0,3.3,0),axis);assert abs(hit-8.8)<1e-5;portal_probes.append({'direction':axis,'y':3.3,'header_hit':hit})
 smooth_seam=[]
 for direction in [(-1,0,0),(0,0,-1)]:
  for y in [3.191,3.199,3.2,3.201,3.209]:
   hit=ray_hit(tris,(0,y,0),direction);assert abs(hit-8.8)<1e-5;smooth_seam.append({'direction':direction,'y':y,'wall_hit':hit})
 planar=[]
 for name in ['Bath_Wall','Bath_UpperDrum']:
  planar.append([[ (v[0],v[2]) for v in t] for t in triangles(original,name) if all(abs(v[1]-3.2)<1e-6 for v in t)])
 overlap=sum(intersection_area(a,b) for a in planar[0] for b in planar[1])
 # No y=3.2 cap is allowed outside the actual apertures.
 newcaps=[t for t in tris if all(abs(v[1]-3.2)<1e-6 for v in t)]
 for t in newcaps:
  x=sum(v[0] for v in t)/3;z=sum(v[2] for v in t)/3
  assert (x>0 and abs(z)<3.05) or (z>0 and abs(x)<3.05)
 baseline=json.loads((DOC/'original-junction-evidence.json').read_text())['production_baselines']
 assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in baseline.items())
 report={'pass':True,'scope':'Geometry-only candidate; no claim of runtime dotted-seam causality or runtime visual acceptance',
 'candidate':str(path.relative_to(ROOT)),'candidate_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
 'candidate_bytes':len(candidate.raw),'original_bytes':len(original.raw),'original_binary_prefix_bytes_untouched':len(original.binary),
 'changed_visual_nodes':changed_nodes,'unrelated_mesh_attribute_bytes_exact':len(untouched),
 'full_source_export_unrelated_attributes_exact':True,'candidate_matches_editable_source_wall_attributes_exact':True,
 'original_collision_proxies_exact':sum(n.startswith('COLLISION_') for n in original.nodes),
 'collision_sha256':candidate.collision_hash(),'source_production_files_unchanged':baseline,
 'normal_samples':normals,'UV0_metre_samples':metric,'UV2_triangles_noncollapsed':len(uv2tris),'UV2_overlap_candidate_pairs_checked':overlap_pairs,
 'closed_manifold_triangle_edges':len(edges),'triangle_edge_incidence':dict(collections.Counter(edges.values())),
 'original_opposing_coplanar_y3_2_cap_overlap_square_metres':overlap,'new_horizontal_y3_2_triangles_only_actual_headers':len(newcaps),
 'portal_ray_probes':portal_probes,'continuous_wall_radius_probes':smooth_seam,
 'counts_before':original.counts(),'counts_after':candidate.counts()}
 (DOC/'glb-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

if __name__=='__main__':main()
