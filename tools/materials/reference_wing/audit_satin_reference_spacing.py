#!/usr/bin/env python3
"""Read-only reference pixel/known-camera comparison; not photogrammetry."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]


def joint_rows(path,box):
    x0,x1,y0,y1=box
    image=np.asarray(Image.open(path).convert('RGB')).astype(float)
    signal=image[y0:y1,x0:x1].mean(axis=(1,2))
    background=np.convolve(np.pad(signal,(5,5),mode='edge'),np.ones(11)/11,mode='valid')
    dip=background-signal
    rows=[i for i in range(1,len(signal)-1) if dip[i]>dip[i-1] and dip[i]>=dip[i+1] and dip[i]>2]
    gaps=np.diff(rows)
    return {'image_size':[image.shape[1],image.shape[0]],'sample_box_xyxy':box,
            'detected_joint_rows':[y0+i for i in rows],'row_gaps_pixels':gaps.tolist(),
            'median_joint_pitch_pixels':float(np.median(gaps)),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def camera(room):
    record=json.loads((ROOT/'assets/models/reference_wing'/f'{room}.geometry.json').read_text())['camera_views'][0]
    eye=np.array(record['position']);forward=np.array(record['target'])-eye;forward/=np.linalg.norm(forward)
    right=np.cross(forward,[0,1,0]);right/=np.linalg.norm(right);up=np.cross(right,forward)
    width,height=record['reference_resolution'];f=height/(2*math.tan(math.radians(record['fov_degrees'])/2))
    def project(point):
        p=np.array(point)-eye;depth=np.dot(p,forward)
        return np.array([width/2+f*np.dot(p,right)/depth,height/2-f*np.dot(p,up)/depth])
    return record,eye,forward,right,up,f,project


def run():
    args=argparse.ArgumentParser();args.add_argument('--reference-root',type=Path,required=True);opt=args.parse_args()
    result={'scope':'Image-space grid-spacing and existing authored camera comparison. Not a real-world dimension measurement or visual acceptance.', 'rooms':{}}
    for room,ref,file,box,scale in [('cyan_corridor',2,'1000074567.jpg',[372,377,75,300],1.5),
                                   ('octagonal_bath',3,'1000074568.jpg',[201,204,203,286],2.0)]:
        sample=joint_rows(opt.reference_root/f'reference-{ref}'/file,box)
        record,eye,forward,right,up,f,project=camera(room)
        if room=='cyan_corridor':
            x_fraction=((box[0]+box[1])/2)/sample['image_size'][0]
            ray=forward+right*((x_fraction-.5)*record['reference_resolution'][0]/f)
            point=eye+ray*((1.8-eye[0])/ray[0])
        else: point=np.array([0.,1.6,-6.5])
        delta=abs(project(point+np.array([0,.1,0]))[1]-project(point)[1])
        normalized=delta*sample['image_size'][0]/record['reference_resolution'][0]
        sample.update({'known_camera':record,'sample_world_point':point.tolist(),
                       'projected_0_10m_vertical_pitch_at_reference_width_pixels':float(normalized),
                       'reference_to_current_pixel_pitch_ratio':sample['median_joint_pitch_pixels']/normalized,
                       'candidate_uniform_scale':scale,'candidate_tile_pitch_metres':.1*scale,
                       'candidate_grout_width_metres':.0018*scale,
                       'candidate_projected_pitch_at_reference_width_pixels':normalized*scale,
                       'candidate_projected_joint_at_reference_width_pixels':normalized*scale*.018,
                       'caution':'Uncalibrated reference lens/framing/aspect and unknown real dimensions. Camera comparison guides a scoped candidate only; joints remain subpixel at distance.'})
        result['rooms'][room]=sample
    print(json.dumps(result,indent=2))


if __name__=='__main__':run()
