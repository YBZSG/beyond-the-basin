#!/usr/bin/env python3
"""Read-only source-PNG face quantization audit, not GPU texture evidence."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCES = {
    'formal': ('assets/textures/formal_ceramic/pool_ceramic_normal_gl_4k.png',16),
    'art_pass': ('assets/materials/art_pass/textures/tile_normal_gl_2k.png',8),
}


def inspect(path, tiles):
    raw = np.asarray(Image.open(path))[...,:2]
    pitch = raw.shape[0]//tiles
    unique = [set(),set()]
    means, magnitudes = [], []
    for y in range(tiles):
        for x in range(tiles):
            face = raw[y*pitch+8:(y+1)*pitch-8,x*pitch+8:(x+1)*pitch-8]
            for axis in range(2): unique[axis].update(np.unique(face[...,axis]).tolist())
            normal_xy = face.astype(np.float64)/255*2-1
            means.append(normal_xy.mean(axis=(0,1)).tolist())
            magnitudes.append(float(np.linalg.norm(normal_xy,axis=2).mean()))
    means = np.asarray(means)
    raw_length = float(np.mean(magnitudes))
    return {
        'path':str(path.relative_to(ROOT)),
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'source_size':list(raw.shape[:2]),'tiles_per_axis':tiles,
        'excluded_margin_texels':8,'interior_xy_unique_bytes':[sorted(v) for v in unique],
        'mean_raw_xy_length':raw_length,
        'after_existing_quiet_face_gain_0_08':raw_length*.08,
        'quiet_face_angle_degrees_approx':float(np.rad2deg(np.arcsin(raw_length*.08))),
        'per_tile_mean_xy_min':means.min(axis=0).tolist(),
        'per_tile_mean_xy_max':means.max(axis=0).tolist(),
        'per_tile_mean_xy_std':means.std(axis=0).tolist(),
    }


if __name__ == '__main__':
    report={'scope':'Source PNG bytes and existing shader 0.08 gain only. Not imported GPU formats, shader execution or visual evidence.',
            'measurements':{name:inspect(ROOT/path,tiles) for name,(path,tiles) in SOURCES.items()}}
    print(json.dumps(report,indent=2))
