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

// Equivalent to additive source-quads. The rectangle is +/-4 sigma.
// Explicit half rounding after each blend preserves the source RGBA16F target.
float sampleDepth(vec2 p){ivec2 c=clamp(ivec2(floor((p/pc.grid.y+.5)*float(SIZE))),ivec2(0),ivec2(SIZE-1));return depth(c);}
void main(){
  ivec2 c=ivec2(gl_GlobalInvocationID.xy);if(c.x>=SIZE||c.y>=SIZE)return;
  vec4 sum=pc.extra.y>0.0?imageLoad(poolSource,c):vec4(0);
  if(depth(c)<=0.0){storeHalf(c,vec4(0));return;}
  vec2 p=(vec2(c)+.5)*DX-pc.grid.y*.5;
  for(int k=0;k<int(pc.misc.w);k++){
    vec4 s=sources.events[k].splat;vec2 q=(p-s.xy)/s.w;
    if(any(greaterThan(abs(q),vec2(4))))continue;
    int steps=int(ceil(length(p-s.xy)/DX));bool blocked=false;
    for(int i=1;i<96;i++){if(i>=steps)break;if(sampleDepth(mix(s.xy,p,float(i)/float(steps)))<=0.0){blocked=true;break;}}
    if(blocked)continue;
    float r2=dot(q,q),r=sqrt(r2),a=pc.misc.z*s.w,w=exp(-.5*r2);
    float sinc=r>.0001?sin(a*r)/r:a;
    float ring=((2.0+a*a-r2)*cos(a*r)+(a-2.0*a*r2)*sinc)/(2.0+2.0*a*a);
    float aeration=smoothstep(.025,.095,s.z)*.65*exp(-2.8*r2);
    sum=halfRound(sum+vec4(s.z*ring*w,sources.events[k].momentum.xy*w,aeration));
  }
  storeHalf(c,sum);
}
