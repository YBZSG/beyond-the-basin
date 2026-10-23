"""Deterministic Blender 4.3 authoring. Metres; Godot-facing coordinates throughout.
Run: blender -b --python tools/blender/build_formal.py
Selected exports: append -- --only formal_sidepool formal_bath.
Unselected GLB/.blend files stay byte-identical; selected manifest sections update.
No water mesh: runtime owns water. COLLISION_ meshes are exact, uninflated proxies.
"""
import bpy, bmesh, math, os, json, sys, argparse
from mathutils import Vector
ARGS=argparse.ArgumentParser(description=__doc__)
ARGS.add_argument('--only',nargs='+',choices=['formal_arch','formal_mainhall','formal_arcade','formal_sidepool','formal_terrace','formal_bath'])
ONLY=ARGS.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []).only
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../..'))
OUT=os.path.join(ROOT,'assets/models/formal'); os.makedirs(OUT,exist_ok=True)
os.makedirs(os.path.join(ROOT,'tools/blender/source'),exist_ok=True)
open(os.path.join(ROOT,'tools/blender/source/.gdignore'),'a').close()
M={}
BOX_CACHE={}
# Seven risers include the final drop onto the continuous basin floor. Only six
# positive-height tread solids are needed; do not author a zero-height seventh.
DEEP_BASINS={
 'sidepool':{'basin_floor':-.52,'deck':.52,'water':.32,'stair_risers':7,'stair_tread':.65,'stair_width':4.8,'stair_entry_z':-4.0,'stair_direction_z':1},
 'bath':{'basin_floor':-.62,'deck':.52,'water':.32,'stair_risers':7,'stair_tread':.65,'stair_width':3.6,'stair_entry_z':6.0,'stair_direction_z':-1},
}
def basin_steps(room):
 c=DEEP_BASINS[room];rise=(c['deck']-c['basin_floor'])/c['stair_risers']
 return [(c['deck']-(i+1)*rise,c['stair_entry_z']+c['stair_direction_z']*(i+.5)*c['stair_tread']) for i in range(c['stair_risers']-1)]

def basin_contract(room):
 c=dict(DEEP_BASINS[room]);c['water_depth']=c['water']-c['basin_floor']
 c['stairs']=[top for top,z in basin_steps(room)]
 c['stair_centres_z']=[z for top,z in basin_steps(room)]
 c['stair_riser_height']=(c['deck']-c['basin_floor'])/c['stair_risers']
 c['stair_run']=(c['stair_risers']-1)*c['stair_tread']
 c['stair_floor_landing_z']=c['stair_entry_z']+c['stair_direction_z']*c['stair_run']
 c['stair_count_note']='Six solid treads plus the basin floor form seven equal risers; no zero-height stair.'
 c['depth_contract']='Geometry-only floor/walls/stairs/proxies update; water +0.32, source 1.04 m cap and 1.25/1.10 m swim latch unchanged.'
 return c
def reset():
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for d in list(bpy.data.materials): bpy.data.materials.remove(d)
 global M, BOX_CACHE
 M={}; BOX_CACHE={}
 for name,col,rough,metal in [('Ceramic',(.48,.69,.73,1),.24,0),('Plaster',(.89,.88,.82,1),.73,0),('Coping',(.79,.80,.75,1),.38,0),('Metal',(.4,.45,.46,1),.22,.85),('Drain',(.07,.10,.105,1),.6,.5),('Glazing',(.63,.79,.84,1),.15,0),('Collision',(1,0,1,1),1,0)]:
  m=bpy.data.materials.new('Formal_'+name);m.diffuse_color=col;m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=col;p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;M[name]=m
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1

def p(v):return (v[0],-v[2],v[1])
def mesh(name,verts,faces,mat='Plaster',bevel=0,collision=False,bevel_segments=3):
 me=bpy.data.meshes.new(name);me.from_pydata([p(v) for v in verts],[],faces);me.update();ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);ob.data.materials.append(M[mat])
 # Recalculate consistent normals then real-world triplanar UV by dominant normal.
 bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 uv=me.uv_layers.new(name='UVMap')
 for f in me.polygons:
  n=f.normal;axis=max(range(3),key=lambda i:abs(n[i])); axes=[i for i in range(3) if i!=axis]
  for li in f.loop_indices:
   co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
 if not collision:
  if bevel:
   mod=ob.modifiers.new('True scale softened edges','BEVEL');mod.width=bevel;mod.segments=bevel_segments;bpy.ops.object.modifier_apply(modifier=mod.name)
   mod=ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name)
  ob['units']='metres';ob['uv0']='1 UV unit = 1 metre; runtime ceramic pitch 0.1m';ob['uv2']='not baked'
 else:ob['collision_proxy']=True;ob.hide_render=True
 ob.select_set(False);return ob
F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
def box(name,c,s,mat='Plaster',bevel=.015,col=True):
 key=(tuple(round(v,5) for v in c),tuple(round(v,5) for v in s),mat)
 if key in BOX_CACHE:return BOX_CACHE[key]
 x,y,z=c;a,b,d=[v/2 for v in s];v=[(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)]
 ob=mesh(name,v,F,mat,bevel);BOX_CACHE[key]=ob
 if col:mesh('COLLISION_'+name,v,F,'Collision',0,True)
 return ob

def append_box(verts,faces,c,s):
 # Batched trim pieces: one material/mesh, not one draw per architectural joint.
 x,y,z=c;a,b,d=[v/2 for v in s];k=len(verts)
 verts.extend([(x-a,y-b,z-d),(x+a,y-b,z-d),(x+a,y+b,z-d),(x-a,y+b,z-d),(x-a,y-b,z+d),(x+a,y-b,z+d),(x+a,y+b,z+d),(x-a,y+b,z+d)])
 faces.extend([tuple(k+j for j in f) for f in F])

def coping_with_joints(name,c,s,axis):
 # Keep the original coping perimeter and .018 m / 3-segment edge bevel.
 # Cut 5 mm-wide joints into that actual mesh, with a 3 mm flat recess,
 # 4 mm below the top. These are not decals or a noisy texture overlay.
 # The original uninterrupted collision proxy remains exactly untouched.
 ob=box(name,c,s,'Coping',.018)
 along=0 if axis=='x' else 2;across=2 if axis=='x' else 0
 count=max(1,round(s[along]/1.05));pitch=s[along]/count
 joints=[c[along]-s[along]/2+i*pitch for i in range(1,count)]
 bm=bmesh.new();bm.from_mesh(ob.data)
 for joint in joints:
  for offset in [-.0025,-.0015,.0015,.0025]:
   co=list(c);co[along]=joint+offset
   normal=Vector((1,0,0) if axis=='x' else (0,1,0))
   bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=Vector(p(co)),plane_no=normal,clear_inner=False,clear_outer=False)
 for vert in bm.verts:
  co=[vert.co.x,vert.co.z,-vert.co.y]
  if any(abs(co[along]-joint)<=.001501 for joint in joints):
   # A shallow filled mortar joint: no open slot through the coping.
   height_fraction=max(0,min(1,(co[1]-(c[1]-s[1]/2))/s[1]))
   co[1]-=.004*height_fraction
   co[across]=c[across]+(co[across]-c[across])*(1-.004/s[across])
   vert.co=p(co)
 bm.normal_update();bm.to_mesh(ob.data);bm.free();ob.data.update()
 # Regenerate UV0 after cutting, retaining metres rather than tile-normalised UV.
 uv=ob.data.uv_layers[0]
 for face in ob.data.polygons:
  axis_id=max(range(3),key=lambda i:abs(face.normal[i]));axes=[i for i in range(3) if i!=axis_id]
  for li in face.loop_indices:
   co=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
 ob['junction_detail']='Recessed physical coping joints; original perimeter bevel and collision preserved'
 ob['joint_centres_metres']=joints;ob['joint_width_metres']=.005;ob['joint_recess_metres']=.004
 return ob

def inset_stair(name,top,z,nosing_verts,nosing_faces,width=4.8,floor=-.12,tread=.42):
 # The pale nosing occupies a shallow seat cut OUT of the visual tread; its
 # top is flush, never raised. Defaults preserve main/terrace box proxies.
 c=(0,(top+floor)/2,z);s=(width,top-floor,tread)
 original=box(name,c,s,'Ceramic',.008)
 bpy.data.objects.remove(original,do_unlink=True)
 BOX_CACHE.pop((tuple(round(v,5) for v in c),tuple(round(v,5) for v in s),'Ceramic'))
 front=z-tread/2;back=z+tread/2;seat=.055;depth=.028
 profile=[(floor,front),(floor,back),(top,back),(top,front+seat),(top-depth,front+seat),(top-depth,front)]
 verts=[(x,y,u) for x in [-width/2,width/2] for y,u in profile]
 faces=[tuple(range(5,-1,-1)),tuple(range(6,12))]
 faces.extend([(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)])
 ob=mesh(name,verts,faces,'Ceramic',.008)
 ob['nosing_seat_depth_metres']=depth;ob['tread_top_metres']=top
 append_box(nosing_verts,nosing_faces,(0,top-depth/2,front+(seat-.001)/2),(width,depth,seat-.001))

