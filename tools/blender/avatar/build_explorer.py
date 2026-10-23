"""Original Pool Explorer, modeled to the AI-generated turnaround in assets/models/avatar.
Blender 4.3.2; run: blender -b --python tools/blender/avatar/build_explorer.py
No external character meshes, downloaded rigs or paid assets are used.
"""
import bpy, bmesh, math, json, os, sys, argparse, random
from mathutils import Vector, Matrix, Quaternion
from pathlib import Path
P=Path(__file__).resolve().parents[3]
OUT=P/'assets/models/avatar'; OUT.mkdir(parents=True,exist_ok=True)
SRC=P/'tools/blender/avatar'
# Animation-only rebuilding preserves the approved source mesh byte-for-byte.
# Usage: blender -b --python tools/blender/avatar/build_explorer.py -- --animation-only
# Optionally add --source-blend /path/to/original.blend for an immutable baseline.
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
animation_only='--animation-only' in args
if animation_only:
 source_path=Path(args[args.index('--source-blend')+1]) if '--source-blend' in args else SRC/'pool_explorer.blend'
 bpy.ops.wm.open_mainfile(filepath=str(source_path))
 scene=bpy.context.scene;rig=next(o for o in bpy.data.objects if o.type=='ARMATURE');arm_data=rig.data
 bones={b.name:(b.head_local.copy(),b.tail_local.copy()) for b in arm_data.bones}
 body=bpy.data.objects['Body_Explorer'];head=bpy.data.objects['Head_Explorer'];objects=[body,head]
 old_manifest=json.loads((OUT/'avatar_manifest.json').read_text())
 weight_stats=old_manifest.get('pre_reduction_weights',old_manifest['weights'])
 rig.animation_data_clear()
 for action in list(bpy.data.actions):bpy.data.actions.remove(action)
