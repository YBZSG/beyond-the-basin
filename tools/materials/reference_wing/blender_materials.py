"""Blender 4.3 material helper for the runtime reference-wing PBR candidate.

Call build_materials() before export or attach_named_materials() after generating
geometry. Existing material objects keep their exact glTF/runtime role names.
This does not render, modify geometry, alter UVs, or touch water.

The standard Blender glTF exporter converts metre-valued UV (u,v) to (u,1-v).
PNG row0 represents runtime V=0, while Blender samples images from bottom-left.
Thus image coordinates are (u/repeat, 1-(1-v)/repeat). Runtime normal +V maps
to Blender tangent -V, so the helper flips the normal's green channel once.
"""
from pathlib import Path
import json
import bpy

ROOT = Path(__file__).resolve().parents[3]
MAPS = ROOT/'assets/materials/reference_wing'
ROLES = ('ref_tile_pearl','ref_tile_teal','ref_tile_pink','ref_tile_dark_teal',
         'ref_tile_dry','ref_tile_teal_dry','ref_tile_pink_dry','ref_tile_dark_teal_dry',
         'ref_tile_teal_satin','ref_tile_teal_satin_dry','ref_tile_pink_satin','ref_tile_pink_satin_dry',
         'ref_tile_pearl_ref5_crown','ref_tile_cyan_satin','ref_tile_cyan_satin_dry')


def image_node(nodes, filename, color_space):
    image = bpy.data.images.load(str(MAPS/filename),check_existing=True)
    image.colorspace_settings.name = color_space
    image['reference_pbr_color_space'] = color_space
    node = nodes.new('ShaderNodeTexImage')
    node.image = image
    node.extension = 'REPEAT'
    node.interpolation = 'Linear'
    return node


