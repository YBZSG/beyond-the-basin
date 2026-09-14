// All slopes use world XZ metres. Height, reflection, refraction and photon
// transport share the same macro + meso field; only micro detail is band-limited.
export const WATER_WAVES=/* glsl */`
uniform sampler2D poolSurface,poolDepth,poolDetail;
uniform float poolCell,detailCell,poolTime,waveHeight,rippleGain,normalBoost,microStrength;
uniform float simulationOn,ripplesOn,microOn,causticsScale,causticsSpeed;
uniform vec2 microOrigin;
float poolRestDepth(vec2 p){return texture2D(poolDepth,(p+48.0)/96.0).r;}
// poolDepth is nearest-filtered: the solver needs a hard land mask. Sampling
// it directly quantises anything derived from depth to the 0.125m cell grid,
// which is what tiled the waterline into screen-space blocks hugging columns
// and step edges. Bilinear it by hand for shading use only.
float poolRestDepthSmooth(vec2 p){
  vec2 g=(p+48.0)/poolCell-.5;
  vec2 i=floor(g),f=fract(g);
  float inv=poolCell/96.0;
  float d00=texture2D(poolDepth,(i+vec2(.5,.5))*inv).r;
  float d10=texture2D(poolDepth,(i+vec2(1.5,.5))*inv).r;
  float d01=texture2D(poolDepth,(i+vec2(.5,1.5))*inv).r;
  float d11=texture2D(poolDepth,(i+vec2(1.5,1.5))*inv).r;
  return mix(mix(d00,d10,f.x),mix(d01,d11,f.x),f.y);
}
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
uniform float cameraNear,cameraFar,reflectionSize;
uniform float foamOn,foamStrength;
uniform vec3 eye,sunColor,sunDirection,waterColor;
varying vec4 mirrorCoord,worldPosition,screenPosition;
#include <common>
#include <packing>
#include <fog_pars_fragment>
float foamField(vec2 p){
  vec2 uv=(p+48.0)/96.0,g=(p+48.0)/poolCell-.5,cell=floor(g),f=fract(g);
  float inv=poolCell/96.0;
  vec2 origin=(cell+.5)*inv;
  float wet=min(min(textureLod(poolDepth,origin,0.0).r,textureLod(poolDepth,origin+vec2(inv,0),0.0).r),
                min(textureLod(poolDepth,origin+vec2(0,inv),0.0).r,textureLod(poolDepth,origin+vec2(inv),0.0).r));
  float density=textureLod(poolSurface,uv,0.0).a;
  if(wet<=0.0){
    // Normalize wet samples across cut cells. Solid zeros must not erode foam
    // before it reaches the wall; geometry depth supplies the visible contour.
    // Explicit LOD avoids undefined derivatives inside this varying branch.
    vec2 a=1.0-f;
    vec4 wx=vec4(a.x*a.x*a.x,3.0*f.x*f.x*f.x-6.0*f.x*f.x+4.0,-3.0*f.x*f.x*f.x+3.0*f.x*f.x+3.0*f.x+1.0,f.x*f.x*f.x)/6.0;
    vec4 wz=vec4(a.y*a.y*a.y,3.0*f.y*f.y*f.y-6.0*f.y*f.y+4.0,-3.0*f.y*f.y*f.y+3.0*f.y*f.y+3.0*f.y+1.0,f.y*f.y*f.y)/6.0;
    float sum=0.0,weight=0.0;
    for(int z=0;z<4;z++)for(int x=0;x<4;x++){
      vec2 q=origin+vec2(float(x-1),float(z-1))*inv;
      float w=wx[x]*wz[z]*step(.0001,textureLod(poolDepth,q,0.0).r);
      sum+=textureLod(poolSurface,q,0.0).a*w;weight+=w;
    }
    density=sum/max(weight,.00001);
  }
  return density;
}
float foamNoise(vec2 p){
  vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
  vec4 h=fract(sin(vec4(dot(i,vec2(127.1,311.7)),dot(i+vec2(1,0),vec2(127.1,311.7)),dot(i+vec2(0,1),vec2(127.1,311.7)),dot(i+vec2(1,1),vec2(127.1,311.7))))*43758.5453);
  return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
void main(){
  vec2 p=worldPosition.xz;
  // The simulation's binary land cells constrain flux, not silhouettes.
  // Opaque depth clips the water against the true curved/rotated geometry.
  float bed=max(.005,poolRestDepthSmooth(p));
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
  // Optical contact follows geometry depth, rather than the binary grid's
  // staircase. Do not paint a cell-wide bright collar around obstacles.
  color+=vec3(.018,.024,.023)*(1.0-smoothstep(0.0,.025,thickness))*waterlineOn;
  // Whitewater is a continuous transported density on this exact water
  // surface. Small pores break up only the field's edge, with footprint
  // filtering; they never draw cells or separate white spheres.
  float density=foamField(p)*foamStrength*foamOn;
  if(density>.015){
    vec2 flow=texture2D(poolSurface,(p+48.0)/96.0).gb;
    float phase=fract(poolTime*.5),other=fract(phase+.5),weight=abs(phase*2.0-1.0);
    vec2 materialP=p-flow*phase*2.0,materialQ=p-flow*other*2.0;
    float coarse=mix(foamNoise(materialP*19.0),foamNoise(materialQ*19.0),weight);
    float fine=mix(foamNoise(materialP*79.0),foamNoise(materialQ*79.0),weight);
    float pores=mix(coarse,coarse*.55+fine*.45,1.0-smoothstep(.004,.018,footprint));
    float crestAffinity=.28+.72*smoothstep(.005,.035,poolHeight(p));
    float cover=smoothstep(.03,.36,density+(pores-.5)*.18)*(1.0-exp(-density*1.8))*crestAffinity;
    float illumination=clamp(.65+sqrt(max(dot(reflected,vec3(.2126,.7152,.0722)),0.0))*.35,.65,1.1);
    vec3 whitewater=vec3(.65,.73,.74)*illumination*(.74+.26*max(N.y,0.0));
    color=mix(color,whitewater,cover*.93);alpha=mix(alpha,1.0,cover);
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