def mainhall_termination_caps():
 # Ceramic trim bridges the tile/plaster seam only where ceramic already ends.
 # Aggregate pieces into one draw; portal intervals and all proxies are unchanged.
 verts=[];faces=[];pieces=[]
 for ob in list(bpy.context.scene.objects):
  if ob.type!='MESH' or not ob.name.startswith('Main_'):continue
  if not ('_TileWainscot' in ob.name or '_CeramicFoot' in ob.name):continue
  coords=[(v.co.x,v.co.z,-v.co.y) for v in ob.data.vertices]
  low=[min(v[i] for v in coords) for i in range(3)];high=[max(v[i] for v in coords) for i in range(3)]
  c=[(a+b)/2 for a,b in zip(low,high)];s=[b-a for a,b in zip(low,high)]
  c[1]=high[1]-.002;s[1]=.036
  if '_CeramicFoot' in ob.name:s[0]+=.020;s[2]+=.020
  elif s[0]<s[2]:s[0]+=.024
  else:s[2]+=.024
  append_box(verts,faces,c,s);pieces.append({'at':ob.name,'centre':c,'size':s})
 ob=mesh('Main_CopingArchitecturalCaps',verts,faces,'Coping',.003,bevel_segments=1)
 ob['junction_detail']='36 mm ceramic cap at the existing wall/pier tile-plaster termination'
 ob['cap_pieces_json']=json.dumps(pieces,sort_keys=True)

def arch(name,center,span,spring,rise,thick=.32,depth=.55,axis='x',cols=True,base=.52):
 # Elliptical intrados/extrados, 72 segments; single manifold uninterrupted arch mesh.
 cx,cz=center;N=72;verts=[]
 for i in range(N+1):
  t=math.pi*i/N
  for r,h in [(span/2,rise),(span/2+thick,rise+thick)]:
   for dep in [-depth/2,depth/2]:
    u=r*math.cos(t);y=spring+h*math.sin(t);verts.append((cx+u,y,cz+dep) if axis=='x' else (cx+dep,y,cz+u))
 faces=[]
 for i in range(N):
  a=i*4;b=a+4;faces.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
 faces.extend([(0,1,3,2),(N*4,N*4+2,N*4+3,N*4+1)])
 ob=mesh(name,verts,faces,'Plaster',.008)
 for poly in ob.data.polygons:poly.use_smooth=True
 if cols:
  for sign in [-1,1]:
   u=sign*(span/2+thick/2);x=cx+u if axis=='x' else cx;z=cz if axis=='x' else cz+u
   size=(thick,spring-base,depth) if axis=='x' else (depth,spring-base,thick)
   box(name+'_Pier'+str(sign),(x,(spring+base)/2,z),size,'Plaster',.012)
   box(name+'_CeramicFoot'+str(sign),(x,(base+1.28)/2,z),(size[0]+.035,1.28-base,size[2]+.035),'Ceramic',.008,col=False)
 # Exact enclosed arch sectors, unsimplified convex proxies; no hull across aperture.
 for i in range(0,N,6):
  vs=verts[i*4:i*4+4]+verts[(i+6)*4:(i+6)*4+4]
  mesh('COLLISION_'+name+'_sector'+str(i),vs,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],'Collision',0,True)

def drain(name,c,length,axis='x'):
 # Preserve the exact channel receiver and floor/collision geometry. Only the
 # existing Metal grating changes: 12 mm ribs / 5 mm slots, in removable panels.
 x,y,z=c;s=(length,.025,.16) if axis=='x' else (.16,.025,length);box(name,c,s,'Drain',.003,False)
 vs=[];fs=[];panels=max(1,math.ceil(length/1.2));pitch=length/panels
 def slat(along,across,along_size,across_size,bottom,top):
  centre=(x+along,(bottom+top)/2,z+across) if axis=='x' else (x+across,(bottom+top)/2,z+along)
  size=(along_size,top-bottom,across_size) if axis=='x' else (across_size,top-bottom,along_size)
  append_box(vs,fs,centre,size)
 for panel in range(panels):
  centre=-length/2+(panel+.5)*pitch;span=pitch-.003
  for rib in range(9):slat(centre,(rib-4)*.017,span-.012,.012,y+.016,y+.024)
  # Six-millimetre end ties close and support each slat; underside rests on the
  # unchanged channel's top, while the panel joint remains only 3 mm wide.
  for sign in [-1,1]:slat(centre+sign*(span-.006)/2,0,.006,.148,y+.0125,y+.024)
 ob=mesh(name+'_Grating',vs,fs,'Metal',0)
 ob['detail_design']='Removable longitudinal stainless grate panels; no code-compliance claim'
 ob['rib_width_metres']=.012;ob['slot_width_metres']=.005
 ob['panel_joint_metres']=.003;ob['panel_pitch_metres']=pitch
 ob['panel_count']=panels;ob['rib_count_per_panel']=9;ob['channel_receiver_preserved']=True

def cylinder_between(name,start,end,radius,mat='Metal',segments=20,collision=False):
 # Explicit capped cylinder, all vertices authored in room metres. No imported
 # transform or overreaching convex hull; a proxy only covers this one segment.
 a=Vector(start);b=Vector(end);t=(b-a).normalized()
 reference=Vector((1,0,0)) if abs(t.x)<.9 else Vector((0,0,1))
 u=t.cross(reference).normalized();v=t.cross(u).normalized()
 verts=[tuple(q+radius*(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments))) for q in [a,b] for i in range(segments)]
 faces=[tuple(range(segments-1,-1,-1)),tuple(range(segments,segments*2))]
 faces.extend([(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)])
 ob=mesh(name,verts,faces,mat,0,collision)
 if not collision:
  for poly in ob.data.polygons:poly.use_smooth=len(poly.vertices)==4
 return ob

def fillet_polyline(points,radius=.16,steps=8):
 # Circular elbow, not an unconstrained auto-Bezier spline. Straight embedded
 # posts and the sloping grip stay straight; corner radius is physically known.
 result=[Vector(points[0])]
 for i in range(1,len(points)-1):
  before=Vector(points[i-1]);corner=Vector(points[i]);after=Vector(points[i+1])
  incoming=(corner-before).normalized();outgoing=(after-corner).normalized()
  angle=math.acos(max(-1,min(1,incoming.dot(outgoing))))
  if angle<1e-5:result.append(corner);continue
  tangent=min(radius*math.tan(angle/2),(corner-before).length*.35,(after-corner).length*.35)
  actual_radius=tangent/math.tan(angle/2)
  start=corner-incoming*tangent;end=corner+outgoing*tangent
  normal=incoming.cross(outgoing).normalized()
  center=start+normal.cross(incoming)*actual_radius
  radial=start-center
  result.append(start)
  for k in range(1,steps+1):
   theta=angle*k/steps
   result.append(center+radial*math.cos(theta)+normal.cross(radial)*math.sin(theta))
 result.append(Vector(points[-1]))
 return result

def tube(name,points,r=.038,bend=.16,collision=True):
 path=fillet_polyline(points,bend);segments=24;verts=[];length=0;lengths=[]
 for i,q in enumerate(path):
  if i:length+=(q-path[i-1]).length
  lengths.append(length)
  t=((path[min(i+1,len(path)-1)]-path[max(i-1,0)])).normalized()
  # This rail lies in a Y/Z plane. Fixed lateral vector prevents UV/frame twist.
  u=Vector((1,0,0));v=t.cross(u).normalized()
  verts.extend([tuple(q+r*(u*math.cos(j*math.tau/segments)+v*math.sin(j*math.tau/segments))) for j in range(segments)])
 faces=[tuple(range(segments-1,-1,-1))]
 for i in range(len(path)-1):
  for j in range(segments):faces.append((i*segments+j,i*segments+(j+1)%segments,(i+1)*segments+(j+1)%segments,(i+1)*segments+j))
 faces.append(tuple((len(path)-1)*segments+j for j in range(segments)))
 ob=mesh(name,verts,faces,'Metal')
 for face in ob.data.polygons:face.use_smooth=len(face.vertices)==4
 uv=ob.data.uv_layers[0]
 for face in ob.data.polygons:
  for li in face.loop_indices:
   vi=ob.data.loops[li].vertex_index;ring=vi//segments;j=vi%segments
   if j==0 and any(ob.data.loops[k].vertex_index%segments==segments-1 for k in face.loop_indices):j=segments
   uv.data[li].uv=(lengths[ring],math.tau*r*j/segments)
 ob['diameter_metres']=r*2;ob['bend_radius_metres']=bend
 ob['construction']='Continuous capped round stainless tube, circular elbows, deck and basin socket mounts'
 if collision:
  # Coarse straight zones plus local elbow sectors, never one hull across stairs.
  for i in range(len(path)-1):
   cylinder_between('COLLISION_'+name+'_segment'+str(i),path[i],path[i+1],r,'Collision',8,True)
 return ob