else:
 random.seed(90271)
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for data in list(bpy.data.materials): bpy.data.materials.remove(data)
 scene=bpy.context.scene
 scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
 scene.render.fps=60
 bpy.context.preferences.filepaths.save_version=0
 objects=[]

 def mat(name,color,rough=.7,metallic=0):
  m=bpy.data.materials.new(name); m.diffuse_color=(*color,1);m.use_nodes=True
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metallic
  return m
 M={
  'shirt':mat('Explorer | warm ivory woven shirt',(.64,.61,.53),.9),
  'shirt_edge':mat('Explorer | stitched shirt edges',(.49,.46,.40),.9),
  'pants':mat('Explorer | charcoal cotton trousers',(.065,.069,.068),.92),
  'pants_edge':mat('Explorer | trouser seams',(.11,.105,.092),.9),
  'shoe':mat('Explorer | dark nubuck shoes',(.057,.052,.045),.86),
  'sole':mat('Explorer | rubber soles',(.027,.029,.028),.96),
  'lace':mat('Explorer | textile shoelaces',(.105,.102,.09),.98),
  'skin':mat('Explorer | neutral warm skin',(.46,.285,.18),.68),
  'lip':mat('Explorer | muted lips',(.29,.14,.105),.74),
  'hair':mat('Explorer | short brown hair',(.055,.035,.023),.94),
  'brow':mat('Explorer | eyebrows',(.043,.028,.018),.94),
  'eye':mat('Explorer | eyes',(.62,.59,.52),.28),
  'iris':mat('Explorer | dark brown irises',(.08,.046,.021),.3),
  'pupil':mat('Explorer | pupils',(.009,.008,.006),.2),
  'button':mat('Explorer | horn buttons',(.22,.20,.17),.7),
  'belt':mat('Explorer | woven belt',(.040,.038,.03),.92),
  'metal':mat('Explorer | dull metal buckle',(.25,.25,.23),.44,.65),
 }
 # Subtle embedded original woven surface texture, not a copy of the reference image.
 # The reference is a modeling guide only, never used as a runtime billboard/texture.
 def woven_texture(name,base):
  size=256; im=bpy.data.images.new(name,width=size,height=size)
  pix=[]
  for y in range(size):
   for x in range(size):
    n=(random.random()-.5)*.015
    v=1+n+(.008 if (x%4)<2 else -.008)+(.006 if (y%4)<2 else -.006)
    pix.extend([min(.99,max(.001,c*v)) for c in base]+[1])
  im.pixels.foreach_set(pix);im.filepath_raw=str(OUT/(name+'.png'));im.file_format='PNG';im.save();im.pack()
  return im
 for key in ['shirt','pants']:
  m=M[key];bs=m.node_tree.nodes.get('Principled BSDF');tx=m.node_tree.nodes.new('ShaderNodeTexImage');tx.image=woven_texture('explorer_'+key+'_weave',tuple(m.diffuse_color[:3]));tx.extension='REPEAT';m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color'])

 # Every mesh gets deterministic weights after authored geometry is complete.
 def mesh_obj(name,verts,faces,material,zone):
  me=bpy.data.meshes.new(name+'_mesh');me.from_pydata(verts,[],faces);me.update()
  o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(M[material]);o['weight_zone']=zone
  for p in me.polygons:p.use_smooth=True
  objects.append(o);return o

 def uv_project(o):
  uv=o.data.uv_layers.new(name='UVMap') if not o.data.uv_layers else o.data.uv_layers[0]
  for poly in o.data.polygons:
   for li in poly.loop_indices:
    p=o.data.vertices[o.data.loops[li].vertex_index].co
    uv.data[li].uv=(p.x*5+p.y*2,p.z*5+p.y*2)

 # Cross-sections use one lateral vector perpendicular to the centerline and the
 # fixed depth axis. Rings share vertices and have a closed cap at either end.
 def loft(name,rings,material,zone,sides=24,wrinkle=0,cap=True):
  vv=[];ff=[]
  for i,(c,rx,ry) in enumerate(rings):
   c=Vector(c)
   prev=Vector(rings[max(0,i-1)][0]);nxt=Vector(rings[min(len(rings)-1,i+1)][0]);d=(nxt-prev).normalized()
   a=Vector((d.z,0,-d.x)).normalized()
   if a.x<0:a=-a
   b=d.cross(a).normalized()
   if b.y<0:b=-b
   for j in range(sides):
    t=2*math.pi*j/sides
    wave=1+wrinkle*math.sin(t*5+i*2.2)*math.sin(i*1.7+.4)
    vv.append(tuple(c+a*rx*math.sin(t)*wave+b*ry*math.cos(t)*wave))
  for i in range(len(rings)-1):
   for j in range(sides):
    n=(j+1)%sides;ff.append((i*sides+j,i*sides+n,(i+1)*sides+n,(i+1)*sides+j))
  if cap:ff.extend([tuple(reversed(range(sides))),tuple((len(rings)-1)*sides+j for j in range(sides))])
  return mesh_obj(name,vv,ff,material,zone)

 def ellipsoid(name,center,scale,material,zone,seg=24,rings=14):
  center=garment_point(name,center)
  bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=center)
  o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  # Put coordinates into mesh space so all meshes share the rig's identity transform.
  o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
  o.data.materials.append(M[material]);o['weight_zone']=zone
  for p in o.data.polygons:p.use_smooth=True
  objects.append(o);return o

 def solid_panel(name,points,material,zone,thickness=.004,bevel=.002):
  points=[garment_point(name,p) for p in points]
  o=mesh_obj(name,points,[tuple(range(len(points)))],material,zone)
  bpy.context.view_layer.objects.active=o;o.select_set(True)
  sol=o.modifiers.new('Fabric thickness','SOLIDIFY');sol.thickness=thickness;bpy.ops.object.modifier_apply(modifier=sol.name)
  if bevel:
   be=o.modifiers.new('Soft sewn edge','BEVEL');be.width=bevel;be.segments=2;bpy.ops.object.modifier_apply(modifier=be.name)
  o.select_set(False);return o

 def garment_point(name,p):
  p=Vector(p)
  if name.startswith(('Body_Placket','Body_ShirtButton','Body_ChestPocket','Body_PocketStitch')) and 'shirt' in globals():
   ok,hit,normal,index=shirt.ray_cast(Vector((p.x,1,p.z)),Vector((0,-1,0)))
   if ok:p.y=hit.y+.0025
  elif name.startswith('Body_TrouserOutseam') and 'pants' in globals():
   sg=1 if p.x>=0 else -1
   ok,hit,normal,index=pants.ray_cast(Vector((sg*1,p.y,p.z)),Vector((-sg,0,0)))
   if ok:p.x=hit.x+sg*.0015
  elif name.startswith(('Body_FrontPocket','Body_BackPocket')) and 'pants' in globals():
   sg=1 if p.y>=0 else -1
   ok,hit,normal,index=pants.ray_cast(Vector((p.x,sg*1,p.z)),Vector((0,-sg,0)))
   if ok:p.y=hit.y+sg*.002
  return tuple(p)

 def tube(name,points,radius,material,zone,segments=6):
  points=[garment_point(name,p) for p in points]
  # Curve converted to genuine mesh, then skinned along with garment.
  cu=bpy.data.curves.new(name+'_curve','CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=radius;cu.bevel_resolution=1;cu.resolution_u=2
  sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
  for p,co in zip(sp.points,points):p.co=(*co,1)
  ob=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob
  bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.ops.object.convert(target='MESH');ob=bpy.context.object;ob.data.materials.append(M[material]);ob['weight_zone']=zone;objects.append(ob);ob.select_set(False);return ob

 def merge_remesh(name,items,voxel=.009,smooth=4,decimate=.7):
  bpy.ops.object.select_all(action='DESELECT')
  for o in items:o.select_set(True)
  bpy.context.view_layer.objects.active=items[0];bpy.ops.object.join();o=items[0];o.name=name
  for removed in items[1:]:
   if removed in objects:objects.remove(removed)
  re=o.modifiers.new('Continuous union surface','REMESH');re.mode='VOXEL';re.voxel_size=voxel;re.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=re.name)
  sm=o.modifiers.new('Anatomical surface relaxation','SMOOTH');sm.factor=1.1;sm.iterations=smooth;bpy.ops.object.modifier_apply(modifier=sm.name)
  if decimate<1:
   de=o.modifiers.new('Game topology reduction','DECIMATE');de.ratio=decimate;bpy.ops.object.modifier_apply(modifier=de.name)
  for p in o.data.polygons:p.use_smooth=True
  o.select_set(False);return o

 # CLOTHING: one closed continuous remeshed shirt with shoulder/sleeve junctions.
 shirt_parts=[loft('Body_ShirtTorso',[
  ((0,0,.967),.150,.092),((0,0,.995),.163,.099),((0,0,1.025),.157,.101),
  ((0,0,1.08),.149,.092),((0,.002,1.16),.165,.102),((0,.002,1.25),.173,.108),
  ((0,-.002,1.32),.177,.108),((0,-.004,1.38),.180,.093),((0,0,1.418),.160,.075),
  ((0,0,1.455),.075,.063),((0,0,1.465),.057,.052)],'shirt','shirt',40,.015)]
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  shirt_parts.append(loft('Body_ShirtSleeve_'+side,[
  ((s*.151,0,1.354),.046,.067),((s*.201,0,1.366),.052,.067),((s*.24,0,1.318),.050,.058),
  ((s*.27,0,1.255),.050,.054),((s*.296,.002,1.19),.048,.052),((s*.307,.004,1.158),.050,.053),
  ((s*.315,.004,1.135),.049,.050)],'shirt','arm_'+side,28,.035))
 for s in [-1,1]:
  shirt_parts.append(ellipsoid('Body_ShoulderBridge_'+str(s),(s*.180,0,1.379),(.055,.075,.056),'shirt','shirt',24,14))
 shirt=merge_remesh('Body_Shirt',shirt_parts,.007,4,.64);shirt['weight_zone']='shirt'
 # A clean sloping shoulder line, not overlapping primitive shoulder caps.
 for v in shirt.data.vertices:
  if abs(v.co.x)>.10 and v.co.z>1.34:
   v.co.z=min(v.co.z,1.467-.30*abs(v.co.x))
 shirt.data.update()
 bpy.context.view_layer.objects.active=shirt
 smoothgroup=shirt.vertex_groups.new(name='Temporary shoulder relaxation')
 for v in shirt.data.vertices:
  if v.co.z>1.31 and abs(v.co.x)>.10:smoothgroup.add([v.index],min(1,(v.co.z-1.31)/.04),'REPLACE')
 sm=shirt.modifiers.new('Soft shoulder sewing envelope','SMOOTH');sm.factor=.75;sm.iterations=8;sm.vertex_group=smoothgroup.name
 bpy.ops.object.modifier_apply(modifier=sm.name);shirt.vertex_groups.clear()
 # cuffs deliberately overlap the continuous sleeve, with a rolled edge.
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  loft('Body_RolledCuff_'+side,[((s*.305,.004,1.16),.052,.054),((s*.309,.004,1.151),.054,.056),((s*.317,.005,1.132),.052,.052),((s*.319,.005,1.127),.049,.050)],'shirt_edge','arm_'+side,28)
  # Actual collar panels, open over the throat.
  solid_panel('Body_Collar_'+side,[(s*.008,.060,1.458),(s*.057,.048,1.468),(s*.091,.064,1.41),(s*.048,.102,1.388)],'shirt','torso',.006,.003)
  tube('Body_ShoulderSeam_'+side,[(s*.064,-.040,1.456),(s*.12,-.030,1.437),(s*.177,-.015,1.417),(s*.211,.008,1.382)],.0015,'shirt_edge','shirt')
 # Shirt placket and six buttons follow the front silhouette.
 placket=[(0,.097,.992),(0,.104,1.05),(0,.105,1.13),(0,.115,1.22),(0,.113,1.30),(0,.092,1.38),(0,.062,1.44)]
 for s in [-1,1]:tube('Body_PlacketEdge_'+str(s),[(x+s*.009,y+.003,z) for x,y,z in placket],.0014,'shirt_edge','torso')
 for i,z in enumerate([1.018,1.085,1.152,1.218,1.284,1.35]):
  y=.102+(.013 if 1.16<z<1.32 else 0)
  ellipsoid('Body_ShirtButton_%02d'%i,(0,y+.006,z),(.0045,.002,.0045),'button','torso',12,8)
 # Single left breast pocket sewn into shirt, not a box stuck onto the body.
 solid_panel('Body_ChestPocket',[(.065,.112,1.303),(.137,.104,1.303),(.132,.107,1.219),(.10,.117,1.207),(.066,.117,1.22)],'shirt','torso',.002,.001)
 tube('Body_PocketStitch',[(.068,.115,1.298),(.134,.108,1.298),(.129,.111,1.224),(.10,.120,1.213),(.069,.121,1.224)],.0009,'shirt_edge','torso')

 # Trousers merged at the pelvis/crotch, with loops positioned at hip/knee/ankle.
 pants_parts=[loft('Body_Pelvis', [((0,-.005,.815),.119,.071),((0,-.003,.86),.155,.096),((0,-.006,.91),.165,.105),((0,0,.965),.152,.093),((0,0,.995),.149,.092)],'pants','pelvis',36,.014)]
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  pants_parts.append(loft('Body_TrouserLeg_'+side,[
  ((s*.085,0,.90),.085,.096),((s*.091,.003,.83),.088,.095),((s*.097,.004,.75),.078,.085),
  ((s*.100,.006,.64),.068,.073),((s*.104,.010,.55),.062,.066),((s*.105,.012,.50),.061,.064),
  ((s*.106,.002,.46),.061,.062),((s*.106,-.006,.38),.064,.066),((s*.106,-.008,.29),.059,.061),
  ((s*.107,-.005,.19),.048,.052),((s*.108,0,.115),.051,.052),((s*.108,0,.087),.051,.053)],'pants','leg_'+side,28,.035))
 pants=merge_remesh('Body_Trousers',pants_parts,.006,3,.62);pants['weight_zone']='pants'
 loft('Body_Waistband',[((0,0,.968),.154,.097),((0,0,.995),.154,.097),((0,0,1.001),.151,.094)],'pants_edge','pelvis',40)
 loft('Body_Belt',[((0,0,.975),.157,.099),((0,0,.992),.157,.099)],'belt','pelvis',40)
 solid_panel('Body_BeltBuckle',[(-.014,.103,.973),(.014,.103,.973),(.014,.103,.995),(-.014,.103,.995)],'metal','pelvis',.004,.002)
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  tube('Body_TrouserOutseam_'+side,[(s*.175,-.002,.91),(s*.181,0,.82),(s*.169,0,.72),(s*.165,0,.63),(s*.168,0,.50),(s*.170,-.005,.37),(s*.159,-.003,.23),(s*.158,0,.11)],.0012,'pants_edge','leg_'+side)
  tube('Body_FrontPocket_'+side,[(s*.122,.076,.965),(s*.143,.079,.927),(s*.156,.064,.898)],.0015,'pants_edge','pelvis')
  solid_panel('Body_BackPocket_'+side,[(s*.035,-.103,.94),(s*.117,-.092,.94),(s*.118,-.092,.866),(s*.075,-.110,.85),(s*.034,-.105,.867)],'pants','pelvis',.002,.001)
  tube('Body_BackPocketSeam_'+side,[(s*.039,-.108,.937),(s*.113,-.096,.937),(s*.114,-.096,.87),(s*.075,-.113,.855),(s*.038,-.109,.87)],.0012,'pants_edge','pelvis')
  # Six belt loops around the waist; front and side are visible in FPS.
  for k,ang in enumerate([.65,1.55,2.45]):
   x=s*.159*math.sin(ang);y=.101*math.cos(ang)
   tube('Body_BeltLoop_%s%d'%(side,k),[(x,y,.965),(x*1.015,y*1.015,.999)],.004,'pants','pelvis')

 # SHOES: closed anatomically broad toe box, heel, layered rubber sole and laces.
 for s in [-1,1]:
  side='L' if s>0 else 'R';x=s*.108
  rings=[]
  # Loft along Y; use explicit elliptical shoe rings in horizontal XY plane by vertical stack.
  # Shoe outline has a rounded toe at +Y and narrower heel at -Y.
  def shoe_shell(name,zs,widths,depths,material):
   vv=[];ff=[];n=40
   for z,w,d in zip(zs,widths,depths):
    for j in range(n):
     a=j*2*math.pi/n; yy=math.cos(a);xx=math.sin(a)
     # Toe box is wider than heel, front foot centered 5 cm ahead of ankle.
     ww=w*(1+.14*yy)
     vv.append((x+ww*xx,.055+d*yy,z+.003*math.cos(2*a)))
   for k in range(len(zs)-1):
    for j in range(n):ff.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
   ff.extend([tuple(reversed(range(n))),tuple((len(zs)-1)*n+j for j in range(n))])
   return mesh_obj(name,vv,ff,material,'foot_'+side)
  shoe_shell('Body_ShoeSole_'+side,[.012,.024,.041],[.056,.061,.058],[.139,.141,.136],'sole')
  shoe_shell('Body_ShoeUpper_'+side,[.037,.061,.087,.12],[.056,.057,.046,.034],[.135,.128,.101,.052],'shoe')
  # Padded ankle top and tongue.
  ellipsoid('Body_ShoeTongue_'+side,(x,.060,.105),(.035,.059,.018),'shoe','foot_'+side)
  for i in range(5):
   y=.053+i*.016;z=.120-i*.005
   tube('Body_Lace_%s%d'%(side,i),[(x-.025,y,z),(x+.025,y+.008,z)],.0021,'lace','foot_'+side)
  for i in range(6):
   y=-.052+i*.04
   for sx in [-1,1]:tube('Body_SoleTread_%s%d%d'%(side,i,sx),[(x+sx*.056,y,.023),(x+sx*.052,y+.012,.023)],.0022,'sole','foot_'+side)

 # SKIN: forearms and articulated hands with five separate connected fingers.
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  fore=loft('Body_Forearm_'+side,[((s*.311,.004,1.147),.044,.046),((s*.332,.006,1.094),.041,.043),((s*.360,.008,1.029),.031,.035),((s*.385,.010,.971),.023,.027),((s*.396,.012,.946),.023,.025)],'skin','arm_'+side,28)
  # Hand includes palm, thumb and all fingers, fused into one continuous surface.
  palm=loft('Body_Palm_'+side,[((s*.392,.011,.952),.023,.026),((s*.404,.014,.922),.025,.037),((s*.416,.019,.886),.023,.040),((s*.423,.020,.870),.018,.036)],'skin','hand_'+side,24)
  hand_parts=[palm]
  for k,(y,length) in enumerate([(.049,.062),(.028,.076),(.006,.071),(-.016,.054)]):
   fingername=['index','middle','ring','little'][k]
   x0=s*.421;z0=.882
   hand_parts.append(loft('Body_Finger_'+fingername+'_'+side,[
    ((x0,y,z0),.010,.010),((s*.430,y+.001,z0-.027),.009,.009),
    ((s*.435,y+.008,z0-length+.012),.0075,.008),((s*.434,y+.012,z0-length),.0035,.005)],'skin','finger_'+fingername+'_'+side,12))
  # Thumb grows from the front edge of palm, angled away from fingers.
  hand_parts.append(loft('Body_Thumb_'+side,[((s*.401,.039,.925),.014,.014),((s*.413,.059,.904),.012,.012),((s*.418,.066,.880),.009,.010),((s*.419,.065,.869),.005,.006)],'skin','thumb_'+side,14))
  hand=merge_remesh('Body_Hand_'+side,hand_parts,.0034,2,.70);hand['weight_zone']='hand_'+side
  # Fingernails lie on the outer (dorsal) side, kept tiny and neutral.
  for k,(y,length) in enumerate([(.049,.062),(.028,.076),(.006,.071),(-.016,.054)]):
   ellipsoid('Body_Nail_%s%d'%(side,k),(s*.441,y+.010,.882-length+.009),(.0013,.005,.008),'shirt_edge','hand_'+side,10,8)

 # Adult hand length/palm breadth refinement; preserve wrist attachment and the
 # exact same editable rig hierarchy. Matching hand/finger rest positions follow.
 for obj in objects:
  if obj.name.startswith(('Body_Hand_','Body_Nail_')):
   side='L' if ('_L' in obj.name) else 'R';sg=1 if side=='L' else -1
   pivot=Vector((sg*.392,.011,.952))
   for v in obj.data.vertices:v.co=pivot+(v.co-pivot)*1.12

 # Neck/head are isolated meshes so only the main camera can hide them.
 loft('Head_Neck',[((0,-.005,1.405),.057,.052),((0,-.002,1.455),.049,.048),((0,0,1.498),.045,.044),((0,.004,1.536),.050,.049)],'skin','neck',32)
 # Authored continuous head profile with jaw, cheek, brow, nose and chin relief.
 profiles=[(1.493,.036,.042,.015),(1.506,.050,.052,.008),(1.525,.063,.062,0),(1.55,.071,.067,-.003),(1.58,.075,.071,-.005),(1.61,.075,.073,-.005),(1.64,.074,.074,-.007),(1.67,.068,.069,-.009),(1.697,.053,.056,-.01),(1.714,.030,.034,-.01),(1.720,.003,.004,-.01)]
 def profile(z):
  for i in range(len(profiles)-1):
   a,b=profiles[i],profiles[i+1]
   if a[0]<=z<=b[0]:
    t=(z-a[0])/(b[0]-a[0]);t=t*t*(3-2*t)
    return tuple(a[k]*(1-t)+b[k]*t for k in range(1,4))
  return profiles[-1][1:]
 def headpoint(z,a,offset=0):
  rx,ry,cy=profile(z);x=rx*math.sin(a);front=max(0,math.cos(a))
  y=cy+ry*math.cos(a)
  # Nose bridge and tip grow naturally from the face, not a separate sphere.
  nose=.026*math.exp(-(x/.014)**2-((z-1.588)/.031)**2)+.017*math.exp(-(x/.020)**2-((z-1.573)/.009)**2)
  sockets=-.007*sum(math.exp(-((x-q)/.016)**2-((z-1.611)/.013)**2) for q in [-.029,.029])
  brow=.005*sum(math.exp(-((x-q)/.026)**2-((z-1.629)/.009)**2) for q in [-.029,.029])
  muzzle=.006*math.exp(-(x/.032)**2-((z-1.543)/.018)**2)
  y+=(nose+sockets+brow+muzzle)*front**10
  return (x+offset*math.sin(a),y+offset*math.cos(a),z)
 verts=[];faces=[];N=64;R=45
 for i in range(R):
  z=1.493+(1.720-1.493)*i/(R-1)
  for j in range(N):verts.append(headpoint(z,j*2*math.pi/N))
 for i in range(R-1):
  for j in range(N):faces.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
 faces.extend([tuple(reversed(range(N))),tuple((R-1)*N+j for j in range(N))])
 mesh_obj('Head_Face',verts,faces,'skin','head')
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  ellipsoid('Head_Ear_'+side,(s*.075,-.004,1.59),(.015,.020,.032),'skin','head',20,12)
  ellipsoid('Head_EarFold_'+side,(s*.086,.003,1.59),(.004,.011,.021),'lip','head',16,10)
  # Recessed eye with visible cornea narrowly shaped, realistic-scale iris.
  ellipsoid('Head_Eye_'+side,(s*.029,.0635,1.611),(.0118,.0080,.0048),'eye','head',20,10)
  ellipsoid('Head_Iris_'+side,(s*.029,.0713,1.611),(.0047,.0015,.0048),'iris','head',16,10)
  ellipsoid('Head_Pupil_'+side,(s*.029,.0725,1.611),(.0021,.0008,.0025),'pupil','head',12,8)
  upper=[];lower=[]
  for k in range(9):
   u=-1+k/4;upper.append((s*.029+.012*u,.068+.003*(1-u*u),1.611+.0043*math.sqrt(max(0,1-u*u))))
   lower.append((s*.029+.012*u,.0675+.003*(1-u*u),1.611-.0037*math.sqrt(max(0,1-u*u))))
  tube('Head_UpperLid_'+side,upper,.0018,'skin','head');tube('Head_LowerLid_'+side,lower,.0015,'skin','head')
  tube('Head_Brow_'+side,[(s*.013,.071,1.63),(s*.027,.073,1.632),(s*.044,.064,1.628)],.0027,'brow','head')
  ellipsoid('Head_Nostril_'+side,(s*.011,.087,1.568),(.0036,.0013,.0018),'lip','head',12,8)
 tube('Head_MouthLine',[(-.022,.066,1.543),(-.011,.071,1.544),(0,.073,1.542),(.011,.071,1.544),(.022,.066,1.543)],.0016,'lip','head')
 tube('Head_LowerLip',[(-.018,.068,1.541),(0,.074,1.538),(.018,.068,1.541)],.0022,'lip','head')
 # Continuous hair cap, sideburns and restrained combed tufts.
 verts=[];faces=[];N=64;R=16
 for i in range(R):
  t=i/(R-1)
  for j in range(N):
   a=j*2*math.pi/N;f=math.cos(a)
   boundary=1.620+.035*max(0,f)**2-.043*max(0,-f)
   z=boundary+(1.719-boundary)*t
   v=Vector(headpoint(z,a,.005+.003*math.sin(a*11+t*9)**2));v.z+=.008*t
   verts.append(tuple(v))
 for i in range(R-1):
  for j in range(N):faces.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
 faces.append(tuple((R-1)*N+j for j in range(N)))
 mesh_obj('Head_Hair',verts,faces,'hair','head')
 for i in range(12):
  a=i*2*math.pi/12
  center=(.038*math.sin(a),-.008+.040*math.cos(a),1.704+.009*math.sin(a*2))
  tuft=ellipsoid('Head_HairTuft_%02d'%i,center,(.021,.029,.016),'hair','head',12,8)

 # RIG: root plus true connected chains; 42 bones including finger articulation.
 arm_data=bpy.data.armatures.new('ExplorerSkeleton');rig=bpy.data.objects.new('ExplorerRig',arm_data);bpy.context.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 bones={}
 def bone(name,head,tail,parent=None,connected=False,deform=True):
  b=arm_data.edit_bones.new(name);b.head=head;b.tail=tail;b.use_deform=deform
  if parent:b.parent=arm_data.edit_bones[parent];b.use_connect=connected
  bones[name]=(Vector(head),Vector(tail));return b
 bone('Root',(0,0,0),(0,0,.10),deform=False)
 bone('Hips',(0,0,.88),(0,0,1.02),'Root')
 bone('Spine',(0,0,1.02),(0,0,1.20),'Hips',True)
 bone('Chest',(0,0,1.20),(0,0,1.39),'Spine',True)
 bone('Neck',(0,0,1.39),(0,0,1.51),'Chest',True)
 bone('Head',(0,0,1.51),(0,0,1.70),'Neck',True)
 for s in [-1,1]:
  side='L' if s>0 else 'R'
  bone('Shoulder_'+side,(0,0,1.39),(s*.205,0,1.399),'Chest',True)
  bone('UpperArm_'+side,(s*.205,0,1.399),(s*.31,.004,1.155),'Shoulder_'+side,True)
  bone('Forearm_'+side,(s*.31,.004,1.155),(s*.392,.011,.952),'UpperArm_'+side,True)
  bone('Hand_'+side,(s*.392,.011,.952),(s*.423,.020,.878),'Forearm_'+side,True)
  for k,(y,length) in enumerate([(.049,.062),(.028,.076),(.006,.071),(-.016,.054)]):
   fn=['Index','Middle','Ring','Little'][k]
   bone(fn+'1_'+side,(s*.421,y,.882),(s*.431,y+.003,.882-length*.52),'Hand_'+side)
   bone(fn+'2_'+side,(s*.431,y+.003,.882-length*.52),(s*.434,y+.012,.882-length),fn+'1_'+side,True)
  bone('Thumb1_'+side,(s*.401,.039,.925),(s*.413,.059,.904),'Hand_'+side)
  bone('Thumb2_'+side,(s*.413,.059,.904),(s*.419,.065,.869),'Thumb1_'+side,True)
  bone('UpperLeg_'+side,(s*.085,0,.88),(s*.105,.012,.50),'Hips')
  bone('LowerLeg_'+side,(s*.105,.012,.50),(s*.108,0,.115),'UpperLeg_'+side,True)
  bone('Foot_'+side,(s*.108,0,.115),(s*.108,.155,.050),'LowerLeg_'+side,True)
  bone('Toe_'+side,(s*.108,.155,.05),(s*.108,.19,.045),'Foot_'+side,True)
 for side,sg in [('L',1),('R',-1)]:
  pivot=Vector((sg*.392,.011,.952))
  for eb in arm_data.edit_bones:
   if eb.name.endswith('_'+side) and eb.name.startswith(('Hand','Index','Middle','Ring','Little','Thumb')):
    old_head,old_tail=bones[eb.name]
    eb.head=pivot+(old_head-pivot)*1.12;eb.tail=pivot+(old_tail-pivot)*1.12
    bones[eb.name]=(eb.head.copy(),eb.tail.copy())
 bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True;rig.data.display_type='OCTAHEDRAL'

 # Anatomically segmented and smoothly blended weights, normalized for every vertex.
 def smoothstep(a,b,x):
  if a==b:return 0
  t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
 def mix_weights(a,b,t):
  d={}
  for k,v in a.items():d[k]=d.get(k,0)+v*(1-t)
  for k,v in b.items():d[k]=d.get(k,0)+v*t
  return d

 def torso_weights(p):
  if p.z<1.05:return mix_weights({'Hips':1},{'Spine':1},smoothstep(.98,1.10,p.z))
  return mix_weights({'Spine':1},{'Chest':1},smoothstep(1.12,1.29,p.z))
 def segment_dist(p,a,b):
  t=max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared));return (p-(a+(b-a)*t)).length

 def arm_weights(p,side):
  # Arm position follows the A-pose centerline. Continuous at shoulder/elbow/wrist.
  if p.z>1.31:
   t=smoothstep(.17,.24,abs(p.x));return mix_weights({'Chest':1},{'UpperArm_'+side:1},t)
  if p.z>1.08:
   return mix_weights({'UpperArm_'+side:1},{'Forearm_'+side:1},1-smoothstep(1.105,1.205,p.z))
  return mix_weights({'Forearm_'+side:1},{'Hand_'+side:1},1-smoothstep(.929,.985,p.z))
 def hand_weights(p,side):
  if p.z>.907:return mix_weights({'Forearm_'+side:1},{'Hand_'+side:1},1-smoothstep(.934,.972,p.z))
  candidates=['Hand_'+side]+[f+str(k)+'_'+side for f in ['Index','Middle','Ring','Little','Thumb'] for k in [1,2]]
  # At the webbing, mix hand and the nearest finger. Finger vertices are rigid enough
  # for a stable natural hand and editable for future grasp animation.
  nearest=sorted([(segment_dist(p,*bones[n]),n) for n in candidates])[:3]
  d={n:1/max(.004,dist)**4 for dist,n in nearest};total=sum(d.values());return {n:w/total for n,w in d.items()}
 def leg_weights(p,side):
  if p.z>.78:return mix_weights({'UpperLeg_'+side:1},{'Hips':1},smoothstep(.80,.93,p.z))
  if p.z>.22:return mix_weights({'LowerLeg_'+side:1},{'UpperLeg_'+side:1},smoothstep(.445,.555,p.z))
  return mix_weights({'Foot_'+side:1},{'LowerLeg_'+side:1},smoothstep(.10,.175,p.z))
 def weight_for(p,zone):
  side='L' if p.x>=0 else 'R'
  if zone=='head':return {'Head':1}
  if zone=='neck':return mix_weights({'Chest':.15,'Neck':.85},{'Head':1},smoothstep(1.47,1.535,p.z))
  if zone=='torso':return torso_weights(p)
  if zone=='pelvis':return {'Hips':1}
  if zone=='pants':return leg_weights(p,side)
  if zone=='shirt':
   if abs(p.x)>.18 and p.z<1.425:return arm_weights(p,side)
   return torso_weights(p)
  if zone.startswith('arm_'):return arm_weights(p,zone[-1])
  if zone.startswith('hand_'):return hand_weights(p,zone[-1])
  if zone.startswith('leg_'):return leg_weights(p,zone[-1])
  if zone.startswith('foot_'):return {'Foot_'+zone[-1]:1}
  return {'Hips':1}
 weight_stats={'vertices':0,'unweighted':0,'max_weight_error':0,'max_influences':0}
 for o in objects:
  if o.type!='MESH':continue
  zone=o.get('weight_zone','torso');groups={}
  uv_project(o)
  for v in o.data.vertices:
   weights={k:w for k,w in weight_for(v.co,zone).items() if w>.0001};total=sum(weights.values());weights={k:w/total for k,w in weights.items()}
   for n,w in weights.items():
    if n not in groups:groups[n]=o.vertex_groups.new(name=n)
    groups[n].add([v.index],w,'REPLACE')
   weight_stats['vertices']+=1;weight_stats['max_weight_error']=max(weight_stats['max_weight_error'],abs(sum(weights.values())-1));weight_stats['max_influences']=max(weight_stats['max_influences'],len(weights))
  o.parent=rig;mod=o.modifiers.new('Explorer skeletal deformation','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
  o['original_asset']=True;o['reference']='explorer_reference_ai.png (AI-generated modeling guide, not a runtime texture)'

 # Consolidate matching material zones to reduce runtime draw overhead while keeping
 # head independently cullable. Material slots retain editing control in .blend.
 def consolidate(prefix,name):
  obs=[o for o in list(objects) if o.name.startswith(prefix)]
  bpy.ops.object.select_all(action='DESELECT')
  for o in obs:o.select_set(True)
  if not obs:return
  bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();obs[0].name=name
  for o in obs[1:]:
   if o in objects:objects.remove(o)
  return obs[0]
 body=consolidate('Body_','Body_Explorer');head=consolidate('Head_','Head_Explorer')
 # Normalize outward winding for all closed authored surface components.
 for obj in [body,head]:
  bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.update()
  bpy.context.view_layer.objects.active=obj
  for selected in bpy.context.selected_objects:selected.select_set(False)
  obj.select_set(True)
  # Continuous source surface remains reproducible in the generator; shipping mesh
  # reduction preserves vertex groups and all material seams.
  de=obj.modifiers.new('Shipping topology reduction','DECIMATE');de.ratio=.43 if obj==body else .68
  bpy.ops.object.modifier_apply(modifier=de.name)
  obj.select_set(False)
  # Match the glTF four-influence runtime contract in the editable source too.
  for v in obj.data.vertices:
   assignments=sorted([(g.group,g.weight) for g in v.groups],key=lambda x:-x[1])
   keep=assignments[:4];total=sum(w for _,w in keep)
   for group_index,weight in assignments[4:]:obj.vertex_groups[group_index].remove([v.index])
   if total>0:
    for group_index,weight in keep:obj.vertex_groups[group_index].add([v.index],weight/total,'REPLACE')

scene.render.fps=120
bpy.context.preferences.filepaths.save_version=0
# Contact-preserving gait, authored at 120 samples per normalized cycle.  +Y is
# forward; phase 0 is LEFT front contact and the RIGHT foot is half a cycle ahead.
# D is distance travelled by the controller in one full left/right cycle, not
# ankle sweep. Stance references travel exactly -D metres per normalized phase.
# Swing is a C2 quintic return with matching -D endpoint velocity. A heel/forefoot
# support pivot adds foot roll without moving the active ground contact.
GAITS={
 'Walk':dict(cycle_distance_m=1.15,stance_fraction=.56,lift=.065,heel=.12,toe=-.28,front_bias=0.,hip_mean=.832,hip_bob=.019,arm=.25),
 'Wade':dict(cycle_distance_m=1.05,stance_fraction=.62,lift=.105,heel=.07,toe=-.20,front_bias=0.,hip_mean=.821,hip_bob=.014,arm=.21),
 'Run':dict(cycle_distance_m=2.40,stance_fraction=.30,lift=.20,heel=-.10,toe=-.45,front_bias=-.03,hip_mean=.785,hip_bob=.032,arm=.48),
}
rig.animation_data_create()
ik_stats={name:dict(max_target_error_m=0.,min_reach_margin_m=10.,min_knee_flex_rad=10.,max_knee_flex_rad=0.) for name in GAITS}

def set_rot_world(name,angles):
 # This is an anatomical-axis LOCAL increment (for torso and arms). The feet use
 # explicit world-space IK below, so body sway/twist cannot leak into contact.
 pb=rig.pose.bones[name];basis=pb.bone.matrix_local.to_3x3().normalized().to_quaternion()
 q=Quaternion((1,0,0),angles[0]) @ Quaternion((0,1,0),angles[1]) @ Quaternion((0,0,1),angles[2])
 pb.rotation_mode='QUATERNION';pb.rotation_quaternion=basis.inverted()@q@basis

def ease(u):
 u=max(0.,min(1.,u));return u*u*(3.-2.*u)

def smoother(u):
 u=max(0.,min(1.,u));return u*u*u*(10.+u*(-15.+6.*u))

def quintic_hermite(a,b,va,vb,u):
 # Values and first derivatives at both ends; endpoint acceleration is zero.
 delta=b-a
 return a+va*u+(10*delta-6*va-4*vb)*u**3+(-15*delta+8*va+7*vb)*u**4+(6*delta-3*va-3*vb)*u**5

def foot_path(g,p,side):
 p=p%1.;stance=g['stance_fraction'];distance=g['cycle_distance_m']
 front=distance*stance*.5+g['front_bias'];rear=front-distance*stance
 heel_pivot=-.080 if g['heel']>=0 else .190
 toe_pivot=.190
 if p<=stance:
  y=front-distance*p;lift=0.
  if p<stance*.18:
   u=p/(stance*.18);pitch=g['heel']*(1.-ease(u));pivot=heel_pivot
  elif p>stance*.76:
   u=(p-stance*.76)/(stance*.24);pitch=g['toe']*ease(u);pivot=toe_pivot
  else:pitch=0.;pivot=0.
 else:
  u=(p-stance)/(1.-stance)
  # A single full-swing quintic overshoots reach at running speed. Localized
  # acceleration windows preserve contact velocity with only small, intentional
  # heel recovery/retraction, rather than clamping an impossible IK target.
  edge=.12;velocity=-distance*(1.-stance)*edge;overshoot=-velocity*.22
  if u<edge:y=quintic_hermite(rear,rear-overshoot,velocity,0.,u/edge)
  elif u>1.-edge:y=quintic_hermite(front+overshoot,front,0.,velocity,(u-1.+edge)/edge)
  else:y=rear-overshoot+(front-rear+2.*overshoot)*smoother((u-edge)/(1.-2.*edge))
  lift=g['lift']*16.*u*u*(1.-u)*(1.-u)
  pitch=g['toe']+(g['heel']-g['toe'])*ease(u)
  pivot=toe_pivot+(heel_pivot-toe_pivot)*ease(u)
 q=Quaternion((1,0,0),pitch)
 # Rigid shoe roll around its ground support, not around the ankle.
 relative=q@Vector((0.,-pivot,.115-.012))
 ankle=Vector((side*.108,y+pivot+relative.y,.012+relative.z+lift))
 return ankle,q

def desired_bone_matrix(name,head,tail):
 rest=rig.data.bones[name].matrix_local
 rest_dir=bones[name][1]-bones[name][0]
 q=rest_dir.rotation_difference(tail-head)
 return Matrix.Translation(head) @ q.to_matrix().to_4x4() @ rest.to_3x3().to_4x4()

def assign_global_pose(name,desired,parent_matrix):
 pb=rig.pose.bones[name];rest=pb.bone.matrix_local
 if pb.parent:
  inherited=parent_matrix @ pb.parent.bone.matrix_local.inverted() @ rest
 else:inherited=rest
 basis=inherited.inverted()@desired
 pb.rotation_mode='QUATERNION';pb.rotation_quaternion=basis.to_quaternion()
 # Analytic IK does not stretch the limbs or translate connected joints.
 pb.location=(0,0,0);pb.scale=(1,1,1)
 return desired

def leg_ik(side,sign,target,foot_rotation,hips_matrix,kind):
 upper='UpperLeg_'+side;lower='LowerLeg_'+side;foot='Foot_'+side
 hip=hips_matrix @ rig.data.bones['Hips'].matrix_local.inverted() @ bones[upper][0]
 l1=(bones[upper][1]-bones[upper][0]).length;l2=(bones[lower][1]-bones[lower][0]).length
 d=target-hip;raw=d.length;reach=min(l1+l2-.00001,max(abs(l1-l2)+.00001,raw));direction=d.normalized()
 # The pole is an anatomical forward knee, projected perpendicular to the leg.
 # Solving in 3D compensates pelvic sway, roll and yaw, not only sagittal swing.
 pole=Vector((0,1,0));bend=(pole-direction*pole.dot(direction)).normalized()
 along=(l1*l1-l2*l2+reach*reach)/(2.*reach)
 knee=hip+direction*along+bend*math.sqrt(max(0,l1*l1-along*along))
 actual_ankle=hip+direction*reach
 upper_matrix=assign_global_pose(upper,desired_bone_matrix(upper,hip,knee),hips_matrix)
 lower_matrix=assign_global_pose(lower,desired_bone_matrix(lower,knee,actual_ankle),upper_matrix)
 foot_matrix=Matrix.Translation(actual_ankle)@foot_rotation.to_matrix().to_4x4()@rig.data.bones[foot].matrix_local.to_3x3().to_4x4()
 assign_global_pose(foot,foot_matrix,lower_matrix)
 flex=math.pi-math.acos(max(-1.,min(1.,(l1*l1+l2*l2-reach*reach)/(2.*l1*l2))))
 stats=ik_stats[kind];stats['max_target_error_m']=max(stats['max_target_error_m'],(actual_ankle-target).length)
 stats['min_reach_margin_m']=min(stats['min_reach_margin_m'],l1+l2-raw)
 stats['min_knee_flex_rad']=min(stats['min_knee_flex_rad'],flex);stats['max_knee_flex_rad']=max(stats['max_knee_flex_rad'],flex)

def pose_at(kind,t):
 for pb in rig.pose.bones:pb.location=(0,0,0);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=(1,0,0,0);pb.scale=(1,1,1)
 phase=t*2*math.pi;run=kind=='Run';walk=kind in GAITS;hold=kind=='Hold';swim=kind=='Swim';climb=kind=='Climb'
 breath=math.sin(phase)
 set_rot_world('Spine',(.009*breath,0,0));set_rot_world('Chest',(-.009*breath,0,0))
 if walk:
  g=GAITS[kind]
  if run:
   half=t%.5
   hip_z=g['hip_mean']-g['hip_bob']*math.sin(math.pi*half/.30)**2 if half<=.30 else g['hip_mean']+g['hip_bob']*math.sin(math.pi*(half-.30)/.20)**2
  else:hip_z=g['hip_mean']-g['hip_bob']*math.cos(2*phase)
  sway=(.009 if run else .012)*math.sin(phase)
  rig.pose.bones['Hips'].location=rig.data.bones['Hips'].matrix_local.to_3x3().inverted()@Vector((sway,0,hip_z-.88))
  set_rot_world('Hips',(0,.012*math.sin(phase),.035*math.cos(phase)))
  set_rot_world('Spine',(-.115 if run else -.025,-.010*math.sin(phase),-.025*math.cos(phase)))
  set_rot_world('Chest',(.025 if run else .010,0,-.035*math.cos(phase)))
  set_rot_world('Neck',(.025 if run else .006,0,.012*math.cos(phase)))
 for sign in [-1,1]:
  side='L' if sign>0 else 'R';p=phase+(0 if sign>0 else math.pi)
  # Contralateral arm swing; slight elbow/wrist response avoids rigid pendulums.
  arm_swing=-math.cos(p)*g['arm'] if walk else .018*breath
  adduct=sign*.31
  elbow=(.95+.12*math.cos(p-.35)) if run else (.22+.055*math.cos(p-.35) if walk else .18)
  leg_swing=0.;knee=0.
  if kind=='Wade':elbow=.32+.045*math.cos(p-.30)
  if hold:arm_swing=1.0;adduct=sign*.22;elbow=.65
  if swim:arm_swing=.85+1.0*math.sin(p);adduct=sign*.20;elbow=.25+.3*(1+math.cos(p));leg_swing=.32*math.sin(p);knee=-.2
  if climb:arm_swing=2.25+.3*math.sin(p);adduct=sign*.16;elbow=.45+.3*math.cos(p);leg_swing=.45+.35*math.sin(p);knee=-.65-.3*math.sin(p)
  if walk:set_rot_world('Shoulder_'+side,(.015*math.cos(p),0,sign*.012*math.sin(p)))
  set_rot_world('UpperArm_'+side,(arm_swing,adduct,0))
  set_rot_world('Forearm_'+side,(elbow,0,0))
  set_rot_world('Hand_'+side,(-.06+(.025*math.cos(p-.4) if walk else 0),0,0))
  if not walk:
   set_rot_world('UpperLeg_'+side,(leg_swing,0,0));set_rot_world('LowerLeg_'+side,(knee,0,0));set_rot_world('Foot_'+side,(0,0,0))
  for fn in ['Index','Middle','Ring','Little']:
   set_rot_world(fn+'1_'+side,(.055 if not hold else .20,0,0));set_rot_world(fn+'2_'+side,(.10 if not hold else .27,0,0))
  set_rot_world('Thumb2_'+side,(.08,0,0))
 if walk:
  # Compute the actual hips transform without relying on a deferred depsgraph
  # evaluation. Rest Root remains identity in all locomotion cycles.
  hips=rig.pose.bones['Hips'];hips_matrix=hips.bone.matrix_local@hips.matrix_basis
  for side,sign,offset in [('L',1,0.),('R',-1,.5)]:
   target,rotation=foot_path(g,t+offset,sign);leg_ik(side,sign,target,rotation,hips_matrix,kind)
 if swim:set_rot_world('Spine',(.22,0,0));set_rot_world('Chest',(.10,0,0))
 if climb:set_rot_world('Spine',(.10,0,0))
 for pb in rig.pose.bones:
  pb.keyframe_insert('rotation_quaternion',frame=scene.frame_current,group=pb.name)
  if pb.name=='Hips':pb.keyframe_insert('location',frame=scene.frame_current,group=pb.name)

animations={}
for name,frames in [('Idle',288),('Walk',120),('Run',120),('Hold',288),('Wade',120),('Swim',184),('Climb',160)]:
 action=bpy.data.actions.new(name);action.use_fake_user=True;rig.animation_data.action=action
 # Frame ZERO is deliberate: starting at 1 exported an extra 1/fps delay and
 # duration on every old clip. Include both matching boundary samples exactly.
 for f in range(frames+1):scene.frame_set(f);pose_at(name,f/frames)
 for fc in action.fcurves:
  for key in fc.keyframe_points:key.interpolation='LINEAR'
 action['loop']=True;action['description']='Original in-place humanoid '+name.lower()+' cycle, metres, 120 Hz samples, frame zero origin.'
 animations[name]={'frames':frames,'duration':frames/120,'sample_rate_hz':120,'start_frame':0,'end_frame':frames}
 if name in GAITS:
  animations[name].update({k:GAITS[name][k] for k in ['cycle_distance_m','stance_fraction']})
  animations[name]['phase_zero']='left front contact; right foot phase offset +0.5'
rig.animation_data.action=bpy.data.actions.get('Idle');scene.frame_set(0)
rig['asset_license']='Original generated geometry, user project asset; no third-party character data.'
rig['coordinate_contract']='Blender +Y front, glTF/Godot -Z front; foot origin at floor, height 1.73 m.'
rig['quality_note']='Procedurally authored game-ready interpretation of reference, not a scan or photoreal likeness.'
# Keep reference sheets in the native file for artist editing, not GLB export.
if not animation_only:
 refs=bpy.data.collections.new('Reference — AI generated, editor only');scene.collection.children.link(refs)
 refimg=bpy.data.images.load(str(OUT/'explorer_reference_ai.png'));refimg.pack()
 for name,loc,rot in [('AI Turnaround',(0,-.50,1.0),(math.pi/2,0,0))]:
  empty=bpy.data.objects.new(name,None);empty.empty_display_type='IMAGE';empty.data=refimg;empty.empty_display_size=3.0;empty.location=loc;empty.rotation_euler=rot;empty.hide_render=True;empty['reference_only']=True;refs.objects.link(empty)
# Named rest pose stored separately in the source. All mesh edits remain available.
scene.frame_start=0;scene.frame_end=288
# Save native source with reference packed before export-only selection.
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'pool_explorer.blend'))
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True);body.select_set(True);head.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'pool_explorer.glb'),export_format='GLB',use_selection=True,
 export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,
 export_skins=True,export_all_influences=False,export_def_bones=False,export_yup=True,
 export_apply=False,export_materials='EXPORT',export_texcoords=True,export_normals=True,
 export_cameras=False,export_lights=False,export_extras=True,export_anim_single_armature=True)
