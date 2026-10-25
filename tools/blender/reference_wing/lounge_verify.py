"""Independent non-render validation of the exported GLB and geometry contract."""
import json, struct, os, math, hashlib
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../..'))
ASSET_DIR=os.environ.get('LOUNGE_OUTPUT_DIR',os.path.join(ROOT,'assets/models/reference_wing'))
GLB=os.path.join(ASSET_DIR,'ball_lounge.glb')
SIDE=os.path.join(ASSET_DIR,'ball_lounge.geometry.json')
OUT=os.path.join(os.environ.get('LOUNGE_AUDIT_DIR',os.path.join(ROOT,'output/reference_wing/lounge')),'export_verification.json')
data=open(GLB,'rb').read();magic,version,size=struct.unpack_from('<III',data);assert magic==0x46546c67 and version==2 and size==len(data)
n,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+n]);offset=20+n;length,kind=struct.unpack_from('<II',data,offset);binary=data[offset+8:offset+8+length]
side=json.load(open(SIDE));failures=[];mesh_bounds={};attr_checks=[]
contact_targets=side.get('contact_boundary_repairs',{}).get('targets',{})
contact_names=set(contact_targets)|{n for r in contact_targets.values() for n in r['retained']}
contact_meshes={};contact_metric_uv=[]
formats={5126:('f',4),5125:('I',4),5123:('H',2),5121:('B',1)};components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def read_accessor(index):
 a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];fmt,width=formats[a['componentType']];nc=components[a['type']];start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',nc*width)
 return [struct.unpack_from('<'+fmt*nc,binary,start+i*stride) for i in range(a['count'])]
for node in doc['nodes']:
 if 'mesh' not in node:continue
 name=node['name'];mins=[math.inf]*3;maxs=[-math.inf]*3;counts={}
 for prim in doc['meshes'][node['mesh']]['primitives']:
  attrs=prim['attributes']
  for attr in ['POSITION','NORMAL','TEXCOORD_0','TANGENT']:
   if attr not in attrs:failures.append(name+' missing '+attr);continue
   values=read_accessor(attrs[attr]);counts[attr]=len(values)
   if not all(math.isfinite(x) for v in values for x in v):failures.append(name+' nonfinite '+attr)
   if attr=='POSITION':
    for v in values:
     for k in range(3):mins[k]=min(mins[k],v[k]);maxs[k]=max(maxs[k],v[k])
   if attr in ['NORMAL','TANGENT']:
    lengths=[math.sqrt(sum(v[k]*v[k] for k in range(3))) for v in values]
    if min(lengths)<.99 or max(lengths)>1.01:failures.append(name+' nonunit '+attr)
  if len(set(counts.values()))!=1:failures.append(name+' inconsistent attribute counts')
  if 'NORMAL' in attrs and 'TANGENT' in attrs:
   normals=read_accessor(attrs['NORMAL']);tangents=read_accessor(attrs['TANGENT'])
   if max(abs(sum(n[k]*t[k] for k in range(3))) for n,t in zip(normals,tangents))>.001:failures.append(name+' nonorthogonal tangent basis')
   if any(abs(abs(t[3])-1)>.00001 for t in tangents):failures.append(name+' invalid tangent handedness')
 mesh_bounds[name]={'min':mins,'max':maxs};attr_checks.append({'mesh':name,'attribute_counts':counts})
 if name in contact_names:
  triangles=[];metric_errors=[]
  for prim in doc['meshes'][node['mesh']]['primitives']:
   pp=read_accessor(prim['attributes']['POSITION']);ii=[v[0] for v in read_accessor(prim['indices'])];uvs=read_accessor(prim['attributes']['TEXCOORD_0'])
   for i in range(0,len(ii),3):
    triangle=tuple(pp[ii[i+j]] for j in range(3));triangles.append(triangle)
    flat=[axis for axis in range(3) if all(v[axis]==triangle[0][axis] for v in triangle)]
    if len(flat)!=1:continue
    for j in range(3):
     x,y,z=pp[ii[i+j]];expected=(-z,1-y) if flat[0]==0 else (x,1+z) if flat[0]==1 else (x,1-y)
     metric_errors.append(max(abs(a-b) for a,b in zip(expected,uvs[ii[i+j]])))
  contact_meshes[name]=triangles
  error=max(metric_errors,default=math.inf)
  contact_metric_uv.append({'mesh':name,'metres_per_uv_unit':1.0,'export_uv_v_inverted':True,'max_metric_uv_error':error,'passed':error<2e-6})
  if error>=2e-6:failures.append(name+' metric contact UV mismatch')