def rail_socket(name,x,z,floor):
 cylinder_between(name+'_Plate',(x,floor+.002,z),(x,floor+.026,z),.105)
 cylinder_between(name+'_Collar',(x,floor+.026,z),(x,floor+.116,z),.053)
 # Four flush screw heads, visible at close range but no decorative collision.
 for dx,dz in [(-.068,0),(.068,0),(0,-.068),(0,.068)]:
  cylinder_between(name+'_Fixing'+str((dx,dz)),(x+dx,floor+.026,z+dz),(x+dx,floor+.030,z+dz),.009,segments=12)

def wall(name,axis,pos,length,height,opening=False,portal_width=8.0):
 # Real clerestory apertures, not luminous decals; explicitly sized portals.
 intervals=[(-length/2,-portal_width/2),(portal_width/2,length/2)] if opening else [(-length/2,length/2)]
 for j,(a,b) in enumerate(intervals):
  w=b-a;c=(a+b)/2
  def wb(suffix,cy,h,mat):box(name+str(j)+suffix,(c,cy,pos) if axis=='x' else (pos,cy,c),(w,h,.35) if axis=='x' else (.35,h,w),mat,.012)
  wb('_Lower',2.34,1.72,'Plaster');wb('_TileWainscot',1.00,.96,'Ceramic')
  wb('_Head',height-.15,.30,'Plaster')
  # mullions and deep sill, glass moved to outer face
  wb('_Sill',3.25,.10,'Coping')
  # Deep finished reveals wrap each true clerestory opening.
  for edge,u in enumerate([a+.07,b-.07]):
   box(name+str(j)+'_WindowReveal'+str(edge),(u,3.9,pos) if axis=='x' else (pos,3.9,u),(.14,1.2,.52) if axis=='x' else (.52,1.2,.14),'Plaster',.008,False)
  box(name+str(j)+'_WindowSoffit',(c,4.45,pos) if axis=='x' else (pos,4.45,c),(w,.10,.52) if axis=='x' else (.52,.10,w),'Plaster',.008,False)
  for k in range(max(1,int(w/2.4))+1):
   u=a+w*k/max(1,int(w/2.4));box(name+str(j)+'_Mullion'+str(k),(u,3.86,pos) if axis=='x' else (pos,3.86,u),(.055,1.13,.40) if axis=='x' else (.40,1.13,.055),'Metal',.002,False)
  box(name+str(j)+'_Glass',(c,3.86,pos) if axis=='x' else (pos,3.86,c),(max(.1,w-.1),1.1,.025) if axis=='x' else (.025,1.1,max(.1,w-.1)),'Glazing',0,False)
 if opening:
  box(name+'_PortalHead',(0,(3.3+height)/2,pos) if axis=='x' else (pos,(3.3+height)/2,0),(portal_width,height-3.3,.35) if axis=='x' else (.35,height-3.3,portal_width),'Plaster',.015)

def ramp(name,axis,start,end,width=8):
 # surface descending from deck .52 at room boundary to legacy -.72 at cell portal.
 v=[]
 for u,top in [(start,.52),(end,-.72)]:
  for side,y in [(-width/2,top-.25),(width/2,top-.25),(width/2,top),(-width/2,top)]:v.append((u,y,side) if axis=='x' else (side,y,u))
 mesh(name,v,F,'Ceramic',.005);mesh('COLLISION_'+name,v,F,'Collision',0,True)

def local_sector_proxy(name,verts,faces,angle):
 # Store each sector in its own rotated local frame. The original source-water
 # depth extractor retains this transform and uses an OBB, not a world AABB.
 centre=Vector((sum(v[0] for v in verts)/len(verts),0,sum(v[2] for v in verts)/len(verts)))
 c=math.cos(angle);s=math.sin(angle)
 local=[]
 for x,y,z in verts:
  dx=x-centre.x;dz=z-centre.z
  local.append((c*dx+s*dz,y,-s*dx+c*dz))
 ob=mesh('COLLISION_'+name,local,faces,'Collision',0,True)
 ob.location=p(centre);ob.rotation_euler=(0,0,-angle)
 ob['terrain_proxy']='Locally oriented exact sector; preserve object rotation for native OBB depth extraction'
 return ob

def perimeter_band(name,inner,outer,low,high,mat='Plaster',skip=None,col=True,bevel=.008,include_inner=True):
 # Continuous manifold ring/run, shared edge vertices, flat horizontal tops.
 # A skip predicate carves actual portals: no hidden whole-ring collision hull.
 count=len(inner)-1;active=[not(skip and skip(i)) for i in range(count)]
 verts=[]
 for a,b in zip(inner[:-1],outer[:-1]):verts.extend([(a[0],low,a[1]),(b[0],low,b[1]),(a[0],high,a[1]),(b[0],high,b[1])])
 faces=[]
 for i,enabled in enumerate(active):
  if not enabled:continue
  a=i*4;b=((i+1)%count)*4
  faces.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a+1,b+1,b+3,a+3)])
  if include_inner:faces.append((a,a+2,b+2,b))
  if not active[(i-1)%count]:faces.append((a,a+1,a+3,a+2))
  if not active[(i+1)%count]:faces.append((b,b+2,b+3,b+1))
  if col:
   corners=[inner[i],outer[i],outer[i+1],inner[i+1]]
   pv=[(x,y,z) for y in [low,high] for x,z in corners]
   edge=(inner[i+1][0]-inner[i][0],inner[i+1][1]-inner[i][1])
   angle=math.atan2(-edge[0],edge[1])
   local_sector_proxy(name+'_sector'+str(i),pv,F,angle)
 ob=mesh(name,verts,faces,mat,0)
 for face in ob.data.polygons:face.use_smooth=abs(face.normal.z)<.1
 if bevel:
  bpy.context.view_layer.objects.active=ob;ob.select_set(True)
  mod=ob.modifiers.new('Controlled continuous masonry edges','BEVEL');mod.width=bevel;mod.segments=3;mod.harden_normals=True;bpy.ops.object.modifier_apply(modifier=mod.name)
  mod=ob.modifiers.new('Preserved planar caps and smooth walls','WEIGHTED_NORMAL');mod.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
 ob['construction']='Continuous swept masonry with real aperture intervals and individual rotated collision sectors'
 return ob

def circle_points(radius,angles):return [(radius*math.cos(a),radius*math.sin(a)) for a in angles]

def bath_outline(angles,offset=0):
 # Circle union a 3.6 m-wide south stair alcove. This is a geometric cutout,
 # not a rectangular water plane pasted over an uncut deck.
 points=[]
 for angle in angles:
  x=math.cos(angle);z=math.sin(angle);radius=4.8
  if z>0:
   rect=min(1.8/max(abs(x),1e-12),6.0/z)
   radius=max(radius,rect)
  radius+=offset
  points.append((radius*x,radius*z))
 return points

def bath_dome(name,angles):
 # A low, smooth paraboloid vault with a real 3.6 m central oculus.
 rings=20;radii=[1.8+(9.16-1.8)*i/rings for i in range(rings+1)]
 verts=[]
 for above in [0,.24]:
  for radius in radii:
   y=4.6+1.02*(1-(radius/9.16)**2)+above
   verts.extend([(radius*math.cos(a),y,radius*math.sin(a)) for a in angles])
 stride=len(angles);layer=stride*len(radii);faces=[]
 for k in range(rings):
  for j in range(stride-1):
   a=k*stride+j;b=a+stride
   faces.append((a,a+1,b+1,b));faces.append((a+layer,b+layer,b+1+layer,a+1+layer))
 for j in range(stride-1):
  for k in [0,rings]:
   a=k*stride+j;faces.append((a,a+layer,a+1+layer,a+1))
 ob=mesh(name,verts,faces,'Plaster',0)
 for face in ob.data.polygons:face.use_smooth=True
 ob['ceiling_edge_metres']=4.6;ob['ceiling_oculus_metres']=4.6+1.02*(1-(1.8/9.16)**2)
 return ob

