shader_type spatial;
#define POOLCORE_RT
render_mode diffuse_burley,specular_schlick_ggx,cull_back;
#include "res://shaders/source_water/caustic_receiver.gdshaderinc"
uniform vec4 pigment : source_color=vec4(.79,.81,.77,1.0);
uniform float roughness_value=.84;
uniform float metallic_value=0.0;
uniform float specular_value=.5;
uniform vec3 light_emission : source_color=vec3(0.0);
uniform float light_energy=0.0;
uniform vec2 source_domain_origin=vec2(0.0);
varying vec3 world_position;
varying vec3 geometric_normal;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;geometric_normal=normalize(transpose(inverse(mat3(MODEL_MATRIX)))*NORMAL);}
void fragment(){
 if((CAMERA_VISIBLE_LAYERS & 524288u)!=0u&&world_position.y<.318)discard;
 ALBEDO=pigment.rgb;ROUGHNESS=roughness_value;METALLIC=metallic_value;SPECULAR=specular_value;
 EMISSION=light_emission*light_energy+ALBEDO*source_caustic_irradiance(world_position-vec3(source_domain_origin.x,0.0,source_domain_origin.y),normalize(geometric_normal))/3.14159265359;
}
