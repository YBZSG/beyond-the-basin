#!/usr/bin/env python3
"""Read-only geometric/normal-domain diagnosis, not a render or BRDF integrator."""
from pathlib import Path
import json, hashlib
import numpy as np
import surface_math as base
import crown_trial_math as crown

ROOT=Path(__file__).resolve().parents[3]
unit=lambda x:np.asarray(x)/np.linalg.norm(x,axis=-1,keepdims=True)
degrees=lambda x:np.rad2deg(x)


def run():
    source=ROOT/'output/reference_wing/stair/stair_planar_interior_trial_checks.json'
    camera=json.loads(source.read_text())['camera']
    eye=np.array(camera['from']);point=np.array(camera['toward']);view=unit(eye-point)
    lens=np.array(camera['actual_lens_emitting_face_center'])
    normal=np.array([-1.,0,0])
    half=lambda s:unit(view+unit(np.asarray(s)-point))
    center=half(lens)
    along=unit(half(lens+[0,0,1e-5])-half(lens-[0,0,1e-5]))
    across=unit(np.cross(center,along))
    forward=unit(point-eye);right=unit(np.cross(forward,[0,1,0]));up=np.cross(right,forward)
    focal=320/np.tan(np.deg2rad(camera['fov_degrees']/2))
    def project(s):
        virtual=np.array(s).copy();virtual[...,0]=5.8-virtual[...,0];q=virtual-eye
        return np.stack((320+focal*(q@right)/(q@forward),320-focal*(q@up)/(q@forward)),axis=-1)
    def angle(a,b):return float(degrees(np.arccos(np.clip(unit(a)@unit(b),-1,1))))
    def coordinates(h):return degrees(np.arctan2(h@along,h@center)),degrees(np.arctan2(h@across,h@center))
    emitters=[];boundaries=[]
    # These are actual builder / saved-crop source values, confirmed by the
    # architecture worker. Both sources remained enabled in all CPU crops.
    for name,s,width in [('emissive_lens',lens,.098),('cpu_area',lens+[0,-.025,0],.120)]:
        a=s+[-width/2,0,0];b=s+[width/2,0,0]
        ha,hb=half(a),half(b);_,xa=coordinates(ha);_,xb=coordinates(hb)
        pixel=project(np.array([a,b]));virtual=np.array([a,b]);virtual[:,0]=5.8-virtual[:,0]
        longpx=project(np.array([s+[0,0,-.765],s+[0,0,.765]]));axis=unit(longpx[1]-longpx[0]);perp=np.array([-axis[1],axis[0]])
        edge=[]
        for sign in [-1,1]:
            points=np.tile(s,(2049,1));points[:,0]+=sign*width/2;points[:,2]+=np.linspace(-.765,.765,2049)
            hlong,hcross=coordinates(half(points));order=np.argsort(hlong);edge.append((hlong[order],hcross[order]))
        boundaries.append(edge)
        emitters.append({'name':name,'center_metres':s.tolist(),'width_metres':width,'length_metres':1.53,
            'width_angle_at_wall_degrees':angle(a-point,b-point),
            'width_angle_of_virtual_source_at_camera_degrees':angle(virtual[0]-eye,virtual[1]-eye),
            'half_vector_transverse_width_degrees':float(abs(xb-xa)),
            'half_vector_transverse_interval_at_source_midpoint_degrees':[float(min(xa,xb)),float(max(xa,xb))],
            'ideal_reflected_width_px_perpendicular_to_strip':float(abs((pixel[1]-pixel[0])@perp)),
            'ideal_reflected_length_px':float(np.linalg.norm(longpx[1]-longpx[0]))})
    alpha=base.FACE_ROUGHNESS**2
    hwhm=float(degrees(np.arcsin(np.sqrt((np.sqrt(2)-1)*alpha*alpha/(1-alpha*alpha)))))
    def outside_envelope(h):
        long,cross=coordinates(h);inside=np.zeros(long.shape,dtype=bool)
        for pair in boundaries:
            a=np.interp(long,*pair[0]);b=np.interp(long,*pair[1]);low=np.minimum(a,b);high=np.maximum(a,b)
            inside|=(cross>=low-hwhm)&(cross<=high+hwhm)
        return ~inside
    local=(np.arange(256)+.5)/256*base.PITCH;u,v=np.meshgrid(local,local)
    interior=(u>.004)&(u<.096)&(v>.004)&(v<.096)
    fields=[]
    for mode,crown_height,gain in [('production',.00005,1),('rejected_gain_1_8',.00005,1.8),('full_cell_crown_120um',.00012,1),('full_cell_crown_150um',.00015,1),('full_cell_crown_180um',.00018,1),('qa_localized_crown_300um_r40mm',.0003,1)]:
        transverse=[];outside=[];minimum=0.;maximum=0.;maximum_slope=0.
        for cy in range(8):
            for cx in range(8):
                U=u+cx*.1;V=v+cy*.1
                if mode.startswith('qa_'):h,du,dv=crown.face_field(U,V)
                else:
                    h,du,dv,_,_=base.face_field(U,V)
                    amplitude=(crown_height-base.CROWN)*(.85+.30*base.cell_hash(cx,cy,3))
                    lu=u/base.PITCH;lv=v/base.PITCH
                    h=(h+amplitude*base.window(lu)*base.window(lv))*gain
                    du=(du+amplitude*base.window_derivative(lu)*base.window(lv)/base.PITCH)*gain
                    dv=(dv+amplitude*base.window(lu)*base.window_derivative(lv)/base.PITCH)*gain
                # Actual right-wall metre UV: runtime U=-Godot Z, V=1-Godot Y.
                normals=unit(np.stack((-np.ones_like(du),dv,du),axis=-1))
                _,cross=coordinates(normals)
                transverse.append(cross[interior]);outside.append(outside_envelope(normals)[interior])
                minimum=min(minimum,float(h.min()));maximum=max(maximum,float(h.max()))
                maximum_slope=max(maximum_slope,float(np.hypot(du,dv).max()))
        angles=np.concatenate(transverse);out=np.concatenate(outside)
        fields.append({'case':mode,'nominal_crown_metres':crown_height*gain,
            'sampled_min_height_metres':minimum,'sampled_max_height_metres':maximum,
            'transverse_normal_angle_std_degrees':float(angles.std()),
            'transverse_normal_angle_range_degrees':[float(angles.min()),float(angles.max())],
            'outside_combined_lens_area_plus_ggx_hwhm_envelope_fraction':float(out.mean()),
            'maximum_normal_deflection_degrees':float(degrees(np.arctan(maximum_slope)))})
    centres=[]
    cx,cy=np.meshgrid(np.arange(8),np.arange(8));hx=base.cell_hash(cx,cy,1)*2-1;hy=base.cell_hash(cx,cy,2)*2-1
    for limit in [.15,.35,.63]:
        tilt=np.tan(np.deg2rad(limit));n=unit(np.stack((-np.ones_like(hx),hy*tilt,hx*tilt),axis=-1));_,a=coordinates(n)
        adjacent=np.r_[np.abs(a-np.roll(a,1,axis=0)).flat,np.abs(a-np.roll(a,1,axis=1)).flat]
        centres.append({'tilt_limit_degrees_per_axis':limit,'transverse_angle_std_degrees':float(a.std()),
            'transverse_angle_range_degrees':[float(a.min()),float(a.max())],
            'adjacent_difference_median_p90_max_degrees':np.percentile(adjacent,[50,90,100]).tolist()})
    result={'scope':'Geometric source footprints and exact analytic normal fields only. No image rendering or visual acceptance.',
        'camera_contract':str(source.relative_to(ROOT)),'camera_contract_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'eye_metres':eye.tolist(),'wall_point_metres':point.tolist(),
        'eye_to_wall_metres':float(np.linalg.norm(eye-point)),
        'wall_to_lens_metres':float(np.linalg.norm(lens-point)),
        'view_angle_from_normal_degrees':angle(view,normal),'emitters':emitters,
        'ggx_assumed_alpha':alpha,'ggx_normal_distribution_hwhm_degrees':hwhm,
        'normal_envelope_caveat':'GGX alpha=roughness squared, isotropic NDF only. Expanding the exact curved half-vector source boundaries by NDF HWHM is a diagnostic angular envelope, not a BRDF convolution, intensity threshold, full renderer or prediction of dark pixels. Includes both enabled lens and 22.45% wider Area; Fresnel, masking, tails, all other fixtures and multiple bounces are not modelled.',
        'field_sampling':'256x256 points over each of all 64 periodic cells; distributions exclude a 4 mm cell-edge band, not genuine bevel. Basis follows actual right-wall exported UVs.',
        'cell_centre_tilt_statistics':centres,'field_statistics':fields,
        'production_materials_changed':False,'native_validation':False}
    path=ROOT/'docs/reference_wing/material_evidence/reflection-cone-diagnosis.json'
    path.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':run()
