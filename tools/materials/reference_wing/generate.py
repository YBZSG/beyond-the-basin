#!/usr/bin/env python3
"""Generate original metric PBR data and exact shader math; no render or SDK."""
from __future__ import annotations
from pathlib import Path
import hashlib
import json
import struct
import zlib
import numpy as np
from PIL import Image
import surface_math as m

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT/'assets/materials/reference_wing'
SHADERS = ROOT/'shaders/reference_wing'
PNG16_ENCODING = {
    'method':'Adaptive lossless PNG byte-row filters None/Sub/Up/Paeth.',
    'bits_per_sample':16,'rgb_bytes_per_pixel':6,'grayscale_bytes_per_pixel':2,
    'resampling':False,'pixel_transform':False,
}
LOSSLESS_DATA_MAPS = {'bevel_slope_rg_2k.png', 'glaze_orm_2k.png'}
DATA_MAP_IMPORT_POLICY = {
    'maps':sorted(LOSSLESS_DATA_MAPS),'compress_mode':0,
    'reason':'Preserve linear slope, roughness and face-coverage bytes; measured BPTC/ASTC joint errors are additional to PNG8 quantization.',
    'mipmaps':True,'normal_conversion':False,'albedo_policy_unchanged':True,
}


def compression_mode(filename):
    return 0 if filename in LOSSLESS_DATA_MAPS else 2


def png16(path, values):
    """Lossless RGB/grayscale PNG16 with adaptive byte-wise row filters.

    Filtering changes only the encoding. RGB16 stride is SIX bytes, grayscale
    stride TWO. The original uint16 samples and big-endian byte order remain.
    """
    values = np.asarray(values, dtype='>u2')
    height, width = values.shape[:2]
    color = 2 if values.ndim == 3 else 0
    if values.ndim not in (2,3) or (values.ndim==3 and values.shape[2]!=3):
        raise ValueError('Expected grayscale or RGB uint16 samples')
    bpp=6 if color==2 else 2
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data)&0xFFFFFFFF)
    rows=values.view(np.uint8).reshape(height,width*bpp)
    previous=np.zeros(width*bpp,dtype=np.uint8)
    encoded=[];counts={0:0,1:0,2:0,4:0}
    for row in rows:
        left=np.zeros_like(row);left[bpp:]=row[:-bpp]
        upper_left=np.zeros_like(row);upper_left[bpp:]=previous[:-bpp]
        a=left.astype(np.int16);b=previous.astype(np.int16);c=upper_left.astype(np.int16)
        p=a+b-c;pa=np.abs(p-a);pb=np.abs(p-b);pc=np.abs(p-c)
        predictor=np.where((pa<=pb)&(pa<=pc),a,np.where(pb<=pc,b,c)).astype(np.uint8)
        options=[(0,row),(1,row-left),(2,row-previous),(4,row-predictor)]
        kind,data=min(options,key=lambda item:int(np.abs(item[1].view(np.int8).astype(np.int16)).sum()))
        counts[kind]+=1;encoded.append(bytes([kind])+data.tobytes())
        previous=row
    raw=b''.join(encoded)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,16,color,0,0,0))+
                     chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
    return {'row_filters':counts,'bytes':path.stat().st_size,'bits_per_sample':16,'bytes_per_pixel':bpp}


def srgb_hex(value):
    return np.array([int(value[i:i+2],16)/255. for i in (1,3,5)])


