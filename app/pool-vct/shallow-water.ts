import * as T from 'three';
import type { Collider } from './physics';

export const WATER_LEVEL=.32, POOL_BOTTOM=-.72;
export const SW_SIZE=768, SW_DOMAIN=96, SW_HALF=SW_DOMAIN/2, SW_CELL=SW_DOMAIN/SW_SIZE;
export const SW_PHYS=384, SW_PHYS_CELL=SW_DOMAIN/SW_PHYS, SW_STEP=1/120;
const REST_DEPTH=WATER_LEVEL-POOL_BOTTOM, MAX_STEPS=8, FRICTION=.45;
const MAX_HEIGHT=.35, MAX_FLOW=2, SOURCE_BATCH=128;
export type SwBox=[number,number,number,number];

export function poolWallAt(x:number,z:number){
  const band=(v:number)=>Math.abs(((v%32)+32)%32-16);
  const mid=(v:number)=>{const m=((v%32)+32)%32;return Math.min(m,32-m);};
  return (band(x)<=.3&&mid(z)>=4)||(band(z)<=.3&&mid(x)>=4);
}

// Variable-depth shallow water on a staggered C grid. Upwind momentum
// advection transports wakes; hydrostatic pressure and face water depths
// preserve still water over submerged steps. Dry cells stay fixed (no flooding).
// RGBA16F: eta at cell centres, u/v at the west/south faces.
const PREAMBLE=/* glsl */`
precision highp float;
uniform sampler2D poolState,poolDepth,poolSource;
uniform float poolDt,poolFriction,poolSourceOn,poolGravity;
const int SIZE=${SW_SIZE};
const float DX=${SW_CELL};
bool inside(ivec2 c){return c.x>=0&&c.y>=0&&c.x<SIZE&&c.y<SIZE;}
float depth(ivec2 c){return inside(c)?texelFetch(poolDepth,c,0).r:0.0;}
vec4 state(ivec2 c){return inside(c)?texelFetch(poolState,c,0):vec4(0.0);}
float faceDepth(float a,float b){return min(a,b)>0.0?2.0*a*b/(a+b):0.0;}
float neighbour(ivec2 c,float centre){return depth(c)>0.0?state(c).r:centre;}
float waterFace(ivec2 a,ivec2 b,float speed){
  float rest=faceDepth(depth(a),depth(b));
  return rest>0.0?max(.02,rest+(speed>=0.0?state(a).r:state(b).r)):0.0;
}
float damping(ivec2 c){
  float edge=float(min(min(c.x,c.y),min(SIZE-1-c.x,SIZE-1-c.y)))*DX;
  return exp(-poolDt*(poolFriction+3.0*(1.0-smoothstep(0.0,5.0,edge))));
}
`;
const VELOCITY=PREAMBLE+/* glsl */`
out vec4 outState;
void main(){
  ivec2 c=ivec2(gl_FragCoord.xy);float h=depth(c);
  if(h<=0.0){outState=vec4(0.0);return;}
  vec4 s=state(c),force=texelFetch(poolSource,c,0)*poolSourceOn;
  vec4 west=state(c-ivec2(1,0)),east=state(c+ivec2(1,0)),south=state(c-ivec2(0,1)),north=state(c+ivec2(0,1));
  float crossV=(s.b+west.b+north.b+state(c+ivec2(-1,1)).b)*.25;
  float crossU=(s.g+south.g+east.g+state(c+ivec2(1,-1)).g)*.25;
  float advU=(s.g*(s.g>=0.0?s.g-west.g:east.g-s.g)+crossV*(crossV>=0.0?s.g-south.g:north.g-s.g))/DX;
  float advV=(crossU*(crossU>=0.0?s.b-west.b:east.b-s.b)+s.b*(s.b>=0.0?s.b-south.b:north.b-s.b))/DX;
  float u=depth(c-ivec2(1,0))>0.0?s.g-poolDt*(poolGravity*(s.r-west.r)/DX+advU)+force.g:0.0;
  float v=depth(c-ivec2(0,1))>0.0?s.b-poolDt*(poolGravity*(s.r-south.r)/DX+advV)+force.b:0.0;
  outState=vec4(s.r,clamp(vec2(u,v)*damping(c),vec2(-${MAX_FLOW}.0),vec2(${MAX_FLOW}.0)),0.0);
}`;
const HEIGHT=PREAMBLE+/* glsl */`
out vec4 outState;
void main(){
  ivec2 c=ivec2(gl_FragCoord.xy);float h=depth(c);
  if(h<=0.0){outState=vec4(0.0);return;}
  vec4 s=state(c);
  float uR=state(c+ivec2(1,0)).g,vU=state(c+ivec2(0,1)).b;
  float fluxX=waterFace(c,c+ivec2(1,0),uR)*uR-waterFace(c-ivec2(1,0),c,s.g)*s.g;
  float fluxZ=waterFace(c,c+ivec2(0,1),vU)*vU-waterFace(c-ivec2(0,1),c,s.b)*s.b;
  float lap=neighbour(c+ivec2(1,0),s.r)+neighbour(c-ivec2(1,0),s.r)+neighbour(c+ivec2(0,1),s.r)+neighbour(c-ivec2(0,1),s.r)-4.0*s.r;
  float eta=s.r-poolDt*(fluxX+fluxZ)/DX+poolDt*.004*lap/(DX*DX);
  eta+=texelFetch(poolSource,c,0).r*poolSourceOn;
  float limit=min(${MAX_HEIGHT},h*.45);
  outState=vec4(clamp(eta,-limit,limit),s.gb,0.0);
}`;
const COPY=/* glsl */`
precision highp float;
uniform sampler2D poolState,poolDepth;
uniform ivec2 shift;
out vec4 outState;
void main(){
  ivec2 c=ivec2(gl_FragCoord.xy),s=c+shift;
  bool valid=s.x>=0&&s.y>=0&&s.x<${SW_SIZE}&&s.y<${SW_SIZE};
  outState=valid&&texelFetch(poolDepth,c,0).r>0.0?texelFetch(poolState,s,0):vec4(0.0);
}`;
const DOWNSAMPLE=/* glsl */`
precision highp float;
uniform sampler2D poolState;
out vec4 outState;
void main(){
  ivec2 base=ivec2(gl_FragCoord.xy)*${SW_SIZE/SW_PHYS};vec4 s=vec4(0.0);
  for(int y=0;y<${SW_SIZE/SW_PHYS};y++)for(int x=0;x<${SW_SIZE/SW_PHYS};x++){
    ivec2 c=base+ivec2(x,y);vec4 a=texelFetch(poolState,c,0);
    vec4 e=texelFetch(poolState,min(c+ivec2(1,0),ivec2(${SW_SIZE-1})),0);
    vec4 n=texelFetch(poolState,min(c+ivec2(0,1),ivec2(${SW_SIZE-1})),0);
    s+=vec4(a.r,(a.g+e.g)*.5,(a.b+n.b)*.5,0.0);
  }
  s/=${(SW_SIZE/SW_PHYS)**2}.0;
  // Preserve weak currents; byte quantization erased flow below 1.6 cm/s.
  outState=vec4(s.rgb,1.0);
}`;
const vertexShader='void main(){gl_Position=vec4(position.xy,0.0,1.0);}';
type Readback={buffer:Uint16Array;generation:number;started:number;done:boolean;failed:boolean};

