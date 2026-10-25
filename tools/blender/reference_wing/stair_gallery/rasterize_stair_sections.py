"""Rasterize the generated simple technical SVG with Pillow (no external renderer)."""
from PIL import Image,ImageDraw,ImageFont
import xml.etree.ElementTree as E,os
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../..'));QA=os.path.join(ROOT,'output/reference_wing/stair')
r=E.parse(os.path.join(QA,'stair_actual_mesh_sections.svg')).getroot();im=Image.new('RGB',(1800,1450),'#f5f4ef');d=ImageDraw.Draw(im)
for el in r:
 tag=el.tag.split('}')[-1];a=el.attrib
 if tag=='line':d.line([(float(a['x1']),float(a['y1'])),(float(a['x2']),float(a['y2']))],fill=a.get('stroke','#333'),width=max(1,round(float(a.get('stroke-width',1)))))
 elif tag=='text':
  size={'title':30,'sub':19,'small':15}.get(a.get('class'),15);font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if a.get('class')=='title' else '')+'.ttf',size)
  d.text((float(a['x']),float(a['y'])),el.text or '',font=font,fill='#25312d',anchor='ls')
im.save(os.path.join(QA,'stair_actual_mesh_sections.png'))
