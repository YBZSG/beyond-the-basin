"""Canonical metric face-height math for the new reference wing only.

UVs here are the actual exported/runtime UV1, in metres. PNG row zero stores
runtime V near zero; the Blender helper accounts for glTF's V inversion.
The hash is integer-only and intentionally repeats every eight tiles, matching
the offline normal/albedo/ORM atlas. No random noise enters face normals.
"""
from __future__ import annotations
import numpy as np

PITCH = 0.1
TILES = 8
REPEAT = PITCH * TILES
SIZE = 2048
SEED = 20261024
GROUT = 0.0018
BEVEL = 0.0006
RELIEF = 0.00028
TILT_DEGREES = 0.35
TILT_SLOPE = float(np.tan(np.deg2rad(TILT_DEGREES)))
CROWN = 0.00005
REF5_CROWN = 0.00030
REF5_CROWN_RADIUS = 0.040
FACE_ROUGHNESS = 0.075
DRY_FACE_ROUGHNESS = 0.26
ROUGHNESS_VARIATION = 0.004
GROUT_ROUGHNESS = 0.82


def srgb_linear_color(hex_color):
    value=np.array([int(hex_color[i:i+2],16)/255 for i in (1,3,5)])
    return np.where(value<=.04045,value/12.92,((value+.055)/1.055)**2.4)


def linear_color_gain(source, target):
    return (srgb_linear_color(target)/srgb_linear_color(source)).tolist()


PALETTES = {
    'ref_tile_pearl': {'face': '#BAC2B6', 'grout': '#879188'},
    'ref_tile_teal': {'face': '#739D96', 'grout': '#657F78'},
    'ref_tile_dark_teal': {'face': '#3F6863', 'grout': '#294842'},
    'ref_tile_pink': {'face': '#C3A6A0', 'grout': '#917B76'},
}
DRY_PALETTES = {'ref_tile_dry':'ref_tile_pearl', 'ref_tile_teal_dry':'ref_tile_teal',
                'ref_tile_pink_dry':'ref_tile_pink', 'ref_tile_dark_teal_dry':'ref_tile_dark_teal'}
SATIN_ROLES = {
    'ref_tile_teal_satin': {'palette':'ref_tile_teal','face_roughness':0.34,'tile_scale':1.5},
    'ref_tile_teal_satin_dry': {'palette':'ref_tile_teal','face_roughness':0.40,'tile_scale':1.5},
    'ref_tile_pink_satin': {'palette':'ref_tile_pink','face_roughness':0.40,'tile_scale':2.0},
    'ref_tile_pink_satin_dry': {'palette':'ref_tile_pink','face_roughness':0.40,'tile_scale':2.0},
    'ref_tile_cyan_satin': {'palette':'ref_tile_teal','face_roughness':0.34,'tile_scale':1.5,
        'face_color_hex':'#63B0A6','grout_color_hex':'#4D8279',
        'face_color_gain':linear_color_gain('#739D96','#63B0A6'),
        'grout_color_gain':linear_color_gain('#657F78','#4D8279')},
    'ref_tile_cyan_satin_dry': {'palette':'ref_tile_teal','face_roughness':0.40,'tile_scale':1.5,
        'face_color_hex':'#63B0A6','grout_color_hex':'#4D8279',
        'face_color_gain':linear_color_gain('#739D96','#63B0A6'),
        'grout_color_gain':linear_color_gain('#657F78','#4D8279')},
}
REF5_ROLES = {
    'ref_tile_pearl_ref5_crown': {'palette':'ref_tile_pearl','face_roughness':0.075,
        'tile_scale':1.0,'face_profile':1,'crown_metres':REF5_CROWN,
        'crown_radius_metres':REF5_CROWN_RADIUS,'normal_gl16':'ref5_crown_normal_gl_16.png'},
}


def role_overrides():
    return {**{role:{'palette':palette,'face_roughness':DRY_FACE_ROUGHNESS}
               for role,palette in DRY_PALETTES.items()}, **SATIN_ROLES, **REF5_ROLES}


