shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx,cull_back;
// Scene-owned StandardMaterial PBR translation; only mirror-plane semantics differ.
uniform sampler2D base_map:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D normal_map:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D orm_map:hint_default_white,filter_linear_mipmap_anisotropic,repeat_enable;
uniform bool mapped=false;
uniform bool normal_enabled=false;
uniform bool ao_enabled=false;
uniform vec3 uv_scale=vec3(1.0);
uniform vec3 uv_offset=vec3(0.0);
uniform vec4 base_color:source_color=vec4(1.0);
uniform float base_roughness=.5;
uniform float base_metallic=0.0;
uniform float base_specular=.5;
uniform float normal_strength=1.0;
uniform float ao_light_affect=0.0;
uniform float base_clearcoat=0.0;
uniform float base_coat_roughness=.1;
varying vec3 source_world_position;
bool soffit_mirror_discard(vec3 p,uint layers){return (layers & 524288u)!=0u && p.y<.318;}
void vertex(){source_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;UV=UV*uv_scale.xy+uv_offset.xy;}
void fragment(){
 if(soffit_mirror_discard(source_world_position,CAMERA_VISIBLE_LAYERS))discard;
 vec2 uv=UV;
 vec4 orm=mapped?texture(orm_map,uv):vec4(1.0);
 ALBEDO=base_color.rgb*(mapped?texture(base_map,uv).rgb:vec3(1.0));
 ROUGHNESS=base_roughness*(mapped?orm.g:1.0);METALLIC=base_metallic;SPECULAR=base_specular;
 NORMAL_MAP=normal_enabled?texture(normal_map,uv).rgb:vec3(.5,.5,1.0);NORMAL_MAP_DEPTH=normal_enabled?normal_strength:0.0;
 AO=ao_enabled?orm.r:1.0;AO_LIGHT_AFFECT=ao_light_affect;
 CLEARCOAT=base_clearcoat;CLEARCOAT_ROUGHNESS=base_coat_roughness;
}