def build_materials(face_roughness=None,face_shape_strength=1.0,roles=None):
    """Optional lab-only wall roughness override; dry floor stays .26.

    The binary shape ablation retains genuine bevel normals. The default
    exactly uses the authored ORM green channel on the three glazed roles.
    """
    if face_shape_strength not in (0.0,1.0):
        raise ValueError('Offline reference supports exact shape ablations 0 or 1 only.')
    manifest = json.loads((MAPS/'material_manifest.json').read_text())
    selected=set(ROLES)|{'ref_grout'} if roles is None else set(roles)
    if not selected.issubset(set(ROLES)|{'ref_grout'}):raise ValueError('Unknown explicit reference role')
    result = {}
    for role in ROLES:
        if role not in selected:continue
        override = manifest['role_overrides'].get(role,{})
        tile_scale = override.get('tile_scale',1.0)
        repeat = manifest['repeat_metres']*tile_scale
        mat = bpy.data.materials.get(role) or bpy.data.materials.new(role)
        mat.use_nodes = True
        nodes,links = mat.node_tree.nodes,mat.node_tree.links
        nodes.clear()
        output = nodes.new('ShaderNodeOutputMaterial')
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        bsdf.inputs['Metallic'].default_value = 0.0
        bsdf.inputs['IOR'].default_value = 1.5
        bsdf.inputs['Specular IOR Level'].default_value = 0.5
        bsdf.inputs['Coat Weight'].default_value = 0.0
        links.new(bsdf.outputs['BSDF'],output.inputs['Surface'])
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'UVMap'
        scale = nodes.new('ShaderNodeVectorMath'); scale.operation = 'MULTIPLY'
        scale.inputs[1].default_value = (1/repeat,1/repeat,1)
        links.new(uv.outputs['UV'],scale.inputs[0])
        phase = nodes.new('ShaderNodeVectorMath'); phase.operation = 'ADD'
        phase.inputs[1].default_value = (0,1-1/repeat,0)
        links.new(scale.outputs['Vector'],phase.inputs[0])
        palette = override.get('palette',role)
        color = image_node(nodes,palette+'_albedo_2k.png','sRGB')
        orm = image_node(nodes,'glaze_orm_2k.png','Non-Color')
        normal_file = override.get('normal_gl16','full_normal_gl_16.png') if face_shape_strength else 'bevel_normal_gl_16.png'
        normal = image_node(nodes,normal_file,'Non-Color')
        for texture in (color,orm,normal): links.new(phase.outputs['Vector'],texture.inputs['Vector'])
        if 'face_color_gain' in override:
            gain=nodes.new('ShaderNodeMixRGB');gain.name='ReferencePaletteRegionGain';gain.blend_type='MIX';gain.use_clamp=False
            gain.inputs[1].default_value=tuple(override['grout_color_gain'])+(1,)
            gain.inputs[2].default_value=tuple(override['face_color_gain'])+(1,)
            links.new(orm.outputs['Alpha'],gain.inputs[0])
            multiply=nodes.new('ShaderNodeMixRGB');multiply.name='ReferencePaletteMultiply';multiply.blend_type='MULTIPLY';multiply.use_clamp=False
            multiply.inputs[0].default_value=1.0
            links.new(color.outputs['Color'],multiply.inputs[1]);links.new(gain.outputs[0],multiply.inputs[2])
            links.new(multiply.outputs[0],bsdf.inputs['Base Color'])
        else:
            links.new(color.outputs['Color'],bsdf.inputs['Base Color'])
        separate = nodes.new('ShaderNodeSeparateColor'); separate.mode = 'RGB'
        links.new(orm.outputs['Color'],separate.inputs['Color'])
        roughness = override.get('face_roughness',face_roughness)
        if roughness is not None:
            # Same coverage offset as the runtime, not a global image tint or
            # a wall-glaze change. Grout remains .82; face becomes .26 +/- .004.
            shift = nodes.new('ShaderNodeMath'); shift.operation = 'MULTIPLY'
            shift.inputs[1].default_value = roughness-manifest['face_roughness']
            links.new(orm.outputs['Alpha'],shift.inputs[0])
            rough = nodes.new('ShaderNodeMath'); rough.operation = 'ADD'
            links.new(shift.outputs[0],rough.inputs[0])
            links.new(separate.outputs['Green'],rough.inputs[1])
            links.new(rough.outputs[0],bsdf.inputs['Roughness'])
        else:
            links.new(separate.outputs['Green'],bsdf.inputs['Roughness'])
        # AO is not multiplied into base colour: the runtime also limits AO to
        # ambient relief. Principled has no equivalent ambient-only AO input.
        flip = nodes.new('ShaderNodeVectorMath'); flip.operation = 'MULTIPLY'
        flip.inputs[1].default_value = (1,-1,1)
        links.new(normal.outputs['Color'],flip.inputs[0])
        offset = nodes.new('ShaderNodeVectorMath'); offset.operation = 'ADD'
        offset.inputs[1].default_value = (0,1,0)
        links.new(flip.outputs['Vector'],offset.inputs[0])
        mapped = nodes.new('ShaderNodeNormalMap')
        mapped.space = 'TANGENT'; mapped.uv_map = 'UVMap'
        mapped.inputs['Strength'].default_value = 1.0
        links.new(offset.outputs['Vector'],mapped.inputs['Color'])
        links.new(mapped.outputs['Normal'],bsdf.inputs['Normal'])
        mat['reference_candidate'] = 'scoped_ref5_crown_cpu_direction' if override.get('face_profile',0)==1 else 'analytic_face_v1_source_only'
        mat['reference_candidate_face_strength'] = face_shape_strength
        mat['tile_scale'] = tile_scale
        mat['tile_pitch_metres'] = manifest['tile_pitch_metres']*tile_scale
        mat['grout_width_metres'] = manifest['grout_width_metres']*tile_scale
        mat['joint_relief_metres'] = manifest['joint_relief_metres']*tile_scale
        mat['crown_metres'] = override.get('crown_metres',manifest['crown_metres'])*tile_scale*face_shape_strength
        mat['face_profile'] = override.get('face_profile',0)
        mat['crown_radius_metres'] = override.get('crown_radius_metres',0.0)*tile_scale
        mat['face_color_gain'] = override.get('face_color_gain',[1.,1.,1.])
        mat['grout_color_gain'] = override.get('grout_color_gain',[1.,1.,1.])
        mat['runtime_uv_contract'] = 'UV1 metre units; standard glTF V flip; no mesh scale.'
        mat['visual_acceptance'] = False
        # Friendly viewport swatch, not another runtime tint multiplier.
        hexcolor = override.get('face_color_hex',manifest['palettes'][palette]['face'])
        mat.diffuse_color = tuple(int(hexcolor[i:i+2],16)/255 for i in (1,3,5))+(1,)
        result[role] = mat
    if 'ref_grout' not in selected:return result
    grout = bpy.data.materials.get('ref_grout') or bpy.data.materials.new('ref_grout')
    grout.use_nodes = True
    p = grout.node_tree.nodes.get('Principled BSDF')
    # Decode the sRGB swatch for Principled's linear value.
    srgb = [int('879188'[i:i+2],16)/255 for i in (0,2,4)]
    linear = [c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in srgb]
    p.inputs['Base Color'].default_value = tuple(linear)+(1,)
    p.inputs['Roughness'].default_value = .82
    p.inputs['Metallic'].default_value = 0.0
    p.inputs['Specular IOR Level'].default_value = .34
    result['ref_grout'] = grout
    return result


def attach_named_materials(objects=None,face_roughness=None,face_shape_strength=1.0):
    materials = build_materials(face_roughness=face_roughness,face_shape_strength=face_shape_strength)
    count = 0
    for ob in list(objects) if objects is not None else list(bpy.data.objects):
        if ob.type != 'MESH': continue
        for index,material in enumerate(ob.data.materials):
            if material is None: continue
            key = material.name.split('.')[0]
            if key in materials:
                ob.data.materials[index] = materials[key]
                count += 1
    return {'rebound_slots':count,'roles':list(materials),'visual_acceptance':False}


def attach_role_materials(roles,objects=None):
    """Build/bind only named roles; every other existing node graph is untouched."""
    materials=build_materials(roles=roles);count=0
    for ob in list(objects) if objects is not None else list(bpy.data.objects):
        if ob.type!='MESH':continue
        for index,material in enumerate(ob.data.materials):
            if material is None:continue
            key=material.name.split('.')[0]
            if key in materials:ob.data.materials[index]=materials[key];count+=1
    return {'rebound_slots':count,'roles':list(materials),'other_node_graphs_rebuilt':False,'visual_acceptance':False}


