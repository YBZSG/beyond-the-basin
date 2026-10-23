#!/usr/bin/env python3
"""Author a dimensioned glazed pool-ceramic PBR atlas; not a scan or photograph.

4K is justified by the 1.8 mm joint and 0.6 mm eased edge: at 1.6 m repeat they
occupy 4.6 and 1.5 texels, respectively. The 100 mm tile faces are almost flat.
The deterministic large atlas carries 256 subtle manufacturing variations.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/textures/formal_ceramic'
SIZE = 4096
TILES = 16
PITCH = .100
GROUT = .0018
BEVEL = .0006
RELIEF = .00028
SEED = 20261021

def smooth(x):
    x = np.clip(x, 0, 1)
    return x*x*(3-2*x)

def generate():
    DEST.mkdir(parents=True, exist_ok=True)
    # Pixel centres and periodic gradients keep the repeat seam exact.
    rng = np.random.default_rng(SEED)
    a = (np.arange(SIZE, dtype=np.float32)+.5) / (SIZE/TILES)
    ux, uy = np.meshgrid(a % 1.0, a % 1.0)
    tx, ty = np.meshgrid(a.astype(np.int32), a.astype(np.int32))
    edge = np.minimum(np.minimum(ux, 1-ux), np.minimum(uy, 1-uy)) * PITCH
    aa = (TILES*PITCH)/SIZE
    face = smooth((edge-GROUT*.5)/aa + .5)
    bevel = smooth((edge-GROUT*.5)/BEVEL)
    tile_variation = rng.uniform(-1,1,(TILES,TILES)).astype(np.float32)[ty,tx]
    # 8 um crown is visible only through a broad reflected highlight. No
    # random per-pixel bumps, rounded cobbles, chipped edges or painted dirt.
    crown = (np.sin(ux*np.pi)*np.sin(uy*np.pi))**2
    height = RELIEF*bevel + .000008*crown
    grad_y, grad_x = np.gradient(height, aa, aa)
    normal = np.stack((-grad_x, -grad_y, np.ones_like(height)), axis=2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    normal_bytes = np.rint(np.clip(normal*.5+.5,0,1)*255).astype(np.uint8)
    # Albedo stores achromatic glaze modulation. Pigment is separately
    # art-directed in Godot. Joint value is not baked occlusion or lighting.
    face_value = .92 + tile_variation*.010 + (crown-.5)*.003
    albedo = np.repeat((face_value*face + .76*(1-face))[...,None],3,axis=2)
    # R: perceptual roughness reference, G: small manufacturing variation,
    # B: linear coverage mask. None is AO; all are linear scalar channels.
    rough = (.42+tile_variation*.015)*face + .82*(1-face)
    surface = np.stack((rough,tile_variation*.5+.5,face),axis=2)
    files = {}
    for name,data in [('pool_ceramic_albedo_4k.png',np.rint(albedo*255).astype(np.uint8)),
                      ('pool_ceramic_normal_gl_4k.png',normal_bytes),
                      ('pool_ceramic_surface_4k.png',np.rint(surface*255).astype(np.uint8))]:
        path=DEST/name
        Image.fromarray(data,'RGB').save(path,optimize=True)
        files[name]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
    report={'provenance':'Original deterministic analytic PBR material; not a captured scan, not a downloaded photograph.',
            'generator':'tools/materials/build_formal_ceramic.py','seed':SEED,'size':[SIZE,SIZE],
            'tiles_per_axis':TILES,'repeat_metres':TILES*PITCH,'tile_pitch_metres':PITCH,
            'joint_width_metres':GROUT,'edge_ease_metres':BEVEL,'joint_relief_metres':RELIEF,
            'tile_crown_metres':.000008,'joint_coverage':float((1-face).mean()),
            'flat_face_normal_xy_rms':float(np.sqrt((normal[face>.999,:2]**2).mean())),
            'channels':{'albedo':'sRGB neutral colour modulation','normal':'OpenGL tangent normal; +Y',
                        'surface':'linear RGB: roughness reference / per-tile variation / face coverage'},
            'files':files}
    (DEST/'material_manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    generate()
