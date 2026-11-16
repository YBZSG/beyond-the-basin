// Source-derived, NOT a native shader dump. See SOURCE-DERIVATION.md and MIT notice.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0);
uniform sampler2D texture_ambient_occlusion : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ao_texture_channel;
uniform float ao_light_affect : hint_range(0.0, 1.0, 0.01);
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;
varying vec3 hollow_source_world_position;
void vertex() {
 hollow_source_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 UV = UV * uv1_scale.xy + uv1_offset.xy;
}
void fragment() {
 if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && hollow_source_world_position.y < 0.318) discard;
 vec2 base_uv = UV;
 // Fixed-distance lower bound supplements hardware derivatives in the native
 // ray-traced material path, where ordinary screen derivatives may be absent.
 float min_lod = clamp(log2(max((length(CAMERA_POSITION_WORLD-hollow_source_world_position)-3.0)/1.5,1.0)),0.0,6.0);
 vec4 albedo_tex = textureLod(texture_albedo, base_uv, min_lod);
 ALBEDO = albedo.rgb * albedo_tex.rgb;
 float metallic_tex = dot(textureLod(texture_metallic, base_uv, min_lod), metallic_texture_channel);
 METALLIC = metallic_tex * metallic;
 SPECULAR = specular;
 vec4 roughness_texture_channel = vec4(0.0, 1.0, 0.0, 0.0);
 float roughness_tex = dot(textureLod(texture_roughness, base_uv, min_lod), roughness_texture_channel);
 ROUGHNESS = roughness_tex * roughness;
 NORMAL_MAP = textureLod(texture_normal, base_uv, min_lod).rgb;
 NORMAL_MAP_DEPTH = normal_scale;
 AO = dot(textureLod(texture_ambient_occlusion, base_uv, min_lod), ao_texture_channel);
 AO_LIGHT_AFFECT = ao_light_affect;
}