def apply_strong_face_candidate(normal_path):
    """Transient exact ref-5 1.8 trial; changes only pearl's normal image.

    Call after attach_named_materials(). Do not save/export a production scene
    with this trial attached. Dry, satin and other palette roles are untouched.
    """
    import hashlib
    path=Path(normal_path).resolve()
    if not path.is_relative_to((ROOT/'output').resolve()):
        raise ValueError('Candidate must be the QA-only generated normal.')
    record=json.loads(path.with_suffix('.json').read_text())
    if record['strength']!=1.8 or record['role']!='ref_tile_pearl' or record['production_asset']:
        raise ValueError('Not the approved bounded candidate.')
    bounds=record['physical_bounds']
    if bounds['absolute_height_bound_metres']>=bounds['relief_metres']:
        raise ValueError('Candidate exceeds the physical relief bound.')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=record['sha256']:
        raise ValueError('Candidate normal hash mismatch.')
    material=bpy.data.materials.get('ref_tile_pearl')
    if material is None or not material.use_nodes:
        raise ValueError('Attach the default reference materials first.')
    normal=next(n for n in material.node_tree.nodes if n.type=='NORMAL_MAP')
    offset=normal.inputs['Color'].links[0].from_node
    flip=offset.inputs[0].links[0].from_node
    texture=flip.inputs[0].links[0].from_node
    image=bpy.data.images.load(str(path),check_existing=True)
    image.colorspace_settings.name='Non-Color'
    texture.image=image
    material['reference_candidate_face_strength']=1.8
    material['crown_metres']=record['physical_bounds']['crown_metres']
    material['visual_acceptance']=False
    return record


def apply_planar_face_candidate(normal_path):
    """One transient QA structural candidate; no runtime/default promotion."""
    import hashlib
    path=Path(normal_path).resolve()
    if not path.is_relative_to((ROOT/'output').resolve()):raise ValueError('QA normal only')
    record=json.loads(path.with_suffix('.json').read_text())
    if record['candidate']!='planar_interior_015deg' or record['role']!='ref_tile_pearl' or record['production_asset']:
        raise ValueError('Not the approved structural candidate')
    bounds=record['physical_bounds']
    if bounds['face_height_absolute_bound_metres']>=bounds['unchanged_relief_metres']:
        raise ValueError('Candidate violates height bound')
    if bounds['face_gradient_length_bound']>=bounds['unchanged_bevel_peak_slope']:
        raise ValueError('Candidate violates slope bound')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=record['sha256']:raise ValueError('QA normal hash mismatch')
    material=bpy.data.materials.get('ref_tile_pearl')
    if material is None or not material.use_nodes:raise ValueError('Attach default reference materials first')
    normal=next(n for n in material.node_tree.nodes if n.type=='NORMAL_MAP')
    offset=normal.inputs['Color'].links[0].from_node;flip=offset.inputs[0].links[0].from_node
    texture=flip.inputs[0].links[0].from_node
    image=bpy.data.images.load(str(path),check_existing=True);image.colorspace_settings.name='Non-Color'
    texture.image=image
    material['reference_candidate']='planar_interior_015deg_qa_only'
    material['crown_metres']=bounds['crown_metres']
    material['visual_acceptance']=False
    return record


def apply_localized_crown_candidate(normal_path):
    """One transient 0.30 mm / R40 mm crown trial; pearl normal only."""
    import hashlib
    path=Path(normal_path).resolve()
    if not path.is_relative_to((ROOT/'output').resolve()):raise ValueError('QA normal only')
    record=json.loads(path.with_suffix('.json').read_text())
    if record['candidate']!='localized_crown_030mm_r40mm' or record['role']!='ref_tile_pearl' or record['production_asset']:
        raise ValueError('Not the approved crown candidate')
    bounds=record['physical_bounds']
    if bounds['minimum_interior_height_bound_metres']<=0 or bounds['maximum_interior_height_bound_metres']>=.00065:
        raise ValueError('Candidate violates interior height bounds')
    if bounds['face_gradient_length_bound']>=bounds['unchanged_bevel_peak_slope']:
        raise ValueError('Candidate violates slope bound')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=record['sha256']:raise ValueError('QA normal hash mismatch')
    material=bpy.data.materials.get('ref_tile_pearl')
    if material is None or not material.use_nodes:raise ValueError('Attach default reference materials first')
    normal=next(n for n in material.node_tree.nodes if n.type=='NORMAL_MAP')
    offset=normal.inputs['Color'].links[0].from_node;flip=offset.inputs[0].links[0].from_node
    texture=flip.inputs[0].links[0].from_node
    image=bpy.data.images.load(str(path),check_existing=True);image.colorspace_settings.name='Non-Color'
    texture.image=image
    material['reference_candidate']='localized_crown_030mm_r40mm_qa_only'
    material['crown_metres']=bounds['crown_metres']
    material['visual_acceptance']=False
    return record