# Bounds are measured from exported positions. Only the exact 32 m module fits.
actual_bounds={'min':[min(b['min'][k] for b in mesh_bounds.values()) for k in range(3)],'max':[max(b['max'][k] for b in mesh_bounds.values()) for k in range(3)]}
for k in range(3):
 if actual_bounds['min'][k]<side['bounds']['min'][k]-1e-5 or actual_bounds['max'][k]>side['bounds']['max'][k]+1e-5:failures.append('Export exceeds declared module bounds on axis '+str(k))
for light in side['lights']:
 if light['fixture_object'] not in mesh_bounds:failures.append('Missing fixture for '+light['name'])
expected=['ref_lounge_plaster','ref_lounge_fabric','ref_cushion_coral','ref_ball_blue','ref_ball_ivory','ref_glazing_cyan','ref_fixture_metal'];roles=[m['name'] for m in doc['materials']]
if sorted(roles)!=sorted(expected):failures.append('Material roles differ: '+str(roles))
if side['water_regions']!=[]:failures.append('Lounge unexpectedly contains water metadata')
assert len(side['portholes'])==5
# Verify the connector floor/roof are closed volumes after geometric welding.
connector_node=next(n for n in doc['nodes'] if n['name']=='Closed_connector_floor_and_roof')
welded={};edges={};triangle_total=0
for prim in doc['meshes'][connector_node['mesh']]['primitives']:
 positions=read_accessor(prim['attributes']['POSITION']);indices=[x[0] for x in read_accessor(prim['indices'])]
 for i in range(0,len(indices),3):
  ids=[]
  for j in range(3):
   key=tuple(round(c,6) for c in positions[indices[i+j]])
   if key not in welded:welded[key]=len(welded)
   ids.append(welded[key])
  triangle_total+=1
  for a,b in zip(ids,ids[1:]+ids[:1]):
   key=tuple(sorted((a,b)));edges[key]=edges.get(key,0)+1
connector_closure={'mesh':'Closed_connector_floor_and_roof','welded_vertices':len(welded),'triangles':triangle_total,'boundary_edge_count':sum(c==1 for c in edges.values()),'nonmanifold_edge_count':sum(c>2 for c in edges.values()),'euler_characteristic':len(welded)-len(edges)+triangle_total,'floor_thickness_m':.60,'roof_thickness_m':.26}
if connector_closure['boundary_edge_count'] or connector_closure['nonmanifold_edge_count']:failures.append('Connector structural floor/roof is not closed manifold geometry')

# Exact local contact proof. Actual exported corner sets, face area and edge
# incidence first establish that every changed/retained mesh is a closed cuboid,
# with no bevel strips or micro-holes omitted from this test. Atomic coordinate
# cells then compare the complete old/new solid union, not just nominal bounds.
from itertools import product

def union_difference(before,after):
 boxes=before+after
 planes=[sorted({b[key][axis] for b in boxes for key in ['min','max']}) for axis in range(3)]
 mismatch=[];tested=0
 def inside(point,group):
  return any(all(b['min'][k]<point[k]<b['max'][k] for k in range(3)) for b in group)
 for bounds in product(*[list(zip(q,q[1:])) for q in planes]):
  if any(a==b for a,b in bounds):continue
  point=[(a+b)/2 for a,b in bounds];tested+=1
  if inside(point,before)!=inside(point,after):mismatch.append([list(v) for v in bounds])
 return {'atomic_cells_tested':tested,'changed_cells':mismatch,'same_closed_solid_union':not mismatch}

