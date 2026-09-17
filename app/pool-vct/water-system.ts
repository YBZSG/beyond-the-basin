import * as T from 'three';
import type { Water } from 'three/addons/objects/Water.js';
import type { Solid, Lamp } from './world';
import { shaderStructs, shaderIntersectFunction } from 'three-mesh-bvh';
import type { ReflectionField } from './rt';
import { ShallowWater, SW_PHYS, SW_PHYS_CELL, SW_HALF, crestPower, crestFoamPower } from './shallow-water.ts';
import { RippleDetail } from './ripple-detail.ts';
import { WATER_WAVES, WATER_FRAGMENT } from './water-optics.ts';
import { WATER_SETTINGS_DEFAULT, WATER_QUALITY, sanitizeWaterSettings, type WaterSettings } from './water-settings.ts';
export { WATER_WAVES, WATER_SETTINGS_DEFAULT };
export type { WaterSettings };
import type { Collider } from './physics';

export function rayBlocked(start:T.Vector3,end:T.Vector3,solids:Solid[]) {
  const dx=end.x-start.x,dy=end.y-start.y,dz=end.z-start.z;
  for(const b of solids){
    let near=0,far=1;
    if(dx>-1e-8&&dx<1e-8){if(start.x<b.min.x||start.x>b.max.x)continue;}
    else{const a=(b.min.x-start.x)/dx,c=(b.max.x-start.x)/dx;if(a<c){if(a>near)near=a;if(c<far)far=c;}else{if(c>near)near=c;if(a<far)far=a;}}
    if(dy>-1e-8&&dy<1e-8){if(start.y<b.min.y||start.y>b.max.y)continue;}
    else{const a=(b.min.y-start.y)/dy,c=(b.max.y-start.y)/dy;if(a<c){if(a>near)near=a;if(c<far)far=c;}else{if(c>near)near=c;if(a<far)far=a;}}
    if(dz>-1e-8&&dz<1e-8){if(start.z<b.min.z||start.z>b.max.z)continue;}
    else{const a=(b.min.z-start.z)/dz,c=(b.max.z-start.z)/dz;if(a<c){if(a>near)near=a;if(c<far)far=c;}else{if(c>near)near=c;if(a<far)far=a;}}
    if(near<=far&&near<.995&&far>.005)return true;
  }
  return false;
}

/** Refractive caustics, not a scrolling texture: forward-project a tessellated
 * wave surface through Snell's law, accumulate transmitted irradiance scaled by
 * the source/receiver area Jacobian into HDR atlases. The 2048² floor target
 * and a 2048×1024 wall atlas (four strips, +X/-X/+Z/-Z) let refracted light
 * climb the tiled walls below the waterline. Wave heights come from the
 * shallow-water state texture, so every splash, reflection and diffraction the
 * solver produces is traced. */
