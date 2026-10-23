// Direct WATER_WAVES port, source commit 66a4543602d9e774db07c2da12ce1d40d522532c.
uniform sampler2D poolSurface : filter_linear, repeat_disable;
uniform sampler2D poolDepth : filter_nearest, repeat_disable;
uniform sampler2D poolDetail : filter_linear, repeat_disable;
uniform float poolCell = 0.125;
uniform float detailCell = 0.0625;
uniform float poolTime = 0.0;
uniform float waveHeight = 1.0;
uniform float rippleGain = 1.0;
uniform float normalBoost = 1.0;
uniform float microStrength = 0.65;
uniform float simulationOn = 1.0;
uniform float ripplesOn = 1.0;
uniform float microOn = 1.0;
uniform float causticsScale = 1.0;
uniform float causticsSpeed = 0.6;
uniform vec2 microOrigin = vec2(0.0);
float poolRestDepth(vec2 p){return texture(poolDepth,(p+48.0)/96.0).r;}
// poolDepth is nearest-filtered: the solver needs a hard land mask. Sampling
// it directly quantises anything derived from depth to the 0.125m cell grid,
// which is what tiled the waterline into screen-space blocks hugging columns
// and step edges. Bilinear it by hand for shading use only.
float poolRestDepthSmooth(vec2 p){
  vec2 g=(p+48.0)/poolCell-.5;
  vec2 i=floor(g),f=fract(g);
  float inv=poolCell/96.0;
  float d00=texture(poolDepth,(i+vec2(.5,.5))*inv).r;
  float d10=texture(poolDepth,(i+vec2(1.5,.5))*inv).r;
  float d01=texture(poolDepth,(i+vec2(.5,1.5))*inv).r;
  float d11=texture(poolDepth,(i+vec2(1.5,1.5))*inv).r;
  return mix(mix(d00,d10,f.x),mix(d01,d11,f.x),f.y);
}
float poolHeight(vec2 p){return texture(poolSurface,(p+48.0)/96.0).r;}
float detailHeight(vec2 p){
  if(ripplesOn<.5)return 0.0;
  vec2 uv=(p+24.0)/48.0;
  float edge=min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y));
  return texture(poolDetail,clamp(uv,vec2(0.0),vec2(1.0))).r*smoothstep(0.0,.045,edge)*rippleGain*ripplesOn;
}
float poolSurfaceHeight(vec2 p){return poolHeight(p)*waveHeight*simulationOn+detailHeight(p);}
vec2 simulationSlope(vec2 p){
  float e=poolCell,h=poolHeight(p);
  float w=poolRestDepth(p-vec2(e,0))>0.0?poolHeight(p-vec2(e,0)):h;
  float r=poolRestDepth(p+vec2(e,0))>0.0?poolHeight(p+vec2(e,0)):h;
  float b=poolRestDepth(p-vec2(0,e))>0.0?poolHeight(p-vec2(0,e)):h;
  float n=poolRestDepth(p+vec2(0,e))>0.0?poolHeight(p+vec2(0,e)):h;
  return vec2(r-w,n-b)/(2.0*e)*waveHeight*normalBoost*simulationOn;
}
vec2 detailSlope(vec2 p){
  float e=detailCell;
  return vec2(detailHeight(p+vec2(e,0))-detailHeight(p-vec2(e,0)),detailHeight(p+vec2(0,e))-detailHeight(p-vec2(0,e)))/(2.0*e);
}
vec2 microSlope(vec2 p,float footprint){
  if(microOn<.5)return vec2(0.0);
  p+=microOrigin;float t=poolTime*causticsSpeed;
  // Two unrelated scales/directions, centimetres per second, millimetre slopes.
  // Analytic band limiting suppresses subpixel frequencies without TAA history.
  vec2 k1=vec2(8.1,5.7)*causticsScale,k2=vec2(-20.3,27.1)*causticsScale;
  float largeFade=1.0-smoothstep(.7,2.4,footprint*length(k1));
  float smallFade=1.0-smoothstep(.7,2.4,footprint*length(k2));
  float phase=sin(dot(p,vec2(.47,-.31))+t*.04)*.35;
  vec2 s=k1*cos(dot(p,k1)+t*.18+phase)*.00020*largeFade;
  s+=k2*cos(dot(p,k2)-t*.11)*.000045*smallFade;
  return s*microStrength*microOn;
}
vec3 poolNormal(vec2 p){return normalize(vec3(-simulationSlope(p)-detailSlope(p)-microSlope(p,.09),1.0).xzy);}
float poolHeightSmooth(vec2 p){
  float h=poolHeight(p)*4.0;
  h+=(poolHeight(p+vec2(.22,0))+poolHeight(p-vec2(.22,0))+poolHeight(p+vec2(0,.22))+poolHeight(p-vec2(0,.22)))*2.0;
  h+=poolHeight(p+vec2(.16,.16))+poolHeight(p-vec2(.16,.16))+poolHeight(p+vec2(-.16,.16))+poolHeight(p+vec2(.16,-.16));
  float d=(detailHeight(p+vec2(.12,0))+detailHeight(p-vec2(.12,0))+detailHeight(p+vec2(0,.12))+detailHeight(p-vec2(0,.12)))*.25;
  return h/16.0*waveHeight*simulationOn+d;
}

// PC_NEARFIELD_BEGIN
// Experimental optical relief only. Default off preserves all source functions.
uniform float pcNearfieldOn = 0.0;
uniform float pcNearfieldStrength = 1.0;
#include "res://shaders/pc_nearfield_lab/height_modes.gdshaderinc"
bool pcNearfieldSurfaceActive(vec2 p){
  return pcNearfieldOn>.5 && abs(p.x)<8.0 && abs(p.y)<6.0;
}
// PC_NEARFIELD_END
