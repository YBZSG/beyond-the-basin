// All slopes use world XZ metres. Height, reflection, refraction and photon
// transport share the same macro + meso field; only micro detail is band-limited.
export const WATER_WAVES=/* glsl */`
uniform sampler2D poolSurface,poolDepth,poolDetail;
uniform float poolCell,detailCell,poolTime,waveHeight,rippleGain,normalBoost,microStrength;
uniform float simulationOn,ripplesOn,microOn,causticsScale,causticsSpeed;
uniform vec2 microOrigin;
float poolRestDepth(vec2 p){return texture2D(poolDepth,(p+48.0)/96.0).r;}
float poolHeight(vec2 p){return texture2D(poolSurface,(p+48.0)/96.0).r;}
float detailHeight(vec2 p){
  if(ripplesOn<.5)return 0.0;
  vec2 uv=(p+24.0)/48.0;
  float edge=min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y));
  return texture2D(poolDetail,clamp(uv,vec2(0.0),vec2(1.0))).r*smoothstep(0.0,.045,edge)*rippleGain*ripplesOn;
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
  if(microOn<.5)return vec2(0);
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
`;

export const WATER_FRAGMENT=WATER_WAVES+/* glsl */`
uniform sampler2D mirrorSampler,sceneColor,sceneDepth,poolCaustics;
uniform float refractionOn,reflectionOn,absorptionOn,fresnelOn,waterlineOn,sceneReady,debugView;
uniform float refractionStrength,fresnelStrength,absorptionStrength,distortionScale,causticGain;
uniform float cameraNear,cameraFar,reflectionSize,foamOn,foamStrength;
uniform vec3 eye,sunColor,sunDirection,waterColor;
varying vec4 mirrorCoord,worldPosition,screenPosition;
#include <common>
#include <packing>
#include <fog_pars_fragment>
float foamField(vec2 p){return texture2D(poolSurface,(p+48.0)/96.0).a;}
float foamHash(vec2 k){return fract(sin(dot(k,vec2(127.1,311.7)))*43758.5453);}
vec2 foamHash2(vec2 k){return fract(sin(vec2(dot(k,vec2(127.1,311.7)),dot(k,vec2(269.5,183.3))))*43758.5453);}
// Worley F1: near zero at feature points, so the pattern reads as a bright
// foam mass with dark air holes at the cell centres (two octaves of holes).
float foamWorley(vec2 p){
  vec2 n=floor(p),f=fract(p);
  float d=1.0;
  for(int j=-1;j<=1;j++)for(int i=-1;i<=1;i++){
    vec2 g=vec2(float(i),float(j));
    d=min(d,length(g+foamHash2(n+g)-f));
  }
  return d;
}
float foamPattern(vec2 q){
  float holes=foamWorley(q)*.6+foamWorley(q*2.7+17.7)*.4;
  return 1.0-smoothstep(.1,.55,holes);
}
float foamClump(vec2 p){
  vec2 q=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
  return mix(mix(foamHash(q),foamHash(q+vec2(1.,0.)),f.x),mix(foamHash(q+vec2(0.,1.)),foamHash(q+vec2(1.,1.)),f.x),f.y);
}
void main(){
  vec2 p=worldPosition.xz;
  float bed=poolRestDepth(p);if(bed<=0.0)discard;
  vec3 V=normalize(eye-worldPosition.xyz);float distanceToEye=length(eye-worldPosition.xyz);
  float footprint=max(length(dFdx(p)),length(dFdy(p)));
  float detailFade=(1.0-smoothstep(8.0,26.0,distanceToEye))*(1.0-smoothstep(.09,.24,footprint));
  vec2 sim=simulationSlope(p),ripple=detailSlope(p)*detailFade;
  vec2 micro=microSlope(p,footprint)*(1.0-smoothstep(4.0,18.0,distanceToEye));
  vec3 N=normalize(vec3(-sim-ripple-micro,1).xzy);
  float theta=clamp(dot(N,V),0.0,1.0);
  const float f0=.020373;
  float fresnel=clamp((f0+(1.0-f0)*pow(1.0-theta,5.0))*fresnelStrength,0.0,1.0)*fresnelOn;
  vec2 screenUv=screenPosition.xy/screenPosition.w*.5+.5;
  vec3 viewP=(viewMatrix*worldPosition).xyz;
  float baseZ=-perspectiveDepthToViewZ(texture2D(sceneDepth,screenUv).r,cameraNear,cameraFar);
  float waterDepth=max(0.0,bed+poolSurfaceHeight(p));
  float thickness=sceneReady>.5?max(0.0,baseZ+viewP.z)*length(viewP)/max(-viewP.z,.01):waterDepth/max(theta,.2);
  thickness=min(thickness,6.0);
  // Perturb the refracted view ray with the actual surface slope, then apply a
  // gentle depth/angle scale. Foreground objects reject offset samples.
  vec3 refracted=refract(-V,N,1.0/1.333),flatRefracted=refract(-V,vec3(0,1,0),1.0/1.333);
  vec2 bend=(mat3(viewMatrix)*(refracted-flatRefracted)).xy;
  vec2 offset=bend*min(thickness,2.5)*.09*refractionStrength*refractionOn/(.7+distanceToEye*.12);
  offset=clamp(offset,vec2(-.016),vec2(.016));
  vec2 refractUv=clamp(screenUv+offset,vec2(.002),vec2(.998));
  float offsetZ=-perspectiveDepthToViewZ(texture2D(sceneDepth,refractUv).r,cameraNear,cameraFar);
  if(offsetZ<-viewP.z+.02)refractUv=screenUv;
  vec3 transmitted=texture2D(sceneColor,refractUv).rgb;
  vec3 absorption=exp(-vec3(.11,.033,.021)*absorptionStrength*absorptionOn*thickness);
  transmitted=transmitted*absorption+vec3(.13,.29,.30)*(1.0-absorption)*.24;
  vec2 reflectUv=mirrorCoord.xy/max(mirrorCoord.w,.001);
  reflectUv+=N.xz*distortionScale*(.002+.025/max(distanceToEye,1.0));
  vec2 border=vec2(1.5/reflectionSize);
  reflectUv=clamp(reflectUv,border,1.0-border);
  vec3 reflected=texture2D(mirrorSampler,reflectUv).rgb;
  float spec=pow(max(dot(N,normalize(V+sunDirection)),0.0),260.0)*.15;
  vec3 color=mix(transmitted,reflected,fresnel*reflectionOn)+sunColor*spec*fresnel;
  // Low quality uses regular alpha transmission without an opaque-scene pass.
  float alpha=1.0;
  if(sceneReady<.5){alpha=clamp(fresnel*reflectionOn+(1.0-absorption.g)*.3,.025,.98);color=mix(waterColor*.25,reflected,fresnel*reflectionOn/max(alpha,.001));}
  float shore=min(min(poolRestDepth(p+vec2(poolCell,0)),poolRestDepth(p-vec2(poolCell,0))),min(poolRestDepth(p+vec2(0,poolCell)),poolRestDepth(p-vec2(0,poolCell))));
  color+=vec3(.018,.024,.023)*(1.0-smoothstep(0.0,.07,shore))*waterlineOn;
  // Foam whitens diffusely and kills the specular sheen under it. The ~25 cm
  // sim field masks a Worley bubble pattern that rides the surface current
  // with the classic flow-map dual-phase blend: two phase-offset samples
  // along the velocity vector crossfade through a triangle weight, so the
  // pattern travels with the water, never stretches, and never strobes at
  // the phase wrap. A low-frequency value noise desyncs the phase and breaks
  // the macro coverage into drifting patches.
  float foam=foamField(p);
  if(foam>.001&&foamOn>.5){
    vec2 flow=texture2D(poolSurface,(p+48.0)/96.0).gb;
    float phaseNoise=foamClump(p*.33)*3.0;
    float t1=fract(poolTime*.85+phaseNoise),t2=fract(poolTime*.85+phaseNoise+.5);
    vec2 q=p*2.6;
    float pat=mix(foamPattern(q-flow*t2*.55),foamPattern(q-flow*t1*.55),1.0-abs(1.0-2.0*t1));
    float clump=foamClump(p*.9+vec2(poolTime*.021,-poolTime*.013));
    foam=clamp(foam*foamStrength*(.15+1.5*pat)*(.45+.8*clump),0.0,1.0);
    foam*=1.0-.5*smoothstep(10.0,30.0,distanceToEye);
    color=mix(color,sunColor*.42+vec3(.6,.67,.72),foam*.9);
    alpha=max(alpha,foam);
  }
  if(debugView>.5){
    alpha=1.0;
    if(debugView<1.5)color=vec3(.5+poolHeight(p)*12.0);
    else if(debugView<2.5){vec2 flow=texture2D(poolSurface,(p+48.0)/96.0).gb;color=vec3(.5+flow*.8,.5);}
    else if(debugView<3.5)color=normalize(vec3(-sim,1).xzy)*.5+.5;
    else if(debugView<4.5)color=vec3(.5+detailHeight(p)*100.0);
    else if(debugView<5.5)color=N*.5+.5;
    else if(debugView<6.5)color=mix(vec3(.02,.04,.05),vec3(.16,.72,.84),clamp(waterDepth/1.3,0.0,1.0));
    else if(debugView<7.5)color=vec3(fresnel);
    else if(debugView<8.5)color=transmitted;
    else if(debugView<9.5)color=texture2D(poolCaustics,p/32.0+.5).rgb*causticGain;
    else if(debugView<10.5)color=reflected*reflectionOn;
    else if(debugView<11.5)color=vec3(foamField(p)*3.0);
    else color=reflected*reflectionOn;
  }
  gl_FragColor=vec4(color,alpha);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
  // Scene color already includes world fog; avoid applying it a second time.
  if(sceneReady<.5&&debugView<.5){
    #include <fog_fragment>
  }
}`;
