"""Read-only GLB contract audit; uses Python stdlib, no rendering or GPU."""
import os,json,struct,math
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
contract=json.load(open(os.path.join(ROOT,'source_provenance/poolrooms_wing/geometry.json')))
results={};failures=[]
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def norm(a):return math.sqrt(sum(x*x for x in a))
for name,r in contract['rooms'].items():
 raw=open(os.path.join(ROOT,r['glb']),'rb').read();js=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+js]);base=20+js+8
 def accessor(i):
  a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];dims={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];sz=struct.calcsize(fmt)*dims;off=base+v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',sz)
  return [struct.unpack_from('<'+fmt*dims,raw,off+j*stride) for j in range(a['count'])]
 stats={'exact_box_proxies':0,'visible_primitives':0,'all_visible_tangents':True,'embedded_images':len(d.get('images',[])),'metric_uv_triangles':0,'uv_triangle_count':0,'metric_uv_worst_area_error':0.,'visible_vertices':0}
 for node in d['nodes']:
  if 'mesh' not in node:continue
  if any(k in node for k in ['matrix','translation','rotation','scale']):
   if node.get('translation',[0,0,0])!=[0,0,0] or node.get('scale',[1,1,1])!=[1,1,1]:failures.append(name+': unexpected transform '+node['name'])
  if node['name'].startswith('COLLISION_'):
   prim=d['meshes'][node['mesh']]['primitives'][0];coords=accessor(prim['attributes']['POSITION']);points=set(tuple(round(v,5) for v in p) for p in coords)
   exact=len(points)==8 and all(len(set(p[a] for p in points))==2 for a in range(3))
   if exact:stats['exact_box_proxies']+=1
   else:failures.append(name+': non-box proxy '+node['name'])
  else:
   for pr in d['meshes'][node['mesh']]['primitives']:
    attrs=pr['attributes'];stats['visible_primitives']+=1
    for required in ['POSITION','NORMAL','TEXCOORD_0','TANGENT']:
     if required not in attrs:failures.append(name+': missing '+required+' '+node['name']);stats['all_visible_tangents']=False
    if 'TEXCOORD_0' not in attrs:continue
    pos=accessor(attrs['POSITION']);uv=accessor(attrs['TEXCOORD_0']);ind=[q[0] for q in accessor(pr['indices'])];stats['visible_vertices']+=len(pos)
    for off in range(0,len(ind),3):
     a,b,c=ind[off:off+3];area3=norm(cross(sub(pos[b],pos[a]),sub(pos[c],pos[a])))
     u=sub(uv[b],uv[a]);v=sub(uv[c],uv[a]);area2=abs(u[0]*v[1]-u[1]*v[0])
     if area3<1e-7:continue
     error=abs(area2/area3-1);stats['uv_triangle_count']+=1;stats['metric_uv_worst_area_error']=max(stats['metric_uv_worst_area_error'],error)
     if error<.015:stats['metric_uv_triangles']+=1
     elif area3>1e-4:failures.append(name+': UV density area error '+str(round(error,5)))
 assert stats['exact_box_proxies']==r['proxy_count']
 assert stats['embedded_images']==0
 assert all(q['riser']<=.15 and q['tread']>=.4 and q['width']>=1.8 for q in r['basin_steps'])
 stats['metric_uv_worst_area_error']=round(stats['metric_uv_worst_area_error'],8)
 results[name]=stats
report={'passed':not failures,'rooms':results,'failures':failures}
path=os.path.join(os.path.dirname(__file__),'geometry_audit.json');json.dump(report,open(path,'w'),indent=2)
print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
