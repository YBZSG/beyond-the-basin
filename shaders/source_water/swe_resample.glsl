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

// Original ShallowWater.inherit: bilinear UV resample, preserving metres and m/s.
vec4 previous(ivec2 c){return imageLoad(poolState,clamp(c,ivec2(0),imageSize(poolState)-1));}
void main(){ivec2 c=ivec2(gl_GlobalInvocationID.xy);if(c.x>=SIZE||c.y>=SIZE)return;vec4 result=vec4(0);
  if(imageLoad(poolDepth,c).r>0.0){vec2 g=(vec2(c)+.5)/float(SIZE)*vec2(imageSize(poolState))-.5;ivec2 b=ivec2(floor(g));vec2 f=fract(g);
    result=mix(mix(previous(b),previous(b+ivec2(1,0)),f.x),mix(previous(b+ivec2(0,1)),previous(b+ivec2(1,1)),f.x),f.y);
  }storeHalf(c,result);
}
