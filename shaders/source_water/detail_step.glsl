#[compute]
#version 450
// Direct source port: poolcore 66a4543602d9e774db07c2da12ce1d40d522532c.
// RGBA16F state = centre eta, west-face u, south-face v, aeration.
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform readonly image2D poolState;
layout(r32f,set=0,binding=1) uniform readonly image2D poolDepth;
layout(rgba16f,set=0,binding=2) uniform readonly image2D poolSource;
layout(rgba16f,set=0,binding=3) uniform writeonly image2D outputState;
struct Source { vec4 splat; vec4 momentum; };
layout(std430,set=0,binding=4) readonly buffer Sources { Source events[]; } sources;
layout(push_constant,std430) uniform Parameters {
  vec4 grid; // size, domain, dx, physics size
  vec4 sim; // dt, friction, gravity, viscosity
  vec4 foam; // gain, decay, diffusivity, splash
  vec4 misc; // sourceOn, wallLoss, packet wavenumber, sourceCount
  vec4 shift; // cell shift x/z, detail domain, detail cell
  vec4 extra; // detail frequency, source accumulate, reserved, reserved
  vec4 pad0; vec4 pad1;
} pc;
#define SIZE int(pc.grid.x)
#define DX pc.grid.z
#define poolDt pc.sim.x
#define poolFriction pc.sim.y
#define poolGravity pc.sim.z
#define poolViscosity pc.sim.w
#define poolFoamGain pc.foam.x
#define poolFoamDecay pc.foam.y
#define poolFoamDiff pc.foam.z
#define poolFoamSplash pc.foam.w
#define poolSourceOn pc.misc.x
#define poolWallLoss pc.misc.y

// Vulkan/WebGL format-conversion rounding is implementation dependent. Normalize
// binary16 writes to IEEE nearest-even explicitly, so the original equations do
// not acquire driver-dependent, biased RTZ decay across hundreds of substeps.
float sourceHalfRNE(float v){
  uint b=floatBitsToUint(v),s=b&0x80000000u,a=b&0x7fffffffu;
  if(a>=0x7f800000u)return v;
  if(a>=0x477ff000u)return uintBitsToFloat(s|0x7f800000u);
  if(a>=0x38800000u){a+=0xfffu+((a>>13u)&1u);return uintBitsToFloat(s|(a&0xffffe000u));}
  float q=roundEven(abs(v)*16777216.0)*5.9604644775390625e-8;
  return uintBitsToFloat(s|floatBitsToUint(q));
}
vec4 halfRound(vec4 v){return vec4(sourceHalfRNE(v.x),sourceHalfRNE(v.y),sourceHalfRNE(v.z),sourceHalfRNE(v.w));}
void storeHalf(ivec2 c,vec4 v){imageStore(outputState,c,halfRound(v));}
vec4 outState;

// Original RippleDetail has a separate 48m domain over the 96m depth field.
float worldDepth(vec2 p){ivec2 d=clamp(ivec2(floor((p/pc.grid.y+.5)*float(imageSize(poolDepth).x))),ivec2(0),imageSize(poolDepth)-1);return imageLoad(poolDepth,d).r;}
bool inside(ivec2 c){return all(greaterThanEqual(c,ivec2(0)))&&all(lessThan(c,ivec2(SIZE)));}
bool wet(ivec2 c){return inside(c)&&worldDepth((vec2(c)+.5)*pc.shift.w-pc.shift.z*.5)>0.0;}
float neighbour(ivec2 c,float h){return wet(c)?imageLoad(poolState,c).r:h;}

void main(){ivec2 c=ivec2(gl_GlobalInvocationID.xy);if(!inside(c))return;if(!wet(c)){storeHalf(c,vec4(0));return;}
  vec2 s=imageLoad(poolState,c).rg;
  float w=neighbour(c-ivec2(1,0),s.r),e=neighbour(c+ivec2(1,0),s.r),n=neighbour(c+ivec2(0,1),s.r),b=neighbour(c-ivec2(0,1),s.r);
  float edge=float(min(min(c.x,c.y),min(SIZE-1-c.x,SIZE-1-c.y)))*pc.shift.w;
  const float STEP=1.0/120.0;
  float damp=exp(-STEP*(1.3+5.0*(1.0-smoothstep(0.0,2.0,edge))));
  float v=(s.g+STEP*.85*.85/(pc.shift.w*pc.shift.w)*(w+e+n+b-4.0*s.r))*damp;
  float h=s.r+STEP*v+imageLoad(poolSource,c).r*poolSourceOn;
  storeHalf(c,vec4(clamp(h,-.012,.012),clamp(v,-.15,.15),0,0));
}
