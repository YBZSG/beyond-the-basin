shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
// Glasswell-only baseline opaque receiver. No aging, caustics, ALPHA or displacement.
// Mirrors use the existing source camera marker; ordinary camera excludes it.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform bool use_textures = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float normal_strength = 1.0;
uniform float base_roughness = 1.0;
uniform float base_metallic = 0.0;
uniform float base_specular = 0.5;
uniform vec4 emission_tint : source_color = vec4(0.0);
uniform float emission_energy = 0.0;
varying vec3 receiver_world;
void vertex(){UV = UV * uv1_scale.xy + uv1_offset.xy;receiver_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if((CAMERA_VISIBLE_LAYERS & 524288u)!=0u && receiver_world.y<.318)discard;
 vec3 albedo=vec3(1.0);vec3 orm=vec3(1.0);
 if(use_textures){vec2 uv=UV;albedo=texture(albedo_tex,uv).rgb;orm=texture(orm_tex,uv).rgb;NORMAL_MAP=texture(normal_tex,uv).rgb;NORMAL_MAP_DEPTH=normal_strength;}
 ALBEDO=albedo*base_tint.rgb;ROUGHNESS=orm.g*base_roughness;METALLIC=orm.b*base_metallic;SPECULAR=base_specular;AO=orm.r;AO_LIGHT_AFFECT=0.0;
 EMISSION=emission_tint.rgb*emission_energy;
}
