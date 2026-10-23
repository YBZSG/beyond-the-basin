shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx,cull_back;
// Direct tile branch of 66a4543 app/pool-vct/world.ts:227–268.
// Rendering API changes only; original 4 tiles/metre, grout, damp band and relief.
#include "res://shaders/source_water/caustic_receiver.gdshaderinc"
uniform vec4 pigment:source_color=vec4(.388,.537,.616,1.0);
uniform bool two_tone=false;
uniform vec2 source_domain_origin=vec2(0.0);
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if((CAMERA_VISIBLE_LAYERS&524288u)!=0u&&world_position.y<.318)discard;
 vec3 wn=abs(normalize(cross(dFdx(world_position),dFdy(world_position))));
 vec2 tile_uv=wn.y>.6?world_position.xz:(wn.x>.6?world_position.zy:world_position.xy);
 vec2 grid=tile_uv*4.0;vec2 edge=min(fract(grid),1.0-fract(grid));
 vec2 aa=max(fwidth(grid),vec2(.003));
 float grout=1.0-smoothstep(.018-aa.x*.4,.025+aa.x*.6,min(edge.x,edge.y));
 float variation=fract(sin(dot(floor(grid),vec2(12.9898,78.233)))*43758.5453);
 float damp=1.0-.12*exp(-max(world_position.y,0.0)*2.5);
 vec3 color=pigment.rgb*mix(.94+variation*.10,.64,grout)*damp;
 if(two_tone&&wn.y<.6){float upper=smoothstep(1.72,1.76,world_position.y);color=mix(color,vec3(.70,.73,.66)*mix(.94+variation*.10,.64,grout),upper);}
 float stain=sin(tile_uv.x*2.4+sin(tile_uv.y*.8))*sin(tile_uv.y*1.7+tile_uv.x*.6);
 float waterline=exp(-abs(world_position.y-.32)*8.0);
 color=mix(color,color*vec3(.58,.56,.36),waterline*(.08+.04*stain));
 color*=1.0-.025*smoothstep(.2,.9,stain);
 ALBEDO=color;
 float wet_band=exp(-max(world_position.y,0.0)*1.2);
 ROUGHNESS=clamp(mix(.30,.82,grout)-.10*wet_band,.16,1.0)*(.96+variation*.12);
 METALLIC=0.0;SPECULAR=.5;
 vec2 te=min(fract(tile_uv*4.0),1.0-fract(tile_uv*4.0));
 float gh=smoothstep(.0,.05,min(te.x,te.y));
 float crown=sin(te.x*3.14159)*sin(te.y*3.14159);
 float h=-.12*(1.0-gh)+.008*crown;
 float dhx=dFdx(h),dhy=dFdy(h);
 vec3 dpx=dFdx(world_position),dpy=dFdy(world_position);
 vec3 world_normal=normalize(cross(dpx,dpy));
 vec3 r1=cross(dpy,world_normal),r2=cross(world_normal,dpx);
 float det=dot(dpx,r1);
 vec3 delta_world=sign(det)*(r1*dhx+r2*dhy)/max(abs(det),1e-8)*.008;
 NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(-delta_world,0.0)).xyz);
 EMISSION=ALBEDO*source_caustic_irradiance(world_position-vec3(source_domain_origin.x,0.0,source_domain_origin.y),normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz))/3.14159265359;
}
