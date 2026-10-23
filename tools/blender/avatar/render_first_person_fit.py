"""CPU-only geometric camera-fit evidence; not a native game screenshot."""
import bpy,math
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[3];OUT=P/'tools/blender/avatar/previews';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(P/'tools/blender/avatar/pool_explorer.blend'))
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=16;s.cycles.use_denoising=False
s.render.resolution_x=960;s.render.resolution_y=720;s.render.resolution_percentage=100
s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.55,.62,.69,1);s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
s.view_settings.view_transform='AgX'
bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.002));floor=bpy.context.object;m=bpy.data.materials.new('Fixture floor');m.diffuse_color=(.12,.17,.19,1);floor.data.materials.append(m)
data=bpy.data.lights.new('Fixture sun','SUN');data.energy=2;ob=bpy.data.objects.new('Fixture sun',data);s.collection.objects.link(ob);ob.rotation_euler=(.4,-.4,.7)
camdata=bpy.data.cameras.new('Exact player eye');cam=bpy.data.objects.new('Exact player eye',camdata);s.collection.objects.link(cam);s.camera=cam
camdata.type='PERSP';camdata.sensor_fit='VERTICAL';camdata.sensor_height=32;camdata.lens=16/math.tan(math.radians(62)/2);camdata.clip_start=.035;cam.location=(0,0,1.6)
rig=bpy.data.objects['ExplorerRig'];rig.animation_data.action=bpy.data.actions['Idle'];s.frame_set(1)
bpy.data.objects['Head_Explorer'].visible_camera=False
for offset in [.10,.13,.16]:
 rig.location.y=-offset
 for pitch in [1.1,1.3]:
  cam.rotation_euler=Vector((0,math.cos(pitch),-math.sin(pitch))).to_track_quat('-Z','Y').to_euler()
  s.render.filepath=str(OUT/('explorer_fit_back%03d_pitch%02d.png'%(int(offset*1000),int(pitch*10))));bpy.ops.render.render(write_still=True)
