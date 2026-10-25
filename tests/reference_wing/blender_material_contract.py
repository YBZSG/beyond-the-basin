"""Blender CPU node/resource check only. No render, export or .blend writes.

blender -b --factory-startup --python-exit-code 1 --python tests/reference_wing/blender_material_contract.py
"""
from pathlib import Path
import json
import math
import sys
import argparse
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/materials/reference_wing'))
import blender_materials as helper
manifest=json.loads((ROOT/'assets/materials/reference_wing/material_manifest.json').read_text())
errors=[]


def check(condition,message):
    if not condition: errors.append(message)


def close(a,b): return math.isclose(a,b,abs_tol=2e-6)


def verify(rough_override=None,shape=1.0):
    materials=helper.build_materials(face_roughness=rough_override,face_shape_strength=shape)
    for role in helper.ROLES:
        material=materials[role];nodes=material.node_tree.nodes
        preset=manifest['role_overrides'].get(role,{})
        scale=preset.get('tile_scale',1.0);repeat=manifest['repeat_metres']*scale
        check(material.name==role,'Role name changed: '+role)
        check(close(material['tile_pitch_metres'],manifest['tile_pitch_metres']*scale),'Wrong pitch: '+role)
        check(close(material['grout_width_metres'],manifest['grout_width_metres']*scale),'Wrong joint: '+role)
        check(close(material['joint_relief_metres'],manifest['joint_relief_metres']*scale),'Wrong relief: '+role)
        check(close(material['crown_metres'],preset.get('crown_metres',manifest['crown_metres'])*scale*shape),'Wrong crown: '+role)
        check(material['face_profile']==preset.get('face_profile',0),'Profile leaked: '+role)
        bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        check(close(bsdf.inputs['Metallic'].default_value,0),'Metal changed: '+role)
        check(close(bsdf.inputs['IOR'].default_value,1.5),'IOR changed: '+role)
        check(close(bsdf.inputs['Coat Weight'].default_value,0),'Coat added: '+role)
        for texture in [n for n in nodes if n.type=='TEX_IMAGE']:
            phase=texture.inputs['Vector'].links[0].from_node
            check(phase.operation=='ADD','Missing coordinate phase: '+role)
            check(close(phase.inputs[1].default_value[1],1-1/repeat),'glTF V phase wrong: '+role)
            mult=phase.inputs[0].links[0].from_node
            check(mult.operation=='MULTIPLY','Missing coordinate scale: '+role)
            check(close(mult.inputs[1].default_value[0],1/repeat) and close(mult.inputs[1].default_value[1],1/repeat),'Texture scale mismatch: '+role)
            file=Path(texture.image.filepath).name
            check(texture.image.colorspace_settings.name==('sRGB' if '_albedo_' in file else 'Non-Color'),'Color-space mismatch: '+role+'/'+file)
        palette=preset.get('palette',role)
        color=bsdf.inputs['Base Color'].links[0].from_node
        if 'face_color_gain' in preset:
            check(color.type=='MIX_RGB' and color.blend_type=='MULTIPLY' and not color.use_clamp,'Missing linear palette multiply: '+role)
            gain=color.inputs[2].links[0].from_node
            check(gain.blend_type=='MIX' and not gain.use_clamp,'Missing region gain: '+role)
            check(gain.inputs[0].links[0].from_socket.name=='Alpha','Palette region mask is not ORM coverage: '+role)
            for i in range(3):
                check(close(gain.inputs[1].default_value[i],preset['grout_color_gain'][i]),'Grout linear gain mismatch: '+role)
                check(close(gain.inputs[2].default_value[i],preset['face_color_gain'][i]),'Face linear gain mismatch: '+role)
            color=color.inputs[1].links[0].from_node
        check(Path(color.image.filepath).name==palette+'_albedo_2k.png','Wrong palette map: '+role)
        normal=next(n for n in nodes if n.type=='NORMAL_MAP')
        check(normal.space=='TANGENT' and normal.uv_map=='UVMap','Normal orientation contract changed: '+role)
        offset=normal.inputs['Color'].links[0].from_node
        flip=offset.inputs[0].links[0].from_node
        check(tuple(flip.inputs[1].default_value)==(1.,-1.,1.),'Expected one green inversion: '+role)
        normal_image=flip.inputs[0].links[0].from_node.image
        check(Path(normal_image.filepath).name==(preset.get('normal_gl16','full_normal_gl_16.png') if shape else 'bevel_normal_gl_16.png'),'Shape ablation lost bevel/profile: '+role)
        expected=preset.get('face_roughness',rough_override)
        rough=bsdf.inputs['Roughness'].links[0].from_node
        if expected is None:
            check(rough.type=='SEPARATE_COLOR','Default ORM roughness altered: '+role)
        else:
            check(rough.type=='MATH' and rough.operation=='ADD','Missing region-specific roughness offset: '+role)
            shift=rough.inputs[0].links[0].from_node
            check(close(shift.inputs[1].default_value,expected-manifest['face_roughness']),'Wrong roughness preset: '+role)
            check(shift.inputs[0].links[0].from_socket.name=='Alpha','Roughness offset must use face coverage: '+role)


