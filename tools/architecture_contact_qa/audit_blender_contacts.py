"""Read-only complete-room source-mesh contact and cross-section inspection.
Never saves or modifies its input .blend. All output paths must be explicit.
Blender 4.3.2: blender -b --factory-startup -t 2 --python THIS -- --input-root ROOT --output-root ROOT
World axes in reports are Godot X,Y(up),Z. Internal ray math is Blender X,Y,Z(up).
"""
import bpy,bmesh,sys,os,json,math,argparse,hashlib
from mathutils import Vector
from mathutils.bvhtree import BVHTree
p=argparse.ArgumentParser();p.add_argument('--input-root',required=True);p.add_argument('--output-root',required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);os.makedirs(a.output_root,exist_ok=True)
EPS=.0005;TOL=.002

def g(v):return [round(float(v[0]),6),round(float(v[2]),6),round(float(-v[1]),6)]
def vector(v):return [round(float(c),6) for c in v]
def target(name):
 return any(k in name for k in ['Cenji','LanePierFooting','InnerPearlDado','InnerOysterPlaster','PortalJamb','OuterNorth','OuterWest','RestNicheDividerWing','PoolCoping','ShallowBasinStair','CommonEntryStep','ArcadeRoofConnection','OriginalContinuous','SolidRoofNotLightPanel','RealSkylightReveal','InnerPortalHeader','ApronRoof','VestibuleTransition']) and 'Fixture' not in name

def type_of(name):
 if 'SubmergedFooting' in name:return 'foundation_footing'
 if 'CenjiLaneRib' in name or 'CenjiCourtArcade' in name:return 'arch_feet'
 if 'Bench' in name:return 'bench_feet'
 if 'Divider' in name or 'Alcove' in name or 'CircularGateway' in name or 'Footing' in name:return 'divider_wall_feet'
 if 'Coping' in name:return 'coping_bedding'
 if 'Stair' in name or 'Step' in name:return 'stair_bedding'
 if any(x in name for x in ['Roof','Vault','Header','Reveal','VestibuleTransition']):return 'spanning_or_upper_member'
 return 'wall_bedding'