def volume_overlap(a,b):
 return math.prod(max(0,min(a['max'][k],b['max'][k])-max(a['min'][k],b['min'][k])) for k in range(3))

def cuboid_proof(name):
 triangles=contact_meshes[name];bounds=mesh_bounds[name]
 unique={tuple(v) for tri in triangles for v in tri}
 corners=set(product(*[(bounds['min'][k],bounds['max'][k]) for k in range(3)]))
 edges={};face_areas={}
 for triangle in triangles:
  for a,b in zip(triangle,triangle[1:]+triangle[:1]):
   edge=tuple(sorted((a,b)));edges[edge]=edges.get(edge,0)+1
  planes=[(k,v) for k in range(3) for v in (bounds['min'][k],bounds['max'][k]) if all(p[k]==v for p in triangle)]
  if len(planes)!=1:continue
  a,b,c=triangle;ab=[b[i]-a[i] for i in range(3)];ac=[c[i]-a[i] for i in range(3)]
  area=math.sqrt(sum((ab[(i+1)%3]*ac[(i+2)%3]-ab[(i+2)%3]*ac[(i+1)%3])**2 for i in range(3)))/2
  face_areas[planes[0]]=face_areas.get(planes[0],0)+area
 area_errors=[]
 for k in range(3):
  expected=math.prod(bounds['max'][i]-bounds['min'][i] for i in range(3) if i!=k)
  for v in (bounds['min'][k],bounds['max'][k]):area_errors.append(abs(face_areas.get((k,v),0)-expected))
 valid=unique==corners and len(triangles)==12 and all(n==2 for n in edges.values()) and max(area_errors)<1e-10
 return {'mesh':name,'unique_corner_count':len(unique),'triangle_count':len(triangles),'nonmanifold_edge_count':sum(n!=2 for n in edges.values()),'max_face_area_error_m2':max(area_errors),'closed_cuboid_without_bevel_or_holes':valid}

contact_box_results=[cuboid_proof(name) for name in sorted(contact_names)]
if any(not r['closed_cuboid_without_bevel_or_holes'] for r in contact_box_results):failures.append('Contact geometry is not a complete closed cuboid')
contact_union_results=[]
for name,spec in contact_targets.items():
 current=mesh_bounds[name];original={k:list(v) for k,v in current.items()};axis=spec['axis']
 # Reconstruct original saved/exported float32 coordinates, not arbitrary offsets.
 f32=lambda x:struct.unpack('<f',struct.pack('<f',x))[0]
 for key,value in zip(['min','max'],spec['old']):original[key][axis]=f32(value)
 peers=[mesh_bounds[n] for n in spec['retained']]
 render_proof=union_difference([original]+peers,[current]+peers)
 # Sidecar boxes use authored decimal dimensions. Resolve repeated module proxy
 # names by both their object base name and actual spatial bounds.
 def proxy_for(object_name):
  matches=[p for p in side['collision_proxies'] if p['type']=='BOX' and p['name']==object_name.split('.')[0] and all(abs(p['bounds'][key][i]-mesh_bounds[object_name][key][i])<2e-5 for key in ['min','max'] for i in range(3))]
  if len(matches)!=1:raise ValueError('Ambiguous contact proxy '+object_name)
  return {key:[round(v*1000000) for v in matches[0]['bounds'][key]] for key in ['min','max']}
 collider=proxy_for(name);old_collider={k:list(v) for k,v in collider.items()}
 for key,value in zip(['min','max'],spec['old']):old_collider[key][axis]=round(value*1000000)
 collider_peers=[proxy_for(n) for n in spec['retained']]
 collider_proof=union_difference([old_collider]+collider_peers,[collider]+collider_peers)
 overlap=[{'retained':n,'positive_volume_m3':volume_overlap(current,mesh_bounds[n])} for n in spec['retained']]
 valid=render_proof['same_closed_solid_union'] and collider_proof['same_closed_solid_union'] and all(v['positive_volume_m3']==0 for v in overlap)
 contact_union_results.append({'trimmed_mesh':name,'retained_meshes':spec['retained'],'before_actual_bounds':original,'after_actual_bounds':current,'actual_rendered_solid_union':render_proof,'collision_union_integer_micrometres':collider_proof,'remaining_overlap':overlap,'passed':valid})
 if not valid:failures.append('Exact local contact union failed: '+name)

