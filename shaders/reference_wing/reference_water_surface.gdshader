shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, cull_back;
// Direct port of water-optics.ts WATER_FRAGMENT from Beyond the Basin 66a4543.
// API-only changes: Godot screen/depth inputs, reverse-Z reconstruction, world
// floating-origin offset, output/tone mapping and mirror-capture uniforms.
// Original Snell offset, Schlick, Beer coefficients, foam advection and
// debug branches are retained; pore modulation is continuous on PC. Caustics are applied to receiver materials,
// NEVER an unrelated procedural texture multiplied into transmission.
#include "res://shaders/source_water/shared_waves.gdshaderinc"
#include "res://shaders/source_water/wind_ripples.gdshaderinc"
#include "res://shaders/reference_wing/reference_ripples.gdshaderinc"
uniform sampler2D mirrorSampler : filter_linear, repeat_disable;
uniform sampler2D sceneColor : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D sceneDepth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D poolCaustics : filter_linear_mipmap, repeat_disable;
uniform vec2 domain_origin = vec2(0.0);
uniform mat4 textureMatrix;
uniform float reflectionReady = 0.0;
uniform float refractionOn = 1.0;
uniform float reflectionOn = 1.0;
uniform float absorptionOn = 1.0;
uniform float fresnelOn = 1.0;
uniform float waterlineOn = 1.0;
uniform float sceneReady = 1.0;
// Source water-optics fallback fog only; normal transmission already samples fogged HDR.
uniform float sourceFogEnabled = 0.0;
uniform float sourceFogDensity = 0.036;
uniform vec3 sourceFogColor = vec3(0.015996,0.034340,0.046665);
uniform float debugView = 0.0;
uniform float refractionStrength = 0.7;
uniform float fresnelStrength = 1.0;
uniform float absorptionStrength = 0.7;
uniform float distortionScale = 0.4;
uniform float causticGain = 1.5;
uniform float reflectionSize = 768.0;
uniform float foamOn = 1.0;
uniform float foamStrength = 1.0;
uniform vec3 sunColor : source_color = vec3(0.63137,0.74118,0.76471);
uniform vec3 sunDirection = vec3(-0.27617,0.92057,-0.27617);
uniform vec3 waterColor : source_color = vec3(0.19608,0.48627,0.50196);
// PC_NEARFIELD_BEGIN
#include "res://shaders/pc_nearfield_lab/reflection_projection.gdshaderinc"
// PC_NEARFIELD_END
varying vec4 mirrorCoord;
varying vec4 worldPosition;
void vertex(){
    vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    VERTEX.y+=poolHeightSmooth(wp.xz-domain_origin);
    worldPosition=MODEL_MATRIX*vec4(VERTEX,1.0);
    mirrorCoord=textureMatrix*worldPosition;
}
float source_view_depth(vec2 uv,mat4 inv_projection){
    float depth=texture(sceneDepth,uv).r;
    vec4 p=inv_projection*vec4(uv*2.0-1.0,depth,1.0);
    return -p.z/p.w;
}
#include "res://shaders/source_water/rt_transmission_filter.gdshaderinc"
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
#include "res://shaders/source_water/foam_appearance.gdshaderinc"
void fragment(){
  vec2 p=worldPosition.xz-domain_origin;
  vec3 eye=CAMERA_POSITION_WORLD;
  // The simulation's binary land cells constrain flux, not silhouettes.
  // Opaque depth clips the water against the true curved/rotated geometry.
  float bed=max(.005,poolRestDepthSmooth(p));
  vec3 V=normalize(eye-worldPosition.xyz);float distanceToEye=length(eye-worldPosition.xyz);
  float footprint=max(length(dFdx(p)),length(dFdy(p)));
  float detailFade=(1.0-smoothstep(8.0,26.0,distanceToEye))*(1.0-smoothstep(.09,.24,footprint));
  vec2 sim=simulationSlope(p),ripple=detailSlope(p)*detailFade;
  vec2 micro=microSlope(p,footprint)*(1.0-smoothstep(4.0,18.0,distanceToEye));
  // PC_NEARFIELD_BEGIN
  bool nearfieldActive=pcNearfieldSurfaceActive(p);
  vec3 nearfieldDetail=vec3(0.0);
  if(nearfieldActive){
    nearfieldDetail=nf_height_gradient(p+microOrigin,poolTime*max(causticsSpeed,0.0),dFdx(p),dFdy(p))*pcNearfieldStrength*(max(microStrength,0.0)/.65);
    micro=nearfieldDetail.yz;
    ripple=detailSlope(p); // Same actual detail slope as photon path in near field.
  }
  // PC_NEARFIELD_END
  // Independent wind relief changes the actual optical normal used below by
  // Fresnel, planar reflection, refraction and highlights, never collision depth.
  vec2 wind=windOpticalSlope(worldPosition.xz,footprint,bed);
  vec2 reference=referenceOpticalSlope(worldPosition.xz,footprint,bed);
  vec3 N=normalize(vec3(-sim-ripple-micro-wind-reference,1).xzy);
  float theta=clamp(dot(N,V),0.0,1.0);
  const float f0=.020373;
  float fresnel=clamp((f0+(1.0-f0)*pow(1.0-theta,5.0))*fresnelStrength,0.0,1.0)*fresnelOn;
  vec2 screenUv=SCREEN_UV;
  vec3 viewP=(VIEW_MATRIX*worldPosition).xyz;
  float baseZ=source_view_depth(screenUv,INV_PROJECTION_MATRIX);
  float waterDepth=max(0.0,bed+poolSurfaceHeight(p));
  // PC_NEARFIELD_BEGIN
  if(nearfieldActive)waterDepth=max(0.0,bed+poolSurfaceHeight(p)+nearfieldDetail.x);
  // PC_NEARFIELD_END
  float thickness=sceneReady>.5?max(0.0,baseZ+viewP.z)*length(viewP)/max(-viewP.z,.01):waterDepth/max(theta,.2);
  thickness=min(thickness,6.0);
  // Perturb the refracted view ray with the actual surface slope, then apply a
  // gentle depth/angle scale. Foreground objects reject offset samples.
  vec3 refracted=refract(-V,N,1.0/1.333),flatRefracted=refract(-V,vec3(0,1,0),1.0/1.333);
  vec2 bend=(mat3(VIEW_MATRIX)*(refracted-flatRefracted)).xy;
  vec2 offset=(bend*vec2(1.0,-1.0))*min(thickness,2.5)*.09*refractionStrength*refractionOn/(.7+distanceToEye*.12);
  offset=clamp(offset,vec2(-.016),vec2(.016));
  vec2 refractUv=clamp(screenUv+offset,vec2(.002),vec2(.998));
  float offsetZ=source_view_depth(refractUv,INV_PROJECTION_MATRIX);
  if(offsetZ<-viewP.z+.02)refractUv=screenUv;
  vec3 transmitted=water_transmission(refractUv,-viewP.z,INV_PROJECTION_MATRIX);
  vec3 absorption=exp(-vec3(.11,.033,.021)*absorptionStrength*absorptionOn*thickness);
  transmitted=transmitted*absorption+vec3(.13,.29,.30)*(1.0-absorption)*.24;
  vec2 reflectUv=mirrorCoord.xy/max(mirrorCoord.w,.001);
  reflectUv+=(N.xz*vec2(1.0,-1.0))*distortionScale*(.002+.025/max(distanceToEye,1.0));
  if(referenceWavesActive>.5){
    // Project the extra normal's change in reflection direction into camera
    // space. The legacy subpixel offset alone leaves lamp images rectangular.
    vec3 baseN=normalize(vec3(-sim-ripple-micro-wind,1).xzy);
    vec3 reflectedDelta=reflect(-V,N)-reflect(-V,baseN);
    vec2 lensBend=(mat3(VIEW_MATRIX)*reflectedDelta).xy;
    reflectUv+=clamp(lensBend*vec2(1.0,-1.0)*.075,vec2(-.065),vec2(.065));
  }
  // PC_NEARFIELD_BEGIN
  if(nearfieldActive){
    vec2 flatUv=mirrorCoord.xy/max(mirrorCoord.w,.001);
    vec3 envelopeMin=vec3(domain_origin.x-11.0,-.12,domain_origin.y-10.0);
    vec3 envelopeMax=vec3(domain_origin.x+11.0,4.8,domain_origin.y+10.0);
    // Finite verified room-envelope proxy, NOT captured-depth ray tracing.
    reflectUv=nf_project_reflection(worldPosition.xyz,V,N,textureMatrix,envelopeMin,envelopeMax,flatUv);
  }
  // PC_NEARFIELD_END
  vec2 border=vec2(1.5/reflectionSize);
  reflectUv=clamp(reflectUv,border,1.0-border);
  vec3 reflected=water_reflection(reflectUv);
  reflected=mix(waterColor*.25,reflected,reflectionReady);
  float spec=pow(max(dot(N,normalize(V+sunDirection)),0.0),260.0)*.15;
  vec3 color=mix(transmitted,reflected,fresnel*reflectionOn)+sunColor*spec*fresnel;
  // Low quality uses regular alpha transmission without an opaque-scene pass.
  float alpha=1.0;
  if(sceneReady<.5){alpha=clamp(fresnel*reflectionOn+(1.0-absorption.g)*.3,.025,.98);color=mix(waterColor*.25,reflected,fresnel*reflectionOn/max(alpha,.001));}
  // Optical contact follows geometry depth, rather than the binary grid's
  // staircase. Do not paint a cell-wide bright collar around obstacles.
  color+=vec3(.018,.024,.023)*(1.0-smoothstep(0.0,.025,thickness))*waterlineOn;
  // Density still comes from the simulation; shade sparse, advected patches.
  float density=foamField(p)*foamStrength*foamOn;
  if(density>.10){
    vec2 flow=texture(poolSurface,(p+48.0)/96.0).gb;
    float cover=foam_coverage(p,flow,density,footprint,poolTime);
    color=mix(color,foam_lit_color(transmitted,reflected),cover);
    alpha=mix(alpha,1.0,cover);
  }
  if(debugView>.5){
    alpha=1.0;
    if(debugView<1.5)color=vec3(.5+poolHeight(p)*12.0);
    else if(debugView<2.5){vec2 flow=texture(poolSurface,(p+48.0)/96.0).gb;color=vec3(.5+flow*.8,.5);}
    else if(debugView<3.5)color=normalize(vec3(-sim,1).xzy)*.5+.5;
    else if(debugView<4.5)color=vec3(.5+detailHeight(p)*100.0);
    else if(debugView<5.5)color=N*.5+.5;
    else if(debugView<6.5)color=mix(vec3(.02,.04,.05),vec3(.16,.72,.84),clamp(waterDepth/1.3,0.0,1.0));
    else if(debugView<7.5)color=vec3(fresnel);
    else if(debugView<8.5)color=transmitted;
    else if(debugView<9.5)color=texture(poolCaustics,p/32.0+.5).rgb*causticGain;
    else if(debugView<10.5)color=reflected*reflectionOn;
    else if(debugView<11.5)color=vec3(foamField(p)*3.0);
    else color=reflected*reflectionOn;
  }
  if(sceneReady<.5 && debugView<.5 && sourceFogEnabled>.5){
    float fogFactor=1.0-exp(-sourceFogDensity*sourceFogDensity*viewP.z*viewP.z);
    color=mix(color,sourceFogColor,fogFactor);
  }
  ALBEDO=color;
  ALPHA=alpha;
}
