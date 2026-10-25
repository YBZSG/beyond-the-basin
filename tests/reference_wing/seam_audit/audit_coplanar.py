"""Read-only Blender CPU audit of cross-object, positive-area coplanar surfaces.
No import, render, save, GPU, production-file edit, or third-party packages.
Run: blender -b -t 2 --python tests/reference_wing/seam_audit/audit_coplanar.py [-- names...]
"""
import bpy,numpy as np,json,pathlib,hashlib,time,sys,math,collections,struct
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
ROOT=pathlib.Path(__file__).resolve().parents[3];OUT=ROOT/'output/reference_wing/seam_audit';OUT.mkdir(parents=True,exist_ok=True)
SOURCES={
'colonnade':('tools/blender/reference_wing/water_sources/colonnade.blend','assets/models/reference_wing/colonnade.glb','assets/models/reference_wing/colonnade.geometry.json'),
'cyan_corridor':('tools/blender/reference_wing/water_sources/cyan_corridor.blend','assets/models/reference_wing/cyan_corridor.glb','assets/models/reference_wing/cyan_corridor.geometry.json'),
'octagonal_bath':('output/reference_wing/water_rooms/octagonal_bath_cap_candidate/candidate.blend','output/reference_wing/water_rooms/octagonal_bath_cap_candidate/octagonal_bath.glb','output/reference_wing/water_rooms/octagonal_bath_cap_candidate/octagonal_bath.geometry.json'),
'ball_lounge':('tools/blender/reference_wing/lounge_sources/ball_lounge.blend','assets/models/reference_wing/ball_lounge.glb','assets/models/reference_wing/ball_lounge.geometry.json'),
'stair_gallery':('tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend','assets/models/reference_wing/stair_gallery.glb','assets/models/reference_wing/stair_gallery.geometry.json')}
PLANE_EPS=1e-5;MIN_AREA=1e-7

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def signed(p):return sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))/2 if len(p)>2 else 0

def clip(subject,bound):
 out=subject;bound=bound if signed(bound)>0 else list(reversed(bound))
 for i,a in enumerate(bound):
  b=bound[(i+1)%len(bound)];old=out;out=[]
  if not old:break
  def cross(p):return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
  for j,e in enumerate(old):
   start=old[j-1];cs=cross(start);ce=cross(e);si=cs>=-1e-10;ei=ce>=-1e-10
   if si!=ei:
    t=cs/(cs-ce);out.append((start[0]+t*(e[0]-start[0]),start[1]+t*(e[1]-start[1])))
   if ei:out.append(e)
 return out

def source_geometry():
 obs=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.hide_render and not o.name.startswith(('COLLISION_','PREVIEW_'))]
 alltri=[];alloi=[];allfi=[];allmi=[];alluv=[];allnorm=[];meta=[];dg=bpy.context.evaluated_depsgraph_get()
 for oi,ob in enumerate(obs):
  eo=ob.evaluated_get(dg);me=eo.to_mesh();me.calc_loop_triangles();v=np.empty(len(me.vertices)*3);me.vertices.foreach_get('co',v);v=v.reshape((-1,3));m=np.array(ob.matrix_world,dtype=float);v=v@m[:3,:3].T+m[:3,3];v=v[:,[0,2,1]];v[:,2]*=-1
  ids=np.empty(len(me.loop_triangles)*3,dtype=np.int32);me.loop_triangles.foreach_get('vertices',ids);ids=ids.reshape((-1,3));fi=np.empty(len(ids),dtype=np.int32);me.loop_triangles.foreach_get('polygon_index',fi)
  mi=np.empty(len(me.polygons),dtype=np.int32);me.polygons.foreach_get('material_index',mi)
  li=np.empty(len(ids)*3,dtype=np.int32);me.loop_triangles.foreach_get('loops',li);li=li.reshape((-1,3));uv=np.zeros((len(me.loops),2));
  if me.uv_layers.active:me.uv_layers.active.data.foreach_get('uv',uv.reshape(-1))
  cn=np.empty((len(me.corner_normals),3));me.corner_normals.foreach_get('vector',cn.reshape(-1));cn=cn@np.linalg.inv(m[:3,:3]);cn=cn[:,[0,2,1]];cn[:,2]*=-1;cn/=np.maximum(np.linalg.norm(cn,axis=1)[:,None],1e-30);alluv.append(uv[li]);allnorm.append(cn[li])
  alltri.append(v[ids]);alloi.append(np.full(len(ids),oi,dtype=np.int32));allfi.append(fi);allmi.append(mi[fi]);meta.append({'name':ob.name,'triangles':len(ids),'materials':[x.name if x else None for x in me.materials],'bounds':[v.min(axis=0).tolist(),v.max(axis=0).tolist()]});eo.to_mesh_clear()
 return np.concatenate(alltri),np.concatenate(alloi),np.concatenate(allfi),np.concatenate(allmi),np.concatenate(alluv),np.concatenate(allnorm),meta

