"""Fixed-axis exact Blender mesh section diagrams; never native-runtime renders."""
import json, pathlib, argparse, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D
p=argparse.ArgumentParser();p.add_argument('--qa-root',required=True);a=p.parse_args();root=pathlib.Path(a.qa_root)
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'savefig.facecolor':'#f4f5f2','axes.facecolor':'#f4f5f2','figure.facecolor':'#f4f5f2'})

def load(phase,room):return json.loads((root/phase/(room+'.json')).read_text())
def color(name):
 if 'Footing' in name:return '#007f73'
 if 'CenjiLaneRib' in name:return '#d16b21'
 if 'Cenji' in name:return '#8a592e'
 if 'Coping' in name:return '#548fbc'
 if 'Vault' in name:return '#713f8d'
 if 'BasinBottom' in name:return '#147e9b'
 return '#3d4b4a'
def draw(ax,data,label,xlim,ylim,title):
 sec=next(s for s in data['sections'] if s['label']==label);h=0 if sec['plane_axis']=='z' else 2
 segs=[[(q[h],q[1]) for q in s['points']] for s in sec['segments']];cs=[color(s['object']) for s in sec['segments']]
 ax.add_collection(LineCollection(segs,colors=cs,linewidths=.85));ax.set_xlim(xlim);ax.set_ylim(ylim);ax.set_aspect('equal');ax.grid(alpha=.18);ax.set_xlabel(('X' if h==0 else 'Z')+' / m');ax.set_ylabel('Y elevation / m');ax.set_title(title+'\n'+sec['plane_axis'].upper()+' = '+str(round(sec['plane_value_m'],3))+' m; orthographic section',fontsize=11,pad=10)
 return ax

def dim(ax,x,y0,y1,text,color='#b3261e',dx=0.):
 ax.annotate('',xy=(x,y0),xytext=(x,y1),arrowprops={'arrowstyle':'|-|','color':color,'lw':1.4});ax.text(x+dx+.06,(y0+y1)/2,text,color=color,fontsize=10,ha='left',va='center',bbox={'facecolor':'#f4f5f2','edgecolor':'none','pad':1.7})
def footnote(fig,text):fig.text(.03,.018,text,fontsize=9,color='#3d4b4a',va='bottom')
phases=['baseline']+(['candidate'] if (root/'candidate/vaulted_lanes.json').exists() else [])
for phase in phases:
 fig,axs=plt.subplots(3,1,figsize=(15,11),constrained_layout=False)
 for ax,room,label,name in zip(axs,['crescent_court','vaulted_lanes','circular_bath'],['court_arcade_longitudinal','lane_rib_cross','bath_gateway_longitudinal'],['Crescent Court: arcade along X=5.25','Vaulted Lanes: rib over both pools','Circular Bath: gateway through X=2.1']):
  d=load(phase,room);draw(ax,d,label,(-12.5,12.5),(-1.35,5.75),name)
  ax.axhline(.52,color='#7b928a',ls='--',lw=.6);ax.text(-12.1,.60,'deck +0.520 m',fontsize=8)
  ax.axhline(-.22,color='#147e9b',ls=':',lw=.6);ax.text(-12.1,-.54,'basin -0.220 m',fontsize=8,color='#147e9b')
 fig.suptitle(('BASELINE' if phase=='baseline' else 'REPAIRED CANDIDATE')+' | Actual source-mesh sections, all three complete rooms',fontsize=17,y=.98)
 fig.subplots_adjust(top=.91,bottom=.11,hspace=.48)
 footnote(fig,'Geometry extracted read-only from Blender 4.3.2. Axes and framing fixed. Lines are true plane/triangle intersections.\nNot a Godot render, no water surface is treated as support, and this is geometry QA, not a structural engineering certification.')
 fig.savefig(root/phase/'all_rooms_sections.png',dpi=160);plt.close(fig)
