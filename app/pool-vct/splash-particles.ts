import * as T from 'three';

const MAX_PARTICLES=1024;
type Flow={u:number;v:number};
type Particle={
  x:number;y:number;z:number;vx:number;vy:number;vz:number;
  life:number;max:number;kind:number;seed:number;size:number;surface?:number;
};

/** Secondary whitewater after Ihmsen et al. (2012), adapted to a height
 * field. Airborne drops and submerged air use instanced geometry.
 * See docs/whitewater.md for the approximation and rendering boundaries. */
export class SplashParticles {
  readonly aboveWater=new T.Group();
  readonly drops:T.InstancedMesh<T.SphereGeometry,T.MeshPhysicalMaterial>;
  readonly submerged:T.InstancedMesh<T.SphereGeometry,T.MeshPhysicalMaterial>;
  get count(){return this.parts.length;}
  get live(){return this.parts;}
  get stats(){return {spray:this.parts.filter(p=>p.kind===0).length,bubbles:this.parts.filter(p=>p.kind===1).length};}
  ripples=0;
  private parts:Particle[]=[];
  private transform=new T.Object3D();
  private velocity=new T.Vector3();
  private up=new T.Vector3(0,1,0);
  private viewport=new T.Vector4();
  private mainCamera:T.Camera|null=null;
  private optical={
    viewport:{value:new T.Vector2(1280,720)},renderOptics:{value:0},
    sceneColor:{value:null},sceneReady:{value:0},
  } as Record<string,T.IUniform>;

