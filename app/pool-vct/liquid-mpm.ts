/// <reference types="@webgpu/types" />
import * as T from 'three';
import { LIQUID_MPM } from './liquid-mpm-shader.ts';

type Flow={u:number;v:number};
export type LiquidImpact={u:number;v:number;vertical?:number;radius?:number};
type Source={x:number;z:number;power:number;flow:LiquidImpact;crest:boolean;seed:number};
type Patch={
  x:number;z:number;base:number;h:number;age:number;elapsed:number;count:number;pending:boolean;disposed:boolean;
  buffers:GPUBuffer[];groups:GPUBindGroup[];params:Float32Array<ArrayBuffer>;data:Float32Array;previous:Float32Array;
  sampleAge:number;sampleDelta:number;blendElapsed:number;removed:Uint8Array;emerged:Uint8Array;
};
const LIMIT=18000,MAX_PATCHES=3,GRID=80*80*80,STEP=1/720;
const ENTRIES=['clear','mass','pressure','velocity','gather','resetHeads','link','exportState'];
type Drop=(x:number,y:number,z:number,vx:number,vy:number,vz:number,size:number)=>void;

/** A bounded three-dimensional liquid domain at an impact, coupled to the
 * existing height field. Only the simulated positions are reconstructed;
 * no predefined crest count, sheet topology or lifetime-shaped silhouette. */
