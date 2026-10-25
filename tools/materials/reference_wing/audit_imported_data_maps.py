#!/usr/bin/env python3
"""Measure already-decoded Godot imports against PNG8 and CPU mip references.

Run dump_imported_data_maps.gd first. This script never runs an importer.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from PIL import Image
import surface_math as base

ROOT=Path(__file__).resolve().parents[3]


def compare(actual,expected,mask,used):
    delta=actual.astype(np.int16)-expected.astype(np.int16);d=delta[mask]
    return {'pixels':len(d),'changed_used_channel_fraction':float(np.any(d[:,used]!=0,axis=1).mean()),
            'max_abs_error_rgba_bytes':np.abs(d).max(axis=0).tolist(),
            'mean_abs_error_rgba_bytes':np.abs(d).mean(axis=0).tolist(),
            'minimum_error_rgba_bytes':d.min(axis=0).tolist(),'maximum_error_rgba_bytes':d.max(axis=0).tolist()}


def normal_error(a,b):
    a=np.dstack([a,np.ones(a.shape[:2])]);b=np.dstack([b,np.ones(b.shape[:2])])
    dot=np.sum(a*b,axis=2)/np.linalg.norm(a,axis=2)/np.linalg.norm(b,axis=2)
    return np.rad2deg(np.arccos(np.clip(dot,-1,1)))


def run():
    parser=argparse.ArgumentParser();parser.add_argument('--directory',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    records=[]
    for meta in sorted(args.directory.glob('decode_*.json')):
        for record in json.loads(meta.read_text())['records']:
            if 'decoded_base_rgba' not in record:records.append(record);continue
            h,w=record['height'],record['width'];name=record['name'];is_bevel=name.startswith('bevel')
            expected=np.asarray(Image.open(record['source_path']).convert('RGBA'))
            actual=np.fromfile(args.directory/record['decoded_base_rgba'],np.uint8).reshape(h,w,4)
            yy,xx=np.indices((h,w));edge=np.minimum.reduce([xx%256,255-xx%256,yy%256,255-yy%256])
            interior=edge>=4;used=[0,1] if is_bevel else [0,1,3]
            result={**record,'used_channels':'RG slope; B ignored' if is_bevel else 'R ambient AO, G roughness, A coverage; B metallic ignored/nonmetal forced',
                'source_png_sha256':hashlib.sha256(Path(record['source_path']).read_bytes()).hexdigest(),
                'imported_file_sha256':hashlib.sha256(Path(record['imported_path']).read_bytes()).hexdigest(),
                'stored_format_name':{22:'BPTC_RGBA / BC7',35:'ASTC_4x4'}.get(record['stored_format'],str(record['stored_format'])),
                'base_regions':{label:compare(actual,expected,mask,used) for label,mask in [('neutral_face_interior',interior),('four_texel_joint_bevel_band',~interior),('all',np.ones_like(interior))]}}
            if is_bevel:
                src=(expected[:,:,:2].astype(float)-128)/127
                error=normal_error((actual[:,:,:2].astype(float)-128)/127,src)
                result['additional_codec_normal_angle_error_degrees']={label:{'maximum':float(error[mask].max()),'p99':float(np.percentile(error[mask],99))} for label,mask in [('neutral_face_interior',interior),('joint_bevel',~interior)]}
                if record['codec_requested']=='bptc':
                    coords=(np.arange(base.SIZE)+.5)/base.SIZE*base.REPEAT;u,v=np.meshgrid(coords,coords)
                    _,du,dv,_=base.bevel_field(u,v)
                    quant=normal_error(src,np.stack([-du,-dv],axis=-1))
                    result['original_png8_quantization_vs_analytic_bevel_normal_degrees']={'maximum':float(quant.max()),'joint_p99':float(np.percentile(quant[~interior],99)),'note':'Existing PNG8 quantization is separate from and precedes the additional codec errors above.'}
            source_mips=np.fromfile(args.directory/record['source_rgba_with_cpu_mips'],np.uint8)
            decoded_mips=np.fromfile(args.directory/record['decoded_all_mips_rgba'],np.uint8)
            result['mip_comparisons']=[]
            for level in record['mip_layout']:
                start=level['offset'];size=level['width']*level['height']*4
                a=decoded_mips[start:start+size].reshape(level['height'],level['width'],4)
                b=source_mips[start:start+size].reshape(level['height'],level['width'],4)
                result['mip_comparisons'].append({**level,**compare(a,b,np.ones(a.shape[:2],bool),used)})
            records.append(result)
    report={'scope':'Actual central ctex get_image/decompress on official Godot CPU, no GPU or import run for this audit. Base-level errors are against source PNG8, not unquantized analytic data.',
        'region_definition':'4 base texels from every 256-texel/100mm tile boundary contain joint/bevel; interior starts at pixel centre 1.758 mm from the boundary, beyond the 1.5 mm bevel top.',
        'mip_reference':'Original PNG loaded into Godot Image, converted to RGBA8, generate_mipmaps(); lower-level differences may include import mip construction as well as block codec. Base-level comparison isolates codec loss.',
        'not_causal_evidence_for_cpu_crop':'Cycles previews use PNG data, not these Godot ctex files.',
        'recommendation':'Use lossless compress/mode=0 for only the two new data maps; keep albedo compression and all original maps unchanged. Do not claim an interior base-level normal-bias defect: neutral RG and interior roughness/coverage are exact in the measured BPTC/ASTC imports.',
        'records':records}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    for r in records:
        if 'base_regions' in r:print(r['name'],r['codec_requested'],r['base_regions'],r.get('additional_codec_normal_angle_error_degrees'))


if __name__=='__main__':run()
