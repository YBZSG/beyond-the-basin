"""Blender CPU: intersect actual source mesh polygons, not nominal bounding boxes.
blender -b -t 2 --python tools/blender/reference_wing/stair_gallery/draw_stair_sections.py
"""
import bpy,os,json,html
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'));QA=os.path.join(ROOT,'output/reference_wing/stair')
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend'))
C=json.load(open(os.path.join(ROOT,'assets/models/reference_wing/stair_gallery.geometry.json')))
parts=['<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1450" viewBox="0 0 1800 1450"><rect width="1800" height="1450" fill="#f5f4ef"/><style>text{font-family:DejaVu Sans,sans-serif;fill:#25312d}.title{font-size:30px;font-weight:bold}.sub{font-size:19px}.small{font-size:15px}</style>']
parts.append('<text x="65" y="55" class="title">Reference 5 · Dry descending gallery · Actual mesh sections</text>')
parts.append('<text x="65" y="86" class="sub">Blender CPU polygon intersections. Not a Godot or NVIDIA render. Coordinates in metres, Godot Y-up.</text>')
colors={'ref_tile_pearl':'#5a756f','ref_tile_teal':'#397f81','ref_grout':'#715b47','ref_fixture_metal':'#4d535b','ref_fixture_emission':'#d0a514','ref_dark_foliage':'#27422e'}
records=[]
for panel,(plane,title) in enumerate([(1.4,'A · Centre of the 3 m walking route (x=1.40)'),(-.24,'B · Continuous sloping parapet (x=-0.24)')]):
 top=145+panel*610;s=46.;xoff=83;ybase=top+540
 def point(z,y):return(xoff+(14.8-z)*s,ybase-y*s)
 parts.append(f'<text x="65" y="{top-20}" class="sub">{title}</text>')
 for y in [0,.52,2.62,4.68,6,8,10,11.32]:
  xx,yy=point(14.8,y);parts.append(f'<line x1="{xx}" y1="{yy}" x2="1520" y2="{yy}" stroke="#d9dfd8" stroke-width="1"/><text x="12" y="{yy+5}" class="small">{y:g}</text>')
 for z in [14.5,9,.68,-3.6,-16]:
  xx,yy=point(z,0);parts.append(f'<line x1="{xx}" y1="{top}" x2="{xx}" y2="{ybase+5}" stroke="#d9dfd8" stroke-width="1"/><text x="{xx-20}" y="{ybase+24}" class="small">z {z:g}</text>')
 count=0
 for ob in bpy.context.scene.objects:
  if ob.type!='MESH' or ob.name.startswith('COLLISION_'):continue
  color=colors.get(ob.data.materials[0].name,'#333')
  for face in ob.data.polygons:
   verts=[ob.matrix_world@ob.data.vertices[i].co for i in face.vertices];hits=[]
   for a,b in zip(verts,verts[1:]+verts[:1]):
    da=a.x-plane;db=b.x-plane
    if abs(da)<1e-8:hits.append(a)
    if da*db<0:hits.append(a+(b-a)*(-da/(db-da)))
   uniq=[]
   for q in hits:
    if all((q-r).length>1e-7 for r in uniq):uniq.append(q)
   if len(uniq)==2:
    a,b=uniq;ax,ay=point(-a.y,a.z);bx,by=point(-b.y,b.z)
    parts.append(f'<line x1="{ax:.3f}" y1="{ay:.3f}" x2="{bx:.3f}" y2="{by:.3f}" stroke="{color}" stroke-width="1.7"/>');count+=1
 records.append({'x_plane':plane,'actual_polygon_intersection_segments':count})
parts.append('<text x="65" y="1390" class="sub">26 × 0.16 m risers · 0.32 m treads · 4.16 m drop · 2.10 m small arch · 10.80 m far-wall height</text>')
parts.append('<text x="65" y="1420" class="small">North exit at z=-16: 3.00 m wide × 2.80 m high, threshold y=0.52. Every other module boundary is closed.</text></svg>')
open(os.path.join(QA,'stair_actual_mesh_sections.svg'),'w').write(''.join(parts));json.dump({'method':'Actual mesh polygon-plane intersections','sections':records},open(os.path.join(QA,'stair_section_checks.json'),'w'),indent=2)
print('ACTUAL_SECTIONS',records)
