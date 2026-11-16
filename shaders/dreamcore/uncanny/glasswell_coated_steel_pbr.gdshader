shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
uniform sampler2D coat_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coat_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coat_normal_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metres_per_repeat=1.0;
uniform float normal_depth=1.0;
varying vec3 receiver_world;
void vertex(){receiver_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if((CAMERA_VISIBLE_LAYERS & 524288u)!=0u && receiver_world.y<.318)discard;
 vec2 uv=vec2(UV.x,-UV.y)/metres_per_repeat;
 vec3 arm=texture(coat_arm,uv).rgb;
 ALBEDO=texture(coat_albedo,uv).rgb;ROUGHNESS=arm.g;METALLIC=arm.b;AO=arm.r;AO_LIGHT_AFFECT=0.0;SPECULAR=.5;
 vec3 mapped=texture(coat_normal_gl,uv).rgb;mapped.g=1.0-mapped.g;NORMAL_MAP=mapped;NORMAL_MAP_DEPTH=normal_depth;EMISSION=vec3(0.0);
}
