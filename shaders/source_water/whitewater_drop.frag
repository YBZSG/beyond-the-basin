// Three r185 MeshPhysicalMaterial specular path, restricted only to the actual
// source material features (dielectric, roughness .065, no clearcoat/sheen).
// GGX, DFG LUT and multiscattering equations remain the original Three code.
layout(set=0,binding=3) uniform sampler2D sceneColor;
layout(set=0,binding=7) uniform samplerCube environmentMap;
layout(set=0,binding=8,std140) uniform SceneLights {vec4 lightInfo;vec4 lightPosition[27];vec4 lightColor[27];vec4 lightShadow[7];};
layout(set=0,binding=9) uniform sampler2D dfgLUT;
layout(location=0) in vec3 eye;
layout(location=1) in vec3 eyeNormal;
layout(location=2) in float dropDiameter;
layout(location=0) out vec4 color;
__DIRECT_SHADOW_BVH__
const float PI=3.141592653589793,EPSILON=1e-6;
const vec3 F0=vec3(((1.333-1.)/(1.333+1.))*((1.333-1.)/(1.333+1.)));
float saturate(float v){return clamp(v,0.,1.);}
vec3 physicalBRDF(vec3 L,vec3 V,vec3 N,float roughness){
 float alpha=roughness*roughness,a2=alpha*alpha;vec3 H=normalize(L+V);
 float NL=saturate(dot(N,L)),NV=saturate(dot(N,V)),NH=saturate(dot(N,H)),VH=saturate(dot(V,H));
 float f=exp2((-5.55473*VH-6.98316)*VH);vec3 F=F0*(1.-f)+vec3(f);
 float gv=NL*sqrt(a2+(1.-a2)*NV*NV),gl=NV*sqrt(a2+(1.-a2)*NL*NL);
 float visibility=.5/max(gv+gl,EPSILON);float denom=NH*NH*(a2-1.)+1.;float distribution=a2/(PI*denom*denom);
 vec3 singleScatter=F*(visibility*distribution);
 vec2 dfgV=texture(dfgLUT,vec2(roughness,NV)).rg,dfgL=texture(dfgLUT,vec2(roughness,NL)).rg;
 vec3 FssV=F0*dfgV.x+dfgV.y,FssL=F0*dfgL.x+dfgL.y;
 float EmsV=1.-dfgV.x-dfgV.y,EmsL=1.-dfgL.x-dfgL.y;
 vec3 Favg=F0+(1.-F0)*.047619;
 vec3 Fms=FssV*FssL*Favg/(1.-EmsV*EmsL*Favg+EPSILON);
 return singleScatter+Fms*(EmsV*EmsL);
}
void main(){
 vec3 N=normalize(eyeNormal),V=normalize(-eye);
 vec3 dxy=max(abs(dFdx(N)),abs(dFdy(N)));float roughness=min(1.,max(.065,.0525)+max(max(dxy.x,dxy.y),dxy.z));
 vec3 totalSpecular=vec3(0.);
 for(int i=0;i<int(lightInfo.x)&&i<27;i++){
  vec3 L;float attenuation=1.;float lightDistance=100.0;
  if(lightPosition[i].w<0.)L=normalize(mat3(viewMatrix)*lightPosition[i].xyz);
  else{vec3 delta=(viewMatrix*vec4(lightPosition[i].xyz,1.)).xyz-eye;float distance=length(delta);lightDistance=distance;L=delta/max(distance,EPSILON);
   attenuation=1./max(pow(distance,lightColor[i].w),.01);if(lightPosition[i].w>0.)attenuation*=pow(saturate(1.-pow(distance/lightPosition[i].w,4.)),2.);
  }
  float visibility=1.;if(lightShadow[i/4][i%4]>.5)visibility=directLightVisible((cameraWorld*vec4(eye,1.)).xyz,normalize(mat3(cameraWorld)*N),normalize(mat3(cameraWorld)*L),lightDistance,lightPosition[i].w);
  totalSpecular+=visibility*saturate(dot(N,L))*lightColor[i].rgb*attenuation*physicalBRDF(L,V,N,roughness);
 }
 if(options.x>.5){
  vec2 fab=texture(dfgLUT,vec2(roughness,saturate(dot(N,V)))).rg;
  vec3 single=F0*fab.x+fab.y;float Ems=1.-fab.x-fab.y;vec3 Favg=F0+(1.-F0)*.047619;
  vec3 multiple=single*Favg/(1.-Ems*Favg)*Ems;
  vec3 R=normalize(mix(reflect(-V,N),N,pow(roughness,4.)));
  vec3 radiance=textureLod(environmentMap,mat3(cameraWorld)*R,roughness*viewport.w).rgb;
  vec3 irradiance=textureLod(environmentMap,mat3(cameraWorld)*N,viewport.w).rgb;
  totalSpecular+=radiance*single+multiple*irradiance;
 }
 float facing=clamp(dot(N,V),0.,1.);float fresnel=.020373+.979627*pow(1.-facing,5.);
 vec2 screen=gl_FragCoord.xy/viewport.xy;
 vec2 bend=N.xy*dropDiameter*.15/max(.15,-eye.z);
 bend.y*=sign(projection[1][1]); // eye-space up -> native framebuffer Y
 vec3 transmitted=texture(sceneColor,clamp(screen+bend,vec2(.001),vec2(.999))).rgb;
 color=vec4(transmitted*(1.-fresnel)+totalSpecular,.94);
}