fig,axs=plt.subplots(len(phases),3,figsize=(18,5.0*len(phases)+1.0),squeeze=False)
for row,phase in enumerate(phases):
 d=load(phase,'vaulted_lanes');label='OLD' if phase=='baseline' else 'NEW'
 draw(axs[row,0],d,'lane_rib_cross',(1.72,3.60),(-.52,1.0),label+' | Right pier foot')
 if phase=='baseline':dim(axs[row,0],2.85,-.22,.52,'0.740 m\nopen gap',dx=-.02)
 else:
  dim(axs[row,0],2.97,-.22,-.04,'0.180 m\nfooting above floor',color='#007f73',dx=-.02)
  axs[row,0].text(1.80,-.43,'0.100 m embed into basin floor',color='#007f73',fontsize=9)
 axs[row,0].axhline(.32,color='#35a0bd',ls='--',lw=.9);axs[row,0].text(1.77,.34,'water datum only',color='#147e9b',fontsize=8)
 draw(axs[row,1],d,'lane_rib_cross',(-2.95,2.95),(3.1,5.05),label+' | Rib / roof / barrel bearing')
 if phase=='baseline':dim(axs[row,1],2.83,4.67,4.70,'0.030 m gap',dx=-1.8)
 else:axs[row,1].text(-2.65,4.84,'Rib top 4.700 m = roof underside',color='#007f73',fontsize=9)
 draw(axs[row,2],d,'entry_transition_section',(9.,12.65),(3.2,5.7),label+' | North/south entry transition')
 if phase=='baseline':
  axs[row,2].annotate('Barrel ends at 9.600 m',xy=(9.6,4.65),xytext=(9.12,5.07),arrowprops={'arrowstyle':'->','color':'#713f8d'},fontsize=9,color='#713f8d')
  axs[row,2].annotate('0.075 m header / soffit gap',xy=(12.0375,4.95),xytext=(9.10,5.47),arrowprops={'arrowstyle':'->','color':'#b3261e'},fontsize=9,color='#b3261e')
 else:
  axs[row,2].annotate('Barrel ends inside header at 11.800 m',xy=(11.8,4.57),xytext=(9.10,5.44),arrowprops={'arrowstyle':'->','color':'#007f73'},fontsize=9,color='#007f73')
  axs[row,2].annotate('Soffit overlaps header 0.100 m',xy=(11.95,5.1),xytext=(9.10,5.15),arrowprops={'arrowstyle':'->','color':'#007f73'},fontsize=9,color='#007f73')
fig.suptitle('Vaulted Lanes | Fixed-axis construction contact comparison',fontsize=18,y=.99);fig.subplots_adjust(top=.89,bottom=.10,hspace=.38,wspace=.32)
footnote(fig,'Source Blender mesh sections, not native-runtime screenshots. Orange: imported rib. Teal: solid footing. Purple: barrel vault.\nWater datum is a reference line only. Gaps are measured against solid meshes; a coping-edge touch does not remove the broad over-pool gap.')
fig.savefig(root/'lanes_contact_comparison.png',dpi=180);plt.close(fig)
print('Wrote exact-mesh section drawings to',root)

fig,axs=plt.subplots(1,3,figsize=(16,6))
old=load('baseline','vaulted_lanes');d=load('candidate','vaulted_lanes')
draw(axs[0],old,'portal_jamb_section',(11.25,12.65),(.10,1.15),'OLD | Portal-jamb trim lip')
dim(axs[0],12.2,.365,.52,'0.155 m',dx=.01)
axs[0].annotate('0.075 m lip beyond deck edge',xy=(12.04,.52),xytext=(11.30,.94),arrowprops={'arrowstyle':'->','color':'#8a592e'},fontsize=9,color='#8a592e')
draw(axs[1],d,'portal_jamb_section',(11.25,12.65),(.10,1.15),'NEW | Jamb bears on first tread')
axs[1].annotate('Bottom +0.365 m = first tread',xy=(12.04,.365),xytext=(11.30,.94),arrowprops={'arrowstyle':'->','color':'#007f73'},fontsize=9,color='#007f73')
axs[1].text(11.30,.16,'0.155 m embed on deck side',color='#007f73',fontsize=9)
draw(axs[2],d,'outer_boundary_section',(-16.65,-15.35),(-1.3,.3),'Shared outer wall / cell boundary')
axs[2].axvline(-16.,ls='--',color='#8a592e',lw=1)
axs[2].annotate('0.300 m on neighboring-cell side',xy=(-16.15,-.72),xytext=(-16.59,-1.13),arrowprops={'arrowstyle':'->','color':'#8a592e'},fontsize=9,color='#8a592e')
fig.suptitle('Entry jamb correction and shared-cell bearing detail',fontsize=15,y=.97)
fig.subplots_adjust(top=.82,bottom=.20,wspace=.35)
footnote(fig,'Source-mesh sections, not native renders. The final jamb now meets the first stair; its deck-side lower section is embedded.\nOuter wall straddles the 32 m cell boundary. Rays against a translated actual foundation meet it; native neighbor presence remains a runtime check.')
fig.savefig(root/'retained_boundary_details.png',dpi=180);plt.close(fig)