  constructor(){
    const dropMaterial=new T.MeshPhysicalMaterial({
      color:0xffffff,roughness:.065,metalness:0,ior:1.333,envMapIntensity:1,
      transparent:true,opacity:.94,depthWrite:true,
    });
    // Keep Three's physical lighting, actual mesh normals and hardware depth.
    // Reuse the pool's HDR scene capture for transmission; a separate built-in
    // transmission pass would render before our transparent water.
    dropMaterial.onBeforeCompile=shader=>{
      Object.assign(shader.uniforms,this.optical);
      shader.vertexShader='varying float dropDiameter;\n'+shader.vertexShader;
      shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>',`
        #include <begin_vertex>
        dropDiameter=length(instanceMatrix[0].xyz)*2.0;
      `);
      shader.fragmentShader=`
        uniform sampler2D sceneColor;uniform vec2 viewport;uniform float sceneReady,renderOptics;
        varying float dropDiameter;
      `+shader.fragmentShader;
      shader.fragmentShader=shader.fragmentShader.replace('#include <opaque_fragment>',`
        float facing=clamp(dot(normal,geometryViewDir),0.0,1.0);
        float fresnel=.020373+.979627*pow(1.0-facing,5.0);
        if(sceneReady>.5&&renderOptics>.5){
          vec2 screen=gl_FragCoord.xy/viewport;
          vec2 bend=normal.xy*dropDiameter*.15/max(.15,vViewPosition.z);
          vec3 transmitted=texture2D(sceneColor,clamp(screen+bend,vec2(.001),vec2(.999))).rgb;
          outgoingLight=transmitted*(1.0-fresnel)+totalSpecular;
        }else{
          diffuseColor.a=clamp(fresnel,.06,.9);
          outgoingLight=totalSpecular/max(diffuseColor.a,.001);
        }
        #include <opaque_fragment>
      `);
    };
    dropMaterial.customProgramCacheKey=()=>'whitewater-mesh-transmission-v1';
    this.drops=new T.InstancedMesh(new T.SphereGeometry(1,12,8),dropMaterial,MAX_PARTICLES);
    this.drops.name='Water droplets (3D)';
    this.drops.onBeforeRender=(renderer,_scene,camera)=>{
      renderer.getCurrentViewport(this.viewport);
      this.optical.viewport.value.set(this.viewport.z,this.viewport.w);
      this.optical.renderOptics.value=+(camera===this.mainCamera);
    };

    this.submerged=new T.InstancedMesh(new T.SphereGeometry(1,8,6),new T.MeshPhysicalMaterial({
      color:0xc6e5e6,roughness:.1,metalness:0,ior:1.333,envMapIntensity:1.2,
      transparent:true,opacity:.26,depthWrite:false,
    }),MAX_PARTICLES);
    this.submerged.name='Entrained air';
    for(const mesh of [this.drops,this.submerged]){
      mesh.count=0;mesh.frustumCulled=false;mesh.instanceMatrix.setUsage(T.DynamicDrawUsage);
    }
    // Bubbles go into the scene capture and are overwritten by the water in
    // the main pass. Drawing them afterwards would display each bubble twice.
    this.submerged.renderOrder=-1;this.drops.renderOrder=3;
    this.aboveWater.add(this.drops);
  }

  attachSurface(uniforms:Record<string,T.IUniform>,camera:T.Camera){
    for(const key of ['sceneColor','sceneReady'])if(key in uniforms)this.optical[key]=uniforms[key];
    this.mainCamera=camera;
  }
  attachTransmission(color:T.IUniform,ready:T.IUniform){this.optical.sceneColor=color;this.optical.sceneReady=ready;}

  private add(p:Particle){if(this.parts.length>=MAX_PARTICLES)this.parts.shift();this.parts.push(p);}

  /** Only detached liquid from the fluid simulation may become a spray drop. */
  release(x:number,y:number,z:number,vx:number,vy:number,vz:number,size:number){
    if(![x,y,z,vx,vy,vz,size].every(Number.isFinite)||size<=0)return;
    this.add({x,y,z,vx,vy,vz,size:Math.min(.025,size),life:0,max:2,kind:0,seed:x*7+z*13});
  }

  bubbles(x:number,y:number,z:number,count:number,flow:Flow={u:0,v:0}){
    if(![x,y,z,count,flow.u,flow.v].every(Number.isFinite))return;
    for(let i=0;i<Math.min(96,count);i++){
      const angle=Math.random()*Math.PI*2,r=Math.sqrt(Math.random())*.18;
      this.add({x:x+Math.cos(angle)*r,y:y-.04-Math.random()*.28,z:z+Math.sin(angle)*r,
        vx:flow.u,vy:-.05-Math.random()*.18,vz:flow.v,life:0,max:3,kind:1,seed:Math.random()*7,size:.004+.01*Math.random()});
    }
  }

  update(dt:number,surface:(x:number,z:number)=>number,ripple:(x:number,z:number,strength:number)=>void,
    flowAt:(x:number,z:number)=>Flow=()=>({u:0,v:0}),depthAt:(x:number,z:number)=>number=()=>1){
    dt=Number.isFinite(dt)?Math.max(0,Math.min(dt,.05)):0;
    const list=this.parts;let w=0;
    for(let r=0;r<list.length;r++){
      const p=list[r];p.life+=dt;
      if(p.life>p.max)continue;
      const ox=p.x,oy=p.y,oz=p.z;
      if(p.kind===0){p.vy-=9.81*dt;const drag=Math.exp(-dt*.45);p.vx*=drag;p.vz*=drag;}
      else{
        const flow=flowAt(p.x,p.z),drag=1-Math.exp(-dt*5);
        p.vx+=(flow.u-p.vx)*drag;p.vz+=(flow.v-p.vz)*drag;
        if(p.kind===1)p.vy+=(.24-p.vy)*(1-Math.exp(-dt*4));
      }
      p.x+=p.vx*dt;p.z+=p.vz*dt;
      if(depthAt(p.x,p.z)<=0){p.x=ox;p.z=oz;p.vx*=.1;p.vz*=.1;if(depthAt(ox,oz)<=0)continue;}
      const s=surface(p.x,p.z);
      p.y+=p.vy*dt;
        if(p.kind===0&&p.y-p.size*.5<=s&&(p.vy<0||oy-p.size*.5>(p.surface??surface(ox,oz)))){
          // Swept contact against the moving height field, including the
          // drop radius. Interpolate the last water height in time and solve
          // along the segment so fast drops do not ripple at an overshoot.
          const startNow=surface(ox,oz),previous=p.surface??startNow;
          let lo=0,hi=1;
          for(let j=0;j<7;j++){
            const t=(lo+hi)*.5,x=ox+(p.x-ox)*t,z=oz+(p.z-oz)*t;
            const height=surface(x,z)+(previous-startNow)*(1-t);
            if(oy+(p.y-oy)*t-p.size*.5>height)lo=t;else hi=t;
          }
          const t=(lo+hi)*.5;
          const waterRise=dt>0?(s-previous)/dt:0;
          ripple(ox+(p.x-ox)*t,oz+(p.z-oz)*t,Math.min(.0025,Math.max(.000025,220*p.size*p.size*p.size*Math.max(.1,waterRise-p.vy))));
          this.ripples++;
          continue;
        }
        if(p.kind===1&&p.y>=s-.006){
          ripple(p.x,p.z,.0001);this.ripples++;
          continue;
        }
      p.surface=s;list[w++]=p;
    }
    list.length=w;
    this.drops.count=this.submerged.count=0;
    for(const p of list){
      const r=p.size*.5;
      this.transform.position.set(p.x,p.y,p.z);this.transform.quaternion.identity();
      if(p.kind===0){
        this.velocity.set(p.vx,p.vy,p.vz);
        const speed=this.velocity.length(),stretch=1+Math.min(.65,speed*speed*.045)*(.8+.2*Math.sin(p.life*32+p.seed));
        if(speed>.001)this.transform.quaternion.setFromUnitVectors(this.up,this.velocity.divideScalar(speed));
        this.transform.scale.set(r/Math.sqrt(stretch),r*stretch,r/Math.sqrt(stretch));
      }else this.transform.scale.set(r,r,r);
      this.transform.updateMatrix();
      const mesh=p.kind===0?this.drops:this.submerged;
      mesh.setMatrixAt(mesh.count++,this.transform.matrix);
    }
    for(const mesh of [this.drops,this.submerged])mesh.instanceMatrix.needsUpdate=true;
  }

  dispose(){for(const mesh of [this.drops,this.submerged]){mesh.geometry.dispose();mesh.material.dispose();mesh.dispose();}}
  rebase(shift:T.Vector3){for(const p of this.parts){p.x-=shift.x;p.y-=shift.y;p.z-=shift.z;if(p.surface!==undefined)p.surface-=shift.y;}}
}
