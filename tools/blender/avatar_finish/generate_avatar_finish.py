#!/usr/bin/env python3
"""Original analytic cloth maps, no image source, Blender, renderer, or downloads.

Pixel samples use tangent-space +U right, +V up. PNG rows are top to bottom.
All maps are DATA, never sRGB. The normal derivative is measured in metres.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/textures/avatar_finish'
AUDIT = Path(__file__).resolve().parent / 'audit'
PROFILES = {
    'shirt_plain': dict(tile_m=0.0224, threads=32, relief_m=0.000009,
                        roughness=0.865, roughness_variation=0.024, kind='plain'),
    'trousers_twill': dict(tile_m=0.0256, threads=32, relief_m=0.000010,
                          roughness=0.905, roughness_variation=0.022, kind='twill'),
}


def field(u, v, profile):
    """Analytic periodic yarn crowns and restrained interlacing, in metres."""
    n = profile['threads']
    tau = 2 * np.pi
    # All frequencies are integral on the tile. Slight deterministic variations
    # avoid a perfectly machined grid; there are no nonperiodic noise samples.
    ux = u * n + 0.018 * np.sin(tau * 3 * v) + 0.012 * np.sin(tau * (u + v))
    vy = v * n + 0.016 * np.sin(tau * 2 * u) + 0.010 * np.sin(tau * (u - v))
    warp = (0.5 + 0.5 * np.cos(tau * ux)) ** 2
    weft = (0.5 + 0.5 * np.cos(tau * vy)) ** 2
    if profile['kind'] == 'plain':
        interlace = np.cos(np.pi * n * u) * np.cos(np.pi * n * v)
    else:
        interlace = np.sin(tau * n * (u - v) / 4)
    # Yarn visibility swaps at intersections without a sharp step or a mask edge.
    a = warp * (0.78 + 0.22 * interlace)
    b = weft * (0.78 - 0.22 * interlace)
    crowns = 0.5 * (a + b + np.sqrt((a - b) ** 2 + 0.035 ** 2))
    fine_twist = 0.025 * (warp * np.sin(tau * (5*n*u + n*v))
                        + weft * np.sin(tau * (n*u - 5*n*v)))
    variation = (0.5 * np.sin(tau * (3*u + 2*v))
               + 0.3 * np.cos(tau * (5*u - 3*v))
               + 0.2 * np.sin(tau * (7*u + 5*v)))
    height = profile['relief_m'] * (crowns * (1 + 0.06 * variation) + fine_twist)
    # Absolute perceptual roughness, not color. Keep broad dry dielectric lobes.
    rough = profile['roughness'] + profile['roughness_variation'] * (
        0.65 * (0.45 - crowns) + 0.25 * variation + 0.1 * interlace)
    return height, np.clip(rough, 0, 1)


def normals(height, tile_m):
    texel_m = tile_m / height.shape[0]
    du = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2*texel_m)
    # Image row goes DOWN, tangent +V goes UP. This minus is intentional.
    dv = -(np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2*texel_m)
    vectors = np.dstack((-du, -dv, np.ones_like(height)))
    return vectors / np.linalg.norm(vectors, axis=-1, keepdims=True)


def write_import(path, is_normal, normal_path=''):
    """Explicit deterministic import settings. Godot fills its cache on import."""
    rel = path.relative_to(ROOT).as_posix()
    digest = hashlib.md5(('res://' + rel).encode()).hexdigest()
    ctex = f'res://.godot/imported/{path.name}-{digest}.ctex'
    # Lossless data avoids subtle 8-bit near-neutral normal block artifacts.
    # 4 x 512 maps are a bounded candidate budget; mipmaps are always enabled.
    config = f'''[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\npath="{ctex}"\nmetadata={{\n"vram_texture": false\n}}\n\n[deps]\n\nsource_file="res://{rel}"\ndest_files=["{ctex}"]\n\n[params]\n\ncompress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map={1 if is_normal else 2}\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=1\nroughness/src_normal=""\nprocess/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n'''
    path.with_suffix(path.suffix + '.import').write_text(config)


def generate(size=512):
    if size < 512 or size % 32:
        raise ValueError('Use at least 512 pixels, divisible by 32 threads.')
    OUT.mkdir(parents=True, exist_ok=True); AUDIT.mkdir(parents=True, exist_ok=True)
    u, v = np.meshgrid((np.arange(size)+0.5)/size, 1-(np.arange(size)+0.5)/size)
    result = dict(generator='generate_avatar_finish.py', original=True,
                  image_inputs=[], randomness='none; deterministic analytic periodic field',
                  color_space='linear data; no sRGB/gamma conversion',
                  normal_convention='OpenGL tangent +X,+Y,+Z; PNG rows downward',
                  size=[size,size], profiles={})
    for name,p in PROFILES.items():
        h,r = field(u,v,p); n = normals(h,p['tile_m'])
        nrgb = np.round(np.clip(0.5+0.5*n,0,1)*255).astype(np.uint8)
        r8 = np.round(r*255).astype(np.uint8)
        npth = OUT/f'{name}_normal.png'; rpth = OUT/f'{name}_roughness.png'
        Image.fromarray(nrgb,'RGB').save(npth, optimize=True)
        Image.fromarray(r8,'L').save(rpth, optimize=True)
        write_import(npth,True);write_import(rpth,False)
        # Editable/auditable height source is not loaded by the game.
        Image.fromarray(np.round((h-h.min())/(h.max()-h.min())*65535).astype(np.uint16)).save(AUDIT/f'{name}_height16.png')
        endpoints = np.linspace(0,1,257)
        hu0,ru0 = field(np.zeros_like(endpoints),endpoints,p)
        hu1,ru1 = field(np.ones_like(endpoints),endpoints,p)
        hv0,rv0 = field(endpoints,np.zeros_like(endpoints),p)
        hv1,rv1 = field(endpoints,np.ones_like(endpoints),p)
        angles = np.degrees(np.arccos(n[:,:,2]))
        result['profiles'][name] = dict(**p, yarn_pitch_m=p['tile_m']/p['threads'],
            height_range_m=[float(h.min()),float(h.max())],
            normal_tilt_degrees=dict(mean=float(angles.mean()),p95=float(np.percentile(angles,95)),max=float(angles.max())),
            encoded_roughness_range=[int(r8.min())/255,int(r8.max())/255],
            encoded_roughness_mean=float(r8.mean()/255),
            analytical_height_seam_error_m=float(max(abs(hu0-hu1).max(),abs(hv0-hv1).max())),
            analytical_roughness_seam_error=float(max(abs(ru0-ru1).max(),abs(rv0-rv1).max())),
            files={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [npth,rpth]})
    result['estimated_uncompressed_rgba8_with_mips_bytes'] = int(4*size*size*4*4/3)
    (OUT/'avatar_finish_candidate_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
    return result

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--size',type=int,default=512)
    generate(parser.parse_args().size)
