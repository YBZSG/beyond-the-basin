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
uniform vec4 oxide_tint : source_color=vec4(.28,.145,.065,1.0);
varying vec3 receiver_world;
void vertex(){UV = UV * uv1_scale.xy + uv1_offset.xy;receiver_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if((CAMERA_VISIBLE_LAYERS & 524288u)!=0u && receiver_world.y<.318)discard;
 vec3 albedo=vec3(1.0);vec3 orm=vec3(1.0);
 if(use_textures){vec2 uv=UV;albedo=texture(albedo_tex,uv).rgb;orm=texture(orm_tex,uv).rgb;NORMAL_MAP=texture(normal_tex,uv).rgb;NORMAL_MAP_DEPTH=normal_strength;}
 ALBEDO=albedo*base_tint.rgb;ROUGHNESS=orm.g*base_roughness;METALLIC=orm.b*base_metallic;SPECULAR=base_specular;AO=orm.r;AO_LIGHT_AFFECT=0.0;
 // Isolated copper-oxide layer; source clean bronze base, not age30 parity.
 vec3 centers[4]=vec3[4](vec3(-15.12,.4,20.0),vec3(-15.0,.4,20.12),vec3(-14.5,.4,20.12),vec3(-14.0,.4,20.12));
 vec3 local=receiver_world-centers[0];float nearest=dot(local,local);
 for(int i=1;i<4;i++){vec3 d=receiver_world-centers[i];float d2=dot(d,d);if(d2<nearest){local=d;nearest=d2;}}
 float radius=length(local.xz);float root=.68*(1.-smoothstep(.001,.004,local.y));
 float head=smoothstep(.010,.0125,local.y);float patch=smoothstep(-.005,.006,-local.x+.35*local.z);
 float head_oxide=.76*head*patch;float side_oxide=.58*(1.-head)*(.55+.45*patch);
 float oxide=1.-(1.-root)*(1.-head_oxide)*(1.-side_oxide);
 float polished=smoothstep(.0147,.0166,radius)*smoothstep(-.003,.002,local.x)*smoothstep(-.004,.002,local.z)*smoothstep(.009,.012,local.y);
 float mask=clamp(oxide*(1.-polished*.96),0.,.82);
 ALBEDO=mix(ALBEDO,oxide_tint.rgb,mask);ROUGHNESS=mix(ROUGHNESS,.82,mask);METALLIC=mix(METALLIC,0.,mask);
 // Native42 intentionally preserves original source normal, no unverified Blender Bump port.
 EMISSION=emission_tint.rgb*emission_energy;
}