def metric_role(role):
    """Physical dimensions, including uniformly scaled relief, never UV density."""
    scale = role_overrides().get(role,{}).get('tile_scale',1.0)
    return {'tile_scale':scale,'tile_pitch_metres':PITCH*scale,
            'repeat_metres':REPEAT*scale,'grout_width_metres':GROUT*scale,
            'bevel_width_metres':BEVEL*scale,'joint_relief_metres':RELIEF*scale,
            'crown_metres':role_overrides().get(role,{}).get('crown_metres',CROWN)*scale,
            'face_profile':role_overrides().get(role,{}).get('face_profile',0),
            'crown_radius_metres':role_overrides().get(role,{}).get('crown_radius_metres',0.0)*scale}


def bounded_shape_excursion(strength, samples_per_cell=512):
    """Conservative height bound: dense grid plus an analytic Lipschitz margin.

    For t=u-.5, max|w+t*w'|=1; max|t*w|=0.14310835;
    max|w'|=16/(3*sqrt(3)). These bound each height-gradient component.
    Every point is within half a grid step per axis of a sample. Include
    the exact zero boundary as well. No optimization/render dependency.
    """
    c=(np.arange(samples_per_cell)+.5)/samples_per_cell
    u,v=np.meshgrid(c,c);wu,wv=window(u),window(v)
    low=0.;high=0.
    for cy in range(TILES):
        for cx in range(TILES):
            tx=(float(cell_hash(cx,cy,1))*2-1)*TILT_SLOPE
            ty=(float(cell_hash(cx,cy,2))*2-1)*TILT_SLOPE
            crown=CROWN*(.85+.30*float(cell_hash(cx,cy,3)))
            h=wu*wv*(tx*(u-.5)*PITCH+ty*(v-.5)*PITCH+crown)
            low=min(low,float(h.min()));high=max(high,float(h.max()))
    max_dw=16/(3*np.sqrt(3));max_tw=.64*np.sqrt(.05)
    component_bound=TILT_SLOPE*(1+max_dw*max_tw)+(CROWN*1.15/PITCH)*max_dw
    # ||gradient||<=sqrt(2)*component_bound, nearest distance<=step/sqrt(2).
    margin=component_bound*PITCH/samples_per_cell
    return {'strength':strength,'samples_per_cell_axis':samples_per_cell,
            'sampled_min_metres':low*strength,'sampled_max_metres':high*strength,
            'continuous_bound_margin_metres':margin*strength,
            'absolute_height_bound_metres':(max(-low,high)+margin)*strength,
            'relief_metres':RELIEF,'centre_tilt_limit_degrees':float(np.rad2deg(np.arctan(TILT_SLOPE*strength))),
            'crown_metres':CROWN*strength,
            'method':'512x512 midpoint samples per cell plus conservative analytic gradient/Lipschitz remainder; includes zero boundaries.'}


def cell_hash(x, y, salt=0):
    """32-bit unsigned hash; shader source is emitted from this same module."""
    x = np.asarray(x, dtype=np.int64) % TILES
    y = np.asarray(y, dtype=np.int64) % TILES
    h = (x.astype(np.uint64) + y.astype(np.uint64) * TILES + SEED
         + np.uint64(salt) * np.uint64(374761393)) & np.uint64(0xFFFFFFFF)
    h = ((h ^ (h >> np.uint64(16))) * np.uint64(2246822519)) & np.uint64(0xFFFFFFFF)
    h = ((h ^ (h >> np.uint64(13))) * np.uint64(3266489917)) & np.uint64(0xFFFFFFFF)
    h = h ^ (h >> np.uint64(16))
    return ((h & np.uint64(0xFFFFFF)).astype(np.float32) / np.float32(16777215.0))


def window(u):
    return 16.0 * u * u * (1.0-u) * (1.0-u)


def window_derivative(u):
    return 32.0 * u * (1.0-u) * (1.0-2.0*u)