def connector(name,axis,start,end,width=6.0,ceiling=3.15):
 ramp(name,axis,start,end,width)
 length=abs(end-start);middle=(start+end)/2
 # Raised tiled returns hug the actual ramp, with a solid plaster backing.
 for sign in [-1,1]:
  side=sign*(width/2+.12)
  box(name+'_SideWall'+str(sign),(middle,1.10,side) if axis=='x' else (side,1.10,middle),(length,4.10,.24) if axis=='x' else (.24,4.10,length),'Plaster',.008)
  vertices=[]
  for u,top in [(start,.52),(end,-.72)]:
   for across,y in [(side-.125,top+.03),(side+.125,top+.03),(side+.125,top+.99),(side-.125,top+.99)]:vertices.append((u,y,across) if axis=='x' else (across,y,u))
  mesh(name+'_TileReturn'+str(sign),vertices,F,'Ceramic',.005)
 # Split roof leaves a real slender top-light, not emissive imitation glazing.
 roof_width=(width-.8)/2
 for sign in [-1,1]:
  across=sign*(.4+roof_width/2)
  box(name+'_Roof'+str(sign),(middle,ceiling+.10,across) if axis=='x' else (across,ceiling+.10,middle),(length,.20,roof_width) if axis=='x' else (roof_width,.20,length),'Plaster',.008)
 box(name+'_Glazing',(middle,ceiling+.25,0) if axis=='x' else (0,ceiling+.25,middle),(length,.02,.80) if axis=='x' else (.80,.02,length),'Glazing',0,False)

def enclose_retained_ramp(name,axis,start,end,width,end_width=None,ceiling=3.15):
 # Add construction around an unchanged historical ramp. Its original visible
 # floor and collision proxy are deliberately authored separately and untouched.
 # The east mainhall half gently meets the narrower 6 m arcade at the grid seam.
 end_width=width if end_width is None else end_width
 thickness=.24
 def band(sign,a,b):return tuple(sorted((sign*a,sign*b)))
 def prism(suffix,edges,heights,material='Plaster',bevel=.008,col=False):
  vertices=[]
  for u,(a,b),(low,high) in zip([start,end],edges,heights):
   for side,y in [(a,low),(b,low),(b,high),(a,high)]:vertices.append((u,y,side) if axis=='x' else (side,y,u))
  ob=mesh(name+suffix,vertices,F,material,bevel)
  ob['retained_connector_enclosure']=True
  ob['clear_width_start_metres']=width;ob['clear_width_end_metres']=end_width
  if col:mesh('COLLISION_'+name+suffix,vertices,F,'Collision',0,True)
  return ob
 def wall_metres(ob,sign):
  # Exact metre UVs on the inclined vertical wall plane, not the shortened
  # dominant-axis projection. This keeps 100 mm ceramic rows physically scaled.
  du=end-start;ds=sign*(end_width-width)/2
  tangent=Vector((du,0,ds) if axis=='x' else (ds,0,du)).normalized()
  normal=Vector((-tangent.z,0,tangent.x))
  uv=ob.data.uv_layers[0]
  for face in ob.data.polygons:
   n=Vector((face.normal.x,face.normal.z,-face.normal.y))
   if abs(n.dot(normal))<.70:continue
   for li in face.loop_indices:
    q=ob.data.vertices[ob.data.loops[li].vertex_index].co
    q=Vector((q.x,q.z,-q.y));uv.data[li].uv=(q.dot(tangent),q.y)
 for sign in [-1,1]:
  edges=[band(sign,half,half+thickness) for half in [width/2,end_width/2]]
  wall=prism('_EnclosureWall'+str(sign),edges,[(-.97,ceiling)]*2,col=True)
  wall_metres(wall,sign)
  edges=[band(sign,half-.010,half+.006) for half in [width/2,end_width/2]]
  tile=prism('_EnclosureTileReturn'+str(sign),edges,[(top+.008,top+.968) for top in [.52,-.72]],'Ceramic',.003)
  wall_metres(tile,sign)
  edges=[band(sign,half-.020,half+.008) for half in [width/2,end_width/2]]
  prism('_EnclosureCopingReturn'+str(sign),edges,[(top+.968,top+.998) for top in [.52,-.72]],'Coping',.003)
  # Full 240 mm bearing over the wall, with 200 mm solid roof thickness.
  edges=[band(sign,.40,half+thickness) for half in [width/2,end_width/2]]
  prism('_EnclosureRoof'+str(sign),edges,[(ceiling,ceiling+.20)]*2,col=True)
  prism('_EnclosureRooflightCurb'+str(sign),[band(sign,.40,.48)]*2,[(ceiling+.20,ceiling+.32)]*2,bevel=.004)
 glass=prism('_EnclosureRooflightGlass',[(-.48,.48)]*2,[(ceiling+.32,ceiling+.34)]*2,'Glazing',0)
 glass['clear_rooflight_width_metres']=.80

def low_courtyard_wall(name,axis,pos,length,opening=False,height=2.45):
 intervals=[(-length/2,-3),(3,length/2)] if opening else [(-length/2,length/2)]
 for i,(a,b) in enumerate(intervals):
  c=(a+b)/2;w=b-a
  for suffix,cy,h,material,thick in [('Wainscot',1.0,.96,'Ceramic',.40),('Upper',(1.48+height)/2,height-1.48,'Plaster',.36),('Cap',height+.035,.07,'Coping',.46)]:
   box(name+'_'+suffix+str(i),(c,cy,pos) if axis=='x' else (pos,cy,c),(w,h,thick) if axis=='x' else (thick,h,w),material,.01)
 if opening:
  for sign in [-1,1]:
   u=sign*3.2
   box(name+'_PortalJamb'+str(sign),(u,1.86,pos) if axis=='x' else (pos,1.86,u),(.4,2.68,.65) if axis=='x' else (.65,2.68,.4),'Plaster',.018)
  box(name+'_PortalLintel',(0,3.43,pos) if axis=='x' else (pos,3.43,0),(6.8,.46,.65) if axis=='x' else (.65,.46,6.8),'Plaster',.018)

def save(name):
 if ONLY and name not in ONLY:return
 bpy.ops.object.select_all(action='DESELECT')
 visible=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.name.startswith('COLLISION_')]
 for o in visible:
  o.select_set(True);o.data.uv_layers.new(name='UV2_Lightmap');o.data.uv_layers.active_index=1
 if visible:
  bpy.context.view_layer.objects.active=visible[0];bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=1.15192,island_margin=.006);bpy.ops.object.mode_set(mode='OBJECT')
 for o in visible:o.data.uv_layers.active_index=0;o['uv2']='packed nonoverlapping smart projection, unbaked'
 bpy.ops.object.select_all(action='DESELECT');bpy.context.scene['authoring']='PoolCore formal reconstruction, Blender 4.3.2; not bit-identical to lost source';bpy.context.scene['runtime_water']='separate Godot simulation, surface y=.32'
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'tools/blender/source',name+'.blend'))
 bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),export_format='GLB',export_yup=True,export_apply=True,export_extras=True,export_cameras=False,export_lights=False)
 print('FORMAL_SAVED',name,len(bpy.data.objects))

