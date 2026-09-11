import * as T from 'three';
import type { Water } from 'three/addons/objects/Water.js';
import type { Solid, Lamp } from './world';
import { shaderStructs, shaderIntersectFunction } from 'three-mesh-bvh';
import type { ReflectionField } from './rt';

// The same height field drives visible normals, floating objects and refracted rays.
export const WATER_WAVES = /* glsl */`
uniform float waterTime;
uniform vec4 impacts[12];
// Pillars and pool-side steps of the central room, as XZ boxes: (minx,minz,maxx,maxz).
uniform vec4 poolBlocks[16];
uniform int poolBlockCount;
float poolWave(vec2 source,vec2 p,float age,float power) {
  float r=length(p-source);
  float front=r-age*1.7;
  return power*exp(-front*front*3.2)*exp(-age*.32)*(1.0-smoothstep(11.0,14.0,age))/sqrt(1.0+r)*sin(front*10.5);
}
// One wall of the room the splash happened in: the mirrored source radiates the
// reflected wave. It is dropped unless its straight path to the receiver crosses
// the wall on solid masonry - the eight metre portal gaps stay open, and waves
// from neighbouring rooms do not leak phantom reflections in.
float poolMirror(vec2 m,vec2 p,float age,float power,float plane,int axis,float centre) {
  float mAxis=axis==0?m.x:m.y,pAxis=axis==0?p.x:p.y;
  if((mAxis>plane)==(pAxis>plane))return 0.0;
  float crossing=(plane-mAxis)/(pAxis-mAxis);
  float along=(axis==0?m.y:m.x)+crossing*((axis==0?p.y:p.x)-(axis==0?m.y:m.x));
  return poolWave(m,p,age,power*1.5*smoothstep(3.2,4.8,abs(along-centre)));
}
// Steps and pillars that cross the waterline bounce ripples too. Every face of
// the block is a short mirror whose reflected wave fades out past the face's
// ends; only splashes in the central room consult the blocks, neighbouring
// rooms keep their wall-only reflection.
float poolBlockMirror(vec2 s,vec2 p,float age,float power,vec4 blk) {
  float h=0.0;
  for(int edge=0;edge<4;edge++) {
    // edge 0/1: faces at x=minx/maxx; edge 2/3: faces at z=minz/maxz.
    float plane=edge==0?blk.x:(edge==1?blk.z:(edge==2?blk.y:blk.w));
    int axis=edge<2?0:1;
    float sA=axis==0?s.x:s.y;
    float m=2.0*plane-sA;
    float pA=axis==0?p.x:p.y;
    if((m>plane)==(pA>plane))continue;
    float crossing=(plane-m)/(pA-m);
    float other=axis==0?s.y+crossing*(p.y-s.y):s.x+crossing*(p.x-s.x);
    float lo=axis==0?blk.y:blk.x;
    float hi=axis==0?blk.w:blk.z;
    float fade=smoothstep(lo-.25,lo,other)*(1.0-smoothstep(hi,hi+.25,other));
    if(fade<=0.0)continue;
    vec2 msource=axis==0?vec2(m,s.y):vec2(s.x,m);
    h+=poolWave(msource,p,age,power*.85*fade);
  }
  return h;
}
float poolHeight(vec2 p) {
  // Enclosed pool: no wind or pump is enabled. Only real interactions add waves.
  float h=0.0;
  for(int i=0;i<12;i++) {
    float age=waterTime-impacts[i].z;
    if(age>0.0 && age<14.0) {
      vec2 s=impacts[i].xy;
      h+=poolWave(s,p,age,impacts[i].w);
      vec2 c=32.0*floor(s/32.0+0.5);
      h+=poolMirror(vec2(2.0*(c.x+15.7)-s.x,s.y),p,age,impacts[i].w,c.x+15.7,0,c.y);
      h+=poolMirror(vec2(2.0*(c.x-15.7)-s.x,s.y),p,age,impacts[i].w,c.x-15.7,0,c.y);
      h+=poolMirror(vec2(s.x,2.0*(c.y+15.7)-s.y),p,age,impacts[i].w,c.y+15.7,1,c.x);
      h+=poolMirror(vec2(s.x,2.0*(c.y-15.7)-s.y),p,age,impacts[i].w,c.y-15.7,1,c.x);
      if(abs(c.x)<16.5&&abs(c.y)<16.5) {
        for(int k=0;k<poolBlockCount;k++)h+=poolBlockMirror(s,p,age,impacts[i].w,poolBlocks[k]);
      }
    }
  }
  return h;
}
vec3 poolNormal(vec2 p) {
  float e=.015;
  return normalize(vec3(poolHeight(p-vec2(e,0))-poolHeight(p+vec2(e,0)),2.0*e,poolHeight(p-vec2(0,e))-poolHeight(p+vec2(0,e))));
}
`;

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
 * climb the tiled walls below the waterline. */