def read_glb(path):
 raw=path.read_bytes();off=12;doc=binary=None
 while off<len(raw):
  size,typ=struct.unpack_from('<II',raw,off);ch=raw[off+8:off+8+size];off+=8+size
  if typ==0x4e4f534a:doc=json.loads(ch)
  elif typ==0x004e4942:binary=ch
 ct={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'};nc={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
 def access(i):
  a=doc['accessors'][i];b=doc['bufferViews'][a['bufferView']];fmt='<'+ct[a['componentType']]*nc[a['type']];stride=b.get('byteStride',struct.calcsize(fmt));off=b.get('byteOffset',0)+a.get('byteOffset',0);return np.array([struct.unpack_from(fmt,binary,off+j*stride)for j in range(a['count'])])
 parents={c:i for i,n in enumerate(doc['nodes'])for c in n.get('children',[])};cache={}
 def world(i):
  if i in cache:return cache[i]
  n=doc['nodes'][i]
  if 'matrix'in n:m=np.array(n['matrix']).reshape((4,4)).T
  else:
   q=n.get('rotation',[0,0,0,1]);m=np.array(Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])),Quaternion((q[3],q[0],q[1],q[2])),Vector(n.get('scale',[1,1,1]))))
  if i in parents:m=world(parents[i])@m
  cache[i]=m;return m
 tri=[];materials=[];names=[];o_ids=[]
 for ni,node in enumerate(doc['nodes']):
  if 'mesh'not in node or node.get('name','').startswith('COLLISION_'):continue
  oi=len(names);names.append(node.get('name',str(ni)));m=world(ni)
  for p in doc['meshes'][node['mesh']]['primitives']:
   v=access(p['attributes']['POSITION']);v=v@m[:3,:3].T+m[:3,3];ix=access(p['indices']).reshape(-1).astype(int).reshape((-1,3)) if 'indices'in p else np.arange(len(v)).reshape((-1,3));tri.append(v[ix]);materials.extend([doc.get('materials',[])[p['material']].get('name')] * len(ix));o_ids.extend([oi]*len(ix))
 return np.concatenate(tri),names,np.array(o_ids),materials

def geometry_signature(tri):
 # Surface integral per material/object is supplemented by a rounded vertex-cloud
 # signature; differing tessellation diagonals deliberately do not fail this test.
 pts=np.unique(np.round(tri.reshape((-1,3)),5),axis=0);pts[pts==0]=0.0;cr=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);area=np.linalg.norm(cr,axis=1)/2
 return {'triangles':len(tri),'unique_positions':len(pts),'unique_positions_sha256_1e_5m':hashlib.sha256(pts.astype('<f8').tobytes()).hexdigest(),'surface_area_m2':float(area.sum()),'bounds':[pts.min(axis=0).tolist(),pts.max(axis=0).tolist()]}

