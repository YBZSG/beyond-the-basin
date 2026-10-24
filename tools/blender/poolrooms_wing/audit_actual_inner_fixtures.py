"""Read-only audit of actual relocated Lanes fixtures and visibility."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3];bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/blender/poolrooms_wing/source/vaulted_lanes.blend'))
p=lambda v:Vector((v[0],-v[2],v[1]));g=lambda v:[round(v[0],6),round(v[2],6),round(-v[1],6)]
contract=json.load(open(ROOT/'source_provenance/poolrooms_wing/geometry.json'))['rooms']['vaulted_lanes'];verts=[];faces=[];owners=[]
for ob in bpy.context.scene.objects:
 if ob.type!='MESH' or ob.name.startswith('COLLISION_'):continue
 off=len(verts);verts.extend(ob.matrix_world@v.co for v in ob.data.vertices)
 for f in ob.data.polygons:faces.append(tuple(off+i for i in f.vertices));owners.append(ob.name)
world=BVHTree.FromPolygons(verts,faces);rows=[]
for ob in bpy.context.scene.objects:
 if ob.type!='MESH' or not ob.name.startswith('GalleryInnerPierFixture'):continue
 cloud=[g(ob.matrix_world@v.co) for v in ob.data.vertices];lo=[min(q[a]for q in cloud)for a in range(3)];hi=[max(q[a]for q in cloud)for a in range(3)];side=-1 if lo[0]<0 else 1;z=(lo[2]+hi[2])/2
 f=min(contract['fixtures'],key=lambda f:abs(f['position'][0]-side*1.765)+abs(f['position'][2]-z));origin=Vector(f['position']);bvh=BVHTree.FromObject(ob,bpy.context.evaluated_depsgraph_get());hit,norm,face,distance=bvh.ray_cast(p(origin),p((side,0,0)),1)
 row={'object':ob.name,'housing_min':lo,'housing_max':hi,'light':f,'lens_hit':g(hit),'lens_normal':g(norm),'light_to_lens_distance':round(distance,6),'normal_faces_corridor':abs(g(norm)[0]+side)<.0001,'housing_width':round(hi[2]-lo[2],6),'pier_depth':.44,'pier_edge_margin':round((.44-(hi[2]-lo[2]))/2,6),'lens_material':ob.data.materials[ob.data.polygons[face].material_index].name,'visibility_probes':[]}
 for kind,y in [('centre_deck',.56),('vault_underside',4.42)]:
  for zz in [-7.5,-5,0,5,7.5]:
   target=Vector((0,y,zz));delta=target-origin;hit,norm,index,dist=world.ray_cast(p(origin),p(delta.normalized()),delta.length-.02)
   row['visibility_probes'].append({'kind':kind,'target':list(target),'distance':round(delta.length,4),'within_light_range':delta.length<=f['range'],'visible':hit is None,'blocked_by':owners[index]if hit else None})
 rows.append(row)
centres=[r for row in rows for r in row['visibility_probes'] if abs(r['target'][2])<.01]
report={'passed':len(rows)==4 and all(r['normal_faces_corridor'] and abs(r['housing_width']-.35)<.0001 and r['pier_edge_margin']>.044 for r in rows) and all(r['visible'] and r['within_light_range']for r in centres),'fixture_count':len(rows),'old_side_fixture_objects':sum(o.name.startswith('GalleryPoolFixture')for o in bpy.context.scene.objects),'housing_clear_corridor_width':round(min(r['housing_min'][0]for r in rows if r['housing_min'][0]>0)-max(r['housing_max'][0]for r in rows if r['housing_max'][0]<0),6),'normal_walking_headroom':round(min(r['housing_min'][1]for r in rows)-(.52+1.64),6),'fixtures':rows}
(ROOT/'tools/blender/poolrooms_wing/actual_inner_fixture_audit.json').write_text(json.dumps(report,indent=2));print('ACTUAL_FIXTURES',report['passed'],report['fixture_count'],report['old_side_fixture_objects'],report['housing_clear_corridor_width'],report['normal_walking_headroom']);print([(r['object'],r['lens_normal'],r['light_to_lens_distance'],r['lens_material'])for r in rows])