export class InteractiveWater {
  static WALL_LOW=-.75; static WALL_HIGH=14.5;
  /** The shallow-water solver; exposed for diagnostics and tests. */
  swe=new ShallowWater();
  private settings={...WATER_SETTINGS_DEFAULT};
  private detailDepth={value:this.swe.uniforms.poolDepth.value as T.Texture};
  private detail=new RippleDetail(WATER_QUALITY.High.ripple,this.detailDepth);
  uniforms={poolSurface:{value:this.swe.uniforms.poolSurface.value},poolDepth:this.detailDepth,poolDetail:{value:this.detail.uniform.value},
    poolCell:{value:this.swe.cell},detailCell:{value:this.detail.cell},poolTime:{value:0},microOrigin:{value:new T.Vector2()},blockCount:{value:0},causticResolution:{value:1024}};
  private tuning:Record<string,{value:number}>=Object.fromEntries(Object.entries(WATER_SETTINGS_DEFAULT).filter(([,v])=>typeof v==='number').map(([k,v])=>[k,{value:v as number}]));
  private layers:Record<string,{value:number}>=Object.fromEntries(['simulation','ripples','micro','refraction','reflection','absorption','fresnel','waterline','foam'].map(k=>[k+'On',{value:1}]));
  private terrain:Collider[]=[];
  private blocks:T.Vector4[]|null=null;
  private opaque=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:true});
  private optics={sceneColor:{value:this.opaque.texture},sceneDepth:{value:null as T.DepthTexture|null},sceneReady:{value:0},cameraNear:{value:.08},cameraFar:{value:100},reflectionSize:{value:768}};
  private lastEnvironment=0;
  private clearColor=new T.Color();
  private renderSize=new T.Vector2();
  private causticFrames=0;
  private captureFrames=0;
  private wavePush=WATER_SETTINGS_DEFAULT.wavePush;
  private waterRef:Water|null=null;
  causticUniforms={poolCaustics:{value:null as T.Texture|null},poolCausticsWalls:{value:null as T.Texture|null},causticGain:{value:1.5},waterLightPower:{value:1}};
  target=new T.WebGLRenderTarget(2048,2048,{type:T.HalfFloatType,depthBuffer:false,generateMipmaps:true,minFilter:T.LinearMipmapLinearFilter,magFilter:T.LinearFilter});
  wallTarget=new T.WebGLRenderTarget(2048,2048,{type:T.HalfFloatType,depthBuffer:false,generateMipmaps:true,minFilter:T.LinearMipmapLinearFilter,magFilter:T.LinearFilter});
  private scene=new T.Scene();
  private wallScene=new T.Scene();
  private camera=new T.Camera();
  private geometry=new T.PlaneGeometry(32,32,384,384);
  private filterTarget=new T.WebGLRenderTarget(2048,2048,{type:T.HalfFloatType,depthBuffer:false});
  private filterScene=new T.Scene();
  private filterMaterial=new T.ShaderMaterial({
    uniforms:{source:{value:null as T.Texture|null},stepSize:{value:new T.Vector2()},strips:{value:1}},
    vertexShader:'varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0,1);}',
    fragmentShader:`uniform sampler2D source;uniform vec2 stepSize;uniform float strips;varying vec2 vUv;
      vec3 sampleLight(vec2 uv){float lo=floor(vUv.y*strips)/strips;uv.y=clamp(uv.y,lo+.00025,lo+1.0/strips-.00025);return texture2D(source,uv).rgb;}
      void main(){vec3 c=sampleLight(vUv)*.227027;
        c+=(sampleLight(vUv+stepSize*1.384615)+sampleLight(vUv-stepSize*1.384615))*.316216;
        c+=(sampleLight(vUv+stepSize*3.230769)+sampleLight(vUv-stepSize*3.230769))*.070270;
        gl_FragColor=vec4(c,1);}`,
    depthTest:false,depthWrite:false,
  });
  private wallGeometries:T.PlaneGeometry[]=[];
  private materials:T.ShaderMaterial[]=[];
  private masks:T.DataTexture[]=[];
  private dirty=true;
  private lastActive=false;
  private lastTime:number|null=null;
  private tracingReady:{value:number}|null=null;
  private lastReady=-1;
  private causticAge=0;
  /** Frames since the last refraction (opaque-scene) capture, for throttling. */
  private refractionAge=Infinity;
  /** Last value of `refractionRefresh`, so a change can invalidate the cache. */
  private lastRefractionRefresh=-1;
  interactionCount=0;
  private static wallDefs=[
    {normal:new T.Vector3(-1,0,0),strip:0,rotY:-Math.PI/2,shift:[16,0]},
    {normal:new T.Vector3(1,0,0),strip:1,rotY:Math.PI/2,shift:[-16,0]},
    {normal:new T.Vector3(0,0,-1),strip:2,rotY:0,shift:[0,16]},
    {normal:new T.Vector3(0,0,1),strip:3,rotY:Math.PI,shift:[0,-16]},
  ];
  constructor(){
    this.opaque.depthTexture=new T.DepthTexture(1,1);this.optics.sceneDepth.value=this.opaque.depthTexture;
    this.filterScene.add(new T.Mesh(new T.PlaneGeometry(2,2),this.filterMaterial));
    this.causticUniforms.poolCaustics.value=this.target.texture;
    this.causticUniforms.poolCausticsWalls.value=this.wallTarget.texture;
    const maskSize=256;
    for(const x of [-9,8]) {
      const visibility=new T.DataTexture(new Uint8Array(maskSize*maskSize).fill(255),maskSize,maskSize,T.RedFormat);
      visibility.minFilter=visibility.magFilter=T.LinearFilter;visibility.needsUpdate=true;this.masks.push(visibility);
      const shared={...this.uniforms,...this.tuning,...this.layers,visibilityMap:{value:visibility},lampPosition:{value:new T.Vector3(x,7.3,-5)},lampPower:{value:95}};
      const floorMat=new T.ShaderMaterial({
        uniforms:{...shared},
        vertexShader:WATER_WAVES+/* glsl */`
          uniform vec3 lampPosition;uniform float lampPower;varying vec2 sourcePoint;varying float powerAtSurface;
          void main(){
            vec2 p=position.xy;float height=.32+poolSurfaceHeight(p);
            vec3 incoming=normalize(vec3(p.x,height,p.y)-lampPosition);
            vec3 n=poolNormal(p);
            vec3 transmitted=refract(incoming,n,1.0/1.333);
            float bed=.32-poolRestDepth(p);
            vec2 receiver=p+transmitted.xz*((bed-height)/transmitted.y);
            bed=.32-poolRestDepth(receiver);
            receiver=p+transmitted.xz*((bed-height)/transmitted.y);
            sourcePoint=p;
            float distance2=dot(vec3(p.x,height,p.y)-lampPosition,vec3(p.x,height,p.y)-lampPosition);
            // 2% Fresnel reflection at normal incidence, Beer absorption through water.
            powerAtSurface=lampPower/(distance2+1.0)*max(dot(-incoming,n),0.0)*.98*exp(-.11*max(height-bed,0.0));
            // Rays leaving the 32m atlas cell clamp to its faded boundary.
            receiver=clamp(receiver,vec2(-16.0),vec2(16.0));
            gl_Position=vec4(receiver.x/16.0,receiver.y/16.0,0.0,1.0);
          }
        `,
        fragmentShader:/* glsl */`
          uniform sampler2D visibilityMap;uniform float causticResolution;varying vec2 sourcePoint;varying float powerAtSurface;
          void main(){
            vec2 dx=dFdx(sourcePoint),dy=dFdy(sourcePoint);
            float sourceArea=abs(dx.x*dy.y-dx.y*dy.x);
            float focus=clamp(sourceArea/(32.0*32.0/(causticResolution*causticResolution)),0.0,9.0);
            float visibility=texture2D(visibilityMap,sourcePoint/32.0+.5).r;
            float light=focus*powerAtSurface*visibility;
            gl_FragColor=vec4(vec3(light)*vec3(.73,.91,1.0),1.0);
          }
        `,
        depthTest:false,depthWrite:false,transparent:true,blending:T.AdditiveBlending,side:T.DoubleSide,
      });
      this.materials.push(floorMat);const mesh=new T.Mesh(this.geometry,floorMat);mesh.frustumCulled=false;this.scene.add(mesh);
      for(const def of InteractiveWater.wallDefs)for(const reflected of [false,true]){
        // Emit from the horizontal water surface. A vertical source collapses
        // to a line in XZ and produces a degenerate, displaced wall atlas.
        const geometry=new T.PlaneGeometry(32,32,192,192);
        geometry.rotateX(-Math.PI/2);
        this.wallGeometries.push(geometry);
        const wallMat=new T.ShaderMaterial({
          uniforms:{...shared,wallNormal:{value:def.normal},wallOffset:{value:-15.7},wallStrip:{value:def.strip},reflected:{value:reflected?1:0}},
          vertexShader:WATER_WAVES+/* glsl */`
            uniform vec3 lampPosition;uniform float lampPower;uniform vec3 wallNormal;uniform float wallOffset;uniform float wallStrip;uniform float reflected;
            varying vec2 sourcePoint;varying float powerAtSurface;varying vec2 wallCell;
            void main(){
              vec2 p=(modelMatrix*vec4(position,1.0)).xz;
              float height=.32+poolSurfaceHeight(p);
              vec3 S=vec3(p.x,height,p.y);
              vec3 incoming=normalize(S-lampPosition);
              vec3 n=poolNormal(p);
              vec3 transmitted=reflected>.5?reflect(incoming,n):refract(incoming,n,1.0/1.333);
              float denom=dot(transmitted,wallNormal);
              float t=abs(denom)>1e-5?(wallOffset-dot(S,wallNormal))/denom:-1.0;
              // Rays that never reach this wall stop at the water surface, whose
              // projection sits in the faded strip border.
              vec3 R=t>0.0&&t<64.0?S+transmitted*t:S;
              float u=((abs(wallNormal.x)>.5?R.z:R.x)+16.0)/32.0;
              float v=(R.y+.75)/15.25;
              sourcePoint=p;wallCell=vec2(u,v);
              float distance2=dot(S-lampPosition,S-lampPosition);
              float fresnel=.02037+.97963*pow(1.0-max(dot(-incoming,n),0.0),5.0);
              float throughput=reflected>.5?fresnel:(1.0-fresnel)*exp(-.18*max(t,0.0));
              powerAtSurface=t>0.0&&t<64.0?lampPower/(distance2+1.0)*max(dot(-incoming,n),0.0)*throughput:0.0;
              gl_Position=vec4(u*2.0-1.0,(wallStrip+v)*.5-1.0,0.0,1.0);
            }
          `,
          fragmentShader:/* glsl */`
            uniform sampler2D visibilityMap;uniform float causticResolution;varying vec2 sourcePoint;varying float powerAtSurface;varying vec2 wallCell;
            void main(){
              if(wallCell.x<.015||wallCell.x>.985||wallCell.y<.001||wallCell.y>.999)discard;
              vec2 dx=dFdx(sourcePoint),dy=dFdy(sourcePoint);
              float sourceArea=abs(dx.x*dy.y-dx.y*dy.x);
              float focus=clamp(sourceArea/(32.0*15.25/(causticResolution*causticResolution*.25)),0.0,9.0);
              float visibility=texture2D(visibilityMap,sourcePoint/32.0+.5).r;
              float fade=smoothstep(0.0,.03,wallCell.x)*(1.0-smoothstep(.97,1.0,wallCell.x))*smoothstep(0.0,.002,wallCell.y)*(1.0-smoothstep(.998,1.0,wallCell.y));
              float light=focus*powerAtSurface*visibility*fade;
              gl_FragColor=vec4(vec3(light)*vec3(.73,.91,1.0),1.0);
            }
          `,
          depthTest:false,depthWrite:false,transparent:true,blending:T.AdditiveBlending,side:T.DoubleSide,
        });
        this.materials.push(wallMat);const wallMesh=new T.Mesh(geometry,wallMat);wallMesh.frustumCulled=false;this.wallScene.add(wallMesh);
      }
    }
  }
  attach(water:Water){
    this.waterRef=water;
    Object.assign(water.material.uniforms,this.uniforms,this.tuning,this.layers,this.optics,this.causticUniforms);
    water.material.vertexShader=WATER_WAVES+'varying vec4 screenPosition;\n'+water.material.vertexShader;
    water.material.vertexShader=water.material.vertexShader.replace('void main() {',`void main() {
      vec3 displacedPosition=position;
      displacedPosition.z+=poolHeightSmooth((modelMatrix*vec4(position,1.0)).xz);
    `).replaceAll('vec4( position, 1.0 )','vec4( displacedPosition, 1.0 )')
      .replace('gl_Position = projectionMatrix * mvPosition;','gl_Position = projectionMatrix * mvPosition; screenPosition=gl_Position;');
    water.material.fragmentShader=WATER_FRAGMENT;
    water.material.needsUpdate=true;
    this.applySettings(this.settings);
  }
  /** Capture the opaque scene in linear HDR before the water pass. It has its
   * own depth attachment, so water never samples its current render target.
   *
   * This re-renders the entire scene, so it is the most expensive single stage
   * while walking. `refractionRefresh` throttles it: 0 = every frame, N = reuse
   * the previous capture for N frames. The camera moves slowly relative to a
   * 60 Hz frame, so a one-frame-old refraction buffer is essentially invisible,
   * and skipping halves the scene's draw cost. The buffer is always refreshed
   * on the first frame after a resize or a quality change so the stale image
   * can never come from a differently sized target. */
  captureScene(renderer:T.WebGLRenderer,scene:T.Scene,camera:T.PerspectiveCamera,excluded:T.Object3D[]=[]){
    const q=WATER_QUALITY[this.settings.quality];
    const needed=q.refraction>0&&(this.settings.refraction||this.settings.absorption||this.settings.debugView===8);
    this.optics.sceneReady.value=needed?1:0;
    if(!needed||!this.waterRef)return;
    renderer.getDrawingBufferSize(this.renderSize);
    const width=Math.max(1,Math.round(this.renderSize.x*q.refraction)),height=Math.max(1,Math.round(this.renderSize.y*q.refraction));
    if(this.opaque.width!==width||this.opaque.height!==height){this.opaque.setSize(width,height);this.refractionAge=Infinity;}
    // A held/thrown prop is excluded from the capture so it does not appear twice;
    // if one is moving the stale buffer would smear it, so force a refresh then.
    const every=Math.max(0,Math.round(this.settings.refractionRefresh));
    if(every>0&&this.refractionAge<every&&!excluded.some(o=>o.visible)){this.refractionAge++;this.optics.cameraNear.value=camera.near;this.optics.cameraFar.value=camera.far;return true;}
    this.refractionAge=0;
    this.captureFrames++;
    this.optics.cameraNear.value=camera.near;this.optics.cameraFar.value=camera.far;
    const target=renderer.getRenderTarget(),visible=this.waterRef.visible,visibility=excluded.map(o=>o.visible);
    try{this.waterRef.visible=false;for(const object of excluded)object.visible=false;renderer.setRenderTarget(this.opaque);renderer.clear();renderer.render(scene,camera);}
    finally{this.waterRef.visible=visible;excluded.forEach((o,i)=>{o.visible=visibility[i];});renderer.setRenderTarget(target);}
    return true;
  }
  get reflectionResolution(){return WATER_QUALITY[this.settings.quality].reflection;}
  get reflectionEnabled(){return this.settings.reflection;}
  attachTracing(field:ReflectionField){
    this.tracingReady=field.uniforms.rtReady;
    for(const material of this.materials){
      Object.assign(material.uniforms,field.uniforms);
      material.vertexShader=`${shaderStructs}\n${shaderIntersectFunction}
        uniform BVH rtBvh;uniform float rtReady;
        float waterRayVisible(vec3 source,vec3 direction,float distanceToReceiver){
          if(rtReady<.5)return 0.0;
          uvec4 face=uvec4(0u);vec3 normal=vec3(0),bary=vec3(0);float side=0.0,dist=0.0;
          bool hit=bvhIntersectFirstHit(rtBvh,source+direction*.025,direction,face,normal,bary,side,dist);
          return hit&&dist<distanceToReceiver-.065?0.0:1.0;
        }
      `+material.vertexShader;
      // The outgoing segment uses scene triangles; the incoming segment uses the light visibility mask.
      material.vertexShader=material.vertexShader.replace('gl_Position=vec4(receiver.x',`
        vec3 source=vec3(p.x,height,p.y);

        powerAtSurface*=waterRayVisible(source,transmitted,length(vec3(receiver.x,bed,receiver.y)-source));
        gl_Position=vec4(receiver.x`);
      material.vertexShader=material.vertexShader.replace('gl_Position=vec4(u*2.0',`

        powerAtSurface*=waterRayVisible(S,transmitted,max(t,0.0));
        gl_Position=vec4(u*2.0`);
      material.needsUpdate=true;
    }
  }
  attachReceiver(material:T.MeshStandardMaterial){
    const before=material.onBeforeCompile;
    const baseKey=material.customProgramCacheKey();
    material.onBeforeCompile=(shader,renderer)=>{
      before.call(material,shader,renderer);Object.assign(shader.uniforms,this.causticUniforms,this.uniforms);
      shader.fragmentShader='uniform sampler2D poolCaustics;uniform sampler2D poolCausticsWalls;uniform float causticGain;\n'+shader.fragmentShader;
      shader.fragmentShader=shader.fragmentShader.replace('#include <lights_fragment_maps>',`#include <lights_fragment_maps>
        {
          vec3 wnr=inverseTransformDirection(normal,viewMatrix);
          if(wnr.y>.5) {
            // Full floor atlas, sampled with an LOD bias to keep the web soft.
            vec2 causticUv=vPoolWorld.xz/32.0+.5;
            if(vPoolWorld.y<.25 && vPoolWorld.y>-.8 && all(greaterThan(causticUv,vec2(0.0))) && all(lessThan(causticUv,vec2(1.0)))) {
              float edgeFade=smoothstep(0.0,.04,min(min(causticUv.x,causticUv.y),min(1.0-causticUv.x,1.0-causticUv.y)));
              float upward=max(wnr.y,0.0);
              irradiance+=texture2D(poolCaustics,causticUv,1.15).rgb*causticGain*upward*edgeFade;
            }
          } else if(abs(wnr.y)<.45 && vPoolWorld.y>-.75 && vPoolWorld.y<14.5) {
            // Underwater wall band: pick the nearest of the four wall strips.
            float ex=abs(15.7-abs(vPoolWorld.x)),ez=abs(15.7-abs(vPoolWorld.z));
            float wallId=ex<ez?(vPoolWorld.x>0.0?0.0:1.0):(vPoolWorld.z>0.0?2.0:3.0);
            float nearWall=1.0-smoothstep(.02,.08,ex<ez?ex:ez);
            float u=((ex<ez?vPoolWorld.z:vPoolWorld.x)+16.0)/32.0;
            float v=clamp((vPoolWorld.y+.75)/15.25,0.0,1.0);
            float uEdge=smoothstep(0.0,.025,u)*(1.0-smoothstep(.975,1.0,u));
            float vEdge=smoothstep(0.0,.002,v)*(1.0-smoothstep(.998,1.0,v));
            vec2 auv=vec2(u,(wallId+v)*.25);
            irradiance+=texture2D(poolCausticsWalls,auv,1.15).rgb*causticGain*nearWall*uEdge*vEdge;
          }
        }
      `);
    };
    material.customProgramCacheKey=()=> `${baseKey}-caustics-4`;material.needsUpdate=true;
  }
  attachFloater(material:T.MeshStandardMaterial){
    const before=material.onBeforeCompile;
    material.onBeforeCompile=(shader,renderer)=>{
      before.call(material,shader,renderer);Object.assign(shader.uniforms,this.uniforms);
      shader.vertexShader=WATER_WAVES+shader.vertexShader;
      shader.vertexShader=shader.vertexShader.replace('sin(poolTime*1.25+instanceMatrix[3].x*.6+instanceMatrix[3].z)*.017','poolHeight(instanceMatrix[3].xz+modelMatrix[3].xz)/max(length(instanceMatrix[1].xyz),.01)');
    };
    material.customProgramCacheKey=()=> 'pool-vct-floating-water-1';material.needsUpdate=true;
  }
  private job:{solids:Solid[];lamp:number;row:number}|null=null;
  setLamps(lamps:Lamp[]){
    this.dirty=true;
    for(let i=0;i<Math.min(2,lamps.length);i++){
      this.materials[i*9].uniforms.lampPosition.value.copy(lamps[i].position);
      this.materials[i*9].uniforms.lampPower.value=lamps[i].power*4.75;
    }
    this.causticUniforms.waterLightPower.value=Math.min(2,lamps.reduce((s,l)=>s+l.power,0)/60);
  }
  beginOcclusion(solids:Solid[]){
    this.dirty=true;
    // Keep only blocks that can stand between the water plane and a lamp head.
    this.job={solids:solids.filter(b=>b.max.y>.31&&b.min.y<7.4&&b.max.x>-16.6&&b.min.x<16.6&&b.max.z>-16.6&&b.min.z<16.6),lamp:0,row:0};
  }
  stepOcclusion(budgetMs:number):boolean{
    const job=this.job;if(!job)return true;
    this.dirty=true;
    const start=performance.now(),ray=new T.Vector3();
    for(let l=job.lamp;l<2;l++){
      const pixels=this.masks[l].image.data!;
      const lamp=this.materials[l*9].uniforms.lampPosition.value as T.Vector3;
      let y=job.row;
      for(;y<256;y++){
        for(let x=0;x<256;x++){
          ray.set((x+.5)/256*32-16,.31,(y+.5)/256*32-16);
          pixels[x+y*256]=rayBlocked(ray,lamp,job.solids)?0:255;
        }
        job.row=y+1;
        if(performance.now()-start>budgetMs){this.masks[l].needsUpdate=true;return false;}
      }
      this.masks[l].needsUpdate=true;job.row=0;job.lamp=l+1;
    }
    this.job=null;return true;
  }
  rebuildOcclusion(solids:Solid[]){this.beginOcclusion(solids);while(!this.stepOcclusion(1e9));}
  impact(x:number,z:number,strength=.07){
    if(![x,z,strength].every(Number.isFinite)||strength<=0||this.swe.isLand(x,z))return;
    this.swe.impact(x,z,strength);this.interactionCount++;
    const depth=Math.min(1,this.depthAt(x,z)/.5);
    this.detail.impact(x,z,Math.min(.005,strength*.016)*this.settings.impact*depth);
    if(strength>.22)for(let i=0;i<9;i++){
      const angle=i*2.39996+this.interactionCount*.73,r=.18+.32*(i%3)/2;
      const px=x+Math.cos(angle)*r,pz=z+Math.sin(angle)*r;
      if(!this.swe.isLand(px,pz))this.detail.impact(px,pz,.0014*depth*this.settings.impact,.12);
    }
  }
  /** Returning drops feed the fine wave solver directly. Their millimetre
   * displacement must not be scaled as another body impact or seed foam. */
  dropRipple(x:number,z:number,amplitude:number){
    if(![x,z,amplitude].every(Number.isFinite)||amplitude<=0||this.swe.isLand(x,z))return;
    this.detail.impact(x,z,amplitude*this.settings.impact,.075);
  }
  /** Moving-body impulses already include elapsed time. */
  push(x:number,z:number,vx:number,vz:number,sigma:number){
    this.swe.push(x,z,vx*this.settings.impact,vz*this.settings.impact,sigma);
    if(!this.swe.isLand(x,z))this.detail.impact(x,z,Math.hypot(vx,vz)*.018*this.settings.impact,.14);
  }
  /** Prop drag contributes only momentum lost by the body. */
  pushWake(x:number,z:number,vx:number,vz:number,sigma:number){this.swe.push(x,z,vx,vz,sigma);}
  /** Bow/stern pressure dipole that gives a moving hull its crisp wake. */
  wakeDipole(x:number,z:number,dx:number,dz:number,speed:number,sigma:number){this.swe.wakeDipole(x,z,dx,dz,speed,sigma);
    if(!this.swe.isLand(x,z))this.detail.impact(x-dx*sigma,z-dz*sigma,Math.min(.001,speed*.00012),.14);
  }
  /** Surface flow for buoyancy drag: props ride the current. */
  flowAt(x:number,z:number){return this.swe.flowAt(x,z);}
  /** Wave slope push + Stokes drift velocity that carries floating props. */
  slopeAt(x:number,z:number,r=.38){const w=this.swe.slopeAt(x,z,r);const s=this.wavePush;return {ax:w.ax*s,az:w.az*s,ux:w.ux*s,uz:w.uz*s};}
  private crestClock=0;
  private crestScan=0;
  crestPatches=0;
  /** Scan every nearby cell at 30 Hz so a narrow travelling ridge cannot be
   * missed by sparse random probes. Only emit on a local convex maximum;
   * refine its position inside the cell and scatter along its tangent. */
  crestSpray(dt:number,emit:(x:number,z:number,power:number,foam:number)=>void,focus={x:0,z:0}){
    const s=this.settings,swe=this.swe,foamOn=s.foam&&s.foamStrength>0;
    if(s.quality==='Low'||!s.simulation||(!foamOn&&s.spray<=0)||swe.settled||swe.peak<.008){this.crestClock=0;return;}
    if(!Number.isFinite(dt)||dt<=0)return;
    this.crestClock+=Math.min(dt,.05);if(this.crestClock<1/30)return;
    const elapsed=Math.min(this.crestClock,.1);this.crestClock=0;
    const start=(centre:number)=>Math.max(1,Math.min(SW_PHYS-65,Math.floor((centre-8+SW_HALF)/SW_PHYS_CELL)));
    const x0=start(focus.x),z0=start(focus.z),eta=swe.physicsEta,cell2=SW_PHYS_CELL*SW_PHYS_CELL;
    const offset=(this.crestScan++*1597)%4096;let emitted=0;
    for(let j=0;j<4096&&emitted<12;j++){
      const k=(j+offset)%4096,ix=x0+k%64,iz=z0+Math.floor(k/64),i=ix+iz*SW_PHYS;
      const h=eta[i],w=eta[i-1],e=eta[i+1],b=eta[i-SW_PHYS],n=eta[i+SW_PHYS];
      if(h<.008)continue;
      const cx=(2*h-w-e)/cell2,cz=(2*h-b-n)/cell2,alongX=cx>=cz;
      const a=alongX?w:b,c=alongX?e:n;
      if(h<a||h<c||Math.max(cx,cz)<=.035)continue;
      const curvature=cx+cz,u=swe.physicsU[i],v=swe.physicsV[i];
      const foam=foamOn?crestFoamPower(h,u,v,curvature):0;
      const div=(swe.physicsU[i+1]-swe.physicsU[i-1]+swe.physicsV[i+SW_PHYS]-swe.physicsV[i-SW_PHYS])/(2*SW_PHYS_CELL);
      const centreX=-SW_HALF+(ix+.5)*SW_PHYS_CELL,centreZ=-SW_HALF+(iz+.5)*SW_PHYS_CELL;
      const power=crestPower(h,u,v,div,swe.depthAt(centreX,centreZ),9.81*swe.waveSpeed,curvature)*s.spray;
      const rate=Math.max(foam,power)*12;
      if(rate<=0||Math.random()>1-Math.exp(-rate*elapsed))continue;
      const ridge=T.MathUtils.clamp(.5*(a-c)/(a-2*h+c),-.5,.5)*SW_PHYS_CELL;
      const tangent=(Math.random()-.5)*SW_PHYS_CELL;
      const x=centreX+(alongX?ridge:tangent),z=centreZ+(alongX?tangent:ridge);
      if(swe.isLand(x,z))continue;
      emit(x,z,power,foam);emitted++;this.crestPatches++;
    }
  }
  /** Live retune of the surface look, driven by the pause-menu sliders. */
  applySettings(values:Partial<WaterSettings>){
    const s=sanitizeWaterSettings(values,this.settings);this.settings=s;this.dirty=true;
    for(const [key,uniform] of Object.entries(this.tuning))uniform.value=s[key as keyof WaterSettings] as number;
    this.layers.simulationOn.value=+s.simulation;
    this.layers.ripplesOn.value=+(s.ripples&&s.quality!=='Low');
    this.layers.microOn.value=+(s.microNormals&&(s.quality==='High'||s.quality==='Ultra'));
    for(const key of ['refraction','reflection','absorption','fresnel','waterline'] as const)this.layers[key+'On'].value=+s[key];
    this.layers.foamOn.value=+(s.foam&&s.quality!=='Low');
    this.causticUniforms.causticGain.value=s.caustics&&s.quality!=='Low'?s.causticsIntensity:0;
    this.wavePush=s.wavePush;
    this.swe.impactScale=s.impact;this.swe.ringWaves=s.ringWaves;this.swe.waveSpeed=s.waveSpeed;
    this.swe.damping=s.damping;this.swe.viscosity=s.viscosity;this.swe.wallLoss=s.wallLoss;
    this.swe.maxSteps=s.solverSteps;
    this.swe.foamDecay=1/Math.max(s.foamLife,.25);
    this.detail.frequency=s.rippleFrequency;
    this.optics.reflectionSize.value=this.reflectionResolution;
    if(this.waterRef)this.waterRef.material.uniforms.distortionScale.value=s.distortion;
    // Force a fresh capture whenever the setting changes so the interval takes
    // effect immediately instead of after up to N stale frames.
    if(this.lastRefractionRefresh!==s.refractionRefresh){this.lastRefractionRefresh=s.refractionRefresh;this.refractionAge=Infinity;}
  }
  snapshot():WaterSettings{return {...this.settings};}
  debug(){return {...this.swe.debug(),quality:this.settings.quality,detailGrid:this.detail.size,detailActive:this.detail.active,
    causticSize:this.target.width,causticFrames:this.causticFrames,reflectionSize:this.reflectionResolution,
    captureFrames:this.captureFrames,refractionAge:Number.isFinite(this.refractionAge)?this.refractionAge:0,
    refractionTargetSize:[this.opaque.width,this.opaque.height],settings:this.snapshot()};}
  private updateQuality(renderer:T.WebGLRenderer){
    const q=WATER_QUALITY[this.settings.quality];
    if(this.waterRef&&(this.waterRef.geometry as T.PlaneGeometry).parameters.widthSegments!==q.surface){
      this.waterRef.geometry.dispose();this.waterRef.geometry=new T.PlaneGeometry(96,96,q.surface,q.surface);
    }
    if(this.swe.size!==q.simulation){
      const old=this.swe,next=new ShallowWater(q.simulation);
      old.frame(renderer,0);
      if(this.blocks)next.setBlocks(this.blocks);else next.setTerrain(this.terrain);
      next.inherit(renderer,old);this.swe=next;old.dispose();
      this.detailDepth.value=next.uniforms.poolDepth.value;this.uniforms.poolCell.value=next.cell;
      this.applySettings(this.settings);
    }
    if(this.detail.size!==q.ripple){this.detail.dispose();this.detail=new RippleDetail(q.ripple,this.detailDepth);this.detail.frequency=this.settings.rippleFrequency;this.uniforms.detailCell.value=this.detail.cell;}
    if(this.target.width===q.caustics)return;
    for(const target of [this.target,this.wallTarget,this.filterTarget])target.setSize(q.caustics,q.caustics);
    this.uniforms.causticResolution.value=q.caustics;
    this.geometry.dispose();this.geometry=new T.PlaneGeometry(32,32,q.photons,q.photons);
    for(const mesh of this.scene.children as T.Mesh[])mesh.geometry=this.geometry;
    for(const g of this.wallGeometries)g.dispose();this.wallGeometries=[];
    for(const mesh of this.wallScene.children as T.Mesh[]){const g=new T.PlaneGeometry(32,32,q.wallPhotons,q.wallPhotons);g.rotateX(-Math.PI/2);mesh.geometry=g;this.wallGeometries.push(g);}
    this.dirty=true;
  }
  heightAt(x:number,z:number){return this.swe.heightAt(x,z);}
  /** Match the visible macro-surface filter. The GPU adds sub-centimetre
   * detail; contact uses the already available asynchronous physics field. */
  surfaceAt(x:number,z:number){
    if(!this.settings.simulation)return .32;
    const h=(dx:number,dz:number)=>this.swe.heightAt(x+dx,z+dz);
    return .32+(4*h(0,0)+2*(h(.22,0)+h(-.22,0)+h(0,.22)+h(0,-.22))
      +h(.16,.16)+h(-.16,-.16)+h(-.16,.16)+h(.16,-.16))/16*this.settings.waveHeight;
  }
  depthAt(x:number,z:number){return this.swe.depthAt(x,z);}
  rebase(shift:T.Vector3){this.dirty=true;this.swe.rebase(shift.x,shift.z);this.detail.rebase(shift.x,shift.z);this.uniforms.microOrigin.value.add(new T.Vector2(shift.x,shift.z));}
  /** Waterline-crossing obstacles of every streamed room (XZ boxes), refreshed
   * after every floating-origin rebase so the solver mask and shader see local
   * coords. Rasterised into the land mask as reflective cells. */
  setBlocks(blocks:T.Vector4[]){
    this.dirty=true;
    this.uniforms.blockCount.value=blocks.length;
    this.blocks=blocks;this.swe.setBlocks(blocks);this.detail.terrainChanged();
  }
  setTerrain(colliders:Collider[]){this.dirty=true;this.uniforms.blockCount.value=colliders.length;this.blocks=null;this.terrain=colliders;this.swe.setTerrain(colliders);this.detail.terrainChanged();}
  render(renderer:T.WebGLRenderer,time:number){
    this.updateQuality(renderer);
    const dt=this.lastTime===null?0:Math.max(0,Math.min(time-this.lastTime,.25));
    this.lastTime=time;
    this.uniforms.poolTime.value=time;
    if(time-this.lastEnvironment>2.7&&this.settings.environmentalStrength>0){
      this.lastEnvironment=time;
      const x=Math.sin(time*1.71)*12,z=Math.sin(time*2.39)*12;
      if(!this.swe.isLand(x,z))this.detail.impact(x,z,.0003*this.settings.environmentalStrength,.12);
    }
    const changed=this.swe.frame(renderer,dt);
    this.uniforms.poolSurface.value=this.swe.uniforms.poolSurface.value;
    this.detail.frame(renderer,dt,this.layers.ripplesOn.value>0);
    this.uniforms.poolDetail.value=this.detail.uniform.value;
    const active=!this.swe.settled||(this.detail.active&&this.layers.ripplesOn.value>0)||(this.layers.microOn.value>0&&this.settings.microStrength>0&&this.settings.causticsSpeed>0);
    if(this.causticUniforms.causticGain.value<=0)return;
    const ready=this.tracingReady?.value??1;
    // A flat, unchanged pool has unchanged light transport. Reuse it instead of
    // retracing millions of rays every frame while the player is standing still.
    if(!changed&&!active&&!this.lastActive&&!this.dirty&&ready===this.lastReady)return;
    // The water field changes on almost every frame, so requiring a *still* pool
    // meant this cache never hit: the 2048² floor + 2048² wall retrace plus the
    // 2048² filter ran in full every frame. Retrace only on the configured
    // cadence; the waves move slowly enough that a few frames of latency is
    // invisible, and 0 restores per-frame tracing.
    const every=Math.max(0,Math.round(this.settings.causticsRefresh));
    if(every>0&&!this.dirty&&ready===this.lastReady&&this.causticAge<every){
      this.causticAge++;return;
    }
    this.causticAge=0;
    // Moving caustics follow every water frame; only settled transport is cached.
    this.lastActive=active;this.lastReady=ready;this.dirty=false;this.causticFrames++;
    const previous=renderer.getRenderTarget(),clear=renderer.getClearColor(this.clearColor),alpha=renderer.getClearAlpha();
    renderer.setRenderTarget(this.target);renderer.setClearColor(0,0);renderer.clear();renderer.render(this.scene,this.camera);
    // Integrate neighbouring computed photon footprints; no image/pattern input.
    this.filterMaterial.uniforms.source.value=this.target.texture;
    this.filterMaterial.uniforms.strips.value=1;
    this.filterMaterial.uniforms.stepSize.value.set(1.4/this.target.width,0);
    renderer.setRenderTarget(this.filterTarget);renderer.render(this.filterScene,this.camera);
    this.filterMaterial.uniforms.source.value=this.filterTarget.texture;
    this.filterMaterial.uniforms.stepSize.value.set(0,1.4/this.target.width);
    renderer.setRenderTarget(this.target);renderer.render(this.filterScene,this.camera);
    renderer.setRenderTarget(this.wallTarget);renderer.setClearColor(0,0);renderer.clear();if(this.settings.quality!=='Medium')renderer.render(this.wallScene,this.camera);
    this.filterMaterial.uniforms.strips.value=4;
    this.filterMaterial.uniforms.source.value=this.wallTarget.texture;
    this.filterMaterial.uniforms.stepSize.value.set(1.6/this.target.width,0);
    renderer.setRenderTarget(this.filterTarget);renderer.render(this.filterScene,this.camera);
    this.filterMaterial.uniforms.source.value=this.filterTarget.texture;
    this.filterMaterial.uniforms.stepSize.value.set(0,1.2/this.target.width);
    renderer.setRenderTarget(this.wallTarget);renderer.render(this.filterScene,this.camera);
    renderer.setRenderTarget(previous);renderer.setClearColor(clear,alpha);
  }
  dispose(){this.swe.dispose();this.detail.dispose();this.opaque.dispose();this.target.dispose();this.wallTarget.dispose();this.filterTarget.dispose();this.filterMaterial.dispose();(this.filterScene.children[0] as T.Mesh).geometry.dispose();this.geometry.dispose();for(const g of this.wallGeometries)g.dispose();for(const m of this.materials)m.dispose();for(const m of this.masks)m.dispose();}
}
