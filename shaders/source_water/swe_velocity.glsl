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
bool inside(ivec2 c){return c.x>=0&&c.y>=0&&c.x<SIZE&&c.y<SIZE;}
float depth(ivec2 c){return inside(c)?imageLoad(poolDepth,c).r:0.0;}
vec4 state(ivec2 c){return inside(c)?imageLoad(poolState,c):vec4(0.0);}
float faceDepth(float a,float b){return min(a,b)>0.0?2.0*a*b/(a+b):0.0;}
float neighbour(ivec2 c,float centre){return depth(c)>0.0?state(c).r:centre;}
float waterFace(ivec2 a,ivec2 b,float speed){
  float rest=faceDepth(depth(a),depth(b));
  return rest>0.0?max(.02,rest+(speed>=0.0?state(a).r:state(b).r)):0.0;
}
float damping(ivec2 c){
  float edge=float(min(min(c.x,c.y),min(SIZE-1-c.x,SIZE-1-c.y)))*DX;
  // Closed faces still reflect. A thin lossy wall band absorbs part of the
  // returning wave without draining surface height or opening a wall flux.
  float wall=0.0;
  for(int i=1;i<=2;i++){
    float wet=min(min(depth(c+ivec2(i,0)),depth(c-ivec2(i,0))),min(depth(c+ivec2(0,i)),depth(c-ivec2(0,i))));
    wall=max(wall,wet<=0.0?1.0/float(i):0.0);
  }
  return exp(-poolDt*(poolFriction+poolWallLoss*wall+3.0*(1.0-smoothstep(0.0,5.0,edge))));
}


void sourceMain(){
  ivec2 c=ivec2((vec2(gl_GlobalInvocationID.xy)+.5));float h=depth(c);
  if(h<=0.0){outState=vec4(0.0);return;}
  vec4 s=state(c),force=imageLoad(poolSource,c)*poolSourceOn;
  vec4 west=state(c-ivec2(1,0)),east=state(c+ivec2(1,0)),south=state(c-ivec2(0,1)),north=state(c+ivec2(0,1));
  float crossV=(s.b+west.b+north.b+state(c+ivec2(-1,1)).b)*.25;
  float crossU=(s.g+south.g+east.g+state(c+ivec2(1,-1)).g)*.25;
  float advU=(s.g*(s.g>=0.0?s.g-west.g:east.g-s.g)+crossV*(crossV>=0.0?s.g-south.g:north.g-s.g))/DX;
  float advV=(crossU*(crossU>=0.0?s.b-west.b:east.b-s.b)+s.b*(s.b>=0.0?s.b-south.b:north.b-s.b))/DX;
  float u=depth(c-ivec2(1,0))>0.0?s.g-poolDt*(poolGravity*(s.r-west.r)/DX+advU)+force.g:0.0;
  float v=depth(c-ivec2(0,1))>0.0?s.b-poolDt*(poolGravity*(s.r-south.r)/DX+advV)+force.b:0.0;
  // Foam rides in alpha: the velocity pass must carry it untouched.
  outState=vec4(s.r,clamp(vec2(u,v)*damping(c),vec2(-2.0),vec2(2.0)),s.a);
}
void main(){ivec2 c=ivec2(gl_GlobalInvocationID.xy);if(c.x>=SIZE||c.y>=SIZE)return;sourceMain();storeHalf(c,outState);}