export class ShallowWater {
  /** Live-tunable source shaping, driven by the pause-menu water sliders:
   * impactScale multiplies splash amplitude, ringWaves is the packet wave
   * number (higher = finer rings, stable above ~4 cells per wavelength), and
   * waveSpeed scales gravity — propagation speed is sqrt(waveSpeed*g*depth). */
  impactScale=1;ringWaves=12;waveSpeed=1;
  private depthData=new Float32Array(SW_SIZE*SW_SIZE);
  private depthTexture=new T.DataTexture(this.depthData,SW_SIZE,SW_SIZE,T.RedFormat,T.FloatType);
  private stateA=this.target(SW_SIZE,T.HalfFloatType);
  private stateB=this.target(SW_SIZE,T.HalfFloatType);
  private sourceTarget=this.target(SW_SIZE,T.HalfFloatType);
  private physTarget=this.target(SW_PHYS,T.HalfFloatType);
  private current=this.stateA;
  uniforms={poolSurface:{value:this.current.texture},poolDepth:{value:this.depthTexture}};
  settled=true;
  physicsEta=new Float32Array(SW_PHYS*SW_PHYS);
  physicsU=new Float32Array(SW_PHYS*SW_PHYS);
  physicsV=new Float32Array(SW_PHYS*SW_PHYS);
  pendingSplats:number[]=[];
  pendingPushes:number[]=[];
  energy=0;
  private peak=0;private acc=0;private clock=0;private quiet=0;private calm=0;
  private booted=false;private disposed=false;private generation=0;
  private pendingShift=new T.Vector2();private terrainDirty=false;
  private readback:Readback|null=null;private readbackLanded=-Infinity;
  private asyncFailed=false;private syncAt=-Infinity;
  private asyncLands=0;private syncReads=0;private rejected=0;private simulated=0;private droppedTime=0;
  private quad=new T.PlaneGeometry(2,2);
  private camera=new T.Camera();private scene=new T.Scene();private mesh=new T.Mesh(this.quad);
  private velocity:T.ShaderMaterial;private height:T.ShaderMaterial;private copy:T.ShaderMaterial;private down:T.ShaderMaterial;
  private sourceGeometry=new T.InstancedBufferGeometry();private sourceScene=new T.Scene();private sourceMaterial:T.ShaderMaterial;
  private sources=new Float32Array(SOURCE_BATCH*4);private momenta=new Float32Array(SOURCE_BATCH*2);