def observers(contract,tri,norm,oi,meta,bvh):
 obs=[]
 def add(name,p,kind):
  if len(p)==3:obs.append({'name':name,'position':[float(x)for x in p],'kind':kind})
 for o in bpy.context.scene.objects:
  if o.type=='CAMERA':v=o.matrix_world.translation;add(o.name,[v.x,v.z,-v.y],'authored_camera')
 for route in contract.get('connector_route_waypoints',[]):
  for i,p in enumerate(route['waypoints']):add(route['name']+'_'+str(i),[p[0],p[1]+1.45,p[2]],'contract_route_eye')
 for route in contract.get('walkable_routes',[]):
  for i,p in enumerate(route.get('centerline',[])):add(route['name']+'_'+str(i),[p[0],p[1]+1.45,p[2]],'contract_route_eye')
 for i,p in enumerate(contract.get('connector_clear_path',{}).get('centerline',[])):add('connector_centerline_'+str(i),[p[0],p[1]+1.45,p[2]],'contract_route_eye')
 for i,t in enumerate(contract.get('steps',[])):
  if 'footprint'in t:
   f=t['footprint'];add('tread_center_'+str(i),[(f['x_min']+f['x_max'])/2,t['top_y']+1.45,(f['z_min']+f['z_max'])/2],'contract_route_eye')
  elif 'center'in t:p=t['center'];add('step_center_'+str(i),[p[0],p[1]+1.45,p[2]],'contract_route_eye')
 if contract.get('door'):p=contract['door'];add('door_approach',[p['center_x'],p['floor_y']+1.45,p['front_z']+.4],'contract_route_eye')
 if contract.get('spawn_local'):p=contract['spawn_local'];add('spawn_eye',[p[0],p[1]+1.45,p[2]],'contract_spawn_eye')
 # Deterministic supplemental viewpoints 1.45m over upward architectural walking
 # surfaces. These are not proof of controller reachability; report separately.
 allowed=('floor','slab','landing','tread','step','deck','apron','threshold','dryrim','foundation','stairflight')
 candidates=np.where(norm[:,1]>.99)[0]
 seen=set()
 for i in candidates:
  name=meta[int(oi[i])]['name']
  if not any(s in name.lower()for s in allowed):continue
  for weights in [(1/3,1/3,1/3),(.6,.2,.2),(.2,.6,.2),(.2,.2,.6)]:
   p=(tri[i]*np.array(weights)[:,None]).sum(axis=0);key=tuple(np.round(p/.5).astype(int))
   if key in seen:continue
   seen.add(key);eye=p+np.array([0,1.45,0]);hit,_,_,dist=bvh.ray_cast(Vector(p+[0,.002,0]),Vector((0,1,0)),1.448)
   if hit is None:add(name+'_sample_'+str(i),eye,'surface_sample_eye_unproven_reachability')
 return obs