export class InteractiveWater {
  static WALL_LOW=-.75; static WALL_HIGH=14.5;
  uniforms={waterTime:{value:0},impacts:{value:Array.from({length:12},()=>new T.Vector4(0,0,-100,0))},
    blocks:{value:Array.from({length:16},()=>new T.Vector4(0,0,0,0))},blockCount:{value:0}};
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
  private cursor=0;
  private dirty=true;
  private lastActive=false;
  private tracingReady:{value:number}|null=null;
  private lastReady=-1;
  interactionCount=0;
  private static wallDefs=[
    {normal:new T.Vector3(-1,0,0),strip:0,rotY:-Math.PI/2,shift:[16,0]},
    {normal:new T.Vector3(1,0,0),strip:1,rotY:Math.PI/2,shift:[-16,0]},
    {normal:new T.Vector3(0,0,-1),strip:2,rotY:0,shift:[0,16]},
    {normal:new T.Vector3(0,0,1),strip:3,rotY:Math.PI,shift:[0,-16]},
  ];
  constructor(){
    this.filterScene.add(new T.Mesh(new T.PlaneGeometry(2,2),this.filterMaterial));
    this.causticUniforms.poolCaustics.value=this.target.texture;
    this.causticUniforms.poolCausticsWalls.value=this.wallTarget.texture;
    const maskSize=256;
    for(const x of [-9,8]) {
      const visibility=new T.DataTexture(new Uint8Array(maskSize*maskSize).fill(255),maskSize,maskSize,T.RedFormat);
      visibility.minFilter=visibility.magFilter=T.LinearFilter;visibility.needsUpdate=true;this.masks.push(visibility);
      const shared={...this.uniforms,visibilityMap:{value:visibility},lampPosition:{value:new T.Vector3(x,7.3,-5)},lampPower:{value:95}};
      const floorMat=new T.ShaderMaterial({
        uniforms:{...shared},
        vertexShader:WATER_WAVES+/* glsl */`
          uniform vec3 lampPosition;uniform float lampPower;varying vec2 sourcePoint;varying float powerAtSurface;
          void main(){
            vec2 p=position.xy;float height=.28+poolHeight(p);
            vec3 incoming=normalize(vec3(p.x,height,p.y)-lampPosition);
            vec3 n=poolNormal(p);
            vec3 transmitted=refract(incoming,n,1.0/1.333);
            vec2 receiver=p+transmitted.xz*((-.72-height)/transmitted.y);
            sourcePoint=p;
            float distance2=dot(vec3(p.x,height,p.y)-lampPosition,vec3(p.x,height,p.y)-lampPosition);
            // 2% Fresnel reflection at normal incidence, Beer absorption through water.
            powerAtSurface=lampPower/(distance2+1.0)*max(dot(-incoming,n),0.0)*.98*exp(-.18*(height+.72));
            // Rays leaving the 32m atlas cell clamp to its faded boundary.
            receiver=clamp(receiver,vec2(-16.0),vec2(16.0));
            gl_Position=vec4(receiver.x/16.0,receiver.y/16.0,0.0,1.0);
          }
        `,
        fragmentShader:/* glsl */`
          uniform sampler2D visibilityMap;varying vec2 sourcePoint;varying float powerAtSurface;
          void main(){
            vec2 dx=dFdx(sourcePoint),dy=dFdy(sourcePoint);
            float sourceArea=abs(dx.x*dy.y-dx.y*dy.x);
            float focus=clamp(sourceArea/(32.0*32.0/(2048.0*2048.0)),0.0,9.0);
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
              float height=.28+poolHeight(p);
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
            uniform sampler2D visibilityMap;varying vec2 sourcePoint;varying float powerAtSurface;varying vec2 wallCell;
            void main(){
              if(wallCell.x<.015||wallCell.x>.985||wallCell.y<.001||wallCell.y>.999)discard;
              vec2 dx=dFdx(sourcePoint),dy=dFdy(sourcePoint);
              float sourceArea=abs(dx.x*dy.y-dx.y*dy.x);
              float focus=clamp(sourceArea/(32.0*15.25/(2048.0*512.0)),0.0,9.0);
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
    Object.assign(water.material.uniforms,this.uniforms);
    water.material.vertexShader=WATER_WAVES+water.material.vertexShader;
    water.material.vertexShader=water.material.vertexShader.replace('void main() {',`void main() {
      vec3 displacedPosition=position;
      displacedPosition.z+=poolHeight((modelMatrix*vec4(position,1.0)).xz);
    `).replaceAll('vec4( position, 1.0 )','vec4( displacedPosition, 1.0 )');
    water.material.fragmentShader=WATER_WAVES+water.material.fragmentShader;
    water.material.fragmentShader=water.material.fragmentShader.replace(/vec3 surfaceNormal = normalize\( noise.xzy \* vec3\([^;]+;/,'vec3 surfaceNormal = poolNormal(worldPosition.xz);');
    // Geometry, reflected image and Fresnel respond to every footstep/click.
    water.material.needsUpdate=true;
  }
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

        powerAtSurface*=waterRayVisible(source,transmitted,length(vec3(receiver.x,-.72,receiver.y)-source));
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
  impact(x:number,z:number,strength=.07){this.uniforms.impacts.value[this.cursor].set(x,z,this.uniforms.waterTime.value,strength);this.cursor=(this.cursor+1)%12;this.interactionCount++;}
  heightAt(x:number,z:number){
    const t=this.uniforms.waterTime.value;
    const wave=(sx:number,sz:number,age:number,power:number)=>{
      const r=Math.hypot(x-sx,z-sz),front=r-age*1.7;
      return power*Math.exp(-front*front*3.2)*Math.exp(-age*.32)*(1-T.MathUtils.smoothstep(age,11,14))/Math.sqrt(1+r)*Math.sin(front*10.5);
    };
    // Mirrors the shader exactly (poolWave/poolMirror/poolBlockMirror): wall
    // reflections of the splash's own room, gated across portal gaps, plus the
    // pillar/step blocks of the central room with edge-faded mirrored sources.
    let h=0;
    const blocks=this.uniforms.blocks.value,blockCount=this.uniforms.blockCount.value;
    for(const p of this.uniforms.impacts.value){
      const age=t-p.z;if(age<=0||age>=14)continue;
      h+=wave(p.x,p.y,age,p.w);
      const cx=32*Math.floor(p.x/32+.5),cz=32*Math.floor(p.y/32+.5);
      for(const axis of [0,1])for(const side of [1,-1]){
        const plane=(axis===0?cx:cz)+side*15.7,mirror=2*plane-(axis===0?p.x:p.y),pAxis=axis===0?x:z;
        if((mirror>plane)===(pAxis>plane))continue;
        const crossing=(plane-mirror)/(pAxis-mirror),base=axis===0?p.y:p.x;
        const along=base+crossing*((axis===0?z:x)-base);
        const gate=T.MathUtils.smoothstep(Math.abs(along-(axis===0?cz:cx)),3.2,4.8);
        h+=wave(axis===0?mirror:p.x,axis===0?p.y:mirror,age,p.w*1.5*gate);
      }
      if(Math.abs(cx)<16.5&&Math.abs(cz)<16.5){
        for(let k=0;k<blockCount;k++){
          const blk=blocks[k];
          for(let edge=0;edge<4;edge++){
            const plane=edge===0?blk.x:edge===1?blk.z:edge===2?blk.y:blk.w,axis=edge<2?0:1;
            const sA=axis===0?p.x:p.y,m=2*plane-sA,pA=axis===0?x:z;
            if((m>plane)===(pA>plane))continue;
            const crossing=(plane-m)/(pA-m);
            const other=axis===0?p.y+crossing*(z-p.y):p.x+crossing*(x-p.x);
            const lo=axis===0?blk.y:blk.x,hi=axis===0?blk.w:blk.z;
            const fade=T.MathUtils.smoothstep(other,lo-.25,lo)*(1-T.MathUtils.smoothstep(other,hi,hi+.25));
            if(fade<=0)continue;
            h+=wave(axis===0?m:p.x,axis===0?p.y:m,age,p.w*.85*fade);
          }
        }
      }
    }
    return h;
  }
  rebase(shift:T.Vector3){this.dirty=true;for(const p of this.uniforms.impacts.value){p.x-=shift.x;p.y-=shift.z;}}
  /** Waterline-crossing pillars/steps of the central room (XZ boxes), refreshed
   * after every floating-origin rebase so the shader and JS see local coords. */
  setBlocks(blocks:T.Vector4[]){
    this.dirty=true;
    const list=blocks.slice(0,16);
    this.uniforms.blocks.value.forEach((slot,i)=>{const b=list[i];if(b)slot.copy(b);else slot.set(0,0,0,0);});
    this.uniforms.blockCount.value=list.length;
  }
  render(renderer:T.WebGLRenderer,time:number){
    this.uniforms.waterTime.value=time;
    const active=this.uniforms.impacts.value.some(p=>time>=p.z&&time-p.z<14);
    const ready=this.tracingReady?.value??1;
    // A flat, unchanged pool has unchanged light transport. Reuse it instead of
    // retracing millions of rays every frame while the player is standing still.
    if(!active&&!this.lastActive&&!this.dirty&&ready===this.lastReady)return;
    // Moving caustics follow every water frame; only settled transport is cached.
    this.lastActive=active;this.lastReady=ready;this.dirty=false;
    const previous=renderer.getRenderTarget(),clear=renderer.getClearColor(new T.Color()),alpha=renderer.getClearAlpha();
    renderer.setRenderTarget(this.target);renderer.setClearColor(0,0);renderer.clear();renderer.render(this.scene,this.camera);
    // Integrate neighbouring computed photon footprints; no image/pattern input.
    this.filterMaterial.uniforms.source.value=this.target.texture;
    this.filterMaterial.uniforms.strips.value=1;
    this.filterMaterial.uniforms.stepSize.value.set(1.4/2048,0);
    renderer.setRenderTarget(this.filterTarget);renderer.render(this.filterScene,this.camera);
    this.filterMaterial.uniforms.source.value=this.filterTarget.texture;
    this.filterMaterial.uniforms.stepSize.value.set(0,1.4/2048);
    renderer.setRenderTarget(this.target);renderer.render(this.filterScene,this.camera);
    renderer.setRenderTarget(this.wallTarget);renderer.setClearColor(0,0);renderer.clear();renderer.render(this.wallScene,this.camera);
    this.filterMaterial.uniforms.strips.value=4;
    this.filterMaterial.uniforms.source.value=this.wallTarget.texture;
    this.filterMaterial.uniforms.stepSize.value.set(1.6/2048,0);
    renderer.setRenderTarget(this.filterTarget);renderer.render(this.filterScene,this.camera);
    this.filterMaterial.uniforms.source.value=this.filterTarget.texture;
    this.filterMaterial.uniforms.stepSize.value.set(0,1.2/2048);
    renderer.setRenderTarget(this.wallTarget);renderer.render(this.filterScene,this.camera);
    renderer.setRenderTarget(previous);renderer.setClearColor(clear,alpha);
  }
  dispose(){this.target.dispose();this.wallTarget.dispose();this.filterTarget.dispose();this.filterMaterial.dispose();(this.filterScene.children[0] as T.Mesh).geometry.dispose();this.geometry.dispose();for(const g of this.wallGeometries)g.dispose();for(const m of this.materials)m.dispose();for(const m of this.masks)m.dispose();}
}