# Godot deliberately preserves earlier extracted embedded PNGs. Synchronize our
# generated copies so reimport cannot silently retain the obsolete high-contrast weave.
import shutil
for material in ([] if animation_only else ['shirt','pants']):
 shutil.copyfile(OUT/('explorer_'+material+'_weave.png'),OUT/('pool_explorer_explorer_'+material+'_weave.png'))
# Stats include source and evaluated triangle counts for reproducible checks.
stats={'generator':'Blender '+bpy.app.version_string,'reference':'explorer_reference_ai.png','height_m':max(v.co.z for o in [body,head] for v in o.data.vertices),'bones':len(arm_data.bones),'connected_bones':sum(b.use_connect for b in arm_data.bones),'meshes':{},'weights':weight_stats,'animations':animations,'coordinate_contract':rig['coordinate_contract'],'quality_note':rig['quality_note'],'gait_ik':ik_stats,'gait_contract':{'phase_zero':'left front contact','right_phase_offset':.5,'phase_driver':'actual planar distance / blended cycle_distance_m','stance_reference_velocity':'minus cycle distance per normalized cycle','source_samples_start_at_zero':True}}
for o in [body,head]:
 o.data.calc_loop_triangles();stats['meshes'][o.name]={'vertices':len(o.data.vertices),'triangles':len(o.data.loop_triangles),'materials':len(o.data.materials),'vertex_groups':len(o.vertex_groups),'armature_modifiers':sum(m.type=='ARMATURE' for m in o.modifiers)}