def import_settings(path):
    """Explicit data-map policy: preserve RGBA and never normal-correct slopes."""
    resource = 'res://' + str(path.relative_to(ROOT))
    digest = hashlib.md5(resource.encode()).hexdigest()
    mode = compression_mode(path.name)
    suffix = '.ctex' if mode == 0 else '.bptc.ctex'
    imported = f'res://.godot/imported/{path.name}-{digest}{suffix}'
    remap = f'path="{imported}"' if mode == 0 else f'path.bptc="{imported}"'
    metadata = '{"vram_texture": false}' if mode == 0 else '{"imported_formats": ["s3tc_bptc"], "vram_texture": true}'
    (Path(str(path)+'.import')).write_text(f'''[remap]
importer="texture"
type="CompressedTexture2D"
{remap}
metadata={metadata}

[deps]
source_file="{resource}"
dest_files=["{imported}"]

[params]
compress/mode={mode}
compress/high_quality=true
compress/lossy_quality=0.7
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/size_limit=0
detect_3d/compress_to=0
''')


def generate():
    DEST.mkdir(parents=True,exist_ok=True)
    SHADERS.mkdir(parents=True,exist_ok=True)
    coordinates = (np.arange(m.SIZE,dtype=np.float64)+.5)/m.SIZE*m.REPEAT
    u,v = np.meshgrid(coordinates,coordinates)
    shape,du,dv,rough,pigment = m.face_field(u,v)
    relief,bu,bv,face = m.bevel_field(u,v)
    # Runtime linear data, NOT a standard encoded normal. Neutral is exactly
    # byte128. The data imports are lossless; albedo keeps its separate policy.
    slope = np.stack((-bu,-bv,np.ones_like(bu)),axis=-1)
    encoded = np.empty_like(slope,dtype=np.uint8)
    encoded[...,:2] = np.rint(np.clip(128+127*slope[...,:2],0,255)).astype(np.uint8)
    encoded[...,2] = 255
    Image.fromarray(encoded,'RGB').save(DEST/'bevel_slope_rg_2k.png',optimize=True)
    # Exact decoded base-level data plus the same analytic face gradient.
    decoded = (encoded[...,:2].astype(np.float64)-128)/127
    normal = np.dstack((decoded[...,0]-du,decoded[...,1]-dv,np.ones_like(u)))
    normal /= np.linalg.norm(normal,axis=2,keepdims=True)
    png16(DEST/'full_normal_gl_16.png',np.rint(np.clip(normal*.5+.5,0,1)*65535).astype(np.uint16))
    bevel_normal = np.dstack((decoded[...,0],decoded[...,1],np.ones_like(u)))
    bevel_normal /= np.linalg.norm(bevel_normal,axis=2,keepdims=True)
    png16(DEST/'bevel_normal_gl_16.png',np.rint(np.clip(bevel_normal*.5+.5,0,1)*65535).astype(np.uint16))
    height = relief+shape
    height_range = [float(height.min()),float(height.max())]
    png16(DEST/'height_16.png',np.rint((height-height_range[0])/(height_range[1]-height_range[0])*65535).astype(np.uint16))
    # Scoped Blender-only profile normal. Runtime evaluates the same metric
    # height derivative analytically; generic normal/height maps stay baseline.
    _,cdu,cdv=m.ref5_crown_face_field(u,v)
    crown_normal=np.dstack((decoded[...,0]-cdu,decoded[...,1]-cdv,np.ones_like(u)))
    crown_normal/=np.linalg.norm(crown_normal,axis=2,keepdims=True)
    png16(DEST/'ref5_crown_normal_gl_16.png',np.rint(np.clip(crown_normal*.5+.5,0,1)*65535).astype(np.uint16))
    for role,palette in m.PALETTES.items():
        rgb = srgb_hex(palette['face'])[None,None,:]*pigment[...,None]
        rgb = rgb*face[...,None]+srgb_hex(palette['grout'])[None,None,:]*(1-face[...,None])
        Image.fromarray(np.rint(np.clip(rgb,0,1)*255).astype(np.uint8),'RGB').save(DEST/(role+'_albedo_2k.png'),optimize=True)
    orm = np.dstack((.78+.22*face,rough*face+m.GROUT_ROUGHNESS*(1-face),np.zeros_like(face),face))
    Image.fromarray(np.rint(np.clip(orm,0,1)*255).astype(np.uint8),'RGBA').save(DEST/'glaze_orm_2k.png',optimize=True)
    (SHADERS/'reference_glaze_math.gdshaderinc').write_text(m.shader_include())
    manifest = {
        'provenance':'Original deterministic metric PBR authorship; no downloaded scans or rendered lighting.',
        'status':'Initial source-only candidate. No native NVIDIA or visual acceptance.',
        'generator':'tools/materials/reference_wing/generate.py',
        'png16_encoding':PNG16_ENCODING,
        'data_map_import_policy':DATA_MAP_IMPORT_POLICY,
        'scoped_profile_status':'Ref5 crown role approved as bounded CPU-reviewed direction; native visual acceptance pending. Generic pearl and satin profiles unchanged.',
        'cyan_palette_candidate_status':'Explicit cyan-only .15m satin roles reuse teal atlas with linear per-region gains; face#63B0A6 and grout#4D8279. Not applied to existing teal/dark-teal/pink roles. Scoped CPU-reviewed palette direction; native visual acceptance pending.',
        'math_source':'tools/materials/reference_wing/surface_math.py',
        'tile_pitch_metres':m.PITCH,'tiles_per_axis':m.TILES,'repeat_metres':m.REPEAT,'texture_size':m.SIZE,
        'grout_width_metres':m.GROUT,'bevel_width_metres':m.BEVEL,'joint_relief_metres':m.RELIEF,
        'centre_tilt_limit_degrees_per_axis':m.TILT_DEGREES,'crown_metres':m.CROWN,
        'face_roughness':m.FACE_ROUGHNESS,'roughness_variation':m.ROUGHNESS_VARIATION,'grout_roughness':m.GROUT_ROUGHNESS,
        'role_overrides':m.role_overrides(),
        'role_physical_dimensions':{role:m.metric_role(role) for role in [*m.PALETTES,*m.role_overrides()]},
        'metallic':0.0,'dielectric_f0':.04,'clearcoat':0.0,'seed':m.SEED,'palettes':m.PALETTES,
        'height_range_metres':height_range,'grout_coverage':float((1-face).mean()),
        'coordinate_contract':'Runtime UV1 is metres. PNG row0 is runtime V=0. Standard Blender glTF runtime V=1-BlenderV; helper compensates sampling phase and tangent Y.',
        'maps':{
            'albedo':'sRGB RGB, batch pigment and grout only; no baked lighting.',
            'bevel_slope_rg_2k.png':'LINEAR custom data: RG encode tangent normal slopes as byte128+127*slope. Not a standard normal map; no normal import conversion.',
            'glaze_orm_2k.png':'LINEAR RGBA: ambient-only local AO, perceptual roughness, metallic zero, face coverage. Alpha is NOT transparency.',
            'full_normal_gl_16.png':'LINEAR 16-bit RGB standard tangent normal, OpenGL +Y in runtime UV coordinates; exact base-level bevel decoding + analytic face field. Blender preview only.',
            'bevel_normal_gl_16.png':'LINEAR 16-bit RGB standard tangent normal for exact shape-off control; same decoded bevel data, no analytic face. Blender lab only.',
            'height_16.png':'LINEAR 16-bit normalized physical height, range given above. Diagnostic/reference; no runtime displacement.',
            'ref5_crown_normal_gl_16.png':'LINEAR RGB16 Blender-only normal for ref_tile_pearl_ref5_crown. Exact analytic compact crown plus unchanged decoded bevel. Height comes from surface_math.ref5_crown_face_field, NOT generic height_16.png; no runtime texture or mesh displacement.',
        },
        'files':{},
    }
    for path in sorted(DEST.glob('*.png')):
        manifest['files'][path.name]={'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.name.endswith('_2k.png'): import_settings(path)
    (DEST/'material_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'generated':len(manifest['files']),'bytes':sum(f['bytes'] for f in manifest['files'].values()),'height_range_metres':height_range}))


if __name__ == '__main__':
    generate()
