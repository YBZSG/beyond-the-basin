layout(set=0,binding=1) uniform sampler2D fluidDepth;
layout(set=0,binding=2) uniform sampler2D background;
layout(set=0,binding=3) uniform sampler2D opaqueDepth;
layout(set=0,binding=4) uniform sampler2D poolSurface;
layout(set=0,binding=5) uniform sampler2D poolDepth;
layout(set=0,binding=6) uniform sampler2D poolDetail;
layout(set=0,binding=7) uniform samplerCube environmentMap;
layout(location=0) in vec2 vUv;
layout(location=0) out vec4 color;
// WATER_WAVES is inserted here by the host, before main.
__SHARED_WAVES__
vec3 eyePosition(vec2 uv,float depth){vec4 p=inverseProjection*vec4(uv*2.-1.,1.,1.);return p.xyz*(-depth/p.z);}
void main(){
 float d=texture(fluidDepth,vUv).r;
 if(d>9000.){color=texture(background,vUv);return;}
 vec3 p=eyePosition(vUv,d),world=(cameraWorld*vec4(p,1.)).xyz;
 float level=.32+poolHeightSmooth(world.xz);
 if(world.y<level-.002||poolRestDepth(world.xz)<=0.){color=texture(background,vUv);return;}
 // Native Vulkan reverse-Z adaptation: decode real depth with frame inverse
 // projection instead of importing Three's WebGL perspectiveDepthToViewZ.
 float sceneZ=texture(opaqueDepth,vUv).r;
 vec4 opaqueEye=inverseProjection*vec4(vUv*2.-1.,sceneZ,1.);
 if(sceneZ>0.&&-opaqueEye.z/opaqueEye.w<-p.z){color=texture(background,vUv);return;}
 vec2 texel=1./viewport.xy;
 float dl=texture(fluidDepth,vUv-vec2(texel.x,0)).r,dr=texture(fluidDepth,vUv+vec2(texel.x,0)).r;
 float db=texture(fluidDepth,vUv-vec2(0,texel.y)).r,dt=texture(fluidDepth,vUv+vec2(0,texel.y)).r;
 if(dl>9000.)dl=d;if(dr>9000.)dr=d;if(db>9000.)db=d;if(dt>9000.)dt=d;
 vec3 dx=abs(dr-d)<abs(dl-d)?eyePosition(vUv+vec2(texel.x,0),dr)-p:p-eyePosition(vUv-vec2(texel.x,0),dl);
 vec3 dy=abs(dt-d)<abs(db-d)?eyePosition(vUv+vec2(0,texel.y),dt)-p:p-eyePosition(vUv-vec2(0,texel.y),db);
 vec3 normal=normalize(cross(dx,dy)),V=normalize(-p);if(dot(normal,V)<0.)normal=-normal;
 float F=.020373+.979627*pow(1.-clamp(dot(normal,V),0.,1.),5.);
 vec3 R=mat3(cameraWorld)*reflect(-V,normal);
 // Native room HDR Cubemap mip sampling replaces Three's packed PMREM layout.
 // The original roughness .07 and world reflection direction remain unchanged.
 vec3 reflected=options.x>.5?textureLod(environmentMap,R,.07*viewport.w).rgb:vec3(.3,.4,.43);
 vec3 refracted=refract(-V,normal,1./1.333);
 vec2 offset=(refracted.xy+V.xy)*.045/max(d,.4);
 // Source offset is eye-space up; Vulkan texture coordinates run downward.
 offset.y*=sign(projection[1][1]);
 vec3 transmitted=texture(background,clamp(vUv+offset,vec2(.001),vec2(.999))).rgb;
 vec3 c=transmitted*(1.-F)+reflected*F;
 float join=smoothstep(-.002,.012,world.y-level);
 color=vec4(mix(texture(background,vUv).rgb,c,join),1.);
}