for room in ['crescent_court','vaulted_lanes','circular_bath']:
 path=os.path.join(a.input_root,'tools/blender/poolrooms_wing/source',room+'.blend')
 before=hashlib.sha256(open(path,'rb').read()).hexdigest();bpy.ops.wm.open_mainfile(filepath=path)
 obs=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.name.startswith('COLLISION_') and 'water' not in o.name.lower()]
 meshes={};object_rows=[];uv_bad=[];normal_bad=[];triangle_keys=[]
 for o in obs:
  verts=[o.matrix_world@v.co for v in o.data.vertices];faces=[tuple(f.vertices) for f in o.data.polygons];bvh=BVHTree.FromPolygons(verts,faces,all_triangles=False)
  lo=Vector([min(v[i] for v in verts) for i in range(3)]);hi=Vector([max(v[i] for v in verts) for i in range(3)])
  meshes[o.name]=(o,verts,faces,bvh,lo,hi)
  for face in faces:
   for j in range(1,len(face)-1):
    triangle_keys.append(tuple(sorted(tuple(round(c*10000) for c in (verts[i].x,verts[i].z,-verts[i].y)) for i in (face[0],face[j],face[j+1]))))
  bm=bmesh.new();bm.from_mesh(o.data);boundary=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges);inconsistent=sum(e.is_manifold and not e.is_contiguous for e in bm.edges);volume=bm.calc_volume(signed=True);bm.free()
  uv=o.data.uv_layers.active;rat=[]
  if uv:
   for f in o.data.polygons:
    for k,li in enumerate(f.loop_indices):
     lj=f.loop_indices[(k+1)%len(f.loop_indices)];v1=verts[o.data.loops[li].vertex_index];v2=verts[o.data.loops[lj].vertex_index];dd=(v2-v1).length
     if dd>1e-6:rat.append((uv.data[lj].uv-uv.data[li].uv).length/dd)
  ratio=[min(rat),max(rat)] if rat else None
  if ratio and (ratio[0]<.998 or ratio[1]>1.002):uv_bad.append({'object':o.name,'uv_to_mesh_edge_ratio_bounds':ratio})
  if volume<-.00001:normal_bad.append({'object':o.name,'signed_volume':volume})
  object_rows.append({'name':o.name,'bounds_min':g(Vector((lo.x,hi.y,lo.z))),'bounds_max':g(Vector((hi.x,lo.y,hi.z))),'vertices':len(verts),'polygons':len(faces),'boundary_edges':boundary,'nonmanifold_edges':nonmanifold,'signed_volume':round(volume,6),'inconsistently_oriented_edges':inconsistent,'matrix_world':[list(r) for r in o.matrix_world],'uv_edge_ratio_bounds':ratio})
 def hit(point,exclude,direction=(0,0,-1),maxdist=50):
  candidates=[];start=Vector(point)+Vector((0,0,EPS if direction[2]<0 else -EPS));d=Vector(direction)
  for nm,(o,vs,fs,bv,lo,hi) in meshes.items():
   if nm==exclude:continue
   if not(lo.x-1e-6<=point.x<=hi.x+1e-6 and lo.y-1e-6<=point.y<=hi.y+1e-6):continue
   h,n,idx,dist=bv.ray_cast(start,d,maxdist)
   if h is None:continue
   raw=dist-EPS;relation='touching' if abs(raw)<=TOL else 'gap';signed=raw;penetration=0.
   # Classify each candidate before choosing a receiver. An embedded footing
   # exits BasinBottom at -.72, coplanar with CommonFoundation's upper face;
   # choosing the nearest ray alone could incorrectly select CommonFoundation.
   if direction[2]<0 and n.z<-.5:
    up,un,ui,ud=bv.ray_cast(start,Vector((0,0,1)),maxdist)
    if up is not None and un.z>.5:
     penetration=max(0.,up.z-point.z);signed=-penetration;relation='embedded' if penetration>TOL else 'touching'
   row={'receiver':nm,'hit':g(h),'gap_m':round(signed,6),'raw_ray_distance_m':round(raw,6),'relation':relation,'penetration_m':round(penetration,6),'receiver_normal':g(n)}
   candidates.append((0. if signed<=TOL else signed,abs(signed),nm,row))
  if candidates:return min(candidates,key=lambda x:x[:3])[3]
  return {'receiver':None,'hit':None,'gap_m':None}

 contacts=[]
 for nm,(o,vs,fs,bv,lo,hi) in meshes.items():
  if not target(nm):continue
  pts=[]
  for f in o.data.polygons:
   fp=[vs[i] for i in f.vertices];n=o.matrix_world.to_3x3()@f.normal
   if n.z<-.8 and max(v.z for v in fp)<=lo.z+.003:
    c=sum(fp,Vector())/len(fp);pts.append(c)
    for v in fp:pts.append(c*.25+v*.75)
  # The capsule has a curved bottom; retain real lowest vertices if no planar foot exists.
  if not pts:pts=[v for v in vs if v.z<=lo.z+.0001]
  seen=set();samples=[]
  for pt in pts:
   key=tuple(round(c,5) for c in pt)
   if key in seen:continue
   seen.add(key);r=hit(pt,nm);samples.append({'foot':g(pt),**r})
  # Upward bearing checks sample real top surface, not an arch's hollow bbox centre.
  tops=[]
  if type_of(nm) in ['arch_feet','divider_wall_feet','wall_bedding']:
   for f in o.data.polygons:
    fp=[vs[i] for i in f.vertices];n=o.matrix_world.to_3x3()@f.normal
    if n.z>.8 and min(v.z for v in fp)>=hi.z-.003:
     c=sum(fp,Vector())/len(fp);tops.append({'top':g(c),**hit(c,nm,direction=(0,0,1))})
  gaps=[r['gap_m'] for r in samples if r['gap_m'] is not None]
  contacts.append({'object':nm,'kind':type_of(nm),'base_y':round(lo.z,6),'top_y':round(hi.z,6),'sample_count':len(samples),'contact_count':sum(r['gap_m'] is not None and r['gap_m']<=TOL for r in samples),'open_ray_count':sum(r['gap_m'] is None for r in samples),'gap_min_m':min(gaps) if gaps else None,'gap_max_m':max(gaps) if gaps else None,'samples':samples,'top_samples':tops})
 # Conditional assembled-module check: translate the actual source foundation
 # mesh by one 32 m cell. This does not claim a native instance was observed.
 seam_contacts=[]
 foundation=next((v for k,v in meshes.items() if k.startswith('CommonFoundation')),None)
 if foundation:
  for c in contacts:
   if not(c['object'].startswith('OuterNorth_') or c['object'].startswith('OuterWest_')):continue
   offset=Vector((0,32,0)) if c['object'].startswith('OuterNorth_') else Vector((-32,0,0))
   bv=BVHTree.FromPolygons([v+offset for v in foundation[1]],foundation[2],all_triangles=False)
   for sample in c['samples']:
    if sample['receiver'] is not None:continue
    q=sample['foot'];point=Vector((q[0],-q[2],q[1]));h,n,idx,dist=bv.ray_cast(point+Vector((0,0,EPS)),Vector((0,0,-1)),50)
    seam_contacts.append({'object':c['object'],'foot':q,'conditional_receiver':'CommonFoundation_001 translated to adjacent north/west cell','neighbor_translation_godot':g(offset),'gap_m':round(dist-EPS,6) if h is not None else None,'actual_native_neighbor_observed':False})
 # Exact plane/triangle intersections, not bbox approximation. Plane in Godot axes.
 section_specs=[('lane_rib_cross','z',2.5),('lane_longitudinal','x',7/3),('entry_transition_section','x',0.)] if room=='vaulted_lanes' else ([('court_arcade_longitudinal','x',5.25),('court_pool_cross','z',0.),('entry_transition_section','x',0.)] if room=='crescent_court' else [('bath_gateway_longitudinal','x',2.1),('bath_pool_cross','z',0.),('entry_transition_section','x',0.)])
 section_specs += [('portal_jamb_section','x',2.3),('outer_boundary_section','x',10.)]
 sections=[]
 for label,axis,value in section_specs:
  ai=0 if axis=='x' else 1;val=value if ai==0 else -value;segs=[]
  for nm,(o,vs,fs,bv,lo,hi) in meshes.items():
   if not lo[ai]-1e-6<=val<=hi[ai]+1e-6:continue
   for face in fs:
    # Sources triangulated; also supports generic quads fan-triangulated read-only.
    for j in range(1,len(face)-1):
     tri=[vs[face[0]],vs[face[j]],vs[face[j+1]]];pts=[]
     for k in range(3):
      va=tri[k];vb=tri[(k+1)%3];da=va[ai]-val;db=vb[ai]-val
      if abs(da)<1e-7:pts.append(va)
      if da*db<0:pts.append(va+(vb-va)*(da/(da-db)))
     unique=[]
     for pt in pts:
      if not any((pt-p).length<1e-6 for p in unique):unique.append(pt)
     if len(unique)==2:segs.append({'object':nm,'points':[g(p) for p in unique]})
  sections.append({'label':label,'plane_axis':axis,'plane_value_m':value,'segments':segs})
 # Collision match for exact named boxes; special source proxies reported separately.
 collision=[]
 for o in bpy.context.scene.objects:
  if o.type!='MESH' or not o.name.startswith('COLLISION_'):continue
  vs=[o.matrix_world@v.co for v in o.data.vertices];lo=[min(v[i] for v in vs) for i in range(3)];hi=[max(v[i] for v in vs) for i in range(3)];nm=o.name[len('COLLISION_'):]
  r={'object':o.name,'visual_name':nm,'bounds_min':g(Vector((lo[0],hi[1],lo[2]))),'bounds_max':g(Vector((hi[0],lo[1],hi[2])))}
  if nm in meshes:
   other=meshes[nm];r['exact_visual_bounds_max_error_m']=round(max(abs(lo[i]-other[4][i]) for i in range(3)) if False else max([abs(lo[i]-other[4][i]) for i in range(3)]+[abs(hi[i]-other[5][i]) for i in range(3)]),7)
  collision.append(r)
 report={'room':room,'input_blend':path,'input_sha256':before,'method':'Actual transformed mesh lower-face samples, rays downward excluding own object, COLLISION_ meshes and water-named meshes. Water surfaces are absent in source; BasinBottom is a solid receiver and is retained. Upper member rays measure geometric space, not whether a clear span is structurally invalid. Tolerance 0.002 m. Exact mesh plane intersections for sections. No Godot launched.','coordinate_system':'Godot X,Y(up),Z; source Blender converted (x,z,-y)','visual_triangle_count':len(triangle_keys),'visual_triangle_geometry_sha256_0_1mm':hashlib.sha256(repr(sorted(triangle_keys)).encode()).hexdigest(),'objects':object_rows,'contacts':contacts,'sections':sections,'collisions':collision,'conditional_neighbor_foundation_contacts':seam_contacts,'uv_failures':uv_bad,'negative_volume_objects':normal_bad,'scene_contract':json.loads(bpy.context.scene.get('room_contract','{}'))}
 assert hashlib.sha256(open(path,'rb').read()).hexdigest()==before
 with open(os.path.join(a.output_root,room+'.json'),'w') as f:json.dump(report,f,indent=2)
 print('AUDIT_ROOM',room,'objects',len(obs),'targets',len(contacts),'uv_failures',len(uv_bad),'negative_volumes',len(normal_bad),flush=True)
 for c in contacts:
  if c['kind'] in ['arch_feet','bench_feet','divider_wall_feet'] or (c['kind']=='wall_bedding' and c['gap_min_m'] and c['gap_min_m']>.002):
   print('FOOT',c['object'],c['kind'],'base',c['base_y'],'gap',c['gap_min_m'],c['gap_max_m'],'contact',c['contact_count'],'/',c['sample_count'],'receivers',sorted(set(s['receiver'] or 'none' for s in c['samples'])),flush=True)
