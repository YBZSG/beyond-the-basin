// Geometry-bound optical contract, mirrored by glasswell_water_optics.gd and
// author_contract.gd. Shared water/default materials never include this file.
uniform vec2 glasswell_origin_xz=vec2(0.0);
uniform vec4 glasswell_pool_rect=vec4(-15.0,-20.0,15.0,20.0);
uniform float glasswell_floor_y=0.12;
uniform float glasswell_glass_bottom_y=0.02;
uniform float glasswell_module=2.5;
uniform float glasswell_cap_width=0.065;
uniform vec4 glasswell_step_a=vec4(-1.6,19.4,1.6,20.0);
uniform vec4 glasswell_step_b=vec4(-1.6,-20.0,1.6,-19.4);
uniform float glasswell_step_top_y=0.26;
float glasswell_box_hit(vec3 o,vec3 d,vec3 low,vec3 high){
 float entry=-1e8;float leave=1e8;
 for(int axis=0;axis<3;axis++){
  if(abs(d[axis])<1e-7){if(o[axis]<low[axis]||o[axis]>high[axis])return 1e8;}
  else{float a=(low[axis]-o[axis])/d[axis];float b=(high[axis]-o[axis])/d[axis];entry=max(entry,min(a,b));leave=min(leave,max(a,b));}
 }
 return leave>=max(entry,0.0)?max(entry,0.0):1e8;
}
// Returned kind:0 glass,1 real step,2 pool side,3 opaque bronze compression cap.
vec2 glasswell_first_boundary(vec3 world_o,vec3 d){
 vec3 o=world_o-vec3(glasswell_origin_xz.x,0.0,glasswell_origin_xz.y);
 float t=max(0.0,(o.y-glasswell_floor_y)/max(-d.y,1e-7));float kind=0.0;
 vec4 boxes[2]=vec4[2](glasswell_step_a,glasswell_step_b);
 for(int i=0;i<2;i++){
  vec4 r=boxes[i];float candidate=glasswell_box_hit(o,d,vec3(r.x,glasswell_floor_y,r.y),vec3(r.z,glasswell_step_top_y,r.w));
  if(candidate<t){t=candidate;kind=1.0;}
 }
 // The dry coping begins exactly at the finite pool boundary; no off-pool water.
 for(int axis=0;axis<2;axis++){
  int component=axis==0?0:2;float low=glasswell_pool_rect[axis];float high=glasswell_pool_rect[axis+2];
  if(abs(d[component])>1e-7){float edge=d[component]>0.0?high:low;float candidate=(edge-o[component])/d[component];if(candidate>=0.0&&candidate<t){t=candidate;kind=2.0;}}
 }
 if(kind<0.5){vec2 q=(o+d*t).xz-glasswell_pool_rect.xy;vec2 seam=abs(mod(q+glasswell_module*0.5,vec2(glasswell_module))-glasswell_module*0.5);if(min(seam.x,seam.y)<=glasswell_cap_width*0.5+1e-5)kind=3.0;}
 return vec2(t,kind);
}
vec3 glasswell_opaque_world(vec2 uv,mat4 inv_projection,mat4 inv_view,float raw_depth){
 vec4 q=inv_projection*vec4(uv*2.0-1.0,raw_depth,1.0);q/=q.w;return(inv_view*q).xyz;
}
bool glasswell_finite3(vec3 value){return all(lessThanEqual(abs(value),vec3(1e8)));}
float glasswell_safe_path(float value){return value>=0.0 && value<=1e8?clamp(value,0.0,6.0):0.0;}
float glasswell_bound_by_opaque_height(vec3 o,vec3 d,float physical_path,vec3 opaque_point){
 // Both candidate distances are measured ALONG the same refracted direction.
 // The opaque sample supplies a Y-plane, NOT an exact off-axis ray/object hit.
 // This explicitly bounded screen-space approximation is inherited from source
 // refraction sampling; a nearer visible object can only shorten the water path.
 if(!glasswell_finite3(opaque_point))return glasswell_safe_path(physical_path);
 float opaque_path=max(0.0,(o.y-opaque_point.y)/max(-d.y,1e-7));return glasswell_safe_path(min(physical_path,opaque_path));
}
float glasswell_pane_exit_path(vec3 world_hit,vec3 d){
 vec3 hit=world_hit-vec3(glasswell_origin_xz.x,0.0,glasswell_origin_xz.y);
 float t=max(0.0,(hit.y-glasswell_glass_bottom_y)/max(-d.y,1e-7));
 vec2 center=floor((hit.xz-glasswell_pool_rect.xy)/glasswell_module)*glasswell_module+glasswell_pool_rect.xy+glasswell_module*0.5;
 float half_width=(glasswell_module-glasswell_cap_width)*0.5;
 for(int axis=0;axis<2;axis++){int component=axis==0?0:2;if(abs(d[component])>1e-7){float edge=center[axis]+(d[component]>0.0?half_width:-half_width);t=min(t,max(0.0,(edge-hit[component])/d[component]));}}
 return t;
}