class FittedDetails:
 """Small closed maintenance fittings, grouped by finish, never fake openings."""
 def __init__(self,prefix):
  self.prefix=prefix;self.parts={'Metal':([],[]),'Drain':([],[])};self.smooth=[];self.records=[]
 def basis(self,normal):
  n=Vector(normal);return Vector((n.z,0,-n.x)),Vector((0,1,0)),n
 def local_box(self,material,centre,normal,width,height,back,front,du=0,dv=0):
  vs,fs=self.parts[material];u,v,n=self.basis(normal);c=Vector(centre)+u*du+v*dv+n*(back+front)/2;k=len(vs)
  for a,b,d in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:vs.append(tuple(c+u*a*width/2+v*b*height/2+n*d*(front-back)/2))
  fs.extend([tuple(k+j for j in face) for face in F])
 def cylinder(self,material,centre,normal,radius,back,front,segments=48):
  vs,fs=self.parts[material];u,v,n=self.basis(normal);c=Vector(centre);k=len(vs)
  for d in [back,front]:
   vs.extend(tuple(c+n*d+radius*(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments))) for i in range(segments))
  fs.extend([tuple(k+j for j in range(segments-1,-1,-1)),tuple(k+segments+j for j in range(segments))])
  fs.extend([(k+i,k+(i+1)%segments,k+(i+1)%segments+segments,k+i+segments) for i in range(segments)])
 def proxy(self,label,centre,normal,width,height,depth):
  # A small convex cover envelope is truthful here: no opening is passable,
  # and no support wall or basin-depth proxy is removed or replaced.
  before=self.parts['Metal'];self.parts['Metal']=([],[])
  self.local_box('Metal',centre,normal,width,height,0,depth)
  vs,fs=self.parts['Metal'];self.parts['Metal']=before
  ob=mesh('COLLISION_'+self.prefix+'_'+label,vs,fs,'Collision',0,True)
  ob['proxy_purpose']='Capsule-scale envelope of a closed surface-mounted fitting; not an opening'
 def return_cover(self,label,centre,normal,radius=.048):
  vs,fs=self.parts['Metal'];u,v,n=self.basis(normal);c=Vector(centre);k=len(vs);N=48;inside=radius*.53
  profile=[(radius,.001),(radius,.0085),(radius-.0015,.010),(inside+.0015,.010),(inside,.0085),(inside,.001)]
  for r,d in profile:vs.extend(tuple(c+n*d+r*(u*math.cos(i*math.tau/N)+v*math.sin(i*math.tau/N))) for i in range(N))
  for j in range(len(profile)):
   for i in range(N):
    if j in [0,1,3,4]:self.smooth.append(len(fs))
    fs.append((k+j*N+i,k+j*N+(i+1)%N,k+((j+1)%len(profile))*N+(i+1)%N,k+((j+1)%len(profile))*N+i))
  self.cylinder('Drain',centre,normal,inside-.0005,.001,.002)
  self.proxy(label,centre,normal,radius*2,radius*2,.0105)
  self.records.append({'kind':'closed_basin_return_cover','label':label,'centre':centre,'normal':normal,'outer_radius':radius,'front_projection':.010,'water_y':.32,'interactive':False})
 def skimmer_cover(self,label,centre,normal):
  w=.32;h=.15;t=.016
  self.local_box('Drain',centre,normal,w-.012,h-.012,.001,.002)
  for sign in [-1,1]:
   self.local_box('Metal',centre,normal,t,h,.002,.014,du=sign*(w-t)/2)
   self.local_box('Metal',centre,normal,w-2*t,t,.002,.014,dv=sign*(h-t)/2)
   self.local_box('Metal',centre,normal,w-2*t,.004,.005,.012,dv=sign*.022)
  self.proxy(label,centre,normal,w,h,.0145)
  self.records.append({'kind':'closed_skimmer_service_face','label':label,'centre':centre,'normal':normal,'size':[w,h],'front_projection':.014,'water_y':.32,'interactive':False})
 def access_cover(self,label,centre,normal,width=.78,height=.62):
  t=.010;u,v,n=self.basis(normal);c=Vector(centre)
  self.local_box('Drain',centre,normal,width-.008,height-.008,.002,.003)
  for sign in [-1,1]:
   self.local_box('Metal',centre,normal,t,height,.004,.023,du=sign*(width-t)/2)
   self.local_box('Metal',centre,normal,width-2*t,t,.004,.023,dv=sign*(height-t)/2)
  # The tile-faced, screw-fastened cover has no door handle or interaction.
  temp=self.parts['Metal'];self.parts['Metal']=([],[])
  self.local_box('Metal',centre,normal,width-.030,height-.030,.008,.020)
  vs,fs=self.parts['Metal'];self.parts['Metal']=temp
  cover=mesh(self.prefix+'_'+label+'_TileFace',vs,fs,'Ceramic',.002,bevel_segments=1)
  cover['detail_function']='Closed, tool-fastened maintenance cover; not a usable doorway'
  for x in [-1,1]:
   for y in [-1,1]:
    screw=c+u*x*(width/2-.035)+v*y*(height/2-.035)
    self.cylinder('Metal',screw,normal,.006,.020,.026,24)
    self.local_box('Drain',screw,normal,.007,.0015,.026,.0265)
  self.proxy(label,centre,normal,width,height,.027)
  self.records.append({'kind':'closed_tool_fastened_access_cover','label':label,'centre':centre,'normal':normal,'size':[width,height],'front_projection':.0265,'interactive':False})
 def finish(self):
  for role,(verts,faces) in self.parts.items():
   if not verts:continue
   ob=mesh(self.prefix+('_StainlessHardware' if role=='Metal' else '_DarkInserts'),verts,faces,role,0)
   if role=='Metal':
    for face in self.smooth:ob.data.polygons[face].use_smooth=True
   ob['fitted_detail_records_json']=json.dumps(self.records,sort_keys=True)
   ob['detail_scope']='Fixed non-interactive service fittings, not simulated water emitters'

def add_main_fittings():
 details=FittedDetails('Main_Fitted')
 for side in [-1,1]:
  for z in [-3.8,3.8]:details.return_cover('Return'+str((side,z)),(side*7.9195,.045,z),(-side,0,0))
 details.skimmer_cover('Skimmer',(5.7,.32,-5.9195),(0,0,1))
 details.access_cover('ServiceAccess',(-7.6,1.05,-9.8245),(0,0,1))
 details.finish()

def add_terrace_fittings():
 details=FittedDetails('Terrace_Fitted')
 for side in [-1,1]:
  for z in [-2.2,2.2]:details.return_cover('Return'+str((side,z)),(side*5.9195,.205,z),(-side,0,0),.042)
 details.skimmer_cover('Skimmer',(3.8,.32,-3.9195),(0,0,1));details.finish()

def add_side_fittings():
 details=FittedDetails('Side_Fitted')
 for side in [-1,1]:details.return_cover('Return'+str(side),(side*3.9195,.045,.9),(-side,0,0))
 details.skimmer_cover('Skimmer',(2.1,.32,3.9195),(0,0,-1));details.finish()
 # Built into the existing west dado, between structural arch piers. The
 # original 3 m deck retains a 1.87 m clear passage past the seat and coping.
 box('Side_Fitted_BenchPlinth',(-6.60,.70,0),(.38,.36,3.08),'Plaster',.012)
 seat=box('Side_Fitted_BenchSeat',(-6.52,.925,0),(.58,.09,3.2),'Coping',.022)
 seat['seat_height_above_deck_metres']=.45;seat['clear_deck_passage_metres']=1.87
 box('Side_Fitted_BenchBack',(-6.76,1.18,0),(.08,.42,3.2),'Ceramic',.008)

def add_arcade_fittings():
 # A shallow built-in service cabinet, not an invented door or loose prop.
 # Its front remains behind the existing bench line; no new route intrusion.
 box('Arcade_Fitted_ServicePlinth',(-4,.575,2.65),(.90,.11,.26),'Plaster',.008)
 body=box('Arcade_Fitted_ServiceCabinet',(-4,1.105,2.62),(.96,.95,.34),'Plaster',.012)
 body['detail_function']='Closed maintenance cabinet; non-interactive; no wall opening'
 box('Arcade_Fitted_ServiceCounter',(-4,1.615,2.61),(1.04,.07,.38),'Coping',.012)
 details=FittedDetails('Arcade_Fitted')
 details.access_cover('ServiceAccess',(-4,1.12,2.4495),(0,0,-1),.84,.76);details.finish()


def build_formal_arch():
 reset();arch('FormalSingleArch',(0,0),7.5,2.55,1.55,.36,.65);save('formal_arch')