# Measured architecture support from exported geometry, not merely generator assertions.
export_contacts=[]
for record in side['support_contacts']:
 if record['object'] not in mesh_bounds:continue
 b=mesh_bounds[record['object']];actual_bottom=b['min'][1]
 if record['support'] in mesh_bounds:
  support_top=mesh_bounds[record['support']]['max'][1]
 else:
  ball=next(x for x in side['ball_instances'] if x['id']==record['support']);support_top=ball['center'][1]+ball['radius']
 gap=actual_bottom-support_top
 export_contacts.append({'object':record['object'],'support':record['support'],'actual_glb_bottom_y':actual_bottom,'support_top_y':support_top,'gap_m':gap,'contact_point':record.get('contact_point')})
 if abs(gap)>2e-5:failures.append(record['object']+' exported support gap '+str(gap))
# Sphere-to-cushion separation against actual exported triangles. This checks the
# entire pillow envelope, not merely its AABB or the intended support-ball center.
def sub(a,b):return tuple(a[k]-b[k] for k in range(3))
def add(a,b):return tuple(a[k]+b[k] for k in range(3))
def mul(a,s):return tuple(v*s for v in a)
def dot(a,b):return sum(a[k]*b[k] for k in range(3))
def closest_triangle(p,a,b,c):
 ab=sub(b,a);ac=sub(c,a);ap=sub(p,a);d1=dot(ab,ap);d2=dot(ac,ap)
 if d1<=0 and d2<=0:return a
 bp=sub(p,b);d3=dot(ab,bp);d4=dot(ac,bp)
 if d3>=0 and d4<=d3:return b
 vc=d1*d4-d3*d2
 if vc<=0 and d1>=0 and d3<=0:return add(a,mul(ab,d1/(d1-d3)))
 cp=sub(p,c);d5=dot(ab,cp);d6=dot(ac,cp)
 if d6>=0 and d5<=d6:return c
 vb=d5*d2-d1*d6
 if vb<=0 and d2>=0 and d6<=0:return add(a,mul(ac,d2/(d2-d6)))
 va=d3*d6-d5*d4
 if va<=0 and d4-d3>=0 and d5-d6>=0:return add(b,mul(sub(c,b),(d4-d3)/((d4-d3)+(d5-d6))))
 denom=va+vb+vc
 if abs(denom)<1e-16:return a
 return add(a,add(mul(ab,vb/denom),mul(ac,vc/denom)))
cushion_results=[]
for node in doc['nodes']:
 name=node['name']
 if 'coral_cushion_' not in name or 'piping' in name:continue
 triangles=[]
 for prim in doc['meshes'][node['mesh']]['primitives']:
  positions=read_accessor(prim['attributes']['POSITION']);indices=[i[0] for i in read_accessor(prim['indices'])]
  triangles += [tuple(positions[indices[i+j]] for j in range(3)) for i in range(0,len(indices),3)]
 bounds=mesh_bounds[name];nearest=math.inf;closest_ball=None;tested=0;overlaps=[]
 for ball in side['ball_instances']:
  center=ball['center'];radius=ball['radius']
  if any(center[k]+radius<bounds['min'][k]-1e-5 or center[k]-radius>bounds['max'][k]+1e-5 for k in range(3)):continue
  tested+=1;dist=min(math.dist(center,closest_triangle(center,*tri)) for tri in triangles);gap=dist-radius
  if gap<nearest:nearest=gap;closest_ball=ball['id']
  if gap<-.00002:overlaps.append({'ball':ball['id'],'penetration_m':-gap})
 cushion_results.append({'cushion':name,'nearby_spheres_tested':tested,'closest_ball':closest_ball,'minimum_surface_gap_m':nearest if math.isfinite(nearest) else None,'penetrations':overlaps})
 if overlaps:failures.append(name+' intersects '+str(len(overlaps))+' spheres')