untouched=bpy.data.materials.new('CONTRACT_UNRELATED_WATER')
untouched.use_nodes=True
old_nodes=tuple(n.name for n in untouched.node_tree.nodes)
verify()
verify(rough_override=.115,shape=0.0)
check(tuple(n.name for n in untouched.node_tree.nodes)==old_nodes,'Unrelated water material was touched')
helper.build_materials()
# The two-role helper must not even recreate another role's existing nodes.
cyan_roles=['ref_tile_cyan_satin','ref_tile_cyan_satin_dry']
node_identity={role:tuple(n.as_pointer() for n in bpy.data.materials[role].node_tree.nodes)
               for role in helper.ROLES if role not in cyan_roles}
helper.attach_role_materials(cyan_roles,objects=[])
for role,identities in node_identity.items():
    check(tuple(n.as_pointer() for n in bpy.data.materials[role].node_tree.nodes)==identities,'Scoped cyan helper rebuilt another graph: '+role)
parser=argparse.ArgumentParser();parser.add_argument('--candidate-normal',type=Path)
parser.add_argument('--planar-normal',type=Path)
parser.add_argument('--crown-normal',type=Path)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
candidate_checked=False
if args.candidate_normal:
    def images(role):
        return [str(Path(n.image.filepath)) for n in bpy.data.materials[role].node_tree.nodes if n.type=='TEX_IMAGE']
    before={role:images(role) for role in helper.ROLES}
    pearl=bpy.data.materials['ref_tile_pearl'];bsdf=next(n for n in pearl.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    roughness_link=bsdf.inputs['Roughness'].links[0].from_node
    helper.apply_strong_face_candidate(args.candidate_normal)
    for role in helper.ROLES:
        if role!='ref_tile_pearl':check(images(role)==before[role],'Trial touched another role: '+role)
    check(images('ref_tile_pearl')[:2]==before['ref_tile_pearl'][:2],'Trial changed pearl base/ORM maps')
    check(bsdf.inputs['Roughness'].links[0].from_node==roughness_link,'Trial changed pearl roughness')
    check(pearl['reference_candidate_face_strength']==1.8,'Trial strength metadata missing')
    check(close(pearl['crown_metres'],.00009),'Trial crown metadata incorrect')
    helper.build_materials()
    check(images('ref_tile_pearl')==before['ref_tile_pearl'],'Default normal not restored')
    check(pearl['reference_candidate_face_strength']==1.0,'Default strength metadata not restored')
    candidate_checked=True
planar_checked=False
if args.planar_normal:
    def image_paths(role):
        return [str(Path(n.image.filepath)) for n in bpy.data.materials[role].node_tree.nodes if n.type=='TEX_IMAGE']
    before={role:image_paths(role) for role in helper.ROLES}
    pearl=bpy.data.materials['ref_tile_pearl'];bsdf=next(n for n in pearl.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    roughness_link=bsdf.inputs['Roughness'].links[0].from_node
    helper.apply_planar_face_candidate(args.planar_normal)
    for role in helper.ROLES:
        if role!='ref_tile_pearl':check(image_paths(role)==before[role],'Planar trial touched another role: '+role)
    check(image_paths('ref_tile_pearl')[:2]==before['ref_tile_pearl'][:2],'Planar trial changed base/ORM')
    check(bsdf.inputs['Roughness'].links[0].from_node==roughness_link,'Planar trial changed roughness')
    check(pearl['reference_candidate']=='planar_interior_015deg_qa_only','Planar trial not labeled')
    check(close(pearl['crown_metres'],.00001),'Planar crown metadata incorrect')
    helper.build_materials()
    check(image_paths('ref_tile_pearl')==before['ref_tile_pearl'],'Planar default normal not restored')
    check(pearl['reference_candidate']=='analytic_face_v1_source_only','Planar tag not restored')
    planar_checked=True
crown_checked=False
if args.crown_normal:
    def image_paths(role):
        return [str(Path(n.image.filepath)) for n in bpy.data.materials[role].node_tree.nodes if n.type=='TEX_IMAGE']
    before={role:image_paths(role) for role in helper.ROLES}
    pearl=bpy.data.materials['ref_tile_pearl'];bsdf=next(n for n in pearl.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    roughness_link=bsdf.inputs['Roughness'].links[0].from_node
    helper.apply_localized_crown_candidate(args.crown_normal)
    for role in helper.ROLES:
        if role!='ref_tile_pearl':check(image_paths(role)==before[role],'Crown trial touched another role: '+role)
    check(image_paths('ref_tile_pearl')[:2]==before['ref_tile_pearl'][:2],'Crown trial changed base/ORM')
    check(bsdf.inputs['Roughness'].links[0].from_node==roughness_link,'Crown trial changed roughness')
    check(pearl['reference_candidate']=='localized_crown_030mm_r40mm_qa_only','Crown trial not labeled')
    check(close(pearl['crown_metres'],.00030),'Crown metadata incorrect')
    helper.build_materials()
    check(image_paths('ref_tile_pearl')==before['ref_tile_pearl'],'Crown default normal not restored')
    check(pearl['reference_candidate']=='analytic_face_v1_source_only','Crown tag not restored')
    crown_checked=True
role_parameters={}
for role in helper.ROLES:
    material=bpy.data.materials[role]
    bsdf=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    source=bsdf.inputs['Roughness'].links[0].from_node
    nominal=manifest['face_roughness']
    if source.type=='MATH':nominal+=source.inputs[0].links[0].from_node.inputs[1].default_value
    role_parameters[role]={key:material[key] for key in ['tile_scale','tile_pitch_metres','grout_width_metres','joint_relief_metres','crown_metres','crown_radius_metres','face_profile']}
    for key in ['face_color_gain','grout_color_gain']:role_parameters[role][key]=list(material[key])
    role_parameters[role]['face_roughness']=nominal
print('REFERENCE_BLENDER_MATERIAL_CONTRACT '+json.dumps({'passed':not errors,'errors':errors,
    'blender':bpy.app.version_string,'tile_roles':list(helper.ROLES),
    'role_parameters':role_parameters,
    'strong_face_candidate_isolation_checked':candidate_checked,
    'planar_face_candidate_isolation_checked':planar_checked,
    'localized_crown_candidate_isolation_checked':crown_checked,
    'scoped_cyan_helper_preserves_other_node_identities':True,
    'scope':'CPU material-node construction, map bindings, color spaces, physical dimensions, V phase and ablation isolation only. No render or GPU/native validation.'}))
if errors: raise RuntimeError('; '.join(errors))