def build_formal_mainhall():
 reset()
 # Continuous dry circulation; no broad floor slab underneath the water.
 box('Main_BasinFloor',(0,-.24,0),(16,.24,12),'Ceramic',.012)
 box('Main_DeckWest',(-9.5,.38,0),(3,.28,20),'Ceramic')
 box('Main_DeckEast',(9.5,.38,0),(3,.28,20),'Ceramic')
 box('Main_DeckNorth',(0,.38,-8),(16,.28,4),'Ceramic')
 box('Main_DeckSouth',(0,.38,8),(16,.28,4),'Ceramic')
 for x in [-8,8]:box('Main_BasinSide'+str(x),(x,.20,0),(.16,.64,12),'Ceramic',.008)
 box('Main_BasinNorth',(0,.20,-6),(16,.64,.16),'Ceramic',.008)
 for x in [-5.2,5.2]:box('Main_BasinSouth'+str(x),(x,.20,6),(5.6,.64,.16),'Ceramic',.008)
 # Butt-jointed coping ring; front4.8m opening feeds shallow stepped descent.
 for x in [-8.18,8.18]:coping_with_joints('Main_CopingSide'+str(x),(x,.535,0),(.36,.07,12.72),'z')
 coping_with_joints('Main_CopingNorth',(0,.535,-6.18),(16,.07,.36),'x')
 for x in [-5.2,5.2]:coping_with_joints('Main_CopingSouth'+str(x),(x,.535,6.18),(5.6,.07,.36),'x')
 # Individual non-overlapping treads with exact collision upper surfaces.
 nosing_verts=[];nosing_faces=[]
 for i,top in enumerate([.38,.24,.10,-.04]):
  z=5.78-i*.42;inset_stair('Main_Stair'+str(i),top,z,nosing_verts,nosing_faces)
 nosings=mesh('Main_CopingStairNosings',nosing_verts,nosing_faces,'Coping',.003,bevel_segments=1)
 nosings['junction_detail']='54 mm pale ceramic nosings inset flush into the four actual treads; no collision changes'
 nosings['tread_tops_metres']=[.38,.24,.10,-.04]
 for x in [-2.25,2.25]:
  tube('Main_StairRail'+str(x),[(x,.54,6.86),(x,1.47,6.86),(x,1.47,6.28),(x,.91,4.16),(x,-.10,4.16)],.038)
  rail_socket('Main_StairRailDeckSocket'+str(x),x,6.86,.52)
  rail_socket('Main_StairRailBasinSocket'+str(x),x,4.16,-.12)
 for x in [-8.63,8.63]:drain('Main_DrainSide'+str(x),(x,.53,0),13.4,'z')
 for z in [-6.65,6.65]:drain('Main_DrainEnd'+str(z),(0,.53,z),16.9)
 wall('Main_West','z',-11,20,4.8);wall('Main_East','z',11,20,4.8,True)
 wall('Main_North','x',-10,22,4.8,True,6.0);wall('Main_South','x',10,22,4.8,True)
 for x in [-3.14,3.14]:box('Main_NorthPortalReveal'+str(x),(x,1.91,-10),(.28,2.78,.52),'Plaster',.012)
 box('Main_NorthPortalSoffit',(0,3.25,-10),(6,.20,.52),'Plaster',.008)
 # 3 transverse bays, repeated across hall: thick masonry, continuous curves.
 for zi,z in enumerate([-6,0,6]):
  for bi,(a,b) in enumerate([(-10,-4),(-4,4),(4,10)]):
   if zi==1 and bi==2:
    # Eastern doorway must remain clear at x=10,z=0. Return the overhead
    # arch into its portal header, supported by the existing x=4 pier.
    # No central doorway pier; preserve arch and header collision above headroom.
    arch('Main_EastPortalReturn',(7.5,0),6.64,3.3,1.0,.36,.64,cols=False)
    box('Main_EastPortalPierExtension',(4,2.975,0),(.36,.65,.64),'Plaster',.012)
   else:
    arch('Main_Arch_%s_%s'%(zi,bi),((a+b)/2,z),b-a-.36,2.65,1.52,.36,.64,base=-.12)
 # Three transverse structural frames, not a second ornamental arch lattice.
 # The clear longitudinal sightline lets the water and continuous roof light read.
 mainhall_termination_caps()
 for x in [-5.85,5.85]:box('Main_Ceiling'+str(x),(x,4.93,0),(10.3,.26,20.35),'Plaster',.012)
 for x in [-.76,.76]:box('Main_SkylightCurb'+str(x),(x,5.10,0),(.12,.30,20.35),'Plaster',.01)
 for z in [-8,-4,0,4,8]:box('Main_SkylightMullion'+str(z),(0,5.24,z),(1.52,.06,.06),'Metal',.002,False)
 box('Main_SkylightGlass',(0,5.27,0),(1.4,.025,20),'Glazing',0,False)
 ramp('Main_EastVestibule','x',11,16);ramp('Main_SouthVestibule','z',10,16)
 enclose_retained_ramp('Main_EastVestibule','x',11,16,8,6)
 enclose_retained_ramp('Main_SouthVestibule','z',10,16,8)
 connector('Main_NorthVestibule','z',-10,-16)
 add_main_fittings()
 save('formal_mainhall')

def build_formal_arcade():
 reset()
 box('Arcade_Deck',(0,.38,0),(24.8,.28,6),'Ceramic')
 box('Arcade_Wall3',(0,2.78,3),(24.8,2.60,.35),'Plaster')
 box('Arcade_Wainscot3',(0,1,3),(24.8,.96,.38),'Ceramic',.008)
 for x in [-7.7,7.7]:
  box('Arcade_NorthWall'+str(x),(x,2.78,-3),(9.4,2.60,.35),'Plaster')
  box('Arcade_NorthWainscot'+str(x),(x,1,-3),(9.4,.96,.38),'Ceramic',.008)
 for x in [-3.14,3.14]:box('Arcade_NorthPortalReveal'+str(x),(x,1.86,-3),(.28,2.68,.52),'Plaster',.012)
 box('Arcade_NorthPortalHead',(0,3.64,-3),(6,.92,.35),'Plaster',.015)
 # Four frames leave the new central branch genuinely clear at full width.
 for x in [-10,-5,5,10]:arch('Arcade_Frame'+str(x),(x,0),5.2,2.3,1.35,.32,.55,'z')
 box('Arcade_Ceiling',(0,4.22,0),(24.8,.24,6.35),'Plaster')
 box('Arcade_EastEnd',(12.4,1.4,0),(.35,1.76,6),'Ceramic');box('Arcade_EastWindow',(12.4,3.05,0),(.03,1.5,5.5),'Glazing',0,False)
 box('Arcade_EastHeader',(12.4,4.0,0),(.35,.2,6),'Plaster')
 ramp('Arcade_WestVestibule','x',-12.4,-16,6)
 enclose_retained_ramp('Arcade_WestVestibule','x',-12.4,-16,6)
 connector('Arcade_NorthVestibule','z',-3,-16)
 for x in [-8,0,8]:box('Arcade_Bench'+str(x),(x,.80,2.6),(2,.16,.65),'Coping',.035);box('Arcade_BenchBase'+str(x),(x,.65,2.6),(1.7,.3,.42),'Plaster')
 add_arcade_fittings()
 save('formal_arcade')

def build_formal_sidepool():
 reset()
 c=DEEP_BASINS['sidepool'];floor=c['basin_floor'];wall_height=c['deck']-floor;wall_centre=(c['deck']+floor)/2
 box('Side_Basin',(0,floor-.12,0),(8,.24,8),'Ceramic')
 for x in [-5.5,5.5]:box('Side_DeckSide'+str(x),(x,.38,0),(3,.28,14),'Ceramic');box('Side_BasinWall'+str(x),(4 if x>0 else -4,wall_centre,0),(.16,wall_height,8),'Ceramic')
 for z in [-5.5,5.5]:box('Side_DeckEnd'+str(z),(0,.38,z),(8,.28,3),'Ceramic')
 box('Side_BasinSouth',(0,wall_centre,4),(8,wall_height,.16),'Ceramic')
 for x in [-3.2,3.2]:box('Side_BasinNorth'+str(x),(x,wall_centre,-4),(1.6,wall_height,.16),'Ceramic')
 for x in [-4.18,4.18]:box('Side_CopingSide'+str(x),(x,.535,0),(.36,.07,8.72),'Coping')
 box('Side_CopingSouth',(0,.535,4.18),(8,.07,.36),'Coping')
 for i,(top,z) in enumerate(basin_steps('sidepool')):box('Side_Stair'+str(i),(0,(top+floor)/2,z),(c['stair_width'],top-floor,c['stair_tread']),'Ceramic',.008)
 for x in [-7,7]:box('Side_Wall'+str(x),(x,2.68,0),(.35,2.40,14),'Plaster');box('Side_Wainscot'+str(x),(x,1,0),(.38,.96,14),'Ceramic')
 box('Side_SouthWall',(0,2.2,7),(14,3.36,.35),'Plaster')
 for x in [-5.5,5.5]:box('Side_NorthPortalJamb'+str(x),(x,2.2,-7),(3,3.36,.35),'Plaster')
 box('Side_NorthPortalHeader',(0,3.6,-7),(8,.6,.35),'Plaster')
 for z in [-4,4]:arch('Side_Arch'+str(z),(0,z),11.8,2.15,1.2,.34,.55)
 for x in [-4,4]:box('Side_Ceiling'+str(x),(x,4.02,0),(6,.24,14),'Plaster')
 box('Side_SkylightGlass',(0,4.15,0),(2,.02,14),'Glazing',0,False)
 ramp('Side_NorthVestibule','z',-7,-16)
 enclose_retained_ramp('Side_NorthVestibule','z',-7,-16,8)
 for x in [-4.65,4.65]:drain('Side_Drain'+str(x),(x,.53,0),9,'z')
 add_side_fittings()
 save('formal_sidepool')

