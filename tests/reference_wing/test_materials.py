#!/usr/bin/env python3
"""CPU/source tests only. No GPU, engine SDK or visual acceptance claim."""
from pathlib import Path
import hashlib
import json
import re
import struct
import sys
import unittest
import zlib
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/materials/reference_wing'))
import surface_math as m
MAPS = ROOT/'assets/materials/reference_wing'
LEGACY_HASHES = {
    'art_pass_pbr':'76649704af544660a2abca2ed9b2129d0191f041d21fb7bd750462031015dd80',
    'art_pass_pbr_rt':'b3fe6f02a7b4198d47d33b32113de161dc468a34871dc284376abeb347a3bbe1',
    'ceramic_world':'8cd39f4de7d09e725faa784016fff2e0cedee35e7cb5f803191e2630be393a1c',
    'ceramic_world_rt':'9c97cbb07aa689c828f15c007cc90fdb1f32fc3f191f13cf1089d0155df39625',
    'pc_source_ceramic':'cea8eab6770511e8974828fb9685cfea8e11c248e1f13f2cbfa80ffbd9e08ba6',
    'pc_source_ceramic_rt':'57d4770ea255c45c5a64e8d0ae6cfe0eaa1dcee6f45cda84e296405e4df3fbec',
}


def read_png16(path):
    data = path.read_bytes(); pos=8; parts=[]; width=height=0
    while pos < len(data):
        length=struct.unpack('>I',data[pos:pos+4])[0]; kind=data[pos+4:pos+8]
        payload=data[pos+8:pos+8+length]; pos+=length+12
        if kind==b'IHDR':
            width,height,depth,color,*_=struct.unpack('>IIBBBBB',payload)
            assert depth==16 and color in (0,2)
        if kind==b'IDAT': parts.append(payload)
    channels=3 if color==2 else 1;bpp=channels*2
    raw=np.frombuffer(zlib.decompress(b''.join(parts)),dtype=np.uint8).reshape(height,1+width*bpp)
    decoded=np.empty((height,width*bpp),dtype=np.uint8)
    previous=np.zeros(width*bpp,dtype=np.uint8)
    for y,packed in enumerate(raw):
        kind=int(packed[0]);row=packed[1:]
        if kind==0: result=row.copy()
        elif kind==1: result=(np.cumsum(row.reshape(width,bpp),axis=0,dtype=np.uint32)&255).astype(np.uint8).reshape(-1)
        elif kind==2: result=row+previous
        elif kind==4:
            # Independent sequential Paeth inverse; no encoder predictor reused.
            result=bytearray(row);up=previous.tobytes()
            for x in range(len(result)):
                a=result[x-bpp] if x>=bpp else 0;b=up[x];c=up[x-bpp] if x>=bpp else 0
                p=a+b-c;pa=abs(p-a);pb=abs(p-b);pc=abs(p-c)
                predicted=a if pa<=pb and pa<=pc else (b if pb<=pc else c)
                result[x]=(result[x]+predicted)&255
            result=np.frombuffer(result,dtype=np.uint8)
        else: raise AssertionError('Unsupported filter '+str(kind))
        decoded[y]=result;previous=decoded[y]
    return decoded.copy().view('>u2').reshape((height,width,3) if color==2 else (height,width))


def read_our_rgb16(path):
    values=read_png16(path)
    assert values.ndim==3 and values.shape[2]==3
    return values