export class LiquidMPM {
  readonly mesh:T.InstancedMesh<T.SphereGeometry,T.ShaderMaterial>;
  status='initializing';error='';released=0;returns=0;ripples=0;
  private device:GPUDevice|null=null;
  private pipelines:GPUComputePipeline[]=[];
  private patches:Patch[]=[];
  private sources:Source[]=[];
  private disposed=false;
  private transform=new T.Matrix4();
  private serial=0;
  get count(){return this.patches.length;}
  get stats(){return {backend:this.status,error:this.error,domains:this.count,fluidParticles:this.mesh.count,released:this.released,returns:this.returns,ages:this.patches.map(p=>p.age),simulatedParticles:this.patches.reduce((n,p)=>n+p.count,0)};}
  constructor(){
    const material=new T.ShaderMaterial({
      vertexShader:`varying vec3 eye;void main(){vec4 p=modelViewMatrix*instanceMatrix*vec4(position,1);eye=p.xyz;gl_Position=projectionMatrix*p;}`,
      fragmentShader:`varying vec3 eye;void main(){gl_FragColor=vec4(-eye.z,0,0,1);}`,
      toneMapped:false,
    });
    this.mesh=new T.InstancedMesh(new T.SphereGeometry(1,10,8),material,LIMIT*MAX_PATCHES);
    this.mesh.name='MLS-MPM fluid reconstruction';this.mesh.count=0;this.mesh.frustumCulled=false;
    this.mesh.instanceMatrix.setUsage(T.DynamicDrawUsage);
    void this.init();
  }
  private async init(){
    try{
      if(typeof navigator==='undefined'||!navigator.gpu){this.status='unavailable';return;}
      const adapter=await navigator.gpu.requestAdapter({powerPreference:'high-performance'});
      if(!adapter){this.status='unavailable';return;}
      const device=await adapter.requestDevice();if(this.disposed){device.destroy();return;}
      this.device=device;
      device.lost.then(info=>{if(!this.disposed){this.status='lost';this.error=info.message;this.clear();}});
      const shader=device.createShaderModule({code:LIQUID_MPM,label:'Local water MLS-MPM'});
      const messages=await shader.getCompilationInfo();
      const errors=messages.messages.filter(m=>m.type==='error');if(errors.length)throw new Error(errors.map(e=>e.message).join('\n'));
      this.pipelines=await Promise.all(ENTRIES.map(entryPoint=>device.createComputePipelineAsync({layout:'auto',compute:{module:shader,entryPoint}})));
      if(!this.disposed)this.status='webgpu';
    }catch(e){this.status='unavailable';this.error=String(e);}
  }
  impact(x:number,z:number,power:number,flow:LiquidImpact={u:0,v:0}){
    if(![x,z,power,flow.u,flow.v,flow.radius??.1,flow.vertical??0].every(Number.isFinite)||power<.08)return;
    if(this.sources.length+this.patches.length>=MAX_PATCHES)return;
    this.sources.push({x,z,power:Math.min(1.2,power),flow:{...flow},crest:false,seed:++this.serial});
  }
  crest(x:number,z:number,power:number,flow:Flow){
    // Foam-only crests do not all turn into identical airborne sheets.
    if(power<.28||this.patches.some(p=>Math.hypot(x-p.x,z-p.z)<.6)||this.sources.length+this.patches.length>=MAX_PATCHES)return;
    this.sources.push({x,z,power:Math.min(.45,power),flow:{...flow},crest:true,seed:++this.serial});
  }
  private create(source:Source,surface:(x:number,z:number)=>number,depth:(x:number,z:number)=>number){
    const device=this.device!;
    const {x,z,power,flow,crest}=source,bodyRadius=flow.radius??(power>.22&&!crest?.075+power*.06:0);
    const radius=bodyRadius>0?T.MathUtils.clamp(bodyRadius*2.5,.16,.34):.085+power*.23;
    const h=Math.max(.014,radius/12),spacing=h*.65,base=surface(x,z),raw=new Float32Array(LIMIT*20);
    // Stratified volume samples start under the actual water surface. The
    // small positional jitter removes lattice aliasing, not prescribed lobes.
    let rng=(source.seed*1664525+1013904223)>>>0;
    const random=()=>{rng=(Math.imul(rng,1664525)+1013904223)>>>0;return rng/4294967296;};
    const bottom=-h*8;let count=0;
    for(let ix=-radius;ix<radius;ix+=spacing)for(let iz=-radius;iz<radius;iz+=spacing){
      const d=Math.hypot(ix,iz);if(d>radius||depth(x+ix,z+iz)<=0)continue;
      for(let iy=bottom;iy<-.001;iy+=spacing){
        if(count>=LIMIT)break;
        const px=ix+(random()-.5)*spacing*.35,pz=iz+(random()-.5)*spacing*.35,py=iy+(random()-.5)*spacing*.25;
        const q=d/radius,envelope=Math.exp(-q*q*3.5);
        // Click/crest pressure impulse. Props instead displace this resting
        // volume with their moving collider in the grid update.
        const impulse=bodyRadius>0?0:Math.sqrt(power)*1.6;
        const upward=crest?impulse*envelope:-impulse*envelope*.55;
        const outward=crest?impulse*envelope*.35:0;
        raw.set([40+px/h,12+py/h,40+pz/h,3.64133,
          (flow.u*.35+(d>.001?px/d:0)*outward)/h,
          upward/h,
          (flow.v*.35+(d>.001?pz/d:0)*outward)/h,1,
          0,0,0,0,0,0,0,0,0,0,0,0],count++*20);
        // The volume, collider, current and contact speed set the result.
      }
    }
    if(!count)return;
    const particle=device.createBuffer({size:count*80,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_DST});
    const grid=device.createBuffer({size:GRID*16,usage:GPUBufferUsage.STORAGE});
    const params=device.createBuffer({size:64,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});
    const packed=device.createBuffer({size:count*80,usage:GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_SRC});
    const staging=device.createBuffer({size:count*80,usage:GPUBufferUsage.MAP_READ|GPUBufferUsage.COPY_DST});
    const links=device.createBuffer({size:(count+1)*4,usage:GPUBufferUsage.STORAGE});
    const buffers=[particle,grid,params,packed,links,staging];
    const bindings=[[1],[0,1,2],[0,1,2],[1,2,4],[0,1,2,4],[1],[0,1,2,4],[0,1,2,3,4]];
    const groups=this.pipelines.map((pipeline,i)=>device.createBindGroup({layout:pipeline.getBindGroupLayout(0),entries:bindings[i].map(binding=>({binding,resource:{buffer:buffers[binding]}}))}));
    const values=new Float32Array(16);new Uint32Array(values.buffer)[0]=count;
    values[1]=h;values[2]=STEP;values[4]=flow.u;values[5]=flow.v;
    values.set([40,12+bodyRadius*.85/h,40,bodyRadius],8);
    values.set([flow.u,Math.min(-1,flow.vertical??-Math.sqrt(power)*4),flow.v,0],12);
    const data=new Float32Array(count*20);
    for(let i=0;i<count;i++){for(let k=0;k<8;k++)data[i*20+k]=raw[i*20+k];data[i*20+8]=data[i*20+13]=data[i*20+18]=.64;}
    device.queue.writeBuffer(particle,0,raw,0,count*20);
    this.patches.push({x,z,base,h,age:0,elapsed:0,count,pending:false,disposed:false,buffers,groups,params:values,data,previous:data.slice(),
      sampleAge:0,sampleDelta:STEP,blendElapsed:0,removed:new Uint8Array(count),emerged:new Uint8Array(count)});
  }
  update(dt:number,surface:(x:number,z:number)=>number,depth:(x:number,z:number)=>number,drop:Drop,ripple:(x:number,z:number,s:number)=>void){
    dt=Number.isFinite(dt)?T.MathUtils.clamp(dt,0,.05):0;
    if(this.status==='webgpu'&&dt>0){for(const source of this.sources)this.create(source,surface,depth);this.sources=[];}
    else if(this.status!=='initializing'&&this.status!=='webgpu')this.sources=[];
    let visible=0;
    for(const patch of this.patches){
      if(depth(patch.x,patch.z)<=0){this.destroyPatch(patch);continue;}
      const {data,previous,h}=patch;
      patch.blendElapsed+=dt;
      const blend=Math.min(1,patch.blendElapsed/patch.sampleDelta);
      const at=(index:number)=>previous[index]+(data[index]-previous[index])*blend;
      for(let i=0;i<patch.count;i++){
        const j=i*20;if(patch.removed[i]||data[j+7]<.5)continue;
        const x=patch.x+(at(j)-40)*h,y=patch.base+(at(j+1)-12)*h,z=patch.z+(at(j+2)-40)*h;
        // The submerged reservoir cannot hit the air/water interface yet.
        // Avoid nine height-field samples for every deep interior particle.
        if(y<patch.base-.06&&!patch.emerged[i])continue;
        const level=surface(x,z),vx=data[j+4]*h,vy=data[j+5]*h,vz=data[j+6]*h;
        if(!Number.isFinite(y)||depth(x,z)<=0){this.remove(patch,i);continue;}
        if(y>level+.025)patch.emerged[i]=1;
        if(dt>0&&patch.emerged[i]&&y<level+.003&&vy<0){
          this.remove(patch,i);this.returns++;
          if(i%24===0){ripple(x,z,T.MathUtils.clamp(h*h*h*Math.abs(vy)*600,.000025,.002));this.ripples++;}
          continue;
        }
        // Sparse detached liquid becomes an independent 3D droplet. It is
        // removed from the fluid domain, so its volume is never drawn twice.
        if(dt>0&&data[j+7]<8&&patch.emerged[i]&&patch.age>.08){
          this.remove(patch,i);drop(x,y,z,vx,vy,vz,h*.72);this.released++;continue;
        }
        if(y+h*.55<level)continue;
        this.transform.set(
          at(j+8)*h,at(j+12)*h,at(j+16)*h,x+at(j+11)*h,
          at(j+9)*h,at(j+13)*h,at(j+17)*h,y+at(j+15)*h,
          at(j+10)*h,at(j+14)*h,at(j+18)*h,z+at(j+19)*h,
          0,0,0,1);
        this.mesh.setMatrixAt(visible++,this.transform);
      }
      patch.elapsed=Math.min(.05,patch.elapsed+dt);
      if(dt<=0||patch.pending)continue;
      const steps=Math.min(36,Math.floor(patch.elapsed/STEP));if(!steps)continue;
      patch.elapsed-=steps*STEP;patch.params[3]=patch.age;patch.age+=steps*STEP;
      if(patch.age>1.5){this.destroyPatch(patch);continue;}
      const device=this.device!;device.queue.writeBuffer(patch.buffers[2],0,patch.params);
      const encoder=device.createCommandEncoder();const pass=encoder.beginComputePass();
      for(let k=0;k<steps;k++)for(let stage=0;stage<5;stage++){
        pass.setPipeline(this.pipelines[stage]);pass.setBindGroup(0,patch.groups[stage]);
        pass.dispatchWorkgroups(stage===0||stage===3?GRID/128:Math.ceil(patch.count/64));
      }
      for(let stage=5;stage<8;stage++){
        pass.setPipeline(this.pipelines[stage]);pass.setBindGroup(0,patch.groups[stage]);
        pass.dispatchWorkgroups(stage===5?GRID/128:Math.ceil(patch.count/64));
      }pass.end();
      encoder.copyBufferToBuffer(patch.buffers[3],0,patch.buffers[5],0,patch.count*80);device.queue.submit([encoder.finish()]);
      patch.pending=true;
      void patch.buffers[5].mapAsync(GPUMapMode.READ).then(()=>{
        if(!patch.disposed){
          patch.previous.set(patch.data);patch.data.set(new Float32Array(patch.buffers[5].getMappedRange()));patch.buffers[5].unmap();
          patch.sampleDelta=Math.max(STEP,patch.age-patch.sampleAge);patch.sampleAge=patch.age;patch.blendElapsed=0;
        }
        patch.pending=false;
      }).catch(e=>{if(!patch.disposed){this.error=String(e);this.destroyPatch(patch);}});
    }
    this.patches=this.patches.filter(p=>!p.disposed);this.mesh.count=visible;this.mesh.instanceMatrix.needsUpdate=true;
  }
  private remove(patch:Patch,index:number){patch.removed[index]=1;this.device!.queue.writeBuffer(patch.buffers[0],index*80+28,new Float32Array([0]));}
  private destroyPatch(patch:Patch){patch.disposed=true;for(const buffer of patch.buffers)buffer.destroy();}
  private clear(){for(const patch of this.patches)this.destroyPatch(patch);this.patches=[];this.sources=[];this.mesh.count=0;}
  rebase(shift:T.Vector3){for(const patch of this.patches){patch.x-=shift.x;patch.z-=shift.z;}for(const source of this.sources){source.x-=shift.x;source.z-=shift.z;}}
  dispose(){this.disposed=true;this.clear();this.mesh.geometry.dispose();this.mesh.material.dispose();this.mesh.dispose();this.device?.destroy();}
}
