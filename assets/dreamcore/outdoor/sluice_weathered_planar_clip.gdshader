shader_type spatial;
render_mode diffuse_burley, cull_disabled;
uniform vec4 base_color : source_color = vec4(.55,.54,.49,1.0);
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap, repeat_enable;
uniform float surface_kind = 0.0;
uniform float wetness = 0.0;
varying vec3 world_p;
varying vec3 world_n;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise3(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){world_p=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;world_n=normalize((MODEL_MATRIX*vec4(NORMAL,0.)).xyz);}
void fragment(){
 if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && world_p.y < 0.318) { discard; }
 vec3 p=world_p;float broad=noise3(p*.17),fine=noise3(p*11.0);float grain=noise3(p*75.0);
 vec2 uv=abs(world_n.y)>.7?p.xz:(abs(world_n.x)>.7?p.zy:p.xy);
 float value=.71+.31*broad+.14*fine+.08*grain;
 if(surface_kind<.5){vec2 grid=abs(fract(uv/vec2(3.2,2.4))-.5);float seam=smoothstep(.486,.499,max(grid.x,grid.y));float streak=noise3(vec3(p.x*3.0,p.y*.065,p.z*3.0));value*=1.-.17*seam;value*=.79+.3*streak;}
 else if(surface_kind<1.5){value*=.62+.55*noise3(p*2.8);}
 else if(surface_kind<2.5){value*=.75+.25*fine;value=mix(value,1.35,smoothstep(.77,.88,noise3(p*1.4)));}
 else if(surface_kind<3.5){value*=.7+.25*grain;}
 else if(surface_kind<4.5){vec2 grid=abs(fract(uv/.65)-.5);float seam=smoothstep(.47,.495,max(grid.x,grid.y));value*=1.-.43*seam;value*=.88+.18*hash(vec3(floor(uv/.65),0.));}
 float dx=noise3((p+vec3(.025,0,0))*11.)-fine;float dz=noise3((p+vec3(0,0,.025))*11.)-fine;NORMAL_MAP=normalize(vec3(dx*.45,dz*.45,1.))*.5+.5;ALBEDO=texture(albedo_map,UV).rgb*base_color.rgb*(.88+.12*value);NORMAL_MAP=texture(normal_map,UV).rgb;if(surface_kind>.5 && surface_kind<1.5){NORMAL_MAP.xy=mix(vec2(.5),NORMAL_MAP.xy,.18);}ROUGHNESS=texture(roughness_map,(surface_kind>2.5 && surface_kind<3.5 ? UV2 : UV)).r;SPECULAR=.38;METALLIC=surface_kind>4.5?.5:0.;
}