def build_formal_terrace():
 reset()
 # The terrace has real ankle-deep water: +.10 m floor, +.32 m water.
 box('Terrace_BasinFloor',(0,-.02,0),(12,.24,8),'Ceramic',.008)
 for x in [-8,8]:box('Terrace_DeckSide'+str(x),(x,.38,0),(4,.28,18),'Ceramic')
 for z in [-6.5,6.5]:box('Terrace_DeckEnd'+str(z),(0,.38,z),(12,.28,5),'Ceramic')
 for x in [-6,6]:box('Terrace_BasinWall'+str(x),(x,.31,0),(.16,.42,8),'Ceramic',.008)
 box('Terrace_BasinNorth',(0,.31,-4),(12,.42,.16),'Ceramic',.008)
 for x in [-4,4]:box('Terrace_BasinSouth'+str(x),(x,.31,4),(4,.42,.16),'Ceramic',.008)
 for x in [-6.18,6.18]:coping_with_joints('Terrace_CopingSide'+str(x),(x,.535,0),(.36,.07,8.72),'z')
 coping_with_joints('Terrace_CopingNorth',(0,.535,-4.18),(12,.07,.36),'x')
 for x in [-4,4]:coping_with_joints('Terrace_CopingSouth'+str(x),(x,.535,4.18),(4,.07,.36),'x')
 nosing_verts=[];nosing_faces=[]
 for i,top in enumerate([.38,.24]):inset_stair('Terrace_Stair'+str(i),top,3.78-i*.42,nosing_verts,nosing_faces,4.0,.10)
 mesh('Terrace_CopingStairNosings',nosing_verts,nosing_faces,'Coping',.003,bevel_segments=1)
 for x in [-1.85,1.85]:
  tube('Terrace_StairRail'+str(x),[(x,.54,4.95),(x,1.47,4.95),(x,1.47,4.2),(x,1.02,2.8),(x,.12,2.8)],.038)
  rail_socket('Terrace_StairRailDeckSocket'+str(x),x,4.95,.52)
  rail_socket('Terrace_StairRailBasinSocket'+str(x),x,2.8,.10)
 for x in [-6.65,6.65]:drain('Terrace_DrainSide'+str(x),(x,.53,0),9.4,'z')
 for z in [-4.65,4.65]:drain('Terrace_DrainEnd'+str(z),(0,.53,z),12.8)
 low_courtyard_wall('Terrace_North','x',-9,20)
 low_courtyard_wall('Terrace_East','z',10,18)
 low_courtyard_wall('Terrace_South','x',9,20,True)
 low_courtyard_wall('Terrace_West','z',-10,18,True)
 # A low rectangular pavilion contrasts with the tall arched main hall.
 # The central 12 x 9 m opening is open sky, with no fake luminous panel.
 for x in [-8,8]:box('Terrace_RoofSide'+str(x),(x,4.32,0),(4,.24,18.3),'Plaster',.012)
 for z in [-6.75,6.75]:box('Terrace_RoofEnd'+str(z),(0,4.32,z),(12,.24,4.5),'Plaster',.012)
 for x in [-6.35,6.35]:
  for z in [-4.85,4.85]:
   box('Terrace_StructurePier'+str((x,z)),(x,2.36,z),(.46,3.68,.46),'Plaster',.018)
   box('Terrace_CeramicFoot'+str((x,z)),(x,1.0,z),(.48,.96,.48),'Ceramic',.008,col=False)
 for z in [-4.68,4.68]:box('Terrace_RoofBearing'+str(z),(0,3.98,z),(13.15,.44,.46),'Plaster',.018)
 for x in [-9.75,9.75]:
  for z in [-8.75,8.75]:box('Terrace_PerimeterPier'+str((x,z)),(x,2.36,z),(.40,3.68,.40),'Plaster',.012)
 for x in [-6.10,6.10]:box('Terrace_ApertureCurb'+str(x),(x,4.48,0),(.20,.20,9.25),'Coping',.008,False)
 for z in [-4.60,4.60]:box('Terrace_ApertureCurbEnd'+str(z),(0,4.48,z),(12.0,.20,.20),'Coping',.008,False)
 box('Terrace_BenchSeat',(9.25,.91,0),(.75,.16,3.8),'Coping',.025)
 box('Terrace_BenchPlinth',(9.35,.67,0),(.52,.30,3.5),'Plaster',.012)
 connector('Terrace_WestVestibule','x',-10,-16)
 connector('Terrace_SouthVestibule','z',9,16)
 add_terrace_fittings()
 save('formal_terrace')

def continuous_bath_plaster_wall(angles):
    """One closed manifold solid; true portals below y=3.2, headers above.

    The y=3.2 rings share vertices and surface edges, but there are no horizontal
    faces except on the actual portal soffits. Only external silhouette corners
    receive the source 8 mm / 3-segment bevel. No decorative seam-covering ring.
    Source Godot coordinates (x,y,z) become Blender (x,-z,y).
    """
    material=M['Plaster']
    count=len(angles)-1
    alpha=math.asin(3.0/8.8)
    opening=[]
    for i in range(count):
        a=(angles[i]+angles[i+1])*.5
        opening.append((math.cos(a)>0 and abs(math.sin(a))<math.sin(alpha)) or
                       (math.sin(a)>0 and abs(math.cos(a))<math.sin(alpha)))
    verts=[]
    for a in angles[:-1]:
        for y in [1.48,3.2,4.6]:
            for r in [8.80,9.16]:
                verts.append((r*math.cos(a),-r*math.sin(a),y))
    def v(i,h,side):return (i%count)*6+h*2+side
    faces=[]
    for i in range(count):
        j=(i+1)%count
        # Shared y=3.2 edges prevent both the former groove and internal caps.
        for h in ([1] if opening[i] else [0,1]):
            faces.extend([(v(i,h,0),v(i,h+1,0),v(j,h+1,0),v(j,h,0)),
                          (v(i,h,1),v(j,h,1),v(j,h+1,1),v(i,h+1,1))])
        faces.append((v(i,2,0),v(i,2,1),v(j,2,1),v(j,2,0)))
        h=1 if opening[i] else 0
        faces.append((v(i,h,0),v(j,h,0),v(j,h,1),v(i,h,1)))
        if not opening[i] and opening[(i-1)%count]:
            faces.append((v(i,0,0),v(i,0,1),v(i,1,1),v(i,1,0)))
        if not opening[i] and opening[j]:
            faces.append((v(j,0,0),v(j,1,0),v(j,1,1),v(j,0,1)))
    me=bpy.data.meshes.new('Bath_Wall_Continuous');me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new('Bath_Wall',me);bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.normal_update();bm.to_mesh(me);bm.free();me.update()
    uv=me.uv_layers.new(name='UVMap')
    for f in me.polygons:
        f.use_smooth=abs(f.normal.z)<.1
        # Same world-metre dominant-axis projection as the original generator.
        axis=max(range(3),key=lambda i:abs(f.normal[i]));axes=[i for i in range(3) if i!=axis]
        for li in f.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('External masonry edges only; no y3.2 joint','BEVEL')
    mod.width=.008;mod.segments=3;mod.limit_method='ANGLE';mod.angle_limit=math.radians(30);mod.harden_normals=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=ob.modifiers.new('Preserved planar caps and smooth walls','WEIGHTED_NORMAL');mod.keep_sharp=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    ob['units']='metres';ob['uv0']='1 UV unit = 1 metre; runtime ceramic pitch 0.1m'
    ob['uv2']='packed nonoverlapping smart projection, unbaked'
    ob['construction']='Single watertight plaster shell with lower east/south portals and upper headers; no internal y=3.2 caps or groove'
    ob['junction_candidate']=True
    ob.select_set(False)
    return ob