stats['pre_reduction_weights']=stats.pop('weights')
final_sums=[sum(g.weight for g in v.groups) for ob in [body,head] for v in ob.data.vertices]
stats['weights']={'vertices':len(final_sums),'unweighted':sum(v<=0 for v in final_sums),'max_weight_error':max(abs(v-1) for v in final_sums),'max_influences':max(len(v.groups) for ob in [body,head] for v in ob.data.vertices),'multi_influence_vertices':sum(len(v.groups)>1 for ob in [body,head] for v in ob.data.vertices)}
import struct
_glb=(OUT/'pool_explorer.glb').read_bytes();_json_len=struct.unpack_from('<I',_glb,12)[0];_gltf=json.loads(_glb[20:20+_json_len])
for animation in _gltf.get('animations',[]):
 bounds=[]
 for sampler in animation['samplers']:
  accessor=_gltf['accessors'][sampler['input']];view=_gltf['bufferViews'][accessor['bufferView']]
  offset=28+_json_len+view.get('byteOffset',0)+accessor.get('byteOffset',0);stride=view.get('byteStride',4)
  bounds.append((struct.unpack_from('<f',_glb,offset)[0],struct.unpack_from('<f',_glb,offset+(accessor['count']-1)*stride)[0]))
 stats['animations'][animation['name']]['exported_start_s']=min(v[0] for v in bounds)
 stats['animations'][animation['name']]['exported_end_s']=max(v[1] for v in bounds)
 stats['animations'][animation['name']]['exported_duration_s']=max(v[1] for v in bounds)-min(v[0] for v in bounds)
(OUT/'avatar_manifest.json').write_text(json.dumps(stats,indent=2))
print('AVATAR_BUILD_RESULT '+json.dumps(stats))