  constructor(){
    this.depthTexture.minFilter=this.depthTexture.magFilter=T.NearestFilter;
    this.mesh.frustumCulled=false;this.scene.add(this.mesh);
    const shared={poolDepth:this.uniforms.poolDepth,poolSource:{value:this.sourceTarget.texture}};
    const make=(fragmentShader:string,uniforms:T.ShaderMaterialParameters['uniforms'])=>new T.ShaderMaterial({
      glslVersion:T.GLSL3,vertexShader,fragmentShader,uniforms,depthTest:false,depthWrite:false,toneMapped:false,
    });
    const state=()=>({...shared,poolState:{value:this.current.texture},poolDt:{value:SW_STEP},poolFriction:{value:FRICTION},poolSourceOn:{value:0},poolGravity:{value:9.81}});
    this.velocity=make(VELOCITY,state());this.height=make(HEIGHT,state());
    this.copy=make(COPY,{...shared,poolState:{value:this.current.texture},shift:{value:new T.Vector2()}});
    this.down=make(DOWNSAMPLE,{poolState:{value:this.current.texture}});
    this.sourceGeometry.index=this.quad.index;this.sourceGeometry.setAttribute('position',this.quad.attributes.position);
    this.sourceGeometry.setAttribute('splat',new T.InstancedBufferAttribute(this.sources,4).setUsage(T.DynamicDrawUsage));
    this.sourceGeometry.setAttribute('momentum',new T.InstancedBufferAttribute(this.momenta,2).setUsage(T.DynamicDrawUsage));
    this.sourceMaterial=new T.ShaderMaterial({
      uniforms:{poolDepth:this.uniforms.poolDepth,poolRingW:{value:this.ringWaves}},
      vertexShader:`attribute vec4 splat;attribute vec2 momentum;varying vec2 q;varying vec3 power;varying vec2 origin;varying float radius;
        void main(){q=position.xy*4.0;power=vec3(splat.z,momentum);origin=splat.xy;radius=splat.w;gl_Position=vec4((splat.xy+q*splat.w)/${SW_HALF}.0,0.0,1.0);}`,
      fragmentShader:`uniform sampler2D poolDepth;uniform float poolRingW;varying vec2 q;varying vec3 power;varying vec2 origin;varying float radius;
        void main(){if(texture2D(poolDepth,gl_FragCoord.xy/${SW_SIZE}.0).r<=0.0)discard;
          vec2 p=gl_FragCoord.xy*${SW_CELL}-${SW_HALF}.0;
          int steps=int(ceil(length(p-origin)/${SW_CELL}));
          for(int i=1;i<96;i++){if(i>=steps)break;
            vec2 probe=mix(origin,p,float(i)/float(steps));
            if(texture2D(poolDepth,(probe+${SW_HALF}.0)/${SW_DOMAIN}.0).r<=0.0)discard;}
          // The radial Laplacian of a Gaussian wave packet has zero net volume
          // in open water: repeated splashes cannot pump the mean water level.
          // poolRingW sets the packet fineness (default ~0.5m rings, well above
          // the 4-cell solver limit so disturbance waves stay crisp, not blobby).
          float r2=dot(q,q),r=sqrt(r2),a=poolRingW*radius,w=exp(-.5*r2);
          float sinc=r>.0001?sin(a*r)/r:a;
          float ring=((2.0+a*a-r2)*cos(a*r)+(a-2.0*a*r2)*sinc)/(2.0+2.0*a*a);
          gl_FragColor=vec4(power.x*ring*w,power.yz*w,0.0);}`,
      transparent:true,blending:T.CustomBlending,blendSrc:T.OneFactor,blendDst:T.OneFactor,blendEquation:T.AddEquation,
      depthTest:false,depthWrite:false,toneMapped:false,
    });
    const sourceMesh=new T.Mesh(this.sourceGeometry,this.sourceMaterial);sourceMesh.frustumCulled=false;this.sourceScene.add(sourceMesh);
    this.setBlocks([]);
  }
  private target(size:number,type:T.TextureDataType){return new T.WebGLRenderTarget(size,size,{type,depthBuffer:false,generateMipmaps:false});}

