"""Read-only composition render from a finished source. Never saves .blend/GLB.
blender -b -t 4 --python tools/blender/reference_wing/water_rooms_render.py -- --room colonnade --samples 48
"""
import bpy,sys,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--room',required=True,choices=['colonnade','cyan_corridor','octagonal_bath']);p.add_argument('--samples',type=int,default=48);p.add_argument('--resolution',type=int,default=700)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/blender/reference_wing/water_sources'/f'{a.room}.blend'))
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=a.samples;s.cycles.use_denoising=False;s.render.resolution_x=a.resolution;s.render.resolution_y=a.resolution;s.render.resolution_percentage=100;s.render.filepath=str(ROOT/'output/reference_wing/water_rooms'/f'{a.room}_blender_cpu.png');s.render.use_stamp=True;s.render.use_stamp_note=True;s.render.stamp_note_text='BLENDER CPU COMPOSITION PREVIEW | NOT GODOT / NVIDIA VALIDATION';bpy.ops.render.render(write_still=True)
print('READ_ONLY_PREVIEW_COMPLETE',a.room)
