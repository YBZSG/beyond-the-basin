// MLS-MPM transfers adapted from matsuoka-601/Splash (MIT).
// See docs/licenses/Splash-MIT.txt. Positions/velocities use grid units;
// time is seconds, and all forces below are converted from metres.
export const LIQUID_MPM = /* wgsl */`
struct Particle { x:vec4f, v:vec4f, C:mat3x3f }
struct Cell { x:atomic<i32>, y:atomic<i32>, z:atomic<i32>, m:atomic<i32> }
struct Params { count:u32, h:f32, dt:f32, age:f32, flow:vec4f, body:vec4f, motion:vec4f }
struct Sample { x:vec4f, v:vec4f, a:vec4f, b:vec4f, c:vec4f }
@group(0) @binding(0) var<storage,read_write> particles:array<Particle>;
@group(0) @binding(1) var<storage,read_write> grid:array<Cell>;
@group(0) @binding(2) var<uniform> p:Params;
@group(0) @binding(3) var<storage,read_write> samples:array<Sample>;
@group(0) @binding(4) var<storage,read_write> links:array<i32>;
@group(0) @binding(5) var<storage,read> deletions:array<u32>;
@compute @workgroup_size(64) fn deleteParticles(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=deletions[0]){return;}let index=deletions[id.x+1];particles[index].v.w=0.;
}
const NX:i32=80; const NY:i32=80; const NZ:i32=80;
// Sufficient fixed-point precision is essential: truncating tiny node masses
// at 1/4096 spuriously accelerates sparse liquid during repeated transfers.
const SCALE:f32=65536.;
fn idx(c:vec3i)->u32 { return u32((c.x*NY+c.y)*NZ+c.z); }
fn weights(d:vec3f)->array<vec3f,3> { return array<vec3f,3>(.5*(.5-d)*(.5-d),.75-d*d,.5*(.5+d)*(.5+d)); }
fn zero()->mat3x3f { return mat3x3f(vec3f(0),vec3f(0),vec3f(0)); }
@compute @workgroup_size(128) fn clear(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=u32(NX*NY*NZ)){return;}
 atomicStore(&grid[id.x].x,0);atomicStore(&grid[id.x].y,0);atomicStore(&grid[id.x].z,0);atomicStore(&grid[id.x].m,0);
}
@compute @workgroup_size(64) fn mass(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=p.count){return;} let a=particles[id.x]; if(a.v.w<.5){return;}
 let base=vec3i(floor(a.x.xyz));let w=weights(a.x.xyz-(vec3f(base)+.5));
 for(var x=0;x<3;x++){for(var y=0;y<3;y++){for(var z=0;z<3;z++){
  let c=base+vec3i(x,y,z)-1;let i=idx(c);let weight=w[x].x*w[y].y*w[z].z;
  let d=vec3f(c)+.5-a.x.xyz;let momentum=weight*(a.v.xyz+a.C*d)*SCALE;
  atomicAdd(&grid[i].m,i32(weight*SCALE));
  atomicAdd(&grid[i].x,i32(momentum.x));atomicAdd(&grid[i].y,i32(momentum.y));atomicAdd(&grid[i].z,i32(momentum.z));
 }}}
}
@compute @workgroup_size(64) fn pressure(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=p.count){return;}let a=particles[id.x];if(a.v.w<.5){return;}
 let base=vec3i(floor(a.x.xyz));let w=weights(a.x.xyz-(vec3f(base)+.5));var density=0.;
 for(var x=0;x<3;x++){for(var y=0;y<3;y++){for(var z=0;z<3;z++){
  density+=f32(atomicLoad(&grid[idx(base+vec3i(x,y,z)-1)].m))/SCALE*w[x].x*w[y].y*w[z].z;
 }}}
 particles[id.x].x.w=density;
 // Weakly compressible water; no negative pressure, elastic springs or
 // rest-shape attraction. Pressure is only a density constraint.
 let pressure=max(0.,64./(p.h*p.h)*(density/3.64133-1.));
 let viscosity=.000001/(p.h*p.h);
 let stress=mat3x3f(vec3f(-pressure,0,0),vec3f(0,-pressure,0),vec3f(0,0,-pressure))+viscosity*(a.C+transpose(a.C));
 let force=-4.*p.dt/max(density,.05)*stress;
 for(var x=0;x<3;x++){for(var y=0;y<3;y++){for(var z=0;z<3;z++){
  let c=base+vec3i(x,y,z)-1;let i=idx(c);let weight=w[x].x*w[y].y*w[z].z;
  let momentum=force*(vec3f(c)+.5-a.x.xyz)*weight*SCALE;
  atomicAdd(&grid[i].x,i32(momentum.x));atomicAdd(&grid[i].y,i32(momentum.y));atomicAdd(&grid[i].z,i32(momentum.z));
 }}}
}
@compute @workgroup_size(128) fn velocity(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=u32(NX*NY*NZ)){return;}let i=id.x;let m=f32(atomicLoad(&grid[i].m));if(m<1.){return;}
 let c=vec3f(f32(i/u32(NY*NZ))+.5,f32((i/u32(NZ))%u32(NY))+.5,f32(i%u32(NZ))+.5);
 var v=vec3f(f32(atomicLoad(&grid[i].x)),f32(atomicLoad(&grid[i].y)),f32(atomicLoad(&grid[i].z)))/m;
 // Hydrostatic pressure of the surrounding height-field reservoir balances
 // gravity below its surface. Airborne liquid receives full gravity.
 v.y-=9.81/p.h*p.dt*smoothstep(10.,12.,c.y);
 // Local submerged reservoir: pressure support and flow from the shallow
 // water field, with a permeable lateral boundary. No bouncing box walls.
 if(c.y<5.){v=mix(v,vec3f(p.flow.x/p.h,max(0.,v.y),p.flow.y/p.h),clamp((5.-c.y)*.65,0.,1.));}
 // A moving collider displaces water over time, not a mesh-shaped emitter.
 let age=f32(links[p.count])*p.dt;
 if(p.body.w>0.&&age<.16){
  let centre=p.body.xyz+p.motion.xyz*age/p.h;
  let d=(c-centre)*p.h;let distance=length(d);
  if(distance<p.body.w&&distance>.00001){
   let n=d/distance;let relative=v-p.motion.xyz/p.h;
   let inward=dot(relative,n);if(inward<0.){v-=inward*n;}
   let correction=min(.6,(p.body.w-distance)*25.)/p.h;
   v+=n*max(0.,correction-dot(v-p.motion.xyz/p.h,n));
  }
 }
 let speed=length(v);if(speed>7./p.h){v*=7./p.h/speed;}
 atomicStore(&grid[i].x,i32(v.x*SCALE));atomicStore(&grid[i].y,i32(v.y*SCALE));atomicStore(&grid[i].z,i32(v.z*SCALE));
}
@compute @workgroup_size(64) fn gather(@builtin(global_invocation_id) id:vec3u){
 if(id.x==0u){links[p.count]+=1;}
 if(id.x>=p.count){return;}var a=particles[id.x];if(a.v.w<.5){return;}
 let base=vec3i(floor(a.x.xyz));let w=weights(a.x.xyz-(vec3f(base)+.5));var v=vec3f(0);var C=zero();
 for(var x=0;x<3;x++){for(var y=0;y<3;y++){for(var z=0;z<3;z++){
  let c=base+vec3i(x,y,z)-1;let i=idx(c);let weight=w[x].x*w[y].y*w[z].z;
  let weighted=vec3f(f32(atomicLoad(&grid[i].x)),f32(atomicLoad(&grid[i].y)),f32(atomicLoad(&grid[i].z)))/SCALE*weight;
  let d=vec3f(c)+.5-a.x.xyz;v+=weighted;C+=mat3x3f(weighted*d.x,weighted*d.y,weighted*d.z);
 }}}
 a.v=vec4f(v,a.v.w);a.C=C*4.;a.x=vec4f(a.x.xyz+v*p.dt,a.x.w);
 if(any(a.x.xyz<vec3f(2.))||any(a.x.xyz>vec3f(77.))){a.v.w=0.;}
 particles[id.x]=a;
}
// Reuse the cleared grid for a particle neighbour list after simulation.
@compute @workgroup_size(128) fn resetHeads(@builtin(global_invocation_id) id:vec3u){
 if(id.x<u32(NX*NY*NZ)){atomicStore(&grid[id.x].m,-1);}
}
@compute @workgroup_size(64) fn link(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=p.count||particles[id.x].v.w<.5){return;}
 let cell=vec3i(floor(particles[id.x].x.xyz));
 links[id.x]=atomicExchange(&grid[idx(cell)].m,i32(id.x));
}
@compute @workgroup_size(64) fn exportState(@builtin(global_invocation_id) id:vec3u){
 if(id.x>=p.count){return;}
 let a=particles[id.x];var shape=mat3x3f(vec3f(.64,0,0),vec3f(0,.64,0),vec3f(0,0,.64));var shift=vec3f(0);var neighbours=64;
 if(a.v.w>.5&&a.x.y>10.5){
  var mean=vec3f(0);var covariance=zero();var sum=0.;neighbours=0;
  let base=vec3i(floor(a.x.xyz));
  for(var x=-2;x<=2;x++){for(var y=-2;y<=2;y++){for(var z=-2;z<=2;z++){
   let cell=base+vec3i(x,y,z);if(any(cell<vec3i(0))||any(cell>=vec3i(80))){continue;}
   var j=atomicLoad(&grid[idx(cell)].m);var budget=0;
   while(j>=0&&budget<96){
    let d=particles[u32(j)].x.xyz-a.x.xyz;let d2=dot(d,d);
    if(d2<4.){
     let w=pow(1.-d2*.25,3.);mean+=d*w;sum+=w;neighbours++;
     covariance+=mat3x3f(d*d.x,d*d.y,d*d.z)*w;
    }j=links[u32(j)];budget++;
   }
  }}}
  if(neighbours>8&&sum>1.){
   mean/=sum;covariance=covariance*(1./sum)-mat3x3f(mean*mean.x,mean*mean.y,mean*mean.z);
   // Cholesky factor of neighbour covariance is an anisotropic kernel.
   // A small variance floor bounds sheet/filament aspect ratios without
   // inflating every particle into an isotropic gel bead.
   let xx=sqrt(max(.035,covariance[0].x));
   let yx=covariance[0].y/xx;let zx=covariance[0].z/xx;
   let yy=sqrt(max(.035,covariance[1].y-yx*yx));
   let zy=(covariance[1].z-yx*zx)/yy;
   let zz=sqrt(max(.035,covariance[2].z-zx*zx-zy*zy));
   shape=mat3x3f(vec3f(xx,yx,zx),vec3f(0,yy,zy),vec3f(0,0,zz));
   shape*=.64/pow(xx*yy*zz,1./3.);shift=mean*.55;
  }
 }
 samples[id.x]=Sample(a.x,vec4f(a.v.xyz,select(0.,f32(neighbours),a.v.w>.5)),vec4f(shape[0],shift.x),vec4f(shape[1],shift.y),vec4f(shape[2],shift.z));
}
`;
