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
// BEGIN SOFFIT FLOOR COMPOSITION
// Soffit-only floor receiver; original published32m atlas, no new source/clock.
// No wall projection. Exact original floor UV, edge fade and mip bias.
uniform sampler2D poolCaustics:hint_default_black,filter_linear_mipmap,repeat_disable;
uniform sampler2D poolCausticsWalls:hint_default_black,filter_linear_mipmap,repeat_disable;
uniform vec2 source_domain_origin=vec2(0.0);
uniform float causticGain=0.0;
uniform float pcNearfieldFloorMipBias=1.15;
uniform vec2 reflectedWallExtents=vec2(15.7);
uniform vec2 transmittedWallExtents=vec2(15.7);
bool soffit_floor_atlas_valid(ivec2 atlas_size){
 // Exact original SourceCaustics.QUALITY sizes. Godot invalid-RID fallback
 // is a4x4 white texture even with a black hint, so do not sample it.
 return atlas_size.x==atlas_size.y && (atlas_size.x==256 || atlas_size.x==768 || atlas_size.x==1024 || atlas_size.x==2048);
}
vec3 soffit_floor_irradiance(vec3 world_position,vec3 geometric_world_normal){
 // Native validated intensity slider is0..3. Reject unsafe local publication,
 // including NaN/Inf/float64->float32 overflow, before touching any sampler.
 if(!(causticGain>0.0 && causticGain<=3.0))return vec3(0.0);
 if(!all(lessThanEqual(abs(source_domain_origin),vec2(3.4028233e38))))return vec3(0.0);
 // Actual real pool and submerged bed/step, NOT shared floor's oldY<.25 gate.
 if(geometric_world_normal.y<=.5 || world_position.y>=.32 || world_position.y<.1199)return vec3(0.0);
 if(world_position.x<-37.2 || world_position.x>37.2 || world_position.z<-54.0 || world_position.z>-2.0)return vec3(0.0);
 vec2 causticUv=(world_position.xz-source_domain_origin)/32.0+.5;
 if(!all(greaterThan(causticUv,vec2(0.0))) || !all(lessThan(causticUv,vec2(1.0))))return vec3(0.0);
 if(!soffit_floor_atlas_valid(textureSize(poolCaustics,0)))return vec3(0.0);
 float edgeFade=smoothstep(0.0,.04,min(min(causticUv.x,causticUv.y),min(1.0-causticUv.x,1.0-causticUv.y)));
#ifdef POOLCORE_RT
 return textureLod(poolCaustics,causticUv,pcNearfieldFloorMipBias).rgb*causticGain*max(geometric_world_normal.y,0.0)*edgeFade;
#else
 return texture(poolCaustics,causticUv,pcNearfieldFloorMipBias).rgb*causticGain*max(geometric_world_normal.y,0.0)*edgeFade;
#endif
}
// END SOFFIT FLOOR COMPOSITION
varying vec3 source_floor_geometric_normal;
varying vec3 source_world_position;
bool soffit_mirror_discard(vec3 p,uint layers){return (layers & 524288u)!=0u && p.y<.318;}
void vertex(){source_floor_geometric_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);source_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;UV=UV*uv_scale.xy+uv_offset.xy;}
void fragment(){
 if(soffit_mirror_discard(source_world_position,CAMERA_VISIBLE_LAYERS))discard;
 vec2 uv=UV;
 vec4 orm=mapped?texture(orm_map,uv):vec4(1.0);
 ALBEDO=base_color.rgb*(mapped?texture(base_map,uv).rgb:vec3(1.0));
 ROUGHNESS=base_roughness*(mapped?orm.g:1.0);METALLIC=base_metallic;SPECULAR=base_specular;
 NORMAL_MAP=normal_enabled?texture(normal_map,uv).rgb:vec3(.5,.5,1.0);NORMAL_MAP_DEPTH=normal_enabled?normal_strength:0.0;
 AO=ao_enabled?orm.r:1.0;AO_LIGHT_AFFECT=ao_light_affect;
 EMISSION=ALBEDO*(1.0-METALLIC)*soffit_floor_irradiance(source_world_position,normalize(source_floor_geometric_normal))/3.141592653589793;
 CLEARCOAT=base_clearcoat;CLEARCOAT_ROUGHNESS=base_coat_roughness;
}