def face_field(metres_u, metres_v):
    """Return shape height, dH/dU, dH/dV, roughness and pigment variation.

    The centre gradient is a modest cell tilt. A smooth window returns height
    AND derivative to zero at boundaries, independently of actual grout/bevel.
    This avoids an unbounded tilted plane cutting through a shallow joint.
    """
    grid_u = np.asarray(metres_u) / PITCH
    grid_v = np.asarray(metres_v) / PITCH
    cx, cy = np.floor(grid_u).astype(np.int64), np.floor(grid_v).astype(np.int64)
    u, v = grid_u-cx, grid_v-cy
    tx = (cell_hash(cx, cy, 1)*2.0-1.0) * TILT_SLOPE
    ty = (cell_hash(cx, cy, 2)*2.0-1.0) * TILT_SLOPE
    crown = CROWN * (0.85 + 0.30*cell_hash(cx, cy, 3))
    height_plane = tx*(u-0.5)*PITCH + ty*(v-0.5)*PITCH + crown
    wu, wv = window(u), window(v)
    height = wu*wv*height_plane
    du = wv*(window_derivative(u)*height_plane/PITCH + wu*tx)
    dv = wu*(window_derivative(v)*height_plane/PITCH + wv*ty)
    rough = FACE_ROUGHNESS + (cell_hash(cx, cy, 4)*2.0-1.0)*ROUGHNESS_VARIATION
    pigment = 1.0 + (cell_hash(cx, cy, 5)*2.0-1.0)*0.018
    return height, du, dv, rough, pigment


def bevel_field(metres_u, metres_v, texel=REPEAT/SIZE):
    u, v = np.mod(np.asarray(metres_u)/PITCH, 1.0), np.mod(np.asarray(metres_v)/PITCH, 1.0)
    eu, ev = np.minimum(u, 1-u)*PITCH, np.minimum(v, 1-v)*PITCH
    edge = np.minimum(eu, ev)
    t = np.clip((edge-GROUT*0.5)/BEVEL, 0, 1)
    height = RELIEF*t*t*(3-2*t)
    derivative = RELIEF/BEVEL * 6*t*(1-t)
    du = np.where(eu <= ev, derivative*np.where(u < .5, 1., -1.), 0.)
    dv = np.where(eu > ev, derivative*np.where(v < .5, 1., -1.), 0.)
    coverage = np.clip((edge-GROUT*.5)/texel+.5, 0, 1)
    coverage = coverage*coverage*(3-2*coverage)
    return height, du, dv, coverage


def compact_crown_field(x, y, amplitude):
    """Metric C2 crown, identically absent beyond radius40mm."""
    t=np.maximum(1-(x*x+y*y)/(REF5_CROWN_RADIUS*REF5_CROWN_RADIUS),0)
    factor=-6*amplitude*t*t/(REF5_CROWN_RADIUS*REF5_CROWN_RADIUS)
    return amplitude*t*t*t, factor*x, factor*y


def ref5_crown_face_field(metres_u, metres_v):
    """Scoped ref5 profile; all generic baseline material math stays unchanged."""
    gu=np.asarray(metres_u)/PITCH;gv=np.asarray(metres_v)/PITCH
    cx=np.floor(gu).astype(np.int64);cy=np.floor(gv).astype(np.int64)
    u=gu-cx;v=gv-cy
    tx=(cell_hash(cx,cy,1)*2-1)*TILT_SLOPE
    ty=(cell_hash(cx,cy,2)*2-1)*TILT_SLOPE
    amplitude=REF5_CROWN*(.85+.30*cell_hash(cx,cy,3))
    x=(u-.5)*PITCH;y=(v-.5)*PITCH;plane=tx*x+ty*y
    wu,wv=window(u),window(v);du,dv=window_derivative(u),window_derivative(v)
    ch,cu,cv=compact_crown_field(x,y,amplitude)
    return wu*wv*plane+ch,wv*(du*plane/PITCH+wu*tx)+cu,wu*(dv*plane/PITCH+wv*ty)+cv


