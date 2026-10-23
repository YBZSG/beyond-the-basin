"""Label unmodified CPU audit renders for owner comparison, no synthetic pixels."""
from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];R=HERE/'audit/renders'
font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font=ImageFont.truetype(font_path,23);small=ImageFont.truetype(font_path,17)
for name,files,labels in [
 ('hand_before_after.png',['baseline_hand_dorsal.png','v2_hand_dorsal.png'],['Baseline: wrist seam / broad webbing','V2: continuous wrist / distinct fingers']),
 ('supported_hand_poses.png',['v2_carry_large.png','v2_cupped_grip.png'],['Supported Carry: thumb root at rest','Optional cupped grip: bounded curl'])]:
 canvas=Image.new('RGB',(1200,884),(29,38,43));draw=ImageDraw.Draw(canvas)
 draw.text((18,12),'Blender CPU anatomy audit | not gameplay or GPU evidence',font=font,fill=(235,239,240))
 for i,(file,label) in enumerate(zip(files,labels)):
  draw.text((i*600+18,50),label,font=small,fill=(203,214,218));canvas.paste(Image.open(R/file).convert('RGB'),(i*600,84))
 canvas.save(HERE/'audit'/name)
manifest=json.loads((ROOT/'assets/models/avatar_v2/avatar_v2_manifest.json').read_text())
accepted={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in R.glob('v2_*.png')}
accepted.update({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in R.glob('baseline_*.png')})
(HERE/'audit/render_manifest.json').write_text(json.dumps({'candidate_glb_sha256':manifest['glb_sha256'],'candidate_blend_sha256':manifest['blend_sha256'],'renderer':'Blender 4.3.2 Cycles CPU, 4 threads, 20 samples, no denoising','gameplay_evidence':False,'gpu_performance_evidence':False,'source':'Saved .blend, hand views isolate actual left-arm geometry to remove torso occlusion.','accepted_renders':accepted,'excluded_diagnostics':'diagnostic_* and rejected_* are process evidence, not final supported pose renders.'},indent=2))
