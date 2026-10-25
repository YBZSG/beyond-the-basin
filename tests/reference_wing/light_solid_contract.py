"""Read-only physical light-sample audit of all five complete Blender sources.
No image/render/import; run Blender background after geometry owners freeze.
"""
import bpy,json,sys,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/reference_wing/light_solid_audit';OUT.mkdir(parents=True,exist_ok=True)
ROOMS={'stair_gallery':'stair_gallery/source/stair_gallery.blend','colonnade':'water_sources/colonnade.blend','cyan_corridor':'water_sources/cyan_corridor.blend','octagonal_bath':'water_sources/octagonal_bath.blend','ball_lounge':'lounge_sources/ball_lounge.blend'}
def p(v):return Vector((v[0],-v[2],v[1]))
def parity(bvh,point,direction):
 o=point.copy();count=0
 for _ in range(256):
  hit,n,idx,dist=bvh.ray_cast(o,direction,1000)
  if idx is None:return count%2
  count+=1;o=hit+direction*1e-5
 return None
DIRECTIONS=[Vector((1,.173,.391)).normalized(),Vector((-.219,1,.373)).normalized(),Vector((.281,-.173,1)).normalized()]
reports=[]
for name,relative in ROOMS.items():
 source=ROOT/'tools/blender/reference_wing'/relative;geometry=ROOT/'assets/models/reference_wing'/f'{name}.geometry.json'
 before=hashlib.sha256(source.read_bytes()).hexdigest();G=json.loads(geometry.read_text());bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene;scene.view_layers[0].update();deps=bpy.context.evaluated_depsgraph_get();solids=[]
 for ob in scene.objects:
  if ob.type!='MESH' or ob.hide_render or ob.name.startswith(('COLLISION_','PREVIEW_ONLY')):continue
  evaluated=ob.evaluated_get(deps);mesh=evaluated.to_mesh();verts=[ob.matrix_world@v.co for v in mesh.vertices];faces=[tuple(q.vertices)for q in mesh.polygons]
  if not verts or not faces:evaluated.to_mesh_clear();continue
  lo=Vector([min(v[i]for v in verts)for i in range(3)]);hi=Vector([max(v[i]for v in verts)for i in range(3)])
  solids.append((ob.name,lo,hi,BVHTree.FromPolygons(verts,faces,all_triangles=False)))
  evaluated.to_mesh_clear()
 rows=[]
 for light in G['lights']:
  if not light.get('runtime_enabled',True):continue
  at=p(light['position']);radius=float(light.get('emitter_radius',.005));d=p(light.get('direction',light.get('emission_direction',[0,0,0])))
  if d.length<1e-8 and 'target'in light:d=p(light['target'])-at
  assert d.length>1e-8,(name,light['name'],'missing direction');d.normalize()
  nearest=None;inside=[];hits=[]
  for object_name,lo,hi,bvh in solids:
   q,n,idx,dist=bvh.find_nearest(at)
   if idx is not None and(nearest is None or dist<nearest['distance_m']):nearest={'object':object_name,'distance_m':float(dist)}
   if all(lo[i]+1e-6<at[i]<hi[i]-1e-6 for i in range(3)):
    votes=[parity(bvh,at,ray)for ray in DIRECTIONS]
    if sum(v==1 for v in votes)>=2:inside.append({'object':object_name,'ray_parity_votes':votes})
   q,n,idx,dist=bvh.ray_cast(at,d,100)
   if idx is not None:hits.append({'object':object_name,'distance_m':float(dist),'normal':list(n)})
  hits.sort(key=lambda x:x['distance_m']);clear=nearest is not None and nearest['distance_m']>=radius-2e-6 and not inside
  rows.append({'name':light['name'],'position_godot':light['position'],'radius_m':radius,'nearest':nearest,'inside_actual_meshes':inside,'axis_first_hit':hits[0]if hits else None,'sphere_clear':clear})
 assert hashlib.sha256(source.read_bytes()).hexdigest()==before
 report={'room':name,'source_sha256':before,'geometry_sha256':hashlib.sha256(geometry.read_bytes()).hexdigest(),'light_count':len(rows),'lights':rows,'pass':all(x['sphere_clear']for x in rows),'scope':'Actual evaluated visible meshes, world-space nearest surface and per-object three-direction parity. Sphere bound by nearest distance; no GPU/light brightness inference.'}
 (OUT/f'{name}.json').write_text(json.dumps(report,indent=2));reports.append(report);print('LIGHT_SOLID',name,report['pass'],len(rows),flush=True)
summary={'rooms':reports,'pass':all(r['pass']for r in reports),'rendered':False,'native_gpu':False};(OUT/'summary.json').write_text(json.dumps(summary,indent=2));print('LIGHT_SOLID_FINAL',summary['pass'],flush=True)
if not summary['pass']:raise RuntimeError('One or more actual source light samples intersects solid geometry; inspect report')