def build_formal_bath():
 reset()
 c=DEEP_BASINS['bath'];floor=c['basin_floor']
 alpha=math.asin(3.0/8.8)
 special=[alpha,math.tau-alpha,math.pi/2-alpha,math.pi/2+alpha]
 # Include exact notch and outer-threshold corners, rather than rounding them
 # to a coarse circular segment or leaving triangular floor holes.
 for half,reach in [(1.8,6.0),(1.8,math.sqrt(4.8**2-1.8**2)),(3.0,9.3)]:
  a=math.atan2(reach,half);special.extend([a,math.pi-a])
 special.extend([math.atan2(3,9.3),math.tau-math.atan2(3,9.3)])
 angles=sorted(set([math.tau*i/96 for i in range(97)]+special))
 inner=bath_outline(angles)
 outer=[]
 for angle in angles:
  x=math.cos(angle);z=math.sin(angle);r=8.82
  if x>0:r=max(r,min(9.3/x,3.0/max(abs(z),1e-12)))
  if z>0:r=max(r,min(9.3/z,3.0/max(abs(x),1e-12)))
  outer.append((r*x,r*z))
 front=lambda i:inner[i][1]>5.999 and inner[i+1][1]>5.999
 # The solid foundation is physically below the entire wet footprint; the
 # raised annular deck above it exposes the genuine circular basin + stair bay.
 box('Bath_BasinFloor',(0,floor-.12,.6),(9.6,.24,10.8),'Ceramic',0)
 perimeter_band('Bath_DeckRing',inner,outer,.24,.52,'Ceramic',bevel=.006,include_inner=False)
 perimeter_band('Bath_BasinWall',inner,bath_outline(angles,.16),floor,.52,'Ceramic',front,bevel=.006)
 perimeter_band('Bath_CopingRim',inner,bath_outline(angles,.36),.50,.57,'Coping',front,bevel=.012)
 perimeter_band('Bath_DrainSlot',bath_outline(angles,.60),bath_outline(angles,.72),.521,.533,'Drain',col=False,bevel=.002)
 nosing_verts=[];nosing_faces=[]
 for i,(top,z) in enumerate(basin_steps('bath')):inset_stair('Bath_Stair'+str(i),top,z,nosing_verts,nosing_faces,c['stair_width'],floor,c['stair_tread'])
 mesh('Bath_CopingStairNosings',nosing_verts,nosing_faces,'Coping',.003,bevel_segments=1)
 for x in [-1.65,1.65]:
  tube('Bath_StairRail'+str(x),[(x,.54,6.86),(x,1.47,6.86),(x,1.47,6.28),(x,floor+1.03,1.72),(x,floor+.02,1.72)],.038)
  rail_socket('Bath_StairRailDeckSocket'+str(x),x,6.86,.52)
  rail_socket('Bath_StairRailBasinSocket'+str(x),x,1.72,floor)
 def doorway(i):
  angle=(angles[i]+angles[i+1])/2
  return (math.cos(angle)>0 and abs(math.sin(angle))<math.sin(alpha)) or (math.sin(angle)>0 and abs(math.cos(angle))<math.sin(alpha))
 perimeter_band('Bath_Wainscot',circle_points(8.78,angles),circle_points(9.16,angles),.52,1.48,'Ceramic',doorway)
 lower_wall=perimeter_band('Bath_Wall',circle_points(8.80,angles),circle_points(9.16,angles),1.48,3.2,'Plaster',doorway)
 upper_wall=perimeter_band('Bath_UpperDrum',circle_points(8.80,angles),circle_points(9.16,angles),3.2,4.6,'Plaster')
 # Keep exactly the original proxy generators above, but replace the two visible
 # solids with one watertight shell. Nothing overlaps to hide the former seam.
 for ob in [lower_wall,upper_wall]:bpy.data.objects.remove(ob,do_unlink=True)
 continuous_bath_plaster_wall(angles)
 marker=bpy.data.objects.new('Bath_UpperDrum',None);bpy.context.collection.objects.link(marker)
 marker['construction']='Geometry unified into Bath_Wall; all original COLLISION_Bath_UpperDrum_* proxies preserved'
 perimeter_band('Bath_CopingWallTermination',circle_points(8.765,angles),circle_points(9.17,angles),1.464,1.50,'Coping',doorway,col=False,bevel=.003)
 for axis in ['x','z']:
  for sign in [-1,1]:
   side=sign*3.16
   box('Bath_PortalReveal'+axis+str(sign),(8.64,1.86,side) if axis=='x' else (side,1.86,8.64),(.82,2.68,.32) if axis=='x' else (.32,2.68,.82),'Plaster',.015)
  box('Bath_PortalSoffit'+axis,(8.95,3.25,0) if axis=='x' else (0,3.25,8.95),(.80,.20,6) if axis=='x' else (6,.20,.80),'Plaster',.008)
 bath_dome('Bath_VaultedCeiling',angles)
 perimeter_band('Bath_OculusCurb',circle_points(1.8,angles),circle_points(2.0,angles),5.79,6.02,'Plaster',col=False)
 glass_verts=[(0,6.025,0)]+[(1.79*math.cos(a),6.025,1.79*math.sin(a)) for a in angles[:-1]]
 glass_faces=[(0,1+i,1+(i+1)%(len(angles)-1)) for i in range(len(angles)-1)]
 mesh('Bath_OculusGlass',glass_verts,glass_faces,'Glazing')
 for axis in ['x','z']:box('Bath_OculusMullion'+axis,(0,6.03,0),(3.6,.06,.045) if axis=='x' else (.045,.06,3.6),'Metal',.003,False)
 bench_skip=lambda i:not(math.pi+.12<(angles[i]+angles[i+1])/2<math.pi*1.5-.12)
 perimeter_band('Bath_CurvedBenchPlinth',circle_points(8.10,angles),circle_points(8.55,angles),.52,.80,'Plaster',bench_skip)
 perimeter_band('Bath_CurvedBenchSeat',circle_points(7.95,angles),circle_points(8.64,angles),.80,.94,'Coping',bench_skip,bevel=.02)
 connector('Bath_EastVestibule','x',9.3,16)
 connector('Bath_SouthVestibule','z',9.3,16)
 save('formal_bath')

BUILDERS={
 'formal_arch':build_formal_arch,
 'formal_mainhall':build_formal_mainhall,
 'formal_arcade':build_formal_arcade,
 'formal_sidepool':build_formal_sidepool,
 'formal_terrace':build_formal_terrace,
 'formal_bath':build_formal_bath,
}
for asset,builder in BUILDERS.items():
 if ONLY is None or asset in ONLY:builder()
manifest={
 'units':'metres','coordinates':'Godot Y up; room origins on 32 m x/z grid',
 'main':{'coord':[-1,-1],'size':[22,20],'ceiling':4.8,'basin':[16,12],'basin_floor':-.12,'deck':.52,'water':.32,'stairs':[.38,.24,.10,-.04],'east_portal':[16,-.72,0],'south_portal':[0,-.72,16],'north_portal':[0,-.72,-16],'north_clear_width':6.0},
 'arcade':{'coord':[0,-1],'size':[24.8,6],'ceiling':4.1,'deck':.52,'water':False,'west_portal':[-16,-.72,0],'north_portal':[0,-.72,-16],'north_clear_width':6.0,'structural_frames':4},
 'sidepool':{'coord':[-1,0],'size':[14,14],'ceiling':3.9,'basin':[8,8],'north_portal':[0,-.72,-16],**basin_contract('sidepool')},
 'terrace':{'coord':[0,-2],'size':[20,18],'ceiling':4.2,'basin':[12,8],'basin_floor':.10,'deck':.52,'water':.32,'stairs':[.38,.24],'stair_width':4.0,'open_sky_rectangle':[-6,-4.5,12,9],'west_portal':[-16,-.72,0],'south_portal':[0,-.72,16],'portal_clear_width':6.0},
 'bath':{'coord':[-1,-2],'inner_radius':8.8,'outer_radius':9.16,'ceiling_edge':4.6,'ceiling_oculus':5.58,'oculus_radius':1.8,'oculus_glass_y':6.025,'basin_radius':4.8,'south_stair_alcove':[-1.8,4.45,3.6,1.55],**basin_contract('bath'),'east_portal':[16,-.72,0],'south_portal':[0,-.72,16],'portal_clear_width':6.0},
 'connections':[['main','arcade'],['main','sidepool'],['main','bath'],['bath','terrace'],['terrace','arcade']],
 'retained_connector_enclosures':{'main_east_widths':[8,6],'main_south_widths':[8,8],'arcade_west_widths':[6,6],'sidepool_north_widths':[8,8],'wall_thickness':.24,'roof_underside':3.15,'roof_thickness':.20,'rooflight_clear_width':.80,'rooflight_glass_y':3.48,'original_ramp_geometry':'unchanged'},
 'fixed_fittings':{'scope': 'Fixed, closed, non-interactive maintenance fittings; no wall openings or water emitters', 'mainhall': ['4 basin return covers', '1 waterline skimmer face', '1 tool-fastened tiled access cover'], 'terrace': ['4 shallow-basin return covers', '1 waterline skimmer face'], 'sidepool': ['2 basin return covers', '1 waterline skimmer face', '450 mm-high built-in west bench; 1.87 m clear deck passage'], 'arcade': ['Shallow closed service cabinet behind existing bench line'], 'grates': {'clear_slot_mm': 5, 'rib_width_mm': 12, 'panel_joint_mm': 3, 'finish': 'Existing brushed stainless role'}, 'original_mainhall_diffuse_receivers_unchanged': 145, 'new_mainhall_diffuse_receivers': 2, 'original_collision_proxies_unchanged': 516, 'new_local_collision_proxies': 21},
 'materials':['Formal_Ceramic','Formal_Plaster','Formal_Coping','Formal_Metal','Formal_Drain','Formal_Glazing','Formal_Collision'],
 'collision':'Objects named COLLISION_; use create_convex_shape(true,false) individually. Never convex-hull a whole room, arch or ring. Preserve rotated local sector transforms for exact OBB terrain extraction. Disable proxy visibility.',
 'uv':'UV0 world metres; tile pitch .1m in runtime material. UV2 packed nonoverlapping smart projection, unbaked. Runtime may regenerate for desired lightmap texel density.',
 'provenance':'Original procedural Blender sources; formal mainhall reconstructed from recovered concept and runtime reference, with authored connected terrace and curved bath.'
}
# --only must never leave selected-room metadata stale or silently revise
# unselected rooms. Merge just exported sections into the delivered manifest.
manifest_path=os.path.join(OUT,'formal_manifest.json')
if ONLY:
 if os.path.exists(manifest_path):
  with open(manifest_path) as f:current=json.load(f)
 else:current={key:manifest[key] for key in ['units','coordinates','materials','collision','uv','provenance']}
 for asset in ONLY:
  section='main' if asset=='formal_mainhall' else asset.removeprefix('formal_')
  if section in manifest:current[section]=manifest[section]
 manifest=current
with open(manifest_path,'w') as f:json.dump(manifest,f,indent=2);f.write('\n')
