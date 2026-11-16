shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back, depth_draw_opaque;
// Owned selective main-PBR-preserving receiver. No ALPHA, aging, or new light.
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_orm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec3 base_uv_scale = vec3(1.0);
uniform vec3 base_uv_offset = vec3(0.0);
uniform float base_normal_strength = 1.0;
uniform float base_roughness = 1.0;
uniform float base_metallic = 0.0;
uniform float base_specular = 0.5;
uniform float base_ao_light_affect = 0.0;
varying vec3 source_world_position;
bool crossing_inverted_mirror_discard(vec3 point, uint layers) {
 return (layers & 524288u)!=0u && point.y<0.318;
}
void vertex() { UV=UV*base_uv_scale.xy+base_uv_offset.xy; source_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 if (crossing_inverted_mirror_discard(source_world_position,CAMERA_VISIBLE_LAYERS)) discard;
 vec3 orm=texture(base_orm,UV).rgb;
 ALBEDO=texture(base_albedo,UV).rgb*base_tint.rgb;
 NORMAL_MAP=texture(base_normal,UV).rgb;
 NORMAL_MAP_DEPTH=base_normal_strength;
 ROUGHNESS=orm.g*base_roughness;
 METALLIC=base_metallic;
 SPECULAR=base_specular;
 AO=orm.r;
 AO_LIGHT_AFFECT=base_ao_light_affect;
}