class ReferenceMaterialContracts(unittest.TestCase):
    def test_legacy_six_shaders_untouched(self):
        for name,expected in LEGACY_HASHES.items():
            self.assertEqual(hashlib.sha256((ROOT/'shaders'/(name+'.gdshader')).read_bytes()).hexdigest(),expected,name)

    def test_generated_math_and_raster_rt_single_source(self):
        shaders=ROOT/'shaders/reference_wing'
        self.assertEqual((shaders/'reference_glaze_math.gdshaderinc').read_text(),m.shader_include())
        raster=(shaders/'reference_glaze.gdshader').read_text()
        rt=(shaders/'reference_glaze_rt.gdshader').read_text().replace('#define POOLCORE_RT\n','')
        self.assertEqual(raster,rt)
        common=(shaders/'reference_glaze_surface.gdshaderinc').read_text()
        self.assertNotRegex(common,r'\b(?:dFdx|dFdy|fwidth)\s*\(')
        self.assertNotRegex(common,r'\bALPHA\s*=')
        self.assertIn('CLEARCOAT = 0.0;',common)
        self.assertIn('METALLIC = 0.0;',common)
        self.assertNotIn('mix(0.08',common)
        self.assertIn('reference_face_field(material_metres)',common)
        self.assertIn('vec2 atlas_uv = material_metres/REFERENCE_REPEAT_METRES;',common)
        self.assertIn('UV/max(tile_scale,0.001)',common)
        self.assertIn('uniform float tile_scale : hint_range(0.5, 3.0) = 1.0;',common)

    def test_metric_hash_periodicity_and_negative_uv(self):
        self.assertEqual(m.PITCH,.1); self.assertEqual(m.REPEAT,.8)
        x,y=np.meshgrid(np.arange(-9,10),np.arange(-9,10))
        for salt in range(1,6):
            values=m.cell_hash(x,y,salt)
            self.assertTrue(np.isfinite(values).all())
            self.assertGreaterEqual(float(values.min()),0); self.assertLessEqual(float(values.max()),1)
            np.testing.assert_array_equal(values,m.cell_hash(x+8,y-16,salt))
        a=m.face_field(np.array([-.035,.025,.173]),np.array([.017,-.062,.138]))
        b=m.face_field(np.array([-.035,.025,.173])+.8,np.array([.017,-.062,.138])-.8)
        for aa,bb in zip(a,b): np.testing.assert_allclose(aa,bb,atol=2e-8)

    def test_height_gradient_finite_and_independent_from_bevel(self):
        u=np.linspace(.001,.799,317);v=np.mod(u*.713+.021,.8)
        h,du,dv,rough,_=m.face_field(u,v); epsilon=1e-7
        finite_du=(m.face_field(u+epsilon,v)[0]-m.face_field(u-epsilon,v)[0])/(2*epsilon)
        finite_dv=(m.face_field(u,v+epsilon)[0]-m.face_field(u,v-epsilon)[0])/(2*epsilon)
        np.testing.assert_allclose(du,finite_du,atol=1e-8)
        np.testing.assert_allclose(dv,finite_dv,atol=1e-8)
        self.assertTrue(np.isfinite(np.stack((h,du,dv,rough))).all())
        self.assertGreaterEqual(float(rough.min()),.071-1e-7)
        self.assertLessEqual(float(rough.max()),.079+1e-7)
        for cell in range(8):
            centre=m.face_field((cell+.5)*.1,.05)
            self.assertAlmostEqual(float(centre[1]),float((m.cell_hash(cell,0,1)*2-1)*m.TILT_SLOPE),places=8)
        for edge in [0.,.1,.2,.8]:
            h,du,dv,*_=m.face_field(edge,.037)
            self.assertAlmostEqual(float(h),0.,places=10)
            self.assertAlmostEqual(float(du),0.,places=10)
            self.assertAlmostEqual(float(dv),0.,places=10)

    def test_pbr_maps_and_explicit_linear_coverage_import(self):
        manifest=json.loads((MAPS/'material_manifest.json').read_text())
        for name,spec in manifest['files'].items():
            self.assertEqual(hashlib.sha256((MAPS/name).read_bytes()).hexdigest(),spec['sha256'])
        orm=np.asarray(Image.open(MAPS/'glaze_orm_2k.png'))
        self.assertEqual(orm.shape,(2048,2048,4))
        self.assertFalse(orm[...,2].any())
        face=orm[...,3].astype(float)/255
        self.assertTrue((face==0).any() and (face==1).any())
        self.assertAlmostEqual(float((1-face).mean()),.0343702129289216,places=8)
        average=face.mean()
        while len(face)>1:
            face=face.reshape(len(face)//2,2,len(face)//2,2).mean(axis=(1,3))
            self.assertAlmostEqual(float(face.mean()),float(average),places=12)
        for path in MAPS.glob('*_2k.png.import'):
            config=path.read_text()
            name=path.name.removesuffix('.import')
            expected_mode=0 if name in {'bevel_slope_rg_2k.png','glaze_orm_2k.png'} else 2
            self.assertIn(f'compress/mode={expected_mode}',config)
            self.assertIn('compress/normal_map=2',config)
            self.assertIn('roughness/mode=0',config)
            self.assertIn('process/fix_alpha_border=false',config)
        self.assertEqual(len(list(MAPS.glob('*_2k.png.import'))),len(m.PALETTES)+2)

    def test_high_precision_reference_normal_matches_runtime_base_math(self):
        normal=read_our_rgb16(MAPS/'full_normal_gl_16.png').astype(np.float64)/65535*2-1
        bevel=np.asarray(Image.open(MAPS/'bevel_slope_rg_2k.png'))[...,:2]
        for y,x in [(128,128),(256,384),(513,768),(1021,1023),(1890,2013),(0,100)]:
            u,v=(x+.5)/m.SIZE*m.REPEAT,(y+.5)/m.SIZE*m.REPEAT
            _,du,dv,*_=m.face_field(u,v)
            slope=(bevel[y,x].astype(float)-128)/127-np.array([du,dv])
            expected=np.array([slope[0],slope[1],1.]);expected/=np.linalg.norm(expected)
            np.testing.assert_allclose(normal[y,x],expected,atol=2/65535)
        self.assertLess(float(np.max(np.abs(np.linalg.norm(normal,axis=2)-1))),4/65535)

    def test_shape_off_preserves_bevel_and_dry_palette_contract(self):
        normal=read_our_rgb16(MAPS/'bevel_normal_gl_16.png').astype(np.float64)/65535*2-1
        bevel=np.asarray(Image.open(MAPS/'bevel_slope_rg_2k.png'))[...,:2].astype(float)
        expected=np.dstack(((bevel-128)/127,np.ones(bevel.shape[:2])))
        expected/=np.linalg.norm(expected,axis=2,keepdims=True)
        np.testing.assert_allclose(normal,expected,atol=2/65535)
        manifest=json.loads((MAPS/'material_manifest.json').read_text())
        for role,palette in m.DRY_PALETTES.items():
            self.assertEqual(manifest['role_overrides'][role],{'palette':palette,'face_roughness':m.DRY_FACE_ROUGHNESS})
        source=(ROOT/'scripts/reference_wing/reference_materials.gd').read_text()
        self.assertIn(f'const DRY_FACE_ROUGHNESS := {m.DRY_FACE_ROUGHNESS}',source)

    def test_room_satin_metric_scale_and_slope_chain_rule(self):
        manifest=json.loads((MAPS/'material_manifest.json').read_text())
        self.assertEqual(manifest['role_overrides'],m.role_overrides())
        for role,preset in m.SATIN_ROLES.items():
            scale=preset['tile_scale'];dims=m.metric_role(role)
            self.assertEqual(manifest['role_physical_dimensions'][role],dims)
            self.assertAlmostEqual(dims['tile_pitch_metres'],.20 if 'pink' in role else .15)
            self.assertAlmostEqual(dims['grout_width_metres'],.0036 if 'pink' in role else .0027)
            self.assertGreaterEqual(preset['face_roughness'],.34)
            # H_actual(U,V)=s*H_base(U/s,V/s). Scaling only UV but retaining
            # physical height would incorrectly reduce the normal slope.
            u,v=.037*scale,.068*scale;eps=1e-7
            expected=m.face_field(u/scale,v/scale)
            du=(scale*m.face_field((u+eps)/scale,v/scale)[0]-scale*m.face_field((u-eps)/scale,v/scale)[0])/(2*eps)
            dv=(scale*m.face_field(u/scale,(v+eps)/scale)[0]-scale*m.face_field(u/scale,(v-eps)/scale)[0])/(2*eps)
            np.testing.assert_allclose([du,dv],[expected[1],expected[2]],atol=1e-8)
            # Standard glTF V inversion + PNG row inversion agree for any
            # repeat, including 1.2m (not an integer divisor of glTF's +1).
            blender_v=-.137;repeat=dims['repeat_metres']
            blender_image_v=blender_v/repeat+1-1/repeat
            runtime_atlas_v=(1-blender_v)/repeat
            self.assertAlmostEqual(blender_image_v,1-runtime_atlas_v)
        for role in [*m.PALETTES,*m.DRY_PALETTES]:
            self.assertEqual(m.metric_role(role)['tile_pitch_metres'],.1)

    def test_strong_face_candidate_has_continuous_height_bound(self):
        bounds=m.bounded_shape_excursion(1.8)
        self.assertLess(bounds['absolute_height_bound_metres'],m.RELIEF)
        self.assertAlmostEqual(bounds['crown_metres'],.00009)
        self.assertAlmostEqual(bounds['centre_tilt_limit_degrees'],.6299824477,places=7)
        self.assertGreater(m.bounded_shape_excursion(2.0)['sampled_max_metres'],m.RELIEF)
        self.assertNotIn('"strong_face"',
                         (ROOT/'scripts/reference_wing/reference_materials.gd').read_text())

    def test_scoped_cyan_palette_linear_math_and_isolation(self):
        for role in ['ref_tile_cyan_satin','ref_tile_cyan_satin_dry']:
            preset=m.role_overrides()[role]
            np.testing.assert_allclose(m.srgb_linear_color('#739D96')*preset['face_color_gain'],m.srgb_linear_color('#63B0A6'),atol=1e-12)
            np.testing.assert_allclose(m.srgb_linear_color('#657F78')*preset['grout_color_gain'],m.srgb_linear_color('#4D8279'),atol=1e-12)
            self.assertEqual(preset['palette'],'ref_tile_teal')
            self.assertEqual(preset['tile_scale'],1.5)
            self.assertEqual(preset.get('face_profile',0),0)
        for role,preset in m.role_overrides().items():
            if not role.startswith('ref_tile_cyan_'):
                self.assertNotIn('face_color_gain',preset);self.assertNotIn('grout_color_gain',preset)


if __name__=='__main__': unittest.main(verbosity=2)
