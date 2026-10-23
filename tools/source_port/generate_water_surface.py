"""Mechanical API translation of original WATER_FRAGMENT; formulas retain provenance.
Run from project root. This generates a Godot shader, not an approximation image.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=(root/'source_provenance/beyond-the-basin-66a4543/app/pool-vct/water-optics.ts').read_text()
fragment=s.split('export const WATER_FRAGMENT=WATER_WAVES+/* glsl */`',1)[1].split('`;',1)[0]
fragment=fragment[fragment.index('float foamField'):]
fragment=fragment.replace('void main(){','void fragment(){')
fragment=fragment.replace('texture2D(', 'texture(')
fragment=fragment.replace('vec2 p=worldPosition.xz;', 'vec2 p=worldPosition.xz-domain_origin;\n  vec3 eye=CAMERA_POSITION_WORLD;')
fragment=fragment.replace('vec2 screenUv=screenPosition.xy/screenPosition.w*.5+.5;', 'vec2 screenUv=SCREEN_UV;')
fragment=fragment.replace('viewMatrix', 'VIEW_MATRIX')
# Native screen/mirror textures have top-left UV, so source view-space Y offsets flip.
fragment=fragment.replace('vec2 offset=bend*', 'vec2 offset=(bend*vec2(1.0,-1.0))*')
fragment=fragment.replace('reflectUv+=N.xz*', 'reflectUv+=(N.xz*vec2(1.0,-1.0))*')
fragment=fragment.replace('-perspectiveDepthToViewZ(texture(sceneDepth,screenUv).r,cameraNear,cameraFar)', 'source_view_depth(screenUv,INV_PROJECTION_MATRIX)')
fragment=fragment.replace('-perspectiveDepthToViewZ(texture(sceneDepth,refractUv).r,cameraNear,cameraFar)', 'source_view_depth(refractUv,INV_PROJECTION_MATRIX)')
fragment=fragment.replace('vec3 reflected=texture(mirrorSampler,reflectUv).rgb;', 'vec3 reflected=texture(mirrorSampler,reflectUv).rgb;\n  reflected=mix(waterColor*.25,reflected,reflectionReady);')
fragment=fragment[:fragment.index('  gl_FragColor=')]+'  ALBEDO=color;\n  ALPHA=alpha;\n}\n'
header='''shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, cull_back;
// Direct port of water-optics.ts WATER_FRAGMENT from Beyond the Basin 66a4543.
// API-only changes: Godot screen/depth inputs, reverse-Z reconstruction, world
// floating-origin offset, output/tone mapping and mirror-capture uniforms.
// Original Snell offset, Schlick, Beer coefficients, foam advection/noise and
// debug branches are retained. Caustics are applied to receiver materials,
// NEVER an unrelated procedural texture multiplied into transmission.
#include "res://shaders/source_water/shared_waves.gdshaderinc"
uniform sampler2D mirrorSampler : filter_linear, repeat_disable;
uniform sampler2D sceneColor : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D sceneDepth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D poolCaustics : filter_linear_mipmap, repeat_disable;
uniform vec2 domain_origin = vec2(0.0);
uniform mat4 textureMatrix;
uniform float reflectionReady = 0.0;
uniform float refractionOn = 1.0;
uniform float reflectionOn = 1.0;
uniform float absorptionOn = 1.0;
uniform float fresnelOn = 1.0;
uniform float waterlineOn = 1.0;
uniform float sceneReady = 1.0;
uniform float debugView = 0.0;
uniform float refractionStrength = 0.7;
uniform float fresnelStrength = 1.0;
uniform float absorptionStrength = 0.7;
uniform float distortionScale = 0.4;
uniform float causticGain = 1.5;
uniform float reflectionSize = 768.0;
uniform float foamOn = 1.0;
uniform float foamStrength = 1.0;
uniform vec3 sunColor : source_color = vec3(0.63137,0.74118,0.76471);
uniform vec3 sunDirection = vec3(-0.27617,0.92057,-0.27617);
uniform vec3 waterColor : source_color = vec3(0.19608,0.48627,0.50196);
varying vec4 mirrorCoord;
varying vec4 worldPosition;
void vertex(){
    vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    VERTEX.y+=poolHeightSmooth(wp.xz-domain_origin);
    worldPosition=MODEL_MATRIX*vec4(VERTEX,1.0);
    mirrorCoord=textureMatrix*worldPosition;
}
float source_view_depth(vec2 uv,mat4 inv_projection){
    float depth=texture(sceneDepth,uv).r;
    vec4 p=inv_projection*vec4(uv*2.0-1.0,depth,1.0);
    return -p.z/p.w;
}
'''
(root/'shaders/source_water_surface.gdshader').write_text(header+fragment)
print('Generated source_water_surface.gdshader from original WATER_FRAGMENT')
