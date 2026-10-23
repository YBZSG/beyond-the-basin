"""CPU-only isolated geometry diagnostics, NOT a Godot visual acceptance test."""
from pathlib import Path
import json,math
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'docs/bath-junction-candidate'

def aim(ob,target):ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
def light(name,loc,target,power,size):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size
 o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;aim(o,target)
for label,src in [('original',ROOT/'tools/blender/source/formal_bath.blend'),('candidate',ROOT/'tools/blender/bath_junction_candidate/formal_bath_continuous_wall.blend')]:
 bpy.ops.wm.open_mainfile(filepath=str(src),load_ui=False,use_scripts=False)
 for ob in list(bpy.context.scene.objects):
  if ob.name not in {'Bath_Wall','Bath_UpperDrum'}:bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.orphans_purge(do_recursive=True)
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=64
 scene.cycles.use_denoising=False;scene.cycles.max_bounces=2;scene.render.threads_mode='FIXED';scene.render.threads=2
 scene.render.resolution_x=640;scene.render.resolution_y=400;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
 scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=-4
 w=bpy.data.worlds.new('Diagnostic world');scene.world=w;w.use_nodes=True;w.node_tree.nodes['Background'].inputs[0].default_value=(.04,.04,.04,1);w.node_tree.nodes['Background'].inputs[1].default_value=.3
 camd=bpy.data.cameras.new('Geometry diagnostic camera');cam=bpy.data.objects.new('Geometry diagnostic camera',camd);bpy.context.collection.objects.link(cam);scene.camera=cam
 cam.location=(-6.0,0,3.2);aim(cam,(-8.8,0,3.2));camd.type='ORTHO';camd.ortho_scale=1.80;camd.clip_start=.05;camd.clip_end=100
 light('Grazing key',(-7.7,-1.7,4.2),(-8.8,0,3.2),140,.8)
 scene.render.filepath=str(OUT/(label+'-junction-cpu.png'));bpy.ops.render.render(write_still=True)
 # A second view proves the unified wall does not fill either doorway.
 camd.type='PERSP';camd.lens=18;cam.location=(0,0,2.7);aim(cam,(7,-7,2.7))
 light('Portal diagnostic fill',(0,0,4.3),(7,-7,2.4),1100,4)
 scene.render.filepath=str(OUT/(label+'-portals-cpu.png'));bpy.ops.render.render(write_still=True)
(OUT/'cpu-render-receipt.json').write_text(json.dumps({'scope':'Isolated plaster geometry diagnostic only; not Godot, not production lighting, not runtime acceptance','engine':'Cycles','device':'CPU','threads':2,'samples':64,'resolution':[640,400],'views':['junction','portals'],'source_files_opened_read_only':True,'rendered':['original-junction-cpu.png','candidate-junction-cpu.png','original-portals-cpu.png','candidate-portals-cpu.png']},indent=2)+'\n')
