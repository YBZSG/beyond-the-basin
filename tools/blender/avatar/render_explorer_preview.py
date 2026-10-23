import bpy,math,sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[3];OUT=P/'tools/blender/avatar/previews';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(P/'tools/blender/avatar/pool_explorer.blend'))
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=False
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world.color=(.3,.3,.3)
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.66,.70,.74,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65
scene.view_settings.view_transform='AgX'
# Neutral studio evidence only; not game marketing/render quality claims.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006));floor=bpy.context.object;floor.name='Preview floor'
m=bpy.data.materials.new('Preview floor');m.diffuse_color=(.14,.16,.17,1);floor.data.materials.append(m)
for name,loc,power,size in [('Key',(-2,3,4),300,3),('Fill',(3,2,2),150,3),('Rim',(0,-3,3),250,2)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
 ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Preview camera');cam=bpy.data.objects.new('Preview camera',camdata);scene.collection.objects.link(cam);scene.camera=cam;camdata.type='ORTHO';camdata.ortho_scale=2.04
rig=bpy.data.objects['ExplorerRig']
for kind,frame,loc in [('rest',1,(0,4,1.1)),('idle',1,(2.5,4,1.6)),('walk',9,(2.5,4,1.6)),('run',6,(2.5,4,1.6)),('side',1,(4,0,1.1)),('back',1,(0,-4,1.1))]:
 if kind=='rest':
  rig.animation_data.action=None
  for pb in rig.pose.bones:pb.rotation_quaternion=(1,0,0,0);pb.location=(0,0,0)
 else:
  rig.animation_data.action=bpy.data.actions.get(kind.capitalize() if kind in ['walk','run'] else 'Idle');scene.frame_set(frame)
 cam.location=loc;cam.rotation_euler=(Vector((0,0,.87))-cam.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=str(OUT/('explorer_preview_'+kind+'.png'));bpy.ops.render.render(write_still=True)