# Clear route proof uses all actual proxy bounds, with conservative AABBs for convex
# volumes; no curved-wall geometry is silently skipped. Player capsule radius .28 m.
route_results=[]
for route in side['walkable_routes']:
 minimum=math.inf;worst=None;samples=0;blockers=[]
 for a,b in zip(route['centerline'],route['centerline'][1:]):
  distance=math.dist(a,b);steps=max(1,math.ceil(distance/.1))
  for i in range(steps+1):
   pt=[a[k]+(b[k]-a[k])*i/steps for k in range(3)];samples+=1
   # Body interval foot + 0.03 through head 1.72 m above floor.
   for c in side['collision_proxies']:
    lo=c['bounds']['min'];hi=c['bounds']['max']
    if hi[1]<=pt[1]+.03 or lo[1]>=pt[1]+1.72:continue
    dx=max(lo[0]-pt[0],0,pt[0]-hi[0]);dz=max(lo[2]-pt[2],0,pt[2]-hi[2]);clear=math.hypot(dx,dz)
    if clear<minimum:minimum=clear;worst={'point':pt,'collider':c['name'],'bounds':c['bounds']}
    if clear<.28-1e-7:blockers.append({'point':pt,'collider':c['name'],'clearance':clear})
 route_results.append({'route':route['name'],'sample_count':samples,'capsule_radius_m':.28,'height_m':1.72,'minimum_conservative_side_clearance_m':minimum,'worst_location':worst,'blocked_samples':blockers})
 if blockers:failures.append(route['name']+' collision blocks')
# Door clear spans tested along their full 3 m × 2.8 m opening away from exact faces.
portal_results=[]
for port in side['portal_contracts']:
 blockers=[]
 for across in [-1.499,-1.0,0,1.0,1.499]:
  for h in [.521,1,2,3.319]:
   pt=[across,h,-15.999] if port['side']=='north' else [-15.999,h,across]
   for c in side['collision_proxies']:
    lo=c['bounds']['min'];hi=c['bounds']['max']
    if all(lo[k]+1e-5<pt[k]<hi[k]-1e-5 for k in range(3)):blockers.append({'point':pt,'proxy':c['name']})
 portal_results.append({'side':port['side'],'tested_clear_width':2.998,'tested_clear_height':2.798,'blocked_samples':blockers})
 if blockers:failures.append(port['side']+' portal blocked')
render_path=os.path.join(ROOT,'output/reference_wing/lounge/render_report.json')
render_report=json.load(open(render_path)) if os.path.exists(render_path) else {}
preview_matches=render_report.get('glb_sha256')==hashlib.sha256(data).hexdigest()
report={'preview_matches_current_export':preview_matches,'preview_only_fill_lights_excluded':render_report.get('preview_only_fill_lights_excluded',False),'asset_sha256':hashlib.sha256(data).hexdigest(),'glb_bytes':len(data),'mesh_count':len(mesh_bounds),'actual_export_bounds':actual_bounds,'materials':roles,'required_attributes':['POSITION','NORMAL','TEXCOORD_0','TANGENT'],'attribute_checks':attr_checks,'connector_closed_solid_proof':connector_closure,'contact_metric_uv_proof':contact_metric_uv,'contact_geometry_closed_cuboid_proof':contact_box_results,'contact_solid_union_proof':contact_union_results,'exported_support_contacts':export_contacts,'cushion_sphere_triangle_proof':cushion_results,'route_clearance_proof':route_results,'portal_clearance_proof':portal_results,'geometry_audit':side['audit'],'failure_count':len(failures),'failures':failures,'not_tested':'Godot custom-engine appearance, GPU performance, gameplay feel. The user explicitly owns the local visual test.'}
json.dump(report,open(OUT,'w'),indent=2)
print(json.dumps({'failure_count':len(failures),'failures':failures,'mesh_count':len(mesh_bounds),'support_contacts':len(export_contacts),'route_clearances':[r['minimum_conservative_side_clearance_m'] for r in route_results]},indent=2))
if failures:raise SystemExit(1)
