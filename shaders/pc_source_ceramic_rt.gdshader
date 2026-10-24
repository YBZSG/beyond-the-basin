shader_type spatial;
#define POOLCORE_RT
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// RT variant: ray-hit stages have no screen derivatives.
// Original analytic PBR atlas, not a photographed scan. Preserve the original
// room's 250 mm tile pitch: 16 tiles in a 4 m repeat, with 4.5 mm mortar joints.
uniform sampler2D scan_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D glaze_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 pigment : source_color = vec4(0.388,0.537,0.616,1.0);
uniform vec4 grout_pigment : source_color = vec4(0.52,0.60,0.61,1.0);
uniform vec4 upper_pigment : source_color = vec4(0.78,0.80,0.75,1.0);
uniform bool two_tone = false;
uniform vec2 source_domain_origin = vec2(0.0);
#include "res://shaders/source_water/caustic_receiver.gdshaderinc"
varying vec3 world_position;
varying vec3 geometric_world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    geometric_world_normal = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
}

void fragment() {
    if ((CAMERA_VISIBLE_LAYERS & 524288u)!=0u && world_position.y<0.318) discard;
    vec3 n = normalize(geometric_world_normal);
    vec3 axis = abs(n);
    // Source rooms use planar ceramic. Project in world metres so imported
    // UV seams and different mesh sizes do not change the apparent tile size.
    vec3 tangent = axis.y>0.6 ? vec3(1,0,0) : (axis.x>0.6 ? vec3(0,0,1) : vec3(1,0,0));
    vec3 bitangent = axis.y>0.6 ? vec3(0,0,1) : vec3(0,1,0);
    vec2 metres = vec2(dot(world_position,tangent),dot(world_position,bitangent));
    vec2 uv = metres / 4.0;
    vec3 surface = texture(scan_roughness,uv).rgb;
    float face = surface.b;
    float grout = 1.0-face;
    float batch = surface.g*2.0-1.0;
    vec3 color_map = texture(scan_albedo,uv).rgb;
    vec3 modulation = clamp(color_map / vec3(mix(0.53824,0.82757,face)),vec3(0.965),vec3(1.035));
    float upper = two_tone ? (1.0-step(0.6,axis.y))*smoothstep(1.72,1.76,world_position.y) : 0.0;
    vec3 ceramic = mix(pigment.rgb,upper_pigment.rgb,upper)*modulation;
    vec4 micro = texture(glaze_detail,metres/0.5);
    ceramic *= 1.0+(micro.a-0.5)*0.025;

    // Capillary damp is restricted to the actual .32 m waterline. Broad
    // stationary variation changes the dry/wet boundary, not every tile.
    float broad = 0.5 + 0.25*sin(dot(world_position.xz,vec2(0.83,0.37)))
                      + 0.20*sin(dot(world_position.xz,vec2(-0.29,1.13))+1.4);
    float wet = 1.0-smoothstep(0.31,0.40+0.11*broad,world_position.y);
    float water_mark = exp(-abs(world_position.y-0.335)*38.0)*(1.0-axis.y);
    ceramic *= 1.0-0.035*wet-0.025*water_mark;
    vec3 mortar = grout_pigment.rgb*(1.0-0.16*wet-0.04*water_mark);
    ALBEDO = mix(mortar,ceramic,face);

    vec2 xy = texture(scan_normal,uv).rg*2.0-1.0;
    // Quarter-scale decoding of the authored 6 um glaze height variation.
    // Keep the atlas brick edges independently raised; suppress only glaze noise.
    float bevel_normal = smoothstep(0.025,0.14,length(xy));
    xy *= mix(0.08,1.0,bevel_normal);
    xy += (micro.rg*2.0-1.0)*0.02*face*(1.0-0.6*wet);
    float footprint = max(0.001, distance(CAMERA_POSITION_WORLD, world_position) / 600.0);
    float detail = 1.0-smoothstep(0.025,0.15,footprint);
    vec3 perturbation = (tangent*xy.x+bitangent*xy.y)*detail;
    perturbation -= n*dot(n,perturbation);
    vec3 mapped = normalize(n+perturbation);
    NORMAL = normalize((VIEW_MATRIX*vec4(mapped,0.0)).xyz);

    // Tiles, porous mortar and thin water film retain distinct BRDFs.
    float glaze = 0.055 + batch*0.003 + (micro.b-0.5)*0.008 - wet*0.01;
    float rough = mix(glaze,0.81-wet*0.12,grout);
    // Filter subpixel glaze with the ray distance footprint.
    float variance = 0.000006 * (1.0-detail);
    ROUGHNESS = clamp(pow(pow(rough,4.0)+variance,0.25),0.04,0.92);
    METALLIC = 0.0;
    // F0 for water is about .0204, lower than a dry ceramic glaze (.04).
    SPECULAR = sqrt(mix(0.25,0.12733,wet))*mix(0.72,1.0,face);
    CLEARCOAT = 0.22*face*(1.0-0.4*wet);
    CLEARCOAT_ROUGHNESS = 0.08;
    EMISSION = vec3(0.0);
    if (causticGain>0.0) {
        EMISSION=ALBEDO*source_caustic_irradiance(world_position-vec3(source_domain_origin.x,0.0,source_domain_origin.y),n)/3.14159265359;
    }
}
