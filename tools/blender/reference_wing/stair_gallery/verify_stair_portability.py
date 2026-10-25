"""Read-only source portability check in original and isolated source+maps roots."""
import bpy,os,json,hashlib,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/reference_wing/stair'
SOURCE_REL=Path('tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend')
GLB=ROOT/'assets/models/reference_wing/stair_gallery.glb'
RESTORE=QA/'portability_restore';RESTORE.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
before_source=sha(ROOT/SOURCE_REL);before_glb=sha(GLB)
(RESTORE/SOURCE_REL).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/SOURCE_REL,RESTORE/SOURCE_REL)
shutil.copytree(ROOT/'assets/materials/reference_wing',RESTORE/'assets/materials/reference_wing',dirs_exist_ok=True)
report={'method':'Open unchanged original .blend, then an isolated copy containing only source .blend plus the material map directory in the same project-relative layout. Resolve and force-read every FILE image. No source save or runtime modification.','before_source_sha256':before_source,'before_glb_sha256':before_glb,'restore_root':str(RESTORE),'roots':[],'failures':[]}
for label,root in [('original',ROOT),('isolated_restore',RESTORE)]:
 bpy.ops.wm.open_mainfile(filepath=str(root/SOURCE_REL));items=[]
 for im in bpy.data.images:
  if im.source!='FILE' or not im.filepath:continue
  actual=Path(bpy.path.abspath(im.filepath)).resolve();relative=im.filepath.startswith('//');inside=actual==root.resolve() or root.resolve() in actual.parents
  item={'image':im.name,'stored_filepath':im.filepath,'stored_project_relative':relative,'resolved_path':str(actual),'inside_selected_root':inside,'exists':actual.is_file()}
  try:
   im.reload();sample=list(im.pixels[:4]);item.update({'decoded_size':list(im.size),'first_pixel_components_read':len(sample),'decode_pass':len(sample)==4 and im.size[0]>0 and im.size[1]>0})
  except Exception as e:item.update({'decode_pass':False,'error':str(e)})
  item['pass']=relative and inside and item['exists'] and item['decode_pass'];items.append(item)
  if not item['pass']:report['failures'].append(item)
 report['roots'].append({'label':label,'root':str(root),'image_count':len(items),'images':items})
report['after_source_sha256']=sha(ROOT/SOURCE_REL);report['after_glb_sha256']=sha(GLB);report['source_unchanged']=before_source==report['after_source_sha256'];report['glb_unchanged']=before_glb==report['after_glb_sha256'];report['summary']={'original_file_images':report['roots'][0]['image_count'],'isolated_file_images':report['roots'][1]['image_count'],'all_project_relative_and_restored':not report['failures'],'source_modified':not report['source_unchanged'],'glb_modified':not report['glb_unchanged'],'failure_count':len(report['failures'])}
json.dump(report,open(QA/'stair_portability_checks.json','w'),indent=2);print('STAIR_PORTABILITY',json.dumps(report['summary']));assert not report['failures'] and report['source_unchanged'] and report['glb_unchanged']
