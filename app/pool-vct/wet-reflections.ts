import * as T from 'three';
import { Pass, FullScreenQuad } from 'three/addons/postprocessing/Pass.js';
import type { Measure } from './perf/recording';

/** Current-frame screen-space reflections on the glazed ceramic. The opaque
 * colour/depth already contains moving props; no probe capture or history is
 * used for hits. Off-screen rays retain the existing PBR environment lighting. */
export class WetReflectionPass extends Pass {
  private normals=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType});
  private normalMaterial=new T.MeshNormalMaterial();
  private occluderMaterial=new T.MeshNormalMaterial();
  private reflections=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:false});
  private material:T.ShaderMaterial;
  private composite:T.ShaderMaterial;
  private quad:FullScreenQuad;
  private compositeQuad:FullScreenQuad;
  constructor(private scene:T.Scene,private camera:T.PerspectiveCamera,
    private tiles:Set<T.Material>,color:T.Texture,depth:T.DepthTexture,private measure:Measure){
    super();this.normals.depthTexture=new T.DepthTexture(1,1);
    const tile=[...tiles].find(m=>m instanceof T.MeshPhysicalMaterial) as T.MeshPhysicalMaterial|undefined;
    this.normalMaterial.normalMap=tile?.clearcoatNormalMap??null;
    this.normalMaterial.normalScale.copy(tile?.clearcoatNormalScale??new T.Vector2(.22,.22));
    this.normalMaterial.userData.poolWetNormals={roughness:tile?.roughnessMap,normal:tile?.clearcoatNormalMap,scale:this.normalMaterial.normalScale};
    this.occluderMaterial.userData.poolWetOccluder=true;
    this.normals.texture.minFilter=this.normals.texture.magFilter=T.NearestFilter;
    this.occluderMaterial.onBeforeCompile=shader=>{
      shader.fragmentShader=shader.fragmentShader.replace(/\n}\s*$/,'\n gl_FragColor.a=0.0;\n}');
    };
    this.normalMaterial.onBeforeCompile=shader=>{
      shader.uniforms.wetRoughness={value:tile?.roughnessMap??null};
      shader.vertexShader='varying vec3 wetWorld;\n'+shader.vertexShader;
      shader.vertexShader=shader.vertexShader.replace('#include <project_vertex>',`#include <project_vertex>
        vec4 wetPosition=vec4(transformed,1.0);
        #ifdef USE_INSTANCING
        wetPosition=instanceMatrix*wetPosition;
        #endif
        wetWorld=(modelMatrix*wetPosition).xyz;`);
      shader.fragmentShader='varying vec3 wetWorld;uniform sampler2D wetRoughness;\n'+shader.fragmentShader;
      shader.fragmentShader=shader.fragmentShader.replace('#include <normal_fragment_begin>',`
        vec3 face=abs(normalize(cross(dFdx(wetWorld),dFdy(wetWorld))));
        vec2 plane=face.y>.6?wetWorld.xz:(face.x>.6?wetWorld.zy:wetWorld.xy);
        vec2 tileUv=mat2(.707107,-.707107,.707107,.707107)*plane*1.2;
        ${T.ShaderChunk.normal_fragment_begin.replaceAll('vNormalMapUv','tileUv')}`);
      shader.fragmentShader=shader.fragmentShader.replace('#include <normal_fragment_maps>',T.ShaderChunk.normal_fragment_maps.replaceAll('vNormalMapUv','tileUv'));
      // Alpha carries ceramic roughness; all opaque geometry still writes
      // depth and normals, so props can both occlude and appear in reflections.
      shader.fragmentShader=shader.fragmentShader.replace(/\n}\s*$/,`
        float wet=exp(-max(wetWorld.y-.32,0.0)*.8);
        float drip=.5+.5*sin(plane.x*8.0+sin(plane.x*2.3)+sin(plane.y*.6)*.3);
        gl_FragColor.a=wetWorld.y>.325?clamp(texture2D(wetRoughness,tileUv).g*.28+.08-.065*wet-.025*drip,.09,.38):0.0;
      }`);
    };
    this.material=new T.ShaderMaterial({
      uniforms:{opaque:{value:color},depth:{value:depth},normals:{value:this.normals.texture},
        maskDepth:{value:this.normals.depthTexture},projection:{value:camera.projectionMatrix},inverseView:{value:camera.matrixWorld},
        inverseProjection:{value:camera.projectionMatrixInverse},pixel:{value:new T.Vector2()},debug:{value:0}},
      vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
      fragmentShader:/* glsl */`
        uniform sampler2D opaque,depth,normals,maskDepth;
        uniform mat4 projection,inverseProjection,inverseView;uniform vec2 pixel;
        varying vec2 vUv;
        vec3 viewPosition(vec2 uv,float d){vec4 p=inverseProjection*vec4(uv*2.-1.,d*2.-1.,1.);return p.xyz/p.w;}
        vec2 projectPoint(vec3 p){vec4 q=projection*vec4(p,1.);return q.xy/q.w*.5+.5;}
        void main(){
          vec4 packed=texture2D(normals,vUv);
          float z=texture2D(depth,vUv).r,maskZ=texture2D(maskDepth,vUv).r;
          vec3 P=viewPosition(vUv,z);
          if(packed.a<.05||z>=.99999||abs(viewPosition(vUv,maskZ).z-P.z)>.015-P.z*.001){gl_FragColor=vec4(0.);return;}
          vec3 N=normalize(packed.xyz*2.-1.);
          vec3 V=normalize(-P),R=reflect(-V,N),start=P+N*.025+R*.06;
          float range=R.z>.001?min(24.,(-.1-start.z)/R.z):24.;
          if(range<.1){gl_FragColor=vec4(0.);return;}
          vec3 end=start+R*range;
          float invA=1./(projection*vec4(start,1.)).w,invB=1./(projection*vec4(end,1.)).w;
          vec2 uvA=projectPoint(start),uvB=projectPoint(end);
          // Clip the projected segment before choosing a stride. Near-plane
          // rays can otherwise span thousands of off-screen pixels and skip
          // the visible intersections in large, repeating horizontal bands.
          vec2 delta=uvB-uvA,exitS=vec2(1.);
          if(abs(delta.x)>.000001)exitS.x=((delta.x>0.?.998:.002)-uvA.x)/delta.x;
          if(abs(delta.y)>.000001)exitS.y=((delta.y>0.?.998:.002)-uvA.y)/delta.y;
          float clipped=clamp(min(exitS.x,exitS.y),0.,1.);
          end=mix(start*invA,end*invB,clipped)/mix(invA,invB,clipped);
          invB=1./(projection*vec4(end,1.)).w;uvB=projectPoint(end);
          float steps=clamp(max(abs((uvB-uvA).x/pixel.x),abs((uvB-uvA).y/pixel.y)),8.,160.);
          float previous=0.,previousGap=viewPosition(uvA,texture2D(depth,uvA).r).z-start.z;
          vec2 hit=vec2(0.);float confidence=0.;
          // Perspective-correct screen-space DDA: screen-sized steps cannot
          // leap over a small prop the way fixed world-distance steps did.
          for(int i=0;i<160;i++){
            if(float(i)>=steps)break;
            float s=(float(i)+1.)/steps;vec2 uv=mix(uvA,uvB,s);
            if(any(lessThan(uv,vec2(.002)))||any(greaterThan(uv,vec2(.998))))break;
            vec3 q=mix(start*invA,end*invB,s)/mix(invA,invB,s);
            float d=texture2D(depth,uv).r;
            float gap=viewPosition(uv,d).z-q.z;
            if(d<.99999&&gap>0.&&previousGap<0.){
              float lo=previous,hi=s;
              for(int j=0;j<8;j++){
                float mid=(lo+hi)*.5;vec3 m=mix(start*invA,end*invB,mid)/mix(invA,invB,mid);vec2 u=mix(uvA,uvB,mid);
                if(viewPosition(u,texture2D(depth,u).r).z>m.z)hi=mid;else lo=mid;
              }
              hit=mix(uvA,uvB,hi);
              vec3 hitPosition=mix(start*invA,end*invB,hi)/mix(invA,invB,hi);
              float error=viewPosition(hit,texture2D(depth,hit).r).z-hitPosition.z;
              float distance=length(hitPosition-start);
              vec3 hitNormal=normalize(texture2D(normals,hit).xyz*2.-1.);
              float thickness=.025-hitPosition.z*.001;
              float edge=min(min(hit.x,hit.y),min(1.-hit.x,1.-hit.y));
              confidence=smoothstep(.005,.055,edge)*(1.-smoothstep(23.,31.,distance))
                *(1.-smoothstep(thickness*.5,thickness,error))*smoothstep(.12,.3,distance)
                *step(.05,-dot(hitNormal,R));
              // A silhouette depth jump is not a surface intersection. Reject
              // it, and keep marching rather than accepting a ghost image.
              if(confidence>0.)break;
            }
            previous=s;previousGap=gap;
          }
          vec3 reflected=vec3(0.);
          if(confidence>0.){
            // A small spatial filter softens the glaze without freezing it.
            vec2 blur=pixel*(1.+packed.a*12.);
            reflected=texture2D(opaque,hit).rgb*.5;
            reflected+=(texture2D(opaque,hit+vec2(blur.x,0)).rgb+texture2D(opaque,hit-vec2(blur.x,0)).rgb
              +texture2D(opaque,hit+vec2(0,blur.y)).rgb+texture2D(opaque,hit-vec2(0,blur.y)).rgb)*.125;
            float fresnel=.045+.955*pow(1.-max(dot(N,V),0.),5.);
            float wet=exp(-max((inverseView*vec4(P,1.)).y-.32,0.)*.8);
            confidence*=min(.35,fresnel*.7)*(1.-packed.a)*(.2+.8*wet);
          }
          gl_FragColor=vec4(reflected,confidence);
        }`,depthTest:false,depthWrite:false,toneMapped:false,blending:T.NoBlending,
    });
    this.quad=new FullScreenQuad(this.material);
    this.composite=new T.ShaderMaterial({uniforms:{image:{value:null},reflection:{value:this.reflections.texture},depth:{value:depth},normals:{value:this.normals.texture},inverseProjection:{value:camera.projectionMatrixInverse},size:{value:new T.Vector2()},debug:this.material.uniforms.debug},
      vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
      fragmentShader:/* glsl */`uniform sampler2D image,reflection,depth,normals;uniform mat4 inverseProjection;uniform vec2 size;uniform float debug;varying vec2 vUv;
        float viewZ(vec2 uv){vec4 p=inverseProjection*vec4(uv*2.-1.,texture2D(depth,uv).r*2.-1.,1.);return p.z/p.w;}
        void main(){
          vec3 base=texture2D(image,vUv).rgb;vec4 centre=texture2D(normals,vUv);
          vec2 g=vUv*size-.5,i=floor(g+.5),f=g-i;vec4 sum=vec4(0.);float total=0.,z=viewZ(vUv);
          for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
            vec2 uv=(i+vec2(float(x),float(y))+.5)/size;
            vec4 n=texture2D(normals,uv);
            vec2 offset=vec2(float(x),float(y))-f;float w=exp(-dot(offset,offset)*.9);
            w*=exp(-abs(viewZ(uv)-z)/(.025-z*.002))*pow(max(dot(normalize(centre.xyz*2.-1.),normalize(n.xyz*2.-1.)),0.),24.);
            vec4 r=texture2D(reflection,uv);sum+=vec4(r.rgb*r.a,r.a)*w;total+=w;
          }
          sum/=max(total,.00001);if(centre.a<.05)sum=vec4(0.);
          gl_FragColor=vec4(debug>.5?vec3(sum.a*3.):base*(1.-sum.a)+sum.rgb,1.);
        }`,
      depthTest:false,depthWrite:false,toneMapped:false,blending:T.NoBlending});
    this.compositeQuad=new FullScreenQuad(this.composite);
  }
  debug(on:boolean){this.material.uniforms.debug.value=on?1:0;}
  render(renderer:T.WebGLRenderer,write:T.WebGLRenderTarget,read:T.WebGLRenderTarget){
    const target=renderer.getRenderTarget(),background=this.scene.background,override=this.scene.overrideMaterial;
    const clear=renderer.getClearColor(new T.Color()),alpha=renderer.getClearAlpha(),auto=renderer.autoClear;
    const shadows=renderer.shadowMap.autoUpdate,hidden:T.Object3D[]=[],replaced:[T.Mesh,T.Material|T.Material[]][]=[];
    this.scene.traverse(o=>{
      if(!o.visible)return;
      if(o instanceof T.Points||o instanceof T.Sprite){hidden.push(o);o.visible=false;}
      else if(o instanceof T.Mesh){
        const material=o.material;
        if((Array.isArray(material)?material:[material]).some(m=>m.transparent)){hidden.push(o);o.visible=false;return;}
        replaced.push([o,material]);o.material=this.tiles.has(material as T.Material)?this.normalMaterial:this.occluderMaterial;
      }
    });
    try{
      this.scene.background=null;this.scene.overrideMaterial=null;
      renderer.shadowMap.autoUpdate=false;renderer.autoClear=true;renderer.setClearColor(0,0);
      this.measure('wet-normals',()=>{renderer.setRenderTarget(this.normals);renderer.render(this.scene,this.camera);});
    }finally{
      for(const o of hidden)o.visible=true;
      for(const [mesh,material] of replaced)mesh.material=material;
      this.scene.background=background;this.scene.overrideMaterial=override;
      renderer.setClearColor(clear,alpha);renderer.autoClear=auto;renderer.shadowMap.autoUpdate=shadows;renderer.setRenderTarget(target);
    }
    this.composite.uniforms.image.value=read.texture;
    this.measure('wet-reflection',()=>{
      renderer.setRenderTarget(this.reflections);this.quad.render(renderer);
      renderer.setRenderTarget(this.renderToScreen?null:write);this.compositeQuad.render(renderer);
    });
  }
  setSize(width:number,height:number){const w=Math.max(1,Math.ceil(width/2)),h=Math.max(1,Math.ceil(height/2));this.normals.setSize(width,height);this.reflections.setSize(w,h);this.material.uniforms.pixel.value.set(1/w,1/h);this.composite.uniforms.size.value.set(w,h);}
  dispose(){this.normals.dispose();this.reflections.dispose();this.normalMaterial.dispose();this.occluderMaterial.dispose();this.material.dispose();this.composite.dispose();this.quad.dispose();this.compositeQuad.dispose();}
}
