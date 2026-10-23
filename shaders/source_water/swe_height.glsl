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



float foamNeighbour(ivec2 c,float centre){return depth(c)>0.0?state(c).a:centre;}
float advectedFoam(vec2 uv,float centre){
  vec2 g=uv*float(SIZE)-.5,f=fract(g);ivec2 base=ivec2(floor(g));
  float value=0.0,weight=0.0;
  for(int z=0;z<2;z++)for(int x=0;x<2;x++){
    ivec2 c=base+ivec2(x,z);
    float w=(x==0?1.0-f.x:f.x)*(z==0?1.0-f.y:f.y);
    if(depth(c)>0.0){value+=state(c).a*w;weight+=w;}
  }
  return weight>.00001?value/weight:centre;
}
void sourceMain(){
  ivec2 c=ivec2((vec2(gl_GlobalInvocationID.xy)+.5));float h=depth(c);
  if(h<=0.0){outState=vec4(0.0);return;}
  vec4 s=state(c);
  float uR=state(c+ivec2(1,0)).g,vU=state(c+ivec2(0,1)).b;
  float fluxX=waterFace(c,c+ivec2(1,0),uR)*uR-waterFace(c-ivec2(1,0),c,s.g)*s.g;
  float fluxZ=waterFace(c,c+ivec2(0,1),vU)*vU-waterFace(c-ivec2(0,1),c,s.b)*s.b;
  float lap=neighbour(c+ivec2(1,0),s.r)+neighbour(c-ivec2(1,0),s.r)+neighbour(c+ivec2(0,1),s.r)+neighbour(c-ivec2(0,1),s.r)-4.0*s.r;
  float eta=s.r-poolDt*(fluxX+fluxZ)/DX+poolDt*poolViscosity*lap/(DX*DX);
  eta+=imageLoad(poolSource,c).r*poolSourceOn;
  float limit=min(.35,h*.45);
  // Advect aeration with cell-centred velocity. Ordinary compression is a
  // travelling wave, not breaking water: require a raised, energetic crest.
  vec2 flow=vec2(s.g+uR,s.b+vU)*.5;
  vec2 back=clamp(((vec2(gl_GlobalInvocationID.xy)+.5)-flow*poolDt/DX)/float(SIZE),vec2(.5/float(SIZE)),vec2(1.0-.5/float(SIZE)));
  float foam=advectedFoam(back,s.a);
  float critical=poolGravity*max(h+s.r,.05);
  float breaking=smoothstep(.72*critical,1.35*critical,dot(flow,flow));
  float convergence=max(0.0,-(uR-s.g+vU-s.b)/DX);
  float front=smoothstep(1.8,4.0,convergence)*smoothstep(.12,.7,length(flow));
  float crest=smoothstep(.018,.075,s.r);
  vec2 slope=vec2(neighbour(c+ivec2(1,0),s.r)-neighbour(c-ivec2(1,0),s.r),neighbour(c+ivec2(0,1),s.r)-neighbour(c-ivec2(0,1),s.r))/(2.0*DX);
  float vertical=abs((fluxX+fluxZ)/DX);
  float convex=smoothstep(.04,.55,-lap/(DX*DX))*smoothstep(.009,.05,s.r);
  float activity=smoothstep(.012,.28,dot(flow,flow)+vertical*vertical);
  float crestAir=convex*activity*max(smoothstep(.03,.18,length(slope)),smoothstep(.06,.55,vertical));
  // Broad wading waves have curvature without entraining air. Require motion
  // relative to local gravity/depth before emitting crest foam; otherwise a
  // stronger bow wave paints an opaque white sheet across the clear pool.
  crestAir*=smoothstep(.10*critical,.40*critical,dot(flow,flow)+vertical*vertical);
  // Mix towards neighbours before adding fresh aeration. This cannot amplify
  // new foam via a Laplacian that uses a different (already decayed) centre.
  float neighbours=(foamNeighbour(c+ivec2(1,0),s.a)+foamNeighbour(c-ivec2(1,0),s.a)+foamNeighbour(c+ivec2(0,1),s.a)+foamNeighbour(c-ivec2(0,1),s.a))*.25;
  foam=mix(foam,neighbours,clamp(4.0*poolDt*poolFoamDiff/(DX*DX),0.0,.24));
  // No-flux foam boundary: material reaches the wall, advects tangentially
  // and decays normally. A dry neighbour is not a sink or a foam exclusion band.
  foam+=poolDt*poolFoamGain*max(crest*max(breaking,front),crestAir*2.8);
  foam+=imageLoad(poolSource,c).a*poolFoamSplash*poolSourceOn;
  foam*=exp(-poolDt*poolFoamDecay);
  outState=vec4(clamp(eta,-limit,limit),s.gb,clamp(foam,0.0,1.0));
}
void main(){ivec2 c=ivec2(gl_GlobalInvocationID.xy);if(c.x>=SIZE||c.y>=SIZE)return;sourceMain();storeHalf(c,outState);}