  /** Sample actual pool columns: submerged treads, round pillars and tilted
   * colliders contribute; overhead bridges leave water beneath them open. */
  setTerrain(colliders:Collider[]){
    this.depthData.fill(REST_DEPTH);
    const inverse=new T.Quaternion(),p=new T.Vector3(),direction=new T.Vector3(),box=new T.Box3();
    for(const c of colliders){
      box.set(c.half.clone().negate(),c.half.clone());
      if(c.rotation)box.applyMatrix4(new T.Matrix4().makeRotationFromQuaternion(c.rotation));box.translate(c.center);
      if(box.min.y>WATER_LEVEL||box.max.y<=POOL_BOTTOM)continue;
      const ix0=Math.max(0,Math.ceil((box.min.x+SW_HALF)/SW_CELL-.5)),iz0=Math.max(0,Math.ceil((box.min.z+SW_HALF)/SW_CELL-.5));
      const ix1=Math.min(SW_SIZE-1,Math.floor((box.max.x+SW_HALF)/SW_CELL-.5)),iz1=Math.min(SW_SIZE-1,Math.floor((box.max.z+SW_HALF)/SW_CELL-.5));
      inverse.copy(c.rotation??new T.Quaternion()).invert();direction.set(0,-1,0).applyQuaternion(inverse);
      for(let z=iz0;z<=iz1;z++)for(let x=ix0;x<=ix1;x++){
        const wx=(x+.5)*SW_CELL-SW_HALF,wz=(z+.5)*SW_CELL-SW_HALF;let top=box.max.y;
        if(c.radius!==undefined&&!c.rotation){if((wx-c.center.x)**2+(wz-c.center.z)**2>c.radius**2)continue;}
        else if(c.rotation){
          p.set(wx,WATER_LEVEL,wz).sub(c.center).applyQuaternion(inverse);let near=-Infinity,far=Infinity;
          for(const axis of ['x','y','z'] as const){
            if(Math.abs(direction[axis])<1e-8){if(Math.abs(p[axis])>c.half[axis])far=-Infinity;}
            else{const a=(-c.half[axis]-p[axis])/direction[axis],b=(c.half[axis]-p[axis])/direction[axis];near=Math.max(near,Math.min(a,b));far=Math.min(far,Math.max(a,b));}
          }
          if(near>far||far<0)continue;top=WATER_LEVEL-near;
        }
        const d=Math.max(0,WATER_LEVEL-top),i=x+z*SW_SIZE;this.depthData[i]=Math.min(this.depthData[i],d<.04?0:d);
      }
    }
    this.depthTexture.needsUpdate=true;this.terrainDirty=true;this.generation++;
  }
  /** Standalone room convenience; the game supplies full geometry instead. */
  setBlocks(boxes:(T.Vector4|SwBox)[]){
    const colliders:Collider[]=[];
    for(const b of boxes){const [x0,z0,x1,z1]=b instanceof T.Vector4?[b.x,b.y,b.z,b.w]:b;
      colliders.push({center:new T.Vector3((x0+x1)/2,0,(z0+z1)/2),half:new T.Vector3((x1-x0)/2,1,(z1-z0)/2)});}
    this.setTerrain(colliders);
    for(let z=0;z<SW_SIZE;z++)for(let x=0;x<SW_SIZE;x++)if(poolWallAt((x+.5)*SW_CELL-SW_HALF,(z+.5)*SW_CELL-SW_HALF))this.depthData[x+z*SW_SIZE]=0;
    this.depthTexture.needsUpdate=true;
  }
  depthAt(x:number,z:number){const i=Math.floor((x+SW_HALF)/SW_CELL),j=Math.floor((z+SW_HALF)/SW_CELL);return i>=0&&j>=0&&i<SW_SIZE&&j<SW_SIZE?this.depthData[i+j*SW_SIZE]:0;}
  isLand(x:number,z:number){return this.depthAt(x,z)<=0;}
  impact(x:number,z:number,strength:number){
    if(![x,z,strength].every(Number.isFinite)||strength<=0||this.isLand(x,z))return;
    this.pendingSplats.push(x,z,Math.min(.13,strength*.3)*this.impactScale,.42+.2*Math.min(strength,.5));this.wake();
  }
  /** Velocity impulse; continuous movers supply acceleration * elapsed time.
   * Source radii clamp at .16m so hull wakes stay thin bands, not blobs. */
  push(x:number,z:number,vx:number,vz:number,sigma:number){
    if(![x,z,vx,vz,sigma].every(Number.isFinite)||this.isLand(x,z)||Math.hypot(vx,vz)<1e-6)return;
    this.pendingPushes.push(x,z,T.MathUtils.clamp(vx,-MAX_FLOW,MAX_FLOW),T.MathUtils.clamp(vz,-MAX_FLOW,MAX_FLOW),T.MathUtils.clamp(sigma,.16,2));this.wake();
  }
  /** Bow/stern pressure dipole of a moving hull. A lone momentum blob in
   * nondispersive shallow water just blooms into a smooth semicircle; the real
   * hull field is high-pressure at the bow and low astern, which sheds the
   * crisp leading crescent and the trailing wave train. Amplitude grows with
   * speed squared, like the form drag that drives it. */
  wakeDipole(x:number,z:number,dx:number,dz:number,speed:number,sigma:number){
    if(![x,z,dx,dz,speed,sigma].every(Number.isFinite)||speed<.05)return;
    const amp=Math.min(.06,.008*speed*speed)*this.impactScale,r=Math.max(.16,sigma);
    const ox=x+dx*r,oz=z+dz*r,nx=x-dx*r,nz=z-dz*r;
    if(!this.isLand(ox,oz))this.pendingSplats.push(ox,oz,amp,r*.9);
    if(!this.isLand(nx,nz))this.pendingSplats.push(nx,nz,-amp,r*.9);
    this.wake();
  }
  private wake(){this.settled=false;this.quiet=0;this.calm=0;}
  private draw(renderer:T.WebGLRenderer,material:T.ShaderMaterial,target:T.WebGLRenderTarget){this.mesh.material=material;renderer.setRenderTarget(target);renderer.render(this.scene,this.camera);}
  private clear(renderer:T.WebGLRenderer,target:T.WebGLRenderTarget){renderer.setRenderTarget(target);renderer.clear();}
  private inject(renderer:T.WebGLRenderer){
    this.clear(renderer,this.sourceTarget);
    this.sourceMaterial.uniforms.poolRingW.value=this.ringWaves;
    const count=this.pendingSplats.length/4+this.pendingPushes.length/5;
    for(let start=0;start<count;start+=SOURCE_BATCH){
      const n=Math.min(SOURCE_BATCH,count-start);
      for(let k=0;k<n;k++){
        const index=start+k,ns=this.pendingSplats.length/4;
        if(index<ns){this.sources.set(this.pendingSplats.slice(index*4,index*4+4),k*4);this.momenta.set([0,0],k*2);}
        else{const i=(index-ns)*5,p=this.pendingPushes;this.sources.set([p[i],p[i+1],0,p[i+4]],k*4);this.momenta.set([p[i+2],p[i+3]],k*2);}
      }
      this.sourceGeometry.instanceCount=n;this.sourceGeometry.attributes.splat.needsUpdate=true;this.sourceGeometry.attributes.momentum.needsUpdate=true;
      renderer.setRenderTarget(this.sourceTarget);renderer.render(this.sourceScene,this.camera);
    }
    this.pendingSplats.length=0;this.pendingPushes.length=0;return count>0;
  }
  frame(renderer:T.WebGLRenderer,dt:number){
    dt=Number.isFinite(dt)?Math.max(0,dt):0;this.clock+=dt;this.quiet+=dt;this.flushReadback();
    const previous=renderer.getRenderTarget(),color=renderer.getClearColor(new T.Color()),alpha=renderer.getClearAlpha(),auto=renderer.autoClear;
    renderer.autoClear=false;renderer.setClearColor(0,0);let changed=false;
    try{
      if(!this.booted){this.clear(renderer,this.stateA);this.clear(renderer,this.stateB);this.clear(renderer,this.sourceTarget);this.booted=true;}
      if(this.terrainDirty||this.pendingShift.lengthSq()>0){
        this.copy.uniforms.poolState.value=this.current.texture;this.copy.uniforms.shift.value.copy(this.pendingShift).divideScalar(SW_CELL).round();
        const other=this.current===this.stateA?this.stateB:this.stateA;this.draw(renderer,this.copy,other);this.current=other;
        this.pendingShift.set(0,0);this.terrainDirty=false;changed=true;
      }
      if(this.settled)return changed;
      const elapsed=Math.min(dt,MAX_STEPS*SW_STEP);this.droppedTime+=dt-elapsed;this.acc=Math.min(this.acc+elapsed,MAX_STEPS*SW_STEP);
      if(this.acc+1e-10<SW_STEP)return changed;
      const sources=this.inject(renderer);let steps=0;
      while(this.acc+1e-10>=SW_STEP&&steps<MAX_STEPS){
        for(const material of [this.velocity,this.height]){material.uniforms.poolSourceOn.value=sources&&steps===0?1:0;material.uniforms.poolFriction.value=FRICTION+1.5*T.MathUtils.smoothstep(this.quiet,8,14);}
        // Gravity scales linearly: wave speed goes with sqrt(waveSpeed*g*depth).
        this.velocity.uniforms.poolGravity.value=9.81*this.waveSpeed;
        const other=this.current===this.stateA?this.stateB:this.stateA;
        this.velocity.uniforms.poolState.value=this.current.texture;this.draw(renderer,this.velocity,other);
        this.height.uniforms.poolState.value=other.texture;this.draw(renderer,this.height,this.current);
        this.acc=Math.max(0,this.acc-SW_STEP);this.simulated+=SW_STEP;steps++;changed=true;
      }
      const fresh=this.clock-this.readbackLanded<.5;this.calm=fresh&&this.peak<.0003&&this.quiet>2?this.calm+elapsed:0;
      if(!sources&&(this.calm>1||this.quiet>22)){
        this.clear(renderer,this.stateA);this.clear(renderer,this.stateB);this.physicsEta.fill(0);this.physicsU.fill(0);this.physicsV.fill(0);
        this.energy=0;this.peak=0;this.acc=0;this.settled=true;this.generation++;
      }else if(!this.readback){this.down.uniforms.poolState.value=this.current.texture;this.draw(renderer,this.down,this.physTarget);this.requestReadback(renderer);}
      return changed;
    }finally{this.uniforms.poolSurface.value=this.current.texture;renderer.setRenderTarget(previous);renderer.setClearColor(color,alpha);renderer.autoClear=auto;}
  }
  private requestReadback(renderer:T.WebGLRenderer){
    const job:Readback={buffer:new Uint16Array(SW_PHYS*SW_PHYS*4),generation:this.generation,started:this.clock,done:false,failed:false};
    if(!this.asyncFailed&&typeof renderer.readRenderTargetPixelsAsync==='function'){
      this.readback=job;renderer.readRenderTargetPixelsAsync(this.physTarget,0,0,SW_PHYS,SW_PHYS,job.buffer).then(()=>{job.done=true;},()=>{job.done=true;job.failed=true;});
    }else if(typeof renderer.readRenderTargetPixels==='function'&&this.clock-this.syncAt>=1/30){
      this.syncAt=this.clock;
      // Three's pending async reader can leave a pixel-pack buffer bound.
      // A synchronous typed-array read must temporarily unbind it.
      const gl=renderer.getContext?.() as WebGL2RenderingContext|undefined,pack=gl?.getParameter(gl.PIXEL_PACK_BUFFER_BINDING);
      try{gl?.bindBuffer(gl.PIXEL_PACK_BUFFER,null);renderer.readRenderTargetPixels(this.physTarget,0,0,SW_PHYS,SW_PHYS,job.buffer);this.syncReads++;this.parseReadback(job.buffer);}
      catch{this.rejected++;}finally{if(gl)gl.bindBuffer(gl.PIXEL_PACK_BUFFER,pack??null);}
    }
  }
  private flushReadback(){
    const job=this.readback;if(!job)return;if(!job.done&&this.clock-job.started<=1)return;this.readback=null;
    if(!job.done||job.failed){this.asyncFailed=true;return;}
    if(this.disposed||job.generation!==this.generation)return;this.asyncLands++;this.parseReadback(job.buffer);
  }
  private parseReadback(bytes:Uint16Array){
    // Half-float alpha=1 marks a completed pixel; reject missing/nonfinite data.
    for(let i=0;i<bytes.length;i+=4)if(bytes[i+3]!==0x3c00||[bytes[i],bytes[i+1],bytes[i+2]].some(v=>(v&0x7c00)===0x7c00)){this.rejected++;return;}
    let energy=0,peak=0;
    for(let i=0,j=0;i<this.physicsEta.length;i++,j+=4){
      const h=T.DataUtils.fromHalfFloat(bytes[j]),u=T.DataUtils.fromHalfFloat(bytes[j+1]),v=T.DataUtils.fromHalfFloat(bytes[j+2]);
      this.physicsEta[i]=h;this.physicsU[i]=u;this.physicsV[i]=v;
      energy+=h*h+(u*u+v*v)*REST_DEPTH/9.81;peak=Math.max(peak,Math.abs(h),Math.abs(u)*.1,Math.abs(v)*.1);
    }
    this.energy=energy/this.physicsEta.length;this.peak=peak;this.readbackLanded=this.clock;
  }
  private sample(arr:Float32Array,x:number,z:number){
    if(this.isLand(x,z))return 0;
    const gx=(x+SW_HALF)/SW_PHYS_CELL-.5,gz=(z+SW_HALF)/SW_PHYS_CELL-.5;
    const ix=Math.max(0,Math.min(SW_PHYS-2,Math.floor(gx))),iz=Math.max(0,Math.min(SW_PHYS-2,Math.floor(gz)));
    const fx=T.MathUtils.clamp(gx-ix,0,1),fz=T.MathUtils.clamp(gz-iz,0,1),i=ix+iz*SW_PHYS;
    return (arr[i]*(1-fx)+arr[i+1]*fx)*(1-fz)+(arr[i+SW_PHYS]*(1-fx)+arr[i+SW_PHYS+1]*fx)*fz;
  }
  heightAt(x:number,z:number){return this.sample(this.physicsEta,x,z);}
  flowAt(x:number,z:number){return {u:this.sample(this.physicsU,x,z),v:this.sample(this.physicsV,x,z)};}
  /** Wave forces on a floating body: (ax,az) is the hydrostatic slope push
   * -g∇η that rocks props over long wave faces, and (ux,uz) is the Stokes
   * drift velocity η·(u,v) — the net transport a wave train carries, which the
   * buoyancy drag chases so props glide along with passing waves. Both are
   * quadratic in wave intensity, so an undisturbed pool never drifts anything.
   * Any land probe returns zeros, so walls never read as sheer cliffs. */
  slopeAt(x:number,z:number,r=.38){
    if(this.isLand(x,z)||this.isLand(x-r,z)||this.isLand(x+r,z)||this.isLand(x,z-r)||this.isLand(x,z+r))return {ax:0,az:0,ux:0,uz:0};
    const slopeX=(this.sample(this.physicsEta,x+r,z)-this.sample(this.physicsEta,x-r,z))/(2*r);
    const slopeZ=(this.sample(this.physicsEta,x,z+r)-this.sample(this.physicsEta,x,z-r))/(2*r);
    const eta=this.sample(this.physicsEta,x,z);
    let ax=-9.81*slopeX,az=-9.81*slopeZ;
    let ux=eta*this.sample(this.physicsU,x,z)*110,uz=eta*this.sample(this.physicsV,x,z)*110;
    const push=Math.hypot(ax,az);
    if(push>3){ax*=3/push;az*=3/push;}
    const drift=Math.hypot(ux,uz);
    if(drift>1.5){ux*=1.5/drift;uz*=1.5/drift;}
    return {ax,az,ux,uz};
  }
  rebase(dx:number,dz:number){
    if(!dx&&!dz)return;this.pendingShift.add(new T.Vector2(dx,dz));this.generation++;
    for(let i=0;i<this.pendingSplats.length;i+=4){this.pendingSplats[i]-=dx;this.pendingSplats[i+1]-=dz;}
    for(let i=0;i<this.pendingPushes.length;i+=5){this.pendingPushes[i]-=dx;this.pendingPushes[i+1]-=dz;}
    const sx=Math.round(dx/SW_PHYS_CELL),sz=Math.round(dz/SW_PHYS_CELL);
    for(const field of [this.physicsEta,this.physicsU,this.physicsV]){
      const old=field.slice();field.fill(0);
      for(let z=Math.max(0,-sz);z<Math.min(SW_PHYS,SW_PHYS-sz);z++){
        const lo=Math.max(0,-sx),hi=Math.min(SW_PHYS,SW_PHYS-sx);
        if(hi>lo)field.set(old.subarray(lo+sx+(z+sz)*SW_PHYS,hi+sx+(z+sz)*SW_PHYS),lo+z*SW_PHYS);
      }
    }
  }
  debug(){return {grid:SW_SIZE,cell:SW_CELL,clock:this.clock,simulated:this.simulated,droppedTime:this.droppedTime,
    landed:Number.isFinite(this.readbackLanded)?this.readbackLanded:null,pending:!!this.readback,energy:this.energy,peak:this.peak,settled:this.settled,
    asyncLands:this.asyncLands,syncReads:this.syncReads,rejected:this.rejected,pendingSplats:this.pendingSplats.length/4,pendingPushes:this.pendingPushes.length/5};}
  dispose(){
    this.disposed=true;this.generation++;this.readback=null;
    for(const t of [this.stateA,this.stateB,this.sourceTarget,this.physTarget])t.dispose();
    for(const m of [this.velocity,this.height,this.copy,this.down,this.sourceMaterial])m.dispose();
    this.quad.dispose();this.sourceGeometry.dispose();this.depthTexture.dispose();
  }
}
