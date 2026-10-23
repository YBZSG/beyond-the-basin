"""Read-only saved-.blend witness; never trusts in-memory pre-save geometry."""
import hashlib,json,sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[3];sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_candidate import signature,TARGETS
src=ROOT/'tools/blender/bath_junction_candidate/formal_bath_continuous_wall.blend';out=ROOT/'assets/models/bath_junction_candidate';doc=ROOT/'docs/bath-junction-candidate'
before=hashlib.sha256(src.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(src),load_ui=False,use_scripts=False)
expected=json.loads((doc/'blend-geometry-report.json').read_text())
assert signature(bpy.data.objects['Bath_Wall'])==expected['new_wall_semantic_sha256']
actual={ob.name:signature(ob) for ob in bpy.context.scene.objects if ob.name not in TARGETS}
assert actual==expected['object_semantic_sha256']
bpy.ops.object.select_all(action='DESELECT');bpy.data.objects['Bath_Wall'].select_set(True);bpy.context.view_layer.objects.active=bpy.data.objects['Bath_Wall']
bpy.ops.export_scene.gltf(filepath=str(out/'saved_source_wall_roundtrip.glb'),export_format='GLB',export_yup=True,export_apply=True,
                         export_extras=True,export_cameras=False,export_lights=False,use_selection=True)
assert hashlib.sha256(src.read_bytes()).hexdigest()==before
from splice_and_verify import GLB,primitive_signature
candidate=GLB(out/'formal_bath_continuous_wall.glb')
roundtrip=GLB(out/'saved_source_wall_roundtrip.glb')
compact=GLB(out/'formal_bath_full_source_export.glb')
original=GLB(ROOT/'assets/models/formal/formal_bath.glb')
assert primitive_signature(candidate,'Bath_Wall')==primitive_signature(roundtrip,'Bath_Wall')
old={n['name']:n for n in original.doc['nodes']};new={n['name']:n for n in compact.doc['nodes']}
for name in set(old)-TARGETS:
 for key in ('matrix','translation','rotation','scale','extras','name'):
  assert old[name].get(key)==new[name].get(key),(name,key)
report={'pass':True,'candidate_blend_sha256':before,'reopened_wall_signature_exact':True,
        'reopened_unrelated_objects_exact':len(actual),'source_file_unchanged':True,
        'roundtrip_export':'assets/models/bath_junction_candidate/saved_source_wall_roundtrip.glb',
        'reopened_export_candidate_attribute_bytes_exact':True,
        'full_export_unrelated_node_transforms_and_extras_exact':True,
        'full_source_export_sha256':hashlib.sha256(compact.raw).hexdigest(),
        'full_source_export_bytes':len(compact.raw)}
(doc/'saved-source-reopen-proof.json').write_text(json.dumps(report,indent=2)+'\n')
print('SAVED_SOURCE_REOPEN_PASS')
