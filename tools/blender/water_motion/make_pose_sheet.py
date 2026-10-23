"""Pure CPU skeletal diagnostic, not a rendered mesh or gameplay screenshot."""
from pathlib import Path
import json,sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];OUT=ROOT/'assets/water_motion'
p=OUT/('motion_validation_draft.json' if '--draft' in sys.argv else 'motion_validation.json')
data=json.loads(p.read_text())
rows=['Wade','Swim','SwimIdle','JumpRise','Land','ThrowRelease']
fig,axs=plt.subplots(len(rows),7,figsize=(16,13),facecolor='#10202c')
for r,name in enumerate(rows):
 clip=data['clips'][name];samples=clip['skeleton_samples']
 for c in range(7):
  ax=axs[r,c];ax.set_facecolor('#142937');sample=samples[min(c,len(samples)-1)]
  for n,(a,b) in sample['bones'].items():
   if any(n.startswith(f) for f in ['Index','Middle','Ring','Little','Thumb','WristSupport','Root']):continue
   # Slight oblique projection makes left/right support and kick visible.
   x=[a[1]+.48*a[0],b[1]+.48*b[0]];z=[a[2],b[2]]
   color='#59d5f5' if n.endswith('_L') else '#f4b36d' if n.endswith('_R') else '#edf6fa'
   ax.plot(x,z,color=color,lw=3 if n in ['Hips','Spine','Chest','Neck','Head'] else 2,marker='o',markersize=2.2)
  ax.axhline(0,color='#527283',lw=.6);ax.set_xlim(-.95,1.15);ax.set_ylim(-.10,1.80);ax.set_aspect('equal');ax.axis('off')
  ax.set_title(f"{sample['frame']/120:.2f} s",fontsize=10,color='#b4ccd8',pad=1)
  if c==0:ax.text(-1.2,.88,name,color='white',fontsize=12,rotation=90,va='center',ha='center')
fig.suptitle('Explorer authored motion | exact rig samples | CPU diagnostic, not gameplay proof',color='white',fontsize=16,y=.995)
fig.text(.5,.012,'Cyan: left chain   Amber: right chain   White: torso   No root travel; controller owns player motion.',ha='center',color='#b4ccd8',fontsize=11)
plt.subplots_adjust(wspace=.02,hspace=.18,top=.96,bottom=.035,left=.045,right=.995)
path=OUT/('pose_sheet_draft.png' if '--draft' in sys.argv else 'pose_sheet.png');fig.savefig(path,dpi=110,facecolor=fig.get_facecolor());print(path)
