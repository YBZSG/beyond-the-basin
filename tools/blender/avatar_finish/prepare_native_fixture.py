"""Prepare an isolated small fixture; this does NOT run Godot or a renderer."""
from pathlib import Path
import shutil,json,hashlib
ROOT=Path(__file__).resolve().parents[3]
STAGE=Path('/tmp/avatar_finish_candidate_stage')
if (STAGE/'captures').exists():shutil.rmtree(STAGE/'captures')
files=['scripts/player/avatar_finish_candidate.gd','shaders/avatar_finish_candidate.gdshader','shaders/avatar_body.gdshader','tests/avatar_finish_candidate_native.gd','assets/models/avatar_v2/pool_explorer_v2.glb']
files += [p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/textures/avatar_finish').glob('*.png')]
files += [p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/textures/avatar_finish').glob('*.png.import')]
files += ['assets/textures/avatar_finish/avatar_finish_candidate.glb']
for f in files:
 dest=STAGE/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/f,dest)
# Keep authored UV2/tangents, no lightmap UV regeneration and no Blend import.
for relative in ['assets/textures/avatar_finish/avatar_finish_candidate.glb','assets/models/avatar_v2/pool_explorer_v2.glb']:
 name=Path(relative).name;digest=hashlib.md5(('res://'+relative).encode()).hexdigest();out=f'res://.godot/imported/{name}-{digest}.scn'
 text=f'''[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{out}"\n\n[deps]\n\nsource_file="res://{relative}"\ndest_files=["{out}"]\n\n[params]\n\nnodes/root_type=""\nnodes/root_name=""\nnodes/root_script=null\nnodes/apply_root_scale=true\nnodes/root_scale=1.0\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=true\nmeshes/light_baking=0\nmeshes/force_disable_compression=true\nskins/use_named_skins=true\nanimation/import=true\nanimation/fps=30\nanimation/trimming=false\nanimation/remove_immutable_tracks=true\nimport_script/path=""\nmaterials/extract=0\n_subresources={{}}\ngltf/naming_version=2\ngltf/embedded_image_handling=1\n'''
 (STAGE/(relative+'.import')).write_text(text)
 if 'textures/avatar_finish/' in relative:(ROOT/(relative+'.import')).write_text(text)
(STAGE/'project.godot').write_text('''config_version=5\n[application]\nconfig/name="Isolated avatar finish candidate QA"\n[display]\nwindow/size/viewport_width=960\nwindow/size/viewport_height=720\nwindow/size/window_width_override=960\nwindow/size/window_height_override=720\n[rendering]\nrenderer/rendering_method="forward_plus"\ntextures/default_filters/use_nearest_mipmap_filter=false\n''')
print(json.dumps(dict(stage=str(STAGE),copied_files={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files},ran_engine=False),indent=2))
