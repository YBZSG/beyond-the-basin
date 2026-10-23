#!/usr/bin/env python3
"""Read actual equal-camera images. Never alter or synthesize a comparison image.
This reports flat-region mottling, not automatic art acceptance.
"""
import argparse,json,pathlib
import numpy as np
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('raw',type=pathlib.Path);p.add_argument('denoised',type=pathlib.Path);p.add_argument('--output',type=pathlib.Path)
a=p.parse_args();images=[np.asarray(Image.open(path).convert('RGB'),dtype=float)/255 for path in [a.raw,a.denoised]]
if images[0].shape!=images[1].shape or images[0].shape[:2]!=(663,1180):raise SystemExit('Require actual matching 1180×663 fixture captures; do not rescale images.')
rows=[]
# Interior blue wall, clear of silhouette, shadow boundary and chart edges.
x0,y0,x1,y1=425,250,550,335
for path,image in zip([a.raw,a.denoised],images):
 region=image[y0:y1,x0:x1];linear=np.where(region<=.04045,region/12.92,((region+.055)/1.055)**2.4)
 luminance=linear@np.array([.2126,.7152,.0722]);y,x=np.mgrid[-1:1:complex(y1-y0),-1:1:complex(x1-x0)]
 # Remove a smooth quadratic illumination field; retain mottling residuals.
 design=np.stack([np.ones_like(x),x,y,x*x,x*y,y*y],axis=-1).reshape(-1,6)
 fit=design@np.linalg.lstsq(design,luminance.ravel(),rcond=None)[0];residual=luminance.ravel()-fit
 rows.append({'image':str(path),'mean_display_rgb':(region.mean((0,1))*255).tolist(),'mean_linear_luminance':float(luminance.mean()),'detrended_linear_rms':float(np.sqrt(np.mean(residual*residual)))})
report={'scope':'Actual image comparison metric only; no synthetic pixels or visual acceptance claim. Quadratic fit removes a smooth illumination gradient.','roi_xyxy':[x0,y0,x1,y1],'images':rows,'denoised_to_raw_detrended_rms_ratio':rows[1]['detrended_linear_rms']/rows[0]['detrended_linear_rms']}
text=json.dumps(report,indent=2)+'\n';print(text,end='')
if a.output:a.output.write_text(text)
