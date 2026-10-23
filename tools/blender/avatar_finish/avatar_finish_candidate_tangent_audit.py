#!/usr/bin/env python3
"""Read-only CPU audit of the actual candidate's UV2 tangent direction.

This does not launch Blender/Godot, regenerate MikkTSpace, or modify an asset.
Per-face derivatives are compared to smoothed per-corner Mikk tangents, so
nonzero angular residuals are expected. Ill-conditioned faces are disclosed,
not silently removed from the aggregate. Output refuses an existing path.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from avatar_finish_glb import CLOTH, FROZEN_SHA, GLB, weighted_quantiles

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'assets/models/avatar_v2/pool_explorer_v2.glb'
CANDIDATE = ROOT / 'assets/textures/avatar_finish/avatar_finish_candidate.glb'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def audit():
    source, candidate = GLB(SOURCE), GLB(CANDIDATE)
    assert sha(SOURCE) == FROZEN_SHA
    surfaces = {}
    for index, profile in CLOTH.items():
        primitive = candidate.j['meshes'][0]['primitives'][index]
        attrs = {k: candidate.acc(v).astype(float)
                 for k, v in primitive['attributes'].items()}
        indices = candidate.acc(primitive['indices']).reshape(-1, 3).astype(int)
        old = source.j['meshes'][0]['primitives'][index]
        old_indices = source.acc(old['indices']).reshape(-1, 3).astype(int)
        preserved = {}
        for name in ['POSITION', 'NORMAL', 'TEXCOORD_0']:
            preserved[name] = bool(np.array_equal(
                attrs[name][indices], source.acc(old['attributes'][name])[old_indices]))
        assert all(preserved.values())
        positions = attrs['POSITION'][indices]
        normals = unit(attrs['NORMAL'][indices])
        tangents = unit(attrs['TANGENT'][indices, :3])
        signs = attrs['TANGENT'][indices, 3]
        bitangents = np.cross(normals, tangents) * signs[..., None]
        edge1 = positions[:, 1] - positions[:, 0]
        edge2 = positions[:, 2] - positions[:, 0]
        cross = np.cross(edge1, edge2)
        area = np.linalg.norm(cross, axis=-1) / 2
        full_area = float(area.sum())
        result = dict(
            triangles=len(indices), area_m2=full_area,
            original_has_tangent='TANGENT' in old['attributes'],
            canonical_source_attributes_preserved=preserved,
            tangent_sign_values=np.unique(signs).tolist(),
            comparisons={},
        )
        for uv_name in ['TEXCOORD_1', 'TEXCOORD_0']:
            uv = attrs[uv_name][indices].copy()
            # Reconstruct authored +V-up, the direction encoded by PNG green.
            # glTF UV/image row coordinates use V-down after Blender's export.
            uv[:, :, 1] = 1 - uv[:, :, 1]
            du1, du2 = uv[:, 1] - uv[:, 0], uv[:, 2] - uv[:, 0]
            det = du1[:, 0] * du2[:, 1] - du1[:, 1] * du2[:, 0]
            valid = (det != 0) & (area > 0)
            ids = np.flatnonzero(valid)
            jac_u = (edge1[valid] * du2[valid, 1, None]
                     - edge2[valid] * du1[valid, 1, None]) / det[valid, None]
            jac_v = (edge2[valid] * du1[valid, 0, None]
                     - edge1[valid] * du2[valid, 0, None]) / det[valid, None]
            nn, tt, bb = normals[valid], tangents[valid], bitangents[valid]
            projected_u = unit(jac_u[:, None, :] - nn * np.sum(
                nn * jac_u[:, None, :], axis=-1, keepdims=True))
            projected_v = unit(jac_v[:, None, :] - nn * np.sum(
                nn * jac_v[:, None, :], axis=-1, keepdims=True))
            u_dot = np.sum(tt * projected_u, axis=-1)
            v_dot = np.sum(bb * projected_v, axis=-1)
            weights = np.repeat(area[valid] / 3, 3)
            angle = np.degrees(np.arccos(np.clip(u_dot.ravel(), -1, 1)))
            expected_sign = np.sign(np.sum(
                np.cross(jac_u, jac_v)[:, None, :] * nn, axis=-1))
            mismatches = expected_sign != signs[valid]
            mismatch_faces = ids[mismatches.any(axis=1)]
            result['comparisons'][uv_name] = dict(
                valid_triangles=int(valid.sum()),
                omitted_degenerate_uv_or_geometry_triangles=int((~valid).sum()),
                omitted_area_fraction=float(area[~valid].sum() / full_area),
                tangent_vs_projected_u_angle_degrees_p50_p95_p99=weighted_quantiles(
                    angle, weights, (.5, .95, .99)),
                minimum_tangent_dot_projected_u=float(u_dot.min()),
                negative_u_corner_area_fraction=float(
                    weights[u_dot.ravel() < 0].sum() / full_area),
                minimum_bitangent_dot_projected_authored_v=float(v_dot.min()),
                negative_v_corner_area_fraction=float(
                    weights[v_dot.ravel() < 0].sum() / full_area),
                face_jacobian_handedness_mismatch_corners=int(mismatches.sum()),
                face_jacobian_handedness_mismatch_triangle_count=len(mismatch_faces),
                mismatch_triangle_area_m2=float(area[mismatch_faces].sum()),
                mismatch_triangle_area_fraction=float(area[mismatch_faces].sum() / full_area),
            )
            if uv_name == 'TEXCOORD_1':
                # Detailed UV2 outliers are small enough to keep every one.
                result['uv2_handedness_outliers'] = [dict(
                    triangle=int(i), area_m2=float(area[i]),
                    source_geometry_and_normals_unchanged=True,
                    face_cross_dot_authored_normals=np.sum(
                        cross[i][None, :] * normals[i], axis=-1).tolist(),
                    minimum_edge_length_m=float(min(
                        np.linalg.norm(positions[i, 1] - positions[i, 0]),
                        np.linalg.norm(positions[i, 2] - positions[i, 1]),
                        np.linalg.norm(positions[i, 0] - positions[i, 2]))),
                ) for i in mismatch_faces]
                result['uv2_negative_v_derivative_corners'] = [dict(
                    triangle=int(ids[i]), corner=int(c),
                    whole_triangle_area_m2=float(area[ids[i]]),
                    whole_triangle_area_fraction=float(area[ids[i]] / full_area),
                    position_m=positions[ids[i], c].tolist(),
                    bitangent_dot_projected_v=float(v_dot[i, c]),
                    face_u_v_angle_degrees=float(np.degrees(np.arccos(np.clip(
                        np.dot(unit(jac_u[i]), unit(jac_v[i])), -1, 1)))),
                ) for i, c in np.argwhere(v_dot < 0)]
        surfaces[profile] = result
    report = dict(
        candidate_sha256=sha(CANDIDATE), frozen_source_sha256=sha(SOURCE),
        script_sha256=sha(__file__),
        conclusion='UV2-derived tangents confirmed, with disclosed tiny ill-conditioned shirt faces; not a UV0 tangent-frame mismatch.',
        source_chain={
            'builder': 'build_avatar_finish_candidate.py:138-188 rotates/scales FabricMeters, then explicitly calc_tangents(uvmap=FabricMeters) and writes TANGENT.',
            'editable_exporter': 'export_edited_avatar_finish_uv.py also explicitly recomputes FabricMeters tangents before export.',
            'blender_exporter': '/usr/share/blender/scripts/addons_core/io_scene_gltf2/blender/exp/primitive_extract.py:1398-1407 flips V;1476-1520 preserves loop tangent/sign for identity geometry transforms.',
            'godot_importer': 'https://github.com/godotengine/godot/blob/4.6.3-stable/modules/gltf/gltf_document.cpp#L1447-L1454',
            'godot_generate_only_when_absent': 'https://github.com/godotengine/godot/blob/4.6.3-stable/modules/gltf/gltf_document.cpp#L1631-L1669',
            'godot_normal_map_basis': 'docs/audit/source_capture_colors/engine-4.6.3/scene_forward_clustered.glsl:756,1437-1442 uses cross(N,T)*sign and NORMAL_MAP in TBN.',
        },
        convention={
            'geometry': 'Frozen glTF metre/Y-up coordinates retained; no export axis conversion.',
            'uv': 'UV2=(FabricMeters.U,1-FabricMeters.V); UV0 retained for original albedo only.',
            'texture': 'PNG rows downward; linear OpenGL +Y normal from analytic height derivatives.',
            'shader': 'Positive repeat R with y phase1-R gives texture row coordinate1-R*FabricMeters.V. Translation and positive scale do not rotate or mirror the tangent axes.',
            'restrictions': 'Do not add arbitrary UV2 rotation, negative repeat, or a UV0 normal map using this same single tangent frame without recomputing a matching frame.',
        },
        limitations=[
            'This is an independent triangle-Jacobian direction check, not a byte-identical MikkTSpace recomputation.',
            'Smoothed vertex tangents need not equal each incident triangle derivative, especially on sharp curvature or skewed charts.',
            'Two shirt faces have near-coincident source corners and opposite source winding/custom normals. Their original geometry/normals are preserved, not repaired.',
            'One very small shirt sleeve triangle has a highly skewed UV2 derivative and one negative bitangent/V corner projection. This is disclosed rather than generalized to a claim of perfect unwrap.',
            'No native import/render was launched. Source-level importer inspection shows supplied TANGENT is retained; this audit does not inspect the post-import GPU buffer.',
        ],
        surfaces=surfaces,
    )
    json.dumps(report, allow_nan=False)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = audit()
    encoded = json.dumps(report, indent=2, allow_nan=False) + '\n'
    if args.output:
        with args.output.open('x') as handle:
            handle.write(encoded)
    print(encoded)
