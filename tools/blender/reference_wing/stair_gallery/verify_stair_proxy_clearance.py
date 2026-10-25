"""CPU ray envelope checks on actual exact collision proxy meshes, not visuals."""
import bpy,os,json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'));QA=os.path.join(ROOT,'output/reference_wing/stair')
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend'))
C=json.load(open(os.path.join(ROOT,'assets/models/reference_wing/stair_gallery.geometry.json')))
def p(v):return(v[0],-v[2],v[1])
trees={o.name:BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(f.vertices) for f in o.data.polygons],all_triangles=False) for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('COLLISION_')}
cases=[]
for side in [-.34,0,.34]:
 for h in [.05,.85,1.8,1.9]:cases.append({'kind':'small_arch_envelope','from':[1.4+side,.52+h,-3.25],'to':[1.4+side,.52+h,-4.35]})
for sample in C['connector_clear_path']['samples']:cases.append({'kind':'shifted_connector_envelope','from':sample['from'],'to':sample['to']})
for x in [-1.16,0,1.16]:
 for h in [.15,1.,1.8]:cases.append({'kind':'centred_north_portal_envelope','from':[x,.52+h,-15.8],'to':[x,.52+h,-16.2]})
checks=[]
for case in cases:
 origin=Vector(p(case['from']));delta=Vector(p(case['to']))-origin;blocked=[]
 for name,tree in trees.items():
  h=tree.ray_cast(origin,delta.normalized(),delta.length)
  if h[0] is not None:blocked.append(name)
 checks.append({**case,'blocking_proxies':blocked,'pass':not blocked})
report={'method':'Exact COLLISION_ proxy BVH ray envelope at centre and ±0.34 m shoulders, up to 1.90 m above threshold. This is not a Godot CharacterBody3D movement test.','checks':checks,'summary':{'total':len(checks),'passed':sum(c['pass'] for c in checks),'failures':sum(not c['pass'] for c in checks)}}
json.dump(report,open(os.path.join(QA,'stair_proxy_clearance_checks.json'),'w'),indent=2);print('PROXY_CLEARANCE',report['summary']);assert not report['summary']['failures']
