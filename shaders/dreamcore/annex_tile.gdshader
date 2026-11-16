shader_type spatial;
uniform vec4 base_color : source_color = vec4(.87,.91,.86,1.0);
uniform float tile_size = 1.2;
uniform float grout_width = .008;
uniform float surface_roughness = .28;
varying vec3 p;
varying vec3 world_normal;
void vertex(){ p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz); }
void fragment(){
 vec3 n=abs(normalize(world_normal)); vec2 q=p.xz;
 if(n.x>n.y&&n.x>n.z){q=p.zy;} else if(n.z>n.y){q=p.xy;}
 vec2 t=abs(fract(q/tile_size)-.5)*2.;
 float line=smoothstep(1.-grout_width*2.,1.-grout_width,max(t.x,t.y));
 float grain=fract(sin(dot(floor(q*150.),vec2(12.9898,78.233)))*43758.5453);
 ALBEDO=base_color.rgb*(.985+.025*grain)*(1.-line*.17);
 ROUGHNESS=surface_roughness+line*.22; SPECULAR=.45;
}
