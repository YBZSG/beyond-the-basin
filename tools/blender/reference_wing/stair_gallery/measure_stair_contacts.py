"""Independently measure both surfaces of each source-geometry support contact."""
import bpy,os,json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'));QA=os.path.join(ROOT,'output/reference_wing/stair');path=os.path.join(ROOT,'assets/models/reference_wing/stair_gallery.geometry.json')
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend'))
C=json.load(open(path));trees={}
def p(v):return(v[0],-v[2],v[1])
def g(v):return[v[0],v[2],-v[1]]
def tree(name):
 if name not in trees:
  ob=bpy.data.objects[name];trees[name]=BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[list(f.vertices) for f in ob.data.polygons],all_triangles=False)
 return trees[name]
report={'method':'Independent BVH nearest-point measurements on both actual contact surfaces; no metadata-only gap inference','contacts':[],'failures':[]}
for rec in C['support_contacts']:
 q=Vector(p(rec['contact_point_godot']));a=tree(rec['supported']).find_nearest(q,.05);b=tree(rec['bearing']).find_nearest(q,.05)
 aa=g(a[0]) if a[0] is not None else None;bb=g(b[0]) if b[0] is not None else None;gap=(a[0]-b[0]).length if aa and bb else None
 rec.update({'supported_contact_position':aa,'bearing_contact_position':bb,'supported_surface_y':aa[1] if aa else None,'bearing_surface_y':bb[1] if bb else None,'supported_mesh_bottom_y':min(v.co.z for v in bpy.data.objects[rec['supported']].data.vertices),'measured_gap_metres':gap,'measurement':report['method']})
 record={**rec,'pass':gap is not None and gap<.006};report['contacts'].append(record)
 if not record['pass']:report['failures'].append(record)
report['summary']={'measured_contacts':len(report['contacts']),'passed':len(report['contacts'])-len(report['failures']),'maximum_gap_metres':max(r['measured_gap_metres'] or 0 for r in report['contacts']),'failure_count':len(report['failures'])}
C['independent_support_measurement']=report['summary'];json.dump(C,open(path,'w'),indent=2);json.dump(report,open(os.path.join(QA,'stair_independent_contact_checks.json'),'w'),indent=2)
print('INDEPENDENT_SUPPORTS',report['summary']);assert not report['failures']