def run(name):
 start=time.time();paths=SOURCES[name];files={k:{'path':p,'sha256':sha(ROOT/p)}for k,p in zip(('source','glb','contract'),paths)}
 bpy.ops.wm.open_mainfile(filepath=str(ROOT/paths[0]));bpy.context.view_layer.update();tri,oi,fi,mi,uv,cn,meta=source_geometry();cr=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);length=np.linalg.norm(cr,axis=1);valid=length>1e-10;tri,oi,fi,mi,cr,length,uv,cn=[x[valid]for x in (tri,oi,fi,mi,cr,length,uv,cn)];norm=cr/length[:,None];dom=np.argmax(abs(norm),axis=1);sign=np.where(norm[np.arange(len(norm)),dom]<0,-1,1);canonical=norm*sign[:,None];d=np.einsum('ij,ij->i',canonical,tri[:,0]);points=tri.reshape((-1,3));bvh=BVHTree.FromPolygons(points.tolist(),np.arange(len(points)).reshape((-1,3)).tolist(),all_triangles=True,epsilon=0)
 contract=json.loads((ROOT/paths[2]).read_text());views=observers(contract,tri,norm,oi,meta,bvh);vpos=np.array([x['position']for x in views]);print('START',name,len(tri),'triangles',len(views),'observers',flush=True)
 pairdata={};tested=set();nchecks=0;plane_groups=0
 for phase in (0,.5):
  keys=np.floor(np.column_stack((canonical*10000,d*10000))+phase).astype(np.int64);order=np.lexsort(keys.T[::-1]);s=keys[order];cuts=np.r_[0,np.where(np.any(s[1:]!=s[:-1],axis=1))[0]+1,len(order)]
  for aa,bb in zip(cuts[:-1],cuts[1:]):
   if bb-aa<2:continue
   ids=order[aa:bb]
   if len(np.unique(oi[ids]))<2:continue
   plane_groups+=1;axes=[a for a in range(3)if a!=dom[ids[0]]];project=tri[ids][:,:,axes];lo=project.min(axis=1);hi=project.max(axis=1);ix=np.argsort(lo[:,0]);active=[]
   for local in ix:
    i=int(ids[local]);active=[a for a in active if hi[a,0]>lo[local,0]+1e-9]
    for prev in active:
     j=int(ids[prev]);
     if oi[i]==oi[j] or hi[prev,1]<=lo[local,1]+1e-9 or hi[local,1]<=lo[prev,1]+1e-9:continue
     ij=(min(i,j),max(i,j))
     if ij in tested:continue
     tested.add(ij);nchecks+=1
     if abs(float(np.dot(norm[i],norm[j])))<1-1e-7 or max(abs((tri[j]-tri[i,0])@norm[i]))>PLANE_EPS:continue
     p=clip([tuple(x)for x in tri[i][:,axes]],[tuple(x)for x in tri[j][:,axes]]);area=abs(signed(p))/abs(norm[i,dom[i]])
     if area<MIN_AREA:continue
     same=bool(np.dot(norm[i],norm[j])>0);a,b=sorted((int(oi[i]),int(oi[j])));key=(a,b,same)
     q=pairdata.setdefault(key,{'objects':[meta[a]['name'],meta[b]['name']],'relation':'same_facing'if same else'opposite_facing_contact','overlap_area_m2':0.,'triangle_intersections':0,'source_face_pairs':set(),'materials':set(),'samples':[],'normal':norm[i].tolist(),'exposure':[],'exposed_intersection_area_m2':0.,'trusted_view_exposed_intersection_area_m2':0.,'trusted_shading_conflict_area_m2':0.,'max_exposed_uv_delta':0.,'max_exposed_corner_normal_delta':0.})
     q['overlap_area_m2']+=area;q['triangle_intersections']+=1;q['source_face_pairs'].add((int(fi[i]),int(fi[j])));q['materials'].add((meta[int(oi[i])]['materials'][int(mi[i])],meta[int(oi[j])]['materials'][int(mi[j])]))
     if same:
      piece_exposed=False;piece_trusted=False;piece_conflict=False
      # Centroid plus inset polygon-vertex samples cover clipped strips/corners.
      pp=np.mean(p,axis=0);sample2=[pp]+[(pp+np.array(x))*0.5 for x in p[:8]]
      for pt2 in sample2:
       pt=np.zeros(3);pt[axes]=pt2;ax=int(dom[i]);pt[ax]=(np.dot(norm[i],tri[i,0])-np.dot(norm[i][axes],pt2))/norm[i,ax]
       if len(q['samples'])<20:q['samples'].append({'point':pt.tolist(),'normal':norm[i].tolist(),'area_piece_m2':area})
       if piece_trusted and len(q['exposure'])>=8:continue
       toward=vpos-pt;front=toward@norm[i]>.002;indices=np.where(front)[0]
       # Authored/route witnesses precede supplemental floor samples.
       for vi in indices:
        dist=float(np.linalg.norm(toward[vi]));direction=-toward[vi]/dist;loc,hn,idx,hd=bvh.ray_cast(Vector(vpos[vi]),Vector(direction),dist+.0002)
        if loc is not None and abs(hd-dist)<3e-4:
         def interp(k,values):
          e=(tri[k,1:]-tri[k,0]).T;bc=np.linalg.lstsq(e,pt-tri[k,0],rcond=None)[0];return values[k,0]*(1-bc.sum())+values[k,1]*bc[0]+values[k,2]*bc[1]
         u1=interp(i,uv);u2=interp(j,uv);n1=interp(i,cn);n1/=np.linalg.norm(n1);n2=interp(j,cn);n2/=np.linalg.norm(n2);ud=float(max(abs(u1-u2)));nd=float(np.linalg.norm(n1-n2));m1=meta[int(oi[i])]['materials'][int(mi[i])];m2=meta[int(oi[j])]['materials'][int(mi[j])];trusted=views[vi]['kind'] in ('authored_camera','contract_route_eye','contract_spawn_eye');conflict=m1!=m2 or ud>1e-4 or nd>1e-3;piece_exposed=True;piece_trusted|=trusted;piece_conflict|=trusted and conflict;q['max_exposed_uv_delta']=max(q['max_exposed_uv_delta'],ud);q['max_exposed_corner_normal_delta']=max(q['max_exposed_corner_normal_delta'],nd)
         witness={'source_triangles':[i,j],'source_faces':[int(fi[i]),int(fi[j])],'source_objects':[meta[int(oi[i])]['name'],meta[int(oi[j])]['name']],'normal_godot':norm[i].tolist(),'uv_pair':[u1.tolist(),u2.tolist()],'uv_delta':ud,'interpolated_corner_normal_delta':nd,'different_materials':m1!=m2,'trusted_view':trusted,'shading_conflict':conflict,'observer':views[vi],'point_godot':pt.tolist(),'distance_m':dist,'first_hit_object':meta[int(oi[idx])]['name'],'first_hit_source_face':int(fi[idx]),'first_hit_distance_error_m':abs(hd-dist)}
         if len(q['exposure'])<8 and not any(e['observer']['name']==views[vi]['name'] and e['shading_conflict']==conflict for e in q['exposure']):q['exposure'].append(witness)
         break
      if piece_exposed:q['exposed_intersection_area_m2']+=area
      if piece_trusted:q['trusted_view_exposed_intersection_area_m2']+=area
      if piece_conflict:q['trusted_shading_conflict_area_m2']+=area
    active.append(local)
 results=[]
 for q in pairdata.values():
  q['source_face_pair_count']=len(q.pop('source_face_pairs'));q['materials']=[list(x)for x in sorted(q['materials'])]
  if q['relation']=='opposite_facing_contact':q['classification']='opposite-facing structural contact; not same-facing z-fighting'
  elif q['trusted_shading_conflict_area_m2']>0:q['classification']='authored/route-view exposed same-facing overlap with material, UV or shading-normal disagreement'
  elif q['trusted_view_exposed_intersection_area_m2']>0:q['classification']='authored/route-view exposed coincident surfaces with matching sampled material, UV and normals; redundant geometry, not demonstrated shading conflict'
  elif q['exposure']:q['classification']='exposure only from supplemental surface sample; reachable-view evidence absent'
  else:q['classification']='same-facing overlap not exposed from sampled viewpoints; buried/outside/occluded or untested view'
  results.append(q)
 results.sort(key=lambda q:(not bool(q['exposure']),q['relation']!='same_facing',-q['overlap_area_m2']))
 gt,gn,go,gm=read_glb(ROOT/paths[1]);ss=geometry_signature(tri);gs=geometry_signature(gt);cons={'source':ss,'glb':gs,'same_unique_positions':ss['unique_positions_sha256_1e_5m']==gs['unique_positions_sha256_1e_5m'],'surface_area_delta_m2':gs['surface_area_m2']-ss['surface_area_m2'],'note':'Triangle diagonals may differ; stair GLB is batched by material, so source retains named-object attribution. Matching unique positions and total surface area support transfer of source findings, but are not a topology equality proof.'}
 unchanged=all(sha(ROOT/v['path'])==v['sha256']for v in files.values())
 report={'files_unchanged_during_audit':unchanged,'scene':name,'files':files,'geometry_consistency':cons,'scope':'Actual evaluated source meshes, cross-object coplanar positive-area triangle intersections. Preview water and hidden collision proxies excluded. Same-facing exposure rays tested against all visible architectural geometry, with authored cameras, contract route eyes and explicitly labelled unproven-reachability surface samples. No GPU/runtime/appearance/UV seam claim.','tolerances':{'plane_m':PLANE_EPS,'positive_area_m2':MIN_AREA,'normal_dot_error':1e-7,'ray_hit_distance_m':.0003,'broadphase':'Two offset quantized normal+plane buckets at 1e-4, exact plane recheck and 2D sweep/clipping; not a general near-coincident or noncoplanar intersection search.'},'counts':{'visible_objects':len(meta),'triangles':len(tri),'observers':len(views),'candidate_triangle_pairs':nchecks,'same_facing_object_pairs':sum(x['relation']=='same_facing'for x in results),'exposed_same_facing_object_pairs':sum(bool(x['exposure'])for x in results),'trusted_view_exposed_pairs':sum(x['trusted_view_exposed_intersection_area_m2']>0 for x in results),'trusted_shading_conflict_pairs':sum(x['trusted_shading_conflict_area_m2']>0 for x in results),'opposite_facing_contact_pairs':sum(x['relation']!='same_facing'for x in results)},'results':results,'objects':meta,'observers':views,'elapsed_seconds':time.time()-start}
 (OUT/(name+'_coplanar.json')).write_text(json.dumps(report,indent=2,default=lambda v:v.item()));print('RESULT',name,json.dumps(report['counts'],default=lambda v:v.item()),cons,'seconds',time.time()-start,flush=True)
 print('EXPOSED',name,json.dumps([{k:v for k,v in q.items()if k not in ('samples',)}for q in results if q['exposure']]),flush=True)
 return report
names=sys.argv[sys.argv.index('--')+1:]if '--'in sys.argv else list(SOURCES)
if '--config'in names:
 ci=names.index('--config');cp=ROOT/names[ci+1];SOURCES.update(json.loads(cp.read_text()));del names[ci:ci+2]
for n in names:run(n)