def shader_include():
    return f'''// Generated by tools/materials/reference_wing/generate.py; edit surface_math.py.
// Exact CPU/Blender/runtime integer hash and differentiable metric face height.
const float REFERENCE_TILE_PITCH = {PITCH:.9f};
const float REFERENCE_REPEAT_METRES = {REPEAT:.9f};
const float REFERENCE_TILT_SLOPE = {TILT_SLOPE:.12f};
const float REFERENCE_CROWN_METRES = {CROWN:.9f};
const float REFERENCE_ROUGHNESS_VARIATION = {ROUGHNESS_VARIATION:.9f};
float reference_hash(ivec2 cell, uint salt) {{
    ivec2 c = ((cell % {TILES}) + {TILES}) % {TILES};
    uint h = uint(c.x) + uint(c.y)*{TILES}u + {SEED}u + salt*374761393u;
    h = (h ^ (h >> 16u))*2246822519u;
    h = (h ^ (h >> 13u))*3266489917u;
    h = h ^ (h >> 16u);
    return float(h & 16777215u)/16777215.0;
}}
float reference_window(float u) {{ return 16.0*u*u*(1.0-u)*(1.0-u); }}
float reference_window_derivative(float u) {{ return 32.0*u*(1.0-u)*(1.0-2.0*u); }}
// XY: dH/dU,dH/dV in metres/metre; Z: physical face height in metres.
vec3 reference_face_field(vec2 metres) {{
    vec2 grid = metres/REFERENCE_TILE_PITCH;
    ivec2 cell = ivec2(floor(grid));
    vec2 uv = fract(grid);
    vec2 tilt = (vec2(reference_hash(cell,1u),reference_hash(cell,2u))*2.0-1.0)*REFERENCE_TILT_SLOPE;
    float crown = REFERENCE_CROWN_METRES*(0.85+0.30*reference_hash(cell,3u));
    float plane = dot(tilt,(uv-vec2(0.5))*REFERENCE_TILE_PITCH)+crown;
    vec2 w = vec2(reference_window(uv.x),reference_window(uv.y));
    vec2 dw = vec2(reference_window_derivative(uv.x),reference_window_derivative(uv.y));
    vec2 gradient = vec2(w.y*(dw.x*plane/REFERENCE_TILE_PITCH+w.x*tilt.x),
                         w.x*(dw.y*plane/REFERENCE_TILE_PITCH+w.y*tilt.y));
    return vec3(gradient,w.x*w.y*plane);
}}
// Profile1 is bound only by ref_tile_pearl_ref5_crown, not global pearl/satin.
const float REFERENCE_REF5_CROWN_METRES = {REF5_CROWN:.9f};
const float REFERENCE_REF5_CROWN_RADIUS = {REF5_CROWN_RADIUS:.9f};
vec3 reference_ref5_crown_face_field(vec2 metres) {{
    vec2 grid = metres/REFERENCE_TILE_PITCH;
    ivec2 cell = ivec2(floor(grid));
    vec2 uv = fract(grid);
    vec2 p = (uv-vec2(0.5))*REFERENCE_TILE_PITCH;
    vec2 tilt = (vec2(reference_hash(cell,1u),reference_hash(cell,2u))*2.0-1.0)*REFERENCE_TILT_SLOPE;
    float amplitude = REFERENCE_REF5_CROWN_METRES*(0.85+0.30*reference_hash(cell,3u));
    float plane = dot(tilt,p);
    vec2 w = vec2(reference_window(uv.x),reference_window(uv.y));
    vec2 dw = vec2(reference_window_derivative(uv.x),reference_window_derivative(uv.y));
    float radius_squared = REFERENCE_REF5_CROWN_RADIUS*REFERENCE_REF5_CROWN_RADIUS;
    float t = max(1.0-dot(p,p)/radius_squared,0.0);
    vec2 gradient = vec2(w.y*(dw.x*plane/REFERENCE_TILE_PITCH+w.x*tilt.x),
                         w.x*(dw.y*plane/REFERENCE_TILE_PITCH+w.y*tilt.y));
    gradient += (-6.0*amplitude*t*t/radius_squared)*p;
    return vec3(gradient,w.x*w.y*plane+amplitude*t*t*t);
}}
'''
