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

float halfRNE(float v){
  uint bits=floatBitsToUint(v), magnitude=bits&0x7fffffffu;
  if(magnitude>=0x38800000u){uint rounded=(magnitude+0xfffu+((magnitude>>13u)&1u))&0xffffe000u;return uintBitsToFloat((bits&0x80000000u)|rounded);}
  float a=abs(v)*16777216.0;float whole=floor(a),remainder=a-whole;
  if(remainder>.5||(remainder==.5&&mod(whole,2.0)>0.0))whole+=1.0;
  return sign(v)*whole/16777216.0;
}
void main(){ivec2 c=ivec2(gl_GlobalInvocationID.xy);if(c.x>=SIZE||c.y>=SIZE)return;float v=(c.x%2==0?1.0:-1.0)*(.1+float(c.y)*.001);imageStore(outputState,c,vec4(v,unpackHalf2x16(packHalf2x16(vec2(v,0))).x,halfRNE(v),1));}
