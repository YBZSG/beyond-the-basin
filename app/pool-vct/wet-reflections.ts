import * as T from 'three';
import { Pass, FullScreenQuad } from 'three/addons/postprocessing/Pass.js';
import type { Measure } from './perf/recording';

/** Current-frame screen-space reflections on the glazed ceramic. The opaque
 * colour/depth already contains moving props; no probe capture or history is
 * used for hits. Off-screen rays retain the existing PBR environment lighting. */
export class WetReflectionPass extends Pass {
  private normals=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType});
  private normalMaterial=new T.MeshNormalMaterial();
  private reflections=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:false});
  private material:T.ShaderMaterial;
  private composite:T.ShaderMaterial;
  private quad:FullScreenQuad;
  private compositeQuad:FullScreenQuad;
  constructor(private scene:T.Scene,private camera:T.PerspectiveCamera,
    private tiles:Set<T.Material>,color:T.Texture,depth:T.DepthTexture,private measure:Measure){
    super();this.normals.depthTexture=new T.DepthTexture(1,1);
    this.normalMaterial.onBeforeCompile=shader=>{
      shader.vertexShader='varying float wetWorldY;\n'+shader.vertexShader;
      shader.vertexShader=shader.vertexShader.replace('#include <project_vertex>',`#include <project_vertex>
        vec4 wetPosition=vec4(transformed,1.0);
        #ifdef USE_INSTANCING
        wetPosition=instanceMatrix*wetPosition;
        #endif
        wetWorldY=(modelMatrix*wetPosition).y;`);
      shader.fragmentShader='varying float wetWorldY;\n'+shader.fragmentShader;
      // Submerged tiles are seen through the separate water optical pass.
      shader.fragmentShader=shader.fragmentShader.replace('void main() {','void main() { if(wetWorldY<.325)discard;');
    };
    this.material=new T.ShaderMaterial({
      uniforms:{opaque:{value:color},depth:{value:depth},normals:{value:this.normals.texture},
        maskDepth:{value:this.normals.depthTexture},projection:{value:camera.projectionMatrix},
        inverseProjection:{value:camera.projectionMatrixInverse},pixel:{value:new T.Vector2()},debug:{value:0}},
      vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
      fragmentShader:/* glsl */`
        uniform sampler2D opaque,depth,normals,maskDepth;
        uniform mat4 projection,inverseProjection;uniform vec2 pixel;
        varying vec2 vUv;
        vec3 viewPosition(vec2 uv,float d){vec4 p=inverseProjection*vec4(uv*2.-1.,d*2.-1.,1.);return p.xyz/p.w;}
        vec2 projectPoint(vec3 p){vec4 q=projection*vec4(p,1.);return q.xy/q.w*.5+.5;}
        void main(){
          vec4 packed=texture2D(normals,vUv);
          float z=texture2D(depth,vUv).r,maskZ=texture2D(maskDepth,vUv).r;
          vec3 P=viewPosition(vUv,z);
          // Half-resolution normal edges are tested in view metres, rather
          // than nonlinear depth units (which rejected near, slanted floors).
          if(packed.a<.5||z>=.99999||abs(viewPosition(vUv,maskZ).z-P.z)>.035-P.z*.006){gl_FragColor=vec4(0.);return;}
          vec3 N=normalize(packed.xyz*2.-1.);
          vec3 V=normalize(-P),R=reflect(-V,N),start=P+N*.04;
          float range=R.z>.001?min(30.,(-.1-start.z)/R.z):30.;
          vec3 end=start+R*range;
          float invA=1./(projection*vec4(start,1.)).w,invB=1./(projection*vec4(end,1.)).w;
          vec2 uvA=projectPoint(start),uvB=projectPoint(end);
          float steps=clamp(length((uvB-uvA)/pixel)*.5,12.,120.);
          float previous=0.,previousGap=-.01;vec2 hit=vec2(0.);float confidence=0.;
          // Perspective-correct screen-space DDA: screen-sized steps cannot
          // leap over a small prop the way fixed world-distance steps did.
          for(int i=0;i<120;i++){
            if(float(i)>=steps)break;
            float s=(float(i)+1.)/steps;vec2 uv=mix(uvA,uvB,s);
            if(any(lessThan(uv,vec2(.002)))||any(greaterThan(uv,vec2(.998))))break;
            vec3 q=mix(start*invA,end*invB,s)/mix(invA,invB,s);
            float d=texture2D(depth,uv).r;
            float gap=viewPosition(uv,d).z-q.z;
            if(d<.99999&&gap>0.&&previousGap<0.){
              float lo=previous,hi=s;
              for(int j=0;j<7;j++){
                float mid=(lo+hi)*.5;vec3 m=mix(start*invA,end*invB,mid)/mix(invA,invB,mid);vec2 u=mix(uvA,uvB,mid);
                if(viewPosition(u,texture2D(depth,u).r).z>m.z)hi=mid;else lo=mid;
              }
              hit=mix(uvA,uvB,hi);
              vec3 hitPosition=mix(start*invA,end*invB,hi)/mix(invA,invB,hi);
              float error=viewPosition(hit,texture2D(depth,hit).r).z-hitPosition.z;
              float distance=length(hitPosition-start);
              float edge=min(min(hit.x,hit.y),min(1.-hit.x,1.-hit.y));
              confidence=smoothstep(.005,.055,edge)*(1.-smoothstep(23.,31.,distance))
                *(1.-smoothstep(.06,.3,error))*smoothstep(.08,.2,distance);break;
            }
            previous=s;previousGap=gap;
          }
          vec3 reflected=vec3(0.);
          if(confidence>0.){
            // A small spatial filter softens the glaze without freezing it.
            reflected=texture2D(opaque,hit).rgb*.5;
            reflected+=(texture2D(opaque,hit+vec2(pixel.x,0)).rgb+texture2D(opaque,hit-vec2(pixel.x,0)).rgb
              +texture2D(opaque,hit+vec2(0,pixel.y)).rgb+texture2D(opaque,hit-vec2(0,pixel.y)).rgb)*.125;
            float fresnel=.045+.955*pow(1.-max(dot(N,V),0.),5.);
            confidence*=min(.58,fresnel*.85);
          }
          gl_FragColor=vec4(reflected,confidence);
        }`,depthTest:false,depthWrite:false,toneMapped:false,blending:T.NoBlending,
    });
    this.quad=new FullScreenQuad(this.material);
    this.composite=new T.ShaderMaterial({uniforms:{image:{value:null},reflection:{value:this.reflections.texture},debug:this.material.uniforms.debug},
      vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
      fragmentShader:'uniform sampler2D image,reflection;uniform float debug;varying vec2 vUv;void main(){vec4 r=texture2D(reflection,vUv);vec3 base=texture2D(image,vUv).rgb;gl_FragColor=vec4(debug>.5?vec3(r.a*2.):base*(1.-r.a*.45)+r.rgb*r.a,1.);}',
      depthTest:false,depthWrite:false,toneMapped:false,blending:T.NoBlending});
    this.compositeQuad=new FullScreenQuad(this.composite);
  }
  debug(on:boolean){this.material.uniforms.debug.value=on?1:0;}
  render(renderer:T.WebGLRenderer,write:T.WebGLRenderTarget,read:T.WebGLRenderTarget){
    const target=renderer.getRenderTarget(),background=this.scene.background,override=this.scene.overrideMaterial;
    const clear=renderer.getClearColor(new T.Color()),alpha=renderer.getClearAlpha(),auto=renderer.autoClear;
    const shadows=renderer.shadowMap.autoUpdate,hidden:T.Object3D[]=[];
    this.scene.traverse(o=>{
      if(o.visible&&((o instanceof T.Mesh&&!this.tiles.has(o.material as T.Material))||o instanceof T.Points||o instanceof T.Sprite)){
        hidden.push(o);o.visible=false;
      }
    });
    try{
      this.scene.background=null;this.scene.overrideMaterial=this.normalMaterial;
      renderer.shadowMap.autoUpdate=false;renderer.autoClear=true;renderer.setClearColor(0,0);
      this.measure('wet-normals',()=>{renderer.setRenderTarget(this.normals);renderer.render(this.scene,this.camera);});
    }finally{
      for(const o of hidden)o.visible=true;
      this.scene.background=background;this.scene.overrideMaterial=override;
      renderer.setClearColor(clear,alpha);renderer.autoClear=auto;renderer.shadowMap.autoUpdate=shadows;renderer.setRenderTarget(target);
    }
    this.composite.uniforms.image.value=read.texture;
    this.measure('wet-reflection',()=>{
      renderer.setRenderTarget(this.reflections);this.quad.render(renderer);
      renderer.setRenderTarget(this.renderToScreen?null:write);this.compositeQuad.render(renderer);
    });
  }
  setSize(width:number,height:number){const w=Math.max(1,Math.ceil(width/2)),h=Math.max(1,Math.ceil(height/2));this.normals.setSize(w,h);this.reflections.setSize(w,h);this.material.uniforms.pixel.value.set(1.5/width,1.5/height);}
  dispose(){this.normals.dispose();this.reflections.dispose();this.normalMaterial.dispose();this.material.dispose();this.composite.dispose();this.quad.dispose();this.compositeQuad.dispose();}
}
