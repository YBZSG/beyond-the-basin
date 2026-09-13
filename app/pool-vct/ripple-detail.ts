import * as T from 'three';

export const DETAIL_DOMAIN=48;
const STEP=1/120,MAX_SOURCES=128;
const vertexShader='void main(){gl_Position=vec4(position.xy,0,1);}';

/** Independent centimetre-scale height field. It adds visual wave energy,
 * never momentum to the shallow solver or buoyancy readback. */
export class RippleDetail {
  readonly size:number;
  readonly cell:number;
  frequency=22;
  private a:T.WebGLRenderTarget;
  private b:T.WebGLRenderTarget;
  private source:T.WebGLRenderTarget;
  private current:T.WebGLRenderTarget;
  readonly uniform:{value:T.Texture};
  private scene=new T.Scene();private camera=new T.Camera();private quad=new T.PlaneGeometry(2,2);
  private mesh:T.Mesh;private material:T.ShaderMaterial;
  private sourceScene=new T.Scene();private sourceGeometry=new T.InstancedBufferGeometry();private sourceMaterial:T.ShaderMaterial;
  private sources=new Float32Array(MAX_SOURCES*4);private queued:number[]=[];
  private acc=0;private quiet=10;private initialized=false;private needsClear=true;
  private shift=new T.Vector2();
  private copy:T.ShaderMaterial;
  constructor(size:number,depth:{value:T.Texture}){
    this.size=size;this.cell=DETAIL_DOMAIN/size;
    const target=()=>new T.WebGLRenderTarget(size,size,{type:T.HalfFloatType,depthBuffer:false});
    this.a=target();this.b=target();this.source=target();this.current=this.a;this.uniform={value:this.current.texture};
    this.material=new T.ShaderMaterial({glslVersion:T.GLSL3,vertexShader,depthTest:false,depthWrite:false,toneMapped:false,
      uniforms:{field:{value:this.current.texture},depth,source:{value:this.source.texture},sourceOn:{value:0}},
      fragmentShader:`precision highp float;
        uniform sampler2D field,depth,source;uniform float sourceOn;out vec4 result;
        bool wet(ivec2 c){vec2 p=(vec2(c)+.5)*${this.cell}-24.0;return all(greaterThanEqual(c,ivec2(0)))&&all(lessThan(c,ivec2(${size})))&&texture(depth,(p+48.0)/96.0).r>0.0;}
        float neighbour(ivec2 c,float h){return wet(c)?texelFetch(field,c,0).r:h;}
        void main(){ivec2 c=ivec2(gl_FragCoord.xy);if(!wet(c)){result=vec4(0);return;}
          vec2 s=texelFetch(field,c,0).rg;
          float w=neighbour(c-ivec2(1,0),s.r),e=neighbour(c+ivec2(1,0),s.r),n=neighbour(c+ivec2(0,1),s.r),b=neighbour(c-ivec2(0,1),s.r);
          float edge=float(min(min(c.x,c.y),min(${size-1}-c.x,${size-1}-c.y)))*${this.cell};
          float damp=exp(-${STEP}*(1.3+5.0*(1.0-smoothstep(0.0,2.0,edge))));
          float v=(s.g+${STEP*.85*.85/(this.cell*this.cell)}*(w+e+n+b-4.0*s.r))*damp;
          float h=s.r+${STEP}*v+texelFetch(source,c,0).r*sourceOn;
          result=vec4(clamp(h,-.012,.012),clamp(v,-.15,.15),0,0);
        }`});
    this.mesh=new T.Mesh(this.quad,this.material);this.mesh.frustumCulled=false;this.scene.add(this.mesh);
    this.sourceGeometry.index=this.quad.index;this.sourceGeometry.setAttribute('position',this.quad.attributes.position);
    this.sourceGeometry.setAttribute('splat',new T.InstancedBufferAttribute(this.sources,4).setUsage(T.DynamicDrawUsage));
    this.sourceMaterial=new T.ShaderMaterial({uniforms:{depth,frequency:{value:this.frequency}},
      vertexShader:`attribute vec4 splat;varying vec2 p,origin;varying float power,radius;
        void main(){origin=splat.xy;power=splat.z;radius=splat.w;p=splat.xy+position.xy*splat.w*3.0;gl_Position=vec4(p/24.0,0,1);}`,
      fragmentShader:`uniform sampler2D depth;uniform float frequency;varying vec2 p,origin;varying float power,radius;
        void main(){if(texture2D(depth,(p+48.0)/96.0).r<=0.0)discard;
          // Sample the source-to-pixel segment: no direct splash injection through masonry.
          for(int i=1;i<=12;i++)if(texture2D(depth,(mix(origin,p,float(i)/12.0)+48.0)/96.0).r<=0.0)discard;
          vec2 q=(p-origin)/radius;float r=length(q),a=frequency*radius;
          float sinc=r>.0001?sin(a*r)/r:a;
          float packet=((2.0+a*a-r*r)*cos(a*r)+(a-2.0*a*r*r)*sinc)/(2.0+2.0*a*a);
          gl_FragColor=vec4(power*packet*exp(-.5*r*r),0,0,0);}`,
      transparent:true,blending:T.AdditiveBlending,blendSrc:T.OneFactor,blendDst:T.OneFactor,
      depthTest:false,depthWrite:false,toneMapped:false});
    // Use explicit ONE + ONE: RGB energy is independent of alpha=0 in the field.
    this.sourceMaterial.blending=T.CustomBlending;
    const emitter=new T.Mesh(this.sourceGeometry,this.sourceMaterial);emitter.frustumCulled=false;this.sourceScene.add(emitter);
    this.copy=new T.ShaderMaterial({vertexShader,fragmentShader:`uniform sampler2D field,depth;uniform vec2 shift;
      void main(){vec2 uv=(gl_FragCoord.xy+shift)/${size}.0;vec2 p=gl_FragCoord.xy*${this.cell}-24.0;
      gl_FragColor=all(greaterThanEqual(uv,vec2(0)))&&all(lessThanEqual(uv,vec2(1)))&&texture2D(depth,(p+48.0)/96.0).r>0.0?texture2D(field,uv):vec4(0);}`,
      uniforms:{field:{value:this.current.texture},depth,shift:{value:this.shift}},depthTest:false,depthWrite:false,toneMapped:false});
  }
  get active(){return this.quiet<8;}
  impact(x:number,z:number,power:number,radius=.16){
    if(![x,z,power,radius].every(Number.isFinite)||Math.abs(x)>23||Math.abs(z)>23||power<=0)return;
    if(this.queued.length>=MAX_SOURCES*4)return;
    this.queued.push(x,z,Math.min(.006,power),Math.max(this.cell*2,radius));this.quiet=0;
  }
  rebase(x:number,z:number){this.shift.add(new T.Vector2(x/this.cell,z/this.cell));for(let i=0;i<this.queued.length;i+=4){this.queued[i]-=x;this.queued[i+1]-=z;}}
  terrainChanged(){this.initialized=false;}
  frame(renderer:T.WebGLRenderer,dt:number,enabled:boolean){
    const old=renderer.getRenderTarget(),color=renderer.getClearColor(new T.Color()),alpha=renderer.getClearAlpha(),auto=renderer.autoClear;
    renderer.autoClear=false;renderer.setClearColor(0,0);
    try{
      if(this.needsClear){for(const t of [this.a,this.b,this.source]){renderer.setRenderTarget(t);renderer.clear();}this.needsClear=false;}
      if(this.shift.lengthSq()>0||!this.initialized){
        this.copy.uniforms.field.value=this.current.texture;this.mesh.material=this.copy;
        const next=this.current===this.a?this.b:this.a;renderer.setRenderTarget(next);renderer.render(this.scene,this.camera);this.current=next;this.shift.set(0,0);this.initialized=true;
      }
      if(!enabled){
        if(this.active)for(const t of [this.a,this.b]){renderer.setRenderTarget(t);renderer.clear();}
        this.queued.length=0;this.quiet=10;this.acc=0;return;
      }
      const wasActive=this.active;this.quiet+=dt;
      if(!this.active){if(wasActive){for(const t of [this.a,this.b]){renderer.setRenderTarget(t);renderer.clear();}}return;}
      this.acc=Math.min(this.acc+Math.min(dt,8*STEP),8*STEP);if(this.acc+1e-10<STEP)return;
      renderer.setRenderTarget(this.source);renderer.clear();const count=this.queued.length/4;
      if(count){this.sources.set(this.queued);this.sourceGeometry.instanceCount=count;this.sourceGeometry.attributes.splat.needsUpdate=true;
        this.sourceMaterial.uniforms.frequency.value=Math.min(this.frequency,Math.PI/(2*this.cell));renderer.render(this.sourceScene,this.camera);this.queued.length=0;}
      let i=0;this.mesh.material=this.material;
      while(this.acc+1e-10>=STEP&&i<8){
        this.material.uniforms.field.value=this.current.texture;this.material.uniforms.sourceOn.value=i===0&&count?1:0;
        const next=this.current===this.a?this.b:this.a;renderer.setRenderTarget(next);renderer.render(this.scene,this.camera);this.current=next;this.acc-=STEP;i++;
      }
    }finally{this.uniform.value=this.current.texture;renderer.setRenderTarget(old);renderer.setClearColor(color,alpha);renderer.autoClear=auto;}
  }
  dispose(){for(const t of [this.a,this.b,this.source])t.dispose();for(const m of [this.material,this.copy,this.sourceMaterial])m.dispose();this.quad.dispose();this.sourceGeometry.dispose();}
}
