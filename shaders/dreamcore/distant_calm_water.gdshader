shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// EXPANSION ONLY: noninteractive distant calm-water representation, NOT another
// shallow-water solver. Border vertices sample the original published height
// textures so the shared 96 m domain boundary has identical geometric height.
#include "res://shaders/source_water/shared_waves.gdshaderinc"
uniform vec2 domain_origin = vec2(0.0);
uniform vec4 calm_color : source_color = vec4(0.29,0.48,0.47,0.52);
uniform sampler2D mirrorSampler : filter_linear, repeat_disable;
uniform mat4 textureMatrix;
uniform float reflectionReady = 0.0;
uniform float reflectionOn = 1.0;
uniform float reflectionSize = 768.0;
varying vec4 mirrorCoord;
varying vec3 worldPos;
void vertex() {
    vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    vec2 relative = p.xz-domain_origin;
    float outside = max(abs(relative.x),abs(relative.y))-48.0;
    float seam = 1.0-smoothstep(0.0,8.0,max(0.0,outside));
    VERTEX.y += poolHeightSmooth(relative)*seam;
    worldPos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    mirrorCoord = textureMatrix * vec4(worldPos,1.0);
}
void fragment() {
    vec3 viewDir=normalize(CAMERA_POSITION_WORLD-worldPos);
    float fresnel=.075+.925*pow(1.0-clamp(viewDir.y,0.0,1.0),5.0);
    vec2 border=vec2(1.5/max(reflectionSize,1.0));
    vec2 uv=clamp(mirrorCoord.xy/max(mirrorCoord.w,.001),border,vec2(1.0)-border);
    vec3 reflection=texture(mirrorSampler,uv).rgb;
    float mixAmount=fresnel*reflectionOn*reflectionReady;
    ALBEDO=mix(calm_color.rgb,reflection,mixAmount);
    ALPHA=mix(calm_color.a,1.0,mixAmount);
}
