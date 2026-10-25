"""Scoped, geometry-neutral reference-5 wall-face role assignment."""
import bpy

ROLE = 'ref_tile_pearl_ref5_crown'
WALL_OBJECTS = {
    'EastWall', 'WestRecessWall', 'SouthClosedWall', 'PlanterEndReturn',
    'LowerLandingWestWall', 'NorthFarWallLeft', 'NorthFarWallRight',
    'NorthFarWallCrown', 'ContinuousSlopingParapet',
} | {'ArchSpandrel_%02d' % i for i in range(24)}


def restore_historical_pearl_bindings():
    """Transient historical A/B control only; callers must never save/export."""
    original = bpy.data.materials.get('ref_tile_pearl')
    assert original is not None
    count = 0
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for index, mat in enumerate(ob.data.materials):
            if mat and mat.name == ROLE:
                ob.data.materials[index] = original
                count += 1
    return count


def bind_ref5_crown_vertical_walls():
    material = bpy.data.materials.get(ROLE)
    if material is None:
        raise RuntimeError('Dedicated reviewed crown material is required before binding.')
    records = []
    for name in sorted(WALL_OBJECTS):
        ob = bpy.data.objects.get(name)
        assert ob is not None and ob.type == 'MESH', name
        index = next((i for i, m in enumerate(ob.data.materials) if m == material), None)
        if index is None:
            ob.data.materials.append(material)
            index = len(ob.data.materials) - 1
        faces, area = [], 0.0
        normal_matrix = ob.matrix_world.to_3x3().inverted().transposed()
        for face in ob.data.polygons:
            old_role = ob.data.materials[face.material_index].name
            if old_role not in ('ref_tile_pearl', ROLE):
                continue
            # BlenderZ is GodotY. Horizontal caps and sloping structural bevels
            # retain their original glaze; only actual vertical wall faces bind.
            normal = (normal_matrix @ face.normal).normalized()
            if abs(normal.z) <= 1e-5:
                face.material_index = index
                faces.append(face.index)
                area += face.area
        assert faces, name
        ob['runtime_roles'] = ['ref_tile_pearl', ROLE]
        records.append({'object': name, 'polygon_indices': faces,
                        'polygon_count': len(faces), 'area_m2': area})
    return {'role': ROLE, 'source_role': 'ref_tile_pearl',
            'scope': 'Vertical pearl faces of main/far walls, continuous parapet and arch spandrels only.',
            'excluded': ['ceiling', 'horizontal parapet caps', 'sloping structural bevels',
                         'dry walking surfaces', 'teal arch', 'foundations', 'hidden connector'],
            'normal_test': 'abs(world_normal_BlenderZ)<=1e-5',
            'objects': records, 'object_count': len(records),
            'polygon_count': sum(r['polygon_count'] for r in records),
            'geometry_modified': False, 'native_visual_acceptance': False}
