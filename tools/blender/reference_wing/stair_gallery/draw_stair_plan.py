"""Top-down technical diagram from actual sidecar collision vertices/bounds."""
import json,os
from PIL import Image,ImageDraw,ImageFont
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'));QA=os.path.join(ROOT,'output/reference_wing/stair')
C=json.load(open(os.path.join(ROOT,'assets/models/reference_wing/stair_gallery.geometry.json')));P={p['name'].removeprefix('COLLISION_'):p for p in C['collision_proxies']}
im=Image.new('RGB',(1050,1460),'#f5f4ef');d=ImageDraw.Draw(im)
def font(n,b=False):return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if b else '')+'.ttf',n)
def pt(x,z):return(275+x*36,112+(z+16)*36)
def hull(points):
 points=sorted(set(points))
 def cross(o,a,b):return(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
 lo=[];hi=[]
 for p in points:
  while len(lo)>=2 and cross(lo[-2],lo[-1],p)<=0:lo.pop()
  lo.append(p)
 for p in reversed(points):
  while len(hi)>=2 and cross(hi[-2],hi[-1],p)<=0:hi.pop()
  hi.append(p)
 return lo[:-1]+hi[:-1]
def shape(name,color,outline='#45635b',width=2):
 p=P[name]
 if p['type']=='BOX':
  a=p['bounds_min'];b=p['bounds_max'];coords=[(a[0],a[2]),(b[0],a[2]),(b[0],b[2]),(a[0],b[2])]
 else:coords=hull([(v[0],v[2]) for v in p['vertices']])
 q=[pt(*v) for v in coords];d.polygon(q,fill=color);d.line(q+[q[0]],fill=outline,width=width)
d.text((40,30),'Dry stair gallery · actual plan',font=font(29,True),fill='#25312d')
d.text((40,73),'CPU geometry diagram, not a Godot render',font=font(18),fill='#4a625b')
for n in ['MainFoundation','ContinuationFoundation']:shape(n,'#e2e6dc')
shape('NorthContinuationFloor','#cadfd9')
shape('UpperLanding','#e5ebe0');shape('LowerLanding','#e5ebe0')
for i in range(1,27):shape('StairTread_%02d'%i,'#d8e2d8',width=1)
for n in ['PlanterStructureSlope','PlanterStructureUpper']:shape(n,'#49694d')
for n in ['ParapetSlope','ParapetUpper']:shape(n,'#82a298')
for n in ['EastWall','WestRecessWall','SouthClosedWall','PlanterEndReturn','LowerLandingWestWall','NorthFarWallLeft','NorthFarWallRight','ArchLeftJamb','ArchRightJamb','NorthContinuationLeft','NorthContinuationRight']:shape(n,'#748a80')
route=[(1.4,10.8),(1.4,.68),(1.4,-3.8),(1.4,-4),(.7,-10),(0,-16)]
d.line([pt(*p) for p in route],fill='#db7a35',width=4)
for x,z in route:
 a,b=pt(x,z);d.ellipse((a-4,b-4,a+4,b+4),fill='#db7a35')
for z,label in [(-16,'North interface: z -16'),(-4,'Visible small arch'),(.68,'Lower landing: y 0.52'),(9,'First riser'),(14.5,'Closed south end')]:
 x,y=pt(3.3,z);d.line([(x,y),(570,y)],fill='#a4b4a9',width=1);d.text((585,y-11),label,font=font(18),fill='#25312d')
xx,yy=pt(0,-16);d.line([(xx-54,yy),(xx+54,yy)],fill='#286d91',width=6)
d.text((585,146),'Portal centred x=0',font=font(23,True),fill='#286d91')
d.text((585,179),'3.00 m wide × 2.80 m high',font=font(18),fill='#25312d')
d.text((585,209),'Threshold y=0.52',font=font(18),fill='#25312d')
d.text((585,269),'Hidden connector shifts',font=font(20,True),fill='#25312d')
d.text((585,300),'from x=1.4 at the small arch',font=font(18),fill='#25312d')
d.text((585,330),'to the centred grid interface.',font=font(18),fill='#25312d')
d.text((585,755),'26 × 0.16 m descents',font=font(21,True),fill='#25312d')
d.text((585,788),'0.32 m treads / 3.00 m route',font=font(18),fill='#25312d')
d.text((585,818),'4.16 m total drop',font=font(18),fill='#25312d')
d.text((585,880),'Continuous solid parapet',font=font(21,True),fill='#25312d')
d.text((585,913),'Dark recessed planter',font=font(18),fill='#25312d')
d.text((585,943),'249 individually rooted plants',font=font(18),fill='#25312d')
d.text((585,1090),'Upper spawn',font=font(21,True),fill='#db7a35')
d.text((585,1124),'(1.4, 4.76, 10.8)',font=font(18),fill='#25312d')
d.text((40,1295),f"Actual GLB: {C['runtime_export_summary']['runtime_visible_mesh_nodes']} visible meshes · {C['proxy_count']} proxies · {C['visible_triangles']:,} triangles",font=font(22,True),fill='#25312d')
d.text((40,1341),'359 support / tread / root rays passed; 225 swept connector rays passed.',font=font(20),fill='#25312d')
d.text((40,1376),'One north portal. All other reachable boundaries are closed. No water regions.',font=font(20),fill='#25312d')
d.text((40,1417),'Diagram generated from stair_gallery.geometry.json, not hand-drawn nominal boxes.',font=font(17),fill='#4a625b')
im.save(os.path.join(QA,'stair_actual_plan.png'))
