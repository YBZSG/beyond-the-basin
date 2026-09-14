import * as T from 'three';
import { Pass, FullScreenQuad } from 'three/addons/postprocessing/Pass.js';
import { WATER_WAVES } from './water-optics.ts';

const VERTEX='varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}';
/** Screen-space reconstruction of simulated liquid. Depth is rasterized
 * from real sphere geometry, filtered within a narrow depth range and then
 * shaded as one surface. The source particles are never drawn as beads. */
export class LiquidSurfacePass extends Pass {
  private fluidScene=new T.Scene();
  private depth=new T.WebGLRenderTarget(1,1,{type:T.FloatType,minFilter:T.NearestFilter,magFilter:T.NearestFilter});
  private filterA=new T.WebGLRenderTarget(1,1,{type:T.FloatType,depthBuffer:false,minFilter:T.NearestFilter,magFilter:T.NearestFilter});
  private filterB=this.filterA.clone();
  private background=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:false});
  private filter=new T.ShaderMaterial({
    uniforms:{source:{value:null},texel:{value:new T.Vector2()},direction:{value:new T.Vector2(1,0)},projectionScale:{value:500}},
    vertexShader:VERTEX,
    // Narrow-range filtering after Truong & Yuksel / Splash. Foreground
    // discontinuities are rejected; a distant sample is clamped rather than
    // pulling the surface backwards into a thick blurred blob.
    fragmentShader:`uniform sampler2D source;uniform vec2 texel,direction;uniform float projectionScale;varying vec2 vUv;
    void main(){float centre=texture2D(source,vUv).r;if(centre>9000.){gl_FragColor=vec4(10000,0,0,1);return;}
      float radius=clamp(projectionScale*.018/centre,1.,6.),sum=centre,weight=1.;
      for(int side=-1;side<=1;side+=2){float lo=centre-.035,hi=centre+.035;
        for(int k=1;k<=6;k++){if(float(k)>radius)break;
          float d=texture2D(source,vUv+direction*texel*float(k*side)).r;
          if(d<lo)break;float w=exp(-float(k*k)/(radius*radius*.5));
          if(d>hi){d=centre+.012;}else{lo=min(lo,d-.035);hi=max(hi,d+.035);}
          sum+=w*d;weight+=w;
        }
      }gl_FragColor=vec4(sum/weight,0,0,1);
    }`,depthTest:false,depthWrite:false,toneMapped:false,
  });
  private copy=new T.ShaderMaterial({uniforms:{image:{value:null}},vertexShader:VERTEX,
    fragmentShader:'uniform sampler2D image;varying vec2 vUv;void main(){gl_FragColor=texture2D(image,vUv);}',depthWrite:false,depthTest:false,toneMapped:false});
  private shade:T.ShaderMaterial;
  private quad=new FullScreenQuad(this.copy);
  private camera:T.PerspectiveCamera;
  private scene:T.Scene;
  private mesh:T.InstancedMesh;
  constructor(scene:T.Scene,camera:T.PerspectiveCamera,mesh:T.InstancedMesh,waterUniforms:Record<string,T.IUniform>){
    super();this.needsSwap=false;this.scene=scene;this.camera=camera;this.mesh=mesh;this.fluidScene.add(mesh);
    this.fluidScene.background=new T.Color(10000,0,0);
    this.shade=new T.ShaderMaterial({
      uniforms:{...waterUniforms,fluidDepth:{value:null},background:{value:this.background.texture},texel:{value:new T.Vector2()},
        inverseProjection:{value:camera.projectionMatrixInverse},projection:{value:camera.projectionMatrix},cameraWorld:{value:camera.matrixWorld},
        environment:{value:null},hasEnvironment:{value:0}},
      defines:{ENVMAP_TYPE_CUBE_UV:'',CUBEUV_TEXEL_WIDTH:1/768,CUBEUV_TEXEL_HEIGHT:1/1024,CUBEUV_MAX_MIP:'8.0'},
      vertexShader:VERTEX,
      fragmentShader:WATER_WAVES+`
        uniform sampler2D fluidDepth,background,environment;uniform vec2 texel;
        uniform mat4 inverseProjection,projection,cameraWorld;uniform float hasEnvironment;
        varying vec2 vUv;
        #include <common>
        #include <cube_uv_reflection_fragment>
        vec3 eyePosition(vec2 uv,float depth){vec4 p=inverseProjection*vec4(uv*2.-1.,1,1);return p.xyz*(-depth/p.z);}
        void main(){
          float d=texture2D(fluidDepth,vUv).r;if(d>9000.)discard;
          vec3 p=eyePosition(vUv,d),world=(cameraWorld*vec4(p,1)).xyz;
          float level=.32+poolHeightSmooth(world.xz);
          if(world.y<level-.002||poolRestDepth(world.xz)<=0.)discard;
          float dl=texture2D(fluidDepth,vUv-vec2(texel.x,0)).r,dr=texture2D(fluidDepth,vUv+vec2(texel.x,0)).r;
          float db=texture2D(fluidDepth,vUv-vec2(0,texel.y)).r,dt=texture2D(fluidDepth,vUv+vec2(0,texel.y)).r;
          vec3 dx=abs(dr-d)<abs(dl-d)?eyePosition(vUv+vec2(texel.x,0),dr)-p:p-eyePosition(vUv-vec2(texel.x,0),dl);
          vec3 dy=abs(dt-d)<abs(db-d)?eyePosition(vUv+vec2(0,texel.y),dt)-p:p-eyePosition(vUv-vec2(0,texel.y),db);
          vec3 normal=normalize(cross(dx,dy)),V=normalize(-p);
          if(dot(normal,V)<0.)normal=-normal;
          float F=.020373+.979627*pow(1.-clamp(dot(normal,V),0.,1.),5.);
          vec3 R=mat3(cameraWorld)*reflect(-V,normal);
          vec3 reflected=hasEnvironment>.5?textureCubeUV(environment,R,.07).rgb:vec3(.3,.4,.43);
          vec3 refracted=refract(-V,normal,1./1.333);
          vec2 offset=(refracted.xy+V.xy)*.045/max(d,.4);
          vec3 transmitted=texture2D(background,clamp(vUv+offset,vec2(.001),vec2(.999))).rgb;
          vec3 color=transmitted*(1.-F)+reflected*F;
          // Reflection and refraction use this reconstructed surface normal.
          // There is no painted film outline or repeated hole pattern.
          float join=smoothstep(-.002,.012,world.y-level);
          color=mix(texture2D(background,vUv).rgb,color,join);
          vec4 clip=projection*vec4(p,1);gl_FragDepth=clip.z/clip.w*.5+.5;
          gl_FragColor=vec4(color,1);
        }`,toneMapped:false,depthTest:true,depthWrite:true,
    });
  }
  render(renderer:T.WebGLRenderer,_write:T.WebGLRenderTarget,read:T.WebGLRenderTarget){
    if(!this.mesh.count)return;
    const auto=renderer.autoClear,shadows=renderer.shadowMap.autoUpdate,target=renderer.getRenderTarget();
    try{
      renderer.shadowMap.autoUpdate=false;
      renderer.autoClear=true;renderer.setRenderTarget(this.depth);renderer.render(this.fluidScene,this.camera);
      renderer.autoClear=false;this.quad.material=this.filter;
      this.filter.uniforms.projectionScale.value=this.depth.height*this.camera.projectionMatrix.elements[5]*.5;
      let source=this.depth.texture;
      for(let i=0;i<4;i++){
        const output=i%2===0?this.filterA:this.filterB;
        this.filter.uniforms.source.value=source;this.filter.uniforms.direction.value.set(i%2===0?1:0,i%2===0?0:1);
        renderer.setRenderTarget(output);this.quad.render(renderer);source=output.texture;
      }
      this.quad.material=this.copy;this.copy.uniforms.image.value=read.texture;
      renderer.setRenderTarget(this.background);this.quad.render(renderer);
      const env=this.scene.environment;
      if(env){
        this.shade.uniforms.environment.value=env;this.shade.uniforms.hasEnvironment.value=1;
        const {width,height}=env.image as {width:number;height:number};
        const mip=Math.log2(height/4);
        if(this.shade.defines.CUBEUV_TEXEL_WIDTH!==1/width){
          Object.assign(this.shade.defines,{CUBEUV_TEXEL_WIDTH:1/width,CUBEUV_TEXEL_HEIGHT:1/height,CUBEUV_MAX_MIP:mip.toFixed(1)});this.shade.needsUpdate=true;
        }
      }
      this.shade.uniforms.fluidDepth.value=source;this.quad.material=this.shade;
      renderer.setRenderTarget(read);this.quad.render(renderer);
    }finally{renderer.autoClear=auto;renderer.shadowMap.autoUpdate=shadows;renderer.setRenderTarget(target);}
  }
  setSize(width:number,height:number){
    for(const target of [this.depth,this.filterA,this.filterB,this.background])target.setSize(width,height);
    this.filter.uniforms.texel.value.set(1/width,1/height);this.shade.uniforms.texel.value.set(1/width,1/height);
  }
  dispose(){for(const target of [this.depth,this.filterA,this.filterB,this.background])target.dispose();this.filter.dispose();this.shade.dispose();this.copy.dispose();this.quad.dispose();}
}
