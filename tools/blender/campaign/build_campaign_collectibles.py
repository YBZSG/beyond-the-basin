"""PoolCore campaign collectibles. Original procedural artwork, CC0-1.0.
Run: blender --background --python tools/blender/campaign/build_campaign_collectibles.py
All assets are authored in metres around their own origin. Blender +Z is the front
face; glTF +Y is the front face. No external inputs, images, or dependencies.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/models/campaign'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name != 'Collection': bpy.data.collections.remove(c)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1

def mat(name,color,metal=0,rough=.5,alpha=1):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,alpha); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,alpha)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    p.inputs['Alpha'].default_value=alpha
    if alpha<1: m.surface_render_method='DITHERED'; m.use_transparency_overlap=False
    return m
brass=mat('Aged satin brass',(.39,.245,.095),.78,.37)
brass_light=mat('Brushed brass edges',(.57,.39,.17),.75,.32)
steel=mat('Oxidized contact steel',(.22,.27,.27),.8,.38)
ceramic=mat('Warm glazed ceramic',(.76,.75,.66),.03,.32)
ink=mat('Indigo maintenance ink',(.018,.058,.075),.05,.7)
paper=mat('Ivory synthetic paper',(.66,.7,.62),0,.78)
blue=mat('PoolCore blue polymer',(.028,.18,.22),0,.52)
rubber=mat('EPDM gasket',(.018,.025,.024),0,.88)
red=mat('Vermilion service marking',(.48,.075,.025),.03,.62)
film=mat('Translucent protective film',(.58,.76,.74),0,.21,.14)
seam=mat('Frosted heat-weld seam',(.38,.55,.52),0,.43,.55)
roots={}; collections={}; current=None

def start(name):
    global current
    current=name
    c=bpy.data.collections.new(name+'_collection'); scene.collection.children.link(c); collections[name]=c
    r=bpy.data.objects.new(name,None); c.objects.link(r); roots[name]=r
    r['asset_kind']=name; r['units']='metres'; r['license']='CC0-1.0'
    return r

def finish(o,name,m,bevel=0,smooth=False):
    o.name=name
    for c in list(o.users_collection): c.objects.unlink(o)
    collections[current].objects.link(o); o.parent=roots[current]
    if m: o.data.materials.append(m)
    if bevel:
        b=o.modifiers.new('Manufactured edge radius','BEVEL'); b.width=bevel; b.segments=3
        b=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL'); b.keep_sharp=True
    if smooth:
        for p in o.data.polygons: p.use_smooth=True
    return o

def box(name,loc,size,m,b=.001):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,m,b)

def cyl(name,loc,r,depth,m,rot=(0,0,0),v=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=v,radius=r,depth=depth,location=loc,rotation=rot)
    return finish(bpy.context.object,name,m,min(.0008,depth*.15),True)

def torus(name,loc,major,minor,m):
    bpy.ops.mesh.primitive_torus_add(major_segments=64,minor_segments=12,location=loc,major_radius=major,minor_radius=minor)
    return finish(bpy.context.object,name,m,0,True)

def line(name,points,r,m):
    curve=bpy.data.curves.new(name,'CURVE'); curve.dimensions='3D'; curve.resolution_u=1; curve.bevel_depth=r; curve.bevel_resolution=2
    p=curve.splines.new('POLY'); p.points.add(len(points)-1)
    for dst,src in zip(p.points,points): dst.co=(*src,1)
    o=bpy.data.objects.new(name,curve); collections[current].objects.link(o); o.parent=roots[current]; curve.materials.append(m)
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH'); o.select_set(False)
    return o

def label(name,text,loc,size,m,rotation=0):
    bpy.ops.object.text_add(location=loc,rotation=(0,0,rotation)); o=bpy.context.object
    o.data.body=text; o.data.size=size; o.data.extrude=.000015; o.data.align_x='CENTER'; o.data.align_y='CENTER'
    bpy.ops.object.convert(target='MESH'); return finish(bpy.context.object,name,m)

start('key')
# Oval pierced bow, milled shaft, two stepped wards and identification tag.
o=torus('Key pierced oval bow',(-.058,0,0),.022,.0045,brass); o.scale=(1,1.18,.7)
box('Key shoulder',(-.027,0,0),(.027,.019,.006),brass,.002)
box('Key shaft',(.025,0,0),(.095,.011,.006),brass_light,.0008)
box('Ward A',(.06,-.013,0),(.014,.022,.006),brass,.0006)
box('Ward B',(.038,-.009,0),(.009,.011,.006),brass,.0006)
box('Key milled channel',(.025,-.001,.00315),(.065,.0014,.00025),ink,.00008)
label('Key stamped number','M-04',(-.027,0,.0031),.005,ink,math.pi/2)

start('fuse')
axis=(0,math.pi/2,0)
cyl('Porcelain cartridge body',(0,0,0),.014,.103,ceramic,axis)
for x in [-.052,.052]:
    cyl('Nickel plated end cap', (x,0,0),.015,.022,steel,axis)
    cyl('Contact brass face',(x+math.copysign(.012,x),0,0),.012,.002,brass_light,axis)
    for dx in [-.006,.006]:
        o=torus('Cap concentric rolled lip',(x+dx,0,0),.0146,.0007,steel); o.rotation_euler=axis
box('Fuse printed rating strip',(0,0,.0133),(.067,.010,.0005),paper,.0004)
label('Fuse rating','32A / 500V',(0,.001,.014),.006,ink)
label('Fuse class','gG  •  PC',(0,-.005,.014),.003,red)

start('valve')
torus('Cast brass handwheel rim',(0,0,0),.061,.007,brass)
# Six spokes with real open gaps and a raised hexagonal spindle boss.
for i in range(6):
    a=i*math.tau/6
    line('Cast radial spoke',[(.012*math.cos(a),.012*math.sin(a),.004),(.057*math.cos(a),.057*math.sin(a),0)],.004,brass)
cyl('Valve hexagonal spindle boss',(0,0,.004),.016,.02,brass_light,v=6)
cyl('Spindle dark recess',(0,0,.0142),.0075,.0005,rubber,v=6)
cyl('Center fastening screw',(0,0,.0146),.004,.001,steel,v=6)
for a in [math.pi*.25,math.pi*1.25]:
    box('Rim foundry grip',(math.cos(a)*.061,math.sin(a)*.061,.006),(.011,.008,.0015),brass_light,.002)
label('Valve direction','OPEN',(0,.041,.006),.005,ink)

start('card')
box('Waterproof polymer card',(0,0,0),(.102,.065,.0022),paper,.0035)
box('Header blue print',(0,.019,.0012),(.095,.018,.00015),blue,.0002)
label('Card facility identity','POOLCORE',(0,.019,.0015),.009,paper)
label('Card access class','MAINTENANCE',(.009,.002,.0015),.0065,ink)
label('Card serial','SERVICE  /  04',(.01,-.012,.0015),.0048,ink)
box('Card embedded contact',(-.034,-.006,.0014),(.017,.018,.0005),brass_light,.0018)
for x in [-.038,-.03]: box('Chip isolation line',(x,-.006,.0017),(.0004,.016,.0001),ink,.00003)
for y in [-.01,-.002]: box('Chip contact division',(-.034,y,.0017),(.015,.0004,.0001),ink,.00003)
for i in range(25):
    x=-.044+i*.0035
    box('Access optical stripe',(x,-.025,.0014),(.0007+(.0005 if i%3 else 0),.006,.0001),ink,.00002)
box('Rear magnetic stripe',(0,.011,-.0012),(.095,.011,.0001),ink,.0001)

start('diagram')
# Folded map panels with shallow alternating crease heights, contained by a sleeve.
for i in range(3):
    x=-.07+i*.07
    box('Folded synthetic sheet panel',(x,0,.0003+(.0002 if i==1 else 0)),(.0698,.145,.001),paper,.0002)
for x in [-.035,.035]:
    line('Visible fold crease',[(x,-.070,.0011),(x,0,.0013),(x,.070,.0011)],.00022,seam)
label('Diagram title','PC / SERVICE CIRCUIT',(0,.057,.0015),.007,ink)
label('Diagram subtitle','PUMP ROOM  •  REV 04',(0,.045,.0015),.0037,ink)
# Architectural circuit: measured linework, valve symbols, connection routes.
for coords in [[(-.085,-.042),(-.085,.027),(-.022,.027),(-.022,-.042),(-.085,-.042)],[(.006,-.042),(.006,.027),(.086,.027),(.086,-.042),(.006,-.042)], [(-.022,.008),(.006,.008)], [(-.055,-.007),(.05,-.007),(.05,-.025)]]:
    line('Printed schematic pipe',[(x,y,.0017) for x,y in coords],.0006,ink)
for x,y in [(-.055,-.007),(.025,-.007),(.05,-.025)]:
    torus('Schematic valve symbol',(x,y,.0018),.004,.00045,blue)
    line('Valve symbol slash',[(x-.003,y-.003,.0018),(x+.003,y+.003,.0018)],.00035,blue)
label('Pump annotation','P-01',(-.053,.013,.0018),.0045,ink)
label('Filter annotation','FILTER',(.049,.013,.0018),.0045,ink)
label('Diagram warning','ISOLATE SUPPLY BEFORE SERVICE',(0,-.056,.0018),.004,red)
# Separate films, perimeter weld and press-seal. Film does not use transmission extension.
box('Clear sleeve front',(0,0,.0024),(.221,.162,.00025),film,.001)
box('Clear sleeve back',(0,0,-.0014),(.221,.162,.00025),film,.001)
for x in [-.108,.108]: box('Heat welded side seam',(x,0,.0004),(.003,.16,.0008),seam,.0005)
box('Bottom sleeve weld',(0,-.079,.0004),(.216,.003,.0008),seam,.0005)
for y in [.076,.079]: box('Sleeve press seal',(0,y,.001),(.217,.0015,.001),seam,.0005)

# All original topology and bevel modifiers are retained in the editable source.
scene['asset_provenance']='Original procedural mesh artwork authored for PoolCore by OpenAI assistant. CC0-1.0.'
scene['mounting']='Each named asset is a root at origin, in metres. Blender +Z front becomes glTF +Y. Assets intentionally overlap in combined scene; instantiate one named root.'
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'campaign_collectibles.blend'))
report={'units':'metres','front_axis_glTF':'+Y','license':'CC0-1.0','assets':{}}
deps=bpy.context.evaluated_depsgraph_get()
for name,root in roots.items():
    bpy.ops.object.select_all(action='DESELECT'); root.select_set(True)
    verts=[]; tris=0; mats=set(); count=0
    for obj in root.children:
        obj.select_set(True)
        if obj.type=='MESH':
            count+=1; ev=obj.evaluated_get(deps); mesh=ev.to_mesh(); mesh.calc_loop_triangles(); tris+=len(mesh.loop_triangles)
            verts += [obj.matrix_world@v.co for v in mesh.vertices]
            mats.update(m.name for m in obj.data.materials); ev.to_mesh_clear()
    lo=[min(v[i] for v in verts) for i in range(3)]; hi=[max(v[i] for v in verts) for i in range(3)]
    report['assets'][name]={'mesh_objects':count,'triangles':tris,'bbox_blender_m':{'min':lo,'max':hi},'dimensions_m':[hi[i]-lo[i] for i in range(3)],'materials':sorted(mats)}
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_extras=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'campaign_collectibles.glb'),export_format='GLB',use_selection=True,export_apply=True,export_extras=True)
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('CAMPAIGN_ASSETS_VALIDATED',json.dumps(report))
