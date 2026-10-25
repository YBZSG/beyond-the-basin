"""Exact, new-room-only water bathymetry reference. No AABB top-height shortcuts.
This is a geometry recipe/QA probe, not a replacement runtime water implementation.
"""
import json,math,struct,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[3]

def contains_convex_xz(p,polygon,epsilon=1e-6):
    signs=[]
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        signs.append((b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0]))
    return min(signs)>=-epsilon or max(signs)<=epsilon

def evaluate_step_floor(contract,x,z):
    point=[x,z]
    regions=[r for r in contract['water_regions'] if contains_convex_xz(point,r['polygon_xz'])]
    if not regions:return {'wet':False,'reason':'outside actual water polygon'}
    if any(contains_convex_xz(point,e['polygon_xz']) for e in contract['water_exclusions']):
        return {'wet':False,'reason':'solid exclusion at water surface'}
    floor=max(r['bottom_y']for r in regions)
    containing=[]
    for step in contract.get('water_steps',contract['steps']):
        if contains_convex_xz(point,step['footprint_xz']):
            floor=max(floor,step['top_y']);containing.append(step.get('object',step.get('name')))
    water=max(r['surface_y']for r in regions)
    return {'wet':floor<water,'floor_y':round(floor,6),'depth_m':round(max(0,water-floor),6),'steps_containing_point':containing}

def glb_horizontal_collider_floor(path,x,z):
    raw=path.read_bytes();off=12;doc=None;binary=None
    while off<len(raw):
        size,typ=struct.unpack_from('<II',raw,off);chunk=raw[off+8:off+8+size];off+=8+size
        if typ==0x4e4f534a:doc=json.loads(chunk)
        elif typ==0x004e4942:binary=chunk
    def access(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];fmt='<'+{5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]*{'SCALAR':1,'VEC3':3}[a['type']];stride=v.get('byteStride',struct.calcsize(fmt));start=v.get('byteOffset',0)+a.get('byteOffset',0)
        return [struct.unpack_from(fmt,binary,start+i*stride)for i in range(a['count'])]
    hit=-math.inf
    for node in doc['nodes']:
        if not node.get('name','').startswith('COLLISION_')or'mesh'not in node:continue
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            p=access(primitive['attributes']['POSITION']);indices=[t[0]for t in access(primitive['indices'])]
            for i in range(0,len(indices),3):
                verts=[p[k]for k in indices[i:i+3]];ys=[v[1]for v in verts]
                if max(ys)-min(ys)>1e-6 or max(ys)>.320001:continue
                poly=[[v[0],v[2]]for v in verts]
                area=(poly[1][0]-poly[0][0])*(poly[2][1]-poly[0][1])-(poly[1][1]-poly[0][1])*(poly[2][0]-poly[0][0])
                if abs(area)<1e-8:continue
                if contains_convex_xz([x,z],poly):hit=max(hit,max(ys))
    return round(hit,6)if hit>-math.inf else None

if __name__=='__main__':
    path=ROOT/'assets/models/reference_wing/octagonal_bath.geometry.json';contract=json.loads(path.read_text());probes=[]
    for label,x,z,expected in [('basin_center',0,0,-.22),('diagonal_AABB_false_positive',2,-2,-.22),('axial_lowest_tread',0,3.6,-.035),('axial_middle_tread',0,3.95,.15),('diagonal_lowest_tread',2.5,-2.5,-.035),('diagonal_middle_tread',2.8,-2.8,.15)]:
        actual=evaluate_step_floor(contract,x,z);mesh=glb_horizontal_collider_floor(path.with_name('octagonal_bath.glb'),x,z);probes.append({'probe':label,'point_xz':[x,z],'expected_floor_y':expected,'exact_polygon_evaluation':actual,'actual_glb_collider_top_y':mesh,'pass':actual.get('floor_y')==expected and abs(mesh-expected)<1e-5})
    cyan_path=ROOT/'assets/models/reference_wing/cyan_corridor.geometry.json';cyan=json.loads(cyan_path.read_text());actual=evaluate_step_floor(cyan,.87,5.15);mesh=glb_horizontal_collider_floor(cyan_path.with_name('cyan_corridor.glb'),.87,5.15);probes.append({'probe':'cyan_submerged_sign_flange_outside_pole','point_xz':[.87,5.15],'expected_floor_y':-.17,'exact_polygon_evaluation':actual,'actual_glb_collider_top_y':mesh,'pass':actual.get('floor_y')==-.17 and abs(mesh+.17)<1e-5})
    result={'scope':'Exact polygon terrain recipe for octagonal treads and submerged cyan sign flange versus real exported horizontal collider triangles. Not a Godot runtime test.','status':'PASS'if all(p['pass']for p in probes)else'FAIL','probes':probes}
    (ROOT/'output/reference_wing/water_rooms/octagonal_depth_polygon_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2));assert result['status']=='PASS'
