#!/usr/bin/env python3
"""CPU numeric estimates, NOT a render or a retouched screenshot.

Applies Godot 4.6.3 AgX/allenwp equations to documented irradiance summaries.
Inputs remain unchanged. See the JSON scope and source URLs for limitations.
"""
from pathlib import Path
import hashlib
import json
import math
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / 'docs/verification/eight-hour/material-lighting'
source = AUDIT / 'mainhall-directional-irradiance-audit.json'
report = json.loads(source.read_text())
INSET = np.array([[.544814746488245,.373787398372697,.0813978551390581],
                  [.140416948464053,.754137554567394,.105445496968552],
                  [.0888104196149096,.178871756420858,.732317823964232]])
OUTSET = np.array([[1.96488741169489,-.855988495690215,-.108898916004672],
                   [-.299313364904742,1.32639796461980,-.0270845997150571],
                   [-.164352742528393,-.238183969428088,1.40253671195648]])
WHITE = 16.29
CONTRAST = 1.05
EXPOSURES = [1.12, 2.2, 3.2, 4.48]


def agx(rgb, exposure, contrast=CONTRAST):
    """Float64 transcription; GPU float/half rounding is not reproduced."""
    x = (np.maximum(np.asarray(rgb), 0.0) * exposure) @ INSET.T
    crossover = .18
    shoulder_max = 1 - crossover
    toe_a = (1/crossover-1)*crossover**contrast
    slope = contrast*crossover**(contrast-1)*toe_a/(crossover**contrast+toe_a)**2
    w = (WHITE-crossover)**2/shoulder_max*slope
    d = x-crossover
    shoulder = slope*d*(1+d/w)/(1+slope*d/shoulder_max)+crossover
    toe = x**contrast/(x**contrast+toe_a)
    return np.minimum(1, np.where(x < crossover, toe, shoulder)) @ OUTSET.T


def srgb(rgb):
    rgb = np.clip(np.asarray(rgb), 0, 1)
    return np.where(rgb < .0031308, 12.92*rgb, 1.055*rgb**(1/2.4)-.055)


def linear(hex_color):
    rgb = np.array([int(hex_color[i:i+2], 16) for i in (0,2,4)])/255
    return np.where(rgb < .04045, rgb/12.92, ((rgb+.055)/1.055)**2.4)


def summarize(rgb):
    return [{'exposure':e, 'ev_delta_from_1_12':math.log2(e/1.12),
             'post_agx_linear_rgb':agx(rgb,e).tolist(),
             'post_agx_srgb_8bit_estimate':(srgb(agx(rgb,e))*255).tolist()}
            for e in EXPOSURES]


reference = agx([.18,.5,2],1.7,1.25)
native_reference = np.array([.42578125,.625,.8984375])
reference_error = float(np.max(np.abs(reference-native_reference)))
assert reference_error < .0005
plaster = linear('e4e3de')
basin = linear('83b4c7')
rows = {}
for name, group in report['interior_orientation_groups'].items():
    pigment = basin if name == 'basin_floor_upward' else plaster
    irradiance = np.array(group['rgb_area_weighted_mean'])
    outgoing = irradiance*pigment
    rows[name] = {'assumed_linear_albedo':pigment.tolist(),
                  'area_mean_irradiance':irradiance.tolist(),
                  'ideal_diffuse_outgoing_rgb_before_direct_specular_ao':outgoing.tolist(),
                  'tone_map_of_mean_not_mean_of_tonemapped_pixels':summarize(outgoing)}

# This neutral reference is a bound/context, not a measured point in the room.
unoccluded = (report['unoccluded_horizontal_white_lambert_sun_reference'] +
              report['sky_upper_horizontal_mean_luminance_reference'])
sky_report = json.loads((AUDIT/'formal-sky-native-comparison.json').read_text())
sky_peak = next(r for r in sky_report['rows'] if r['mode']=='physical-energy-matched-fog-off')['audit']['finite_max']
result = {
    'pass': True,
    'source_irradiance_report_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'source_exr_sha256':report['source_exr_sha256'],
    'source_urls':[
        'https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/shaders/effects/tonemap.glsl',
        'https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/storage/environment_storage.cpp',
        'https://github.com/godotengine/godot/blob/4.6.3-stable/scene/resources/environment.cpp'],
    'agx_contrast':CONTRAST, 'agx_white':WHITE,
    'native_reference':{'input_rgb':[.18,.5,2], 'exposure':1.7, 'contrast':1.25,
                        'actual_post_agx_linear_rgb':native_reference.tolist(),
                        'cpu_float64_linear_rgb':reference.tolist(),
                        'max_abs_error':reference_error,
                        'evidence':'docs/audit/source_capture_colors/native-validation.json'},
    'groups':rows,
    'neutral_unoccluded_horizontal_diffuse_reference':{
        'sum_of_sun_and_sky_luminance_not_actual_rgb_or_visible_receiver':unoccluded,
        'hypothetical_plaster_linear_rgb':(unoccluded*plaster).tolist(),
        'predictions':summarize(unoccluded*plaster)},
    'neutral_curve_examples':[{'input_linear':v,'predictions':summarize([v]*3)}
                              for v in [.005,.02,.05,.1,.2,.5,1.,2.,3.74166822433472]],
    'headroom':[{'exposure':e, 'neutral_input_at_agx_white':WHITE/e,
                 'measured_128x64_sky_max_channel_times_exposure':sky_peak*e,
                 'coarse_sky_channel_bound_below_agx_white':sky_peak*e<WHITE}
                for e in EXPOSURES],
    'scope':[
        'Numerical estimate only, not a native image or alteration of any screenshot.',
        'Tone-mapping an area-mean irradiance is not the mean of tone-mapped pixels.',
        'Ideal Lambert diffuse uses authored flat pigment and no division by pi: Godot lightmap output is already the diffuse lighting multiplier.',
        'Normal maps, texture variation, live direct/fill lights, occlusion, specular, fog and screen effects are absent.',
        'The coarse native sky panorama can miss the solar disk; a component maximum is not a full-scene HDR distribution.',
        'A neutral-white clipping threshold does not prove absence of gamut/outset clipping on colored highlights.',
        'Increasing exposure changes display response only; it cannot supply missing bounce or remove the blue-to-red illumination ratio.',
        'No production resource, bake, sky, water algorithm or running comparison input was changed.']}
(AUDIT/'formal-exposure-estimate.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'pass':True,'native_reference_max_abs_error':reference_error,
                  'ceiling':rows['ceiling_downward']['tone_map_of_mean_not_mean_of_tonemapped_pixels'],
                  'soffit':rows['arch_soffit_downward']['tone_map_of_mean_not_mean_of_tonemapped_pixels'],
                  'headroom':result['headroom']},indent=2))
