import * as T from 'three';
import * as TSL from 'three/tsl';
import type { NodeMaterial } from 'three/webgpu';
import { legacyTexture, liveTexture } from './legacy-texture.ts';
import { bvhTextures } from './bvh-visibility.ts';
import { RT_LAMP_CAP } from '../rt.ts';

// TSL's base Node type omits vector operations exposed by its proxies.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Graph=any;
const N:Graph=TSL;
type Uniforms=Record<string,T.IUniform>;

const ref=(u:Uniforms,key:string,type='float')=>N.reference('value',type as never,u[key]);

const voxelSample=N.wgslFn(`
fn poolVoxelSample(a:texture_3d<f32>,b:texture_3d<f32>,c:texture_3d<f32>,d:texture_3d<f32>,s:sampler,
  uv:vec3f,lod:f32)->vec4f {
  if(any(uv<vec3f(0))||any(uv>vec3f(1))){return vec4f(0);}
  if(lod<1){return mix(textureSampleLevel(a,s,uv,0),textureSampleLevel(b,s,uv,0),lod);}
  if(lod<2){return mix(textureSampleLevel(b,s,uv,0),textureSampleLevel(c,s,uv,0),lod-1);}
  return mix(textureSampleLevel(c,s,uv,0),textureSampleLevel(d,s,uv,0),clamp(lod-2,0,1));
}`);
const traceCone=N.wgslFn(`fn poolCone(a:texture_3d<f32>,b:texture_3d<f32>,c:texture_3d<f32>,d:texture_3d<f32>,s:sampler,
  p:vec3f,dir:vec3f,origin:vec3f,extent:vec3f)->vec3f {
  var acc=vec4f(0);var distance=1.05;
  for(var i=0;i<16;i++){
    let diameter=max(.75,distance*.65);
    let value=poolVoxelSample(a,b,c,d,s,(p+dir*distance-origin)/extent,clamp(log2(diameter/.75),0,3));
    acc+=(1-acc.a)*value;distance+=diameter*.7;
    if(acc.a>.95||distance>23){break;}
  }
  return acc.rgb;
}`,[voxelSample]);
const cone=N.wgslFn(`fn poolIndirect(a:texture_3d<f32>,b:texture_3d<f32>,c:texture_3d<f32>,d:texture_3d<f32>,s:sampler,
  p:vec3f,n:vec3f,origin:vec3f,extent:vec3f)->vec3f {
  let axis=select(vec3f(1,0,0),vec3f(0,1,0),abs(n.y)<.95);
  let t=normalize(cross(n,axis));let bitangent=cross(n,t);let start=p+n*.85;
  return poolCone(a,b,c,d,s,start,n,origin,extent)*.28+.18*(
    poolCone(a,b,c,d,s,start,normalize(n+t),origin,extent)+poolCone(a,b,c,d,s,start,normalize(n-t),origin,extent)+
    poolCone(a,b,c,d,s,start,normalize(n+bitangent),origin,extent)+poolCone(a,b,c,d,s,start,normalize(n-bitangent),origin,extent));
}`,[traceCone]);

// Closest-hit reflection of the same streamed BVH used by water visibility.
const reflection=N.wgslFn(`fn poolReflect(bounds:texture_2d<f32>,contents:texture_2d<u32>,indices:texture_2d<u32>,positions:texture_2d<f32>,colors:texture_2d<f32>,
  a:texture_3d<f32>,b:texture_3d<f32>,c:texture_3d<f32>,d:texture_3d<f32>,s:sampler,
  lamps:array<vec4f,${RT_LAMP_CAP}>,lampColors:array<vec4f,${RT_LAMP_CAP}>,lampCount:i32,
  p:vec3f,n:vec3f,view:vec3f,voxelOrigin:vec3f,extent:vec3f,voxelReady:f32)->vec3f {
  let ray=p+n*.03;let direction=reflect(-view,n);let inverse=1/direction;
  let bw=textureDimensions(bounds).x;let cw=textureDimensions(contents).x;
  let iw=textureDimensions(indices).x;let pw=textureDimensions(positions).x;let aw=textureDimensions(colors).x;
  var stack:array<u32,60>;stack[0]=0u;var pointer=0i;
  var nearest=60.0;var hitNormal=vec3f(0);var hitColor=vec4f(0);var found=false;
  loop {
    if(pointer<0||pointer>=58){break;}
    let node=stack[pointer];pointer-=1;let lowIndex=node*2u;let highIndex=lowIndex+1u;
    let low=textureLoad(bounds,vec2i(i32(lowIndex%bw),i32(lowIndex/bw)),0).xyz;
    let high=textureLoad(bounds,vec2i(i32(highIndex%bw),i32(highIndex/bw)),0).xyz;
    let t0=min((low-ray)*inverse,(high-ray)*inverse);let t1=max((low-ray)*inverse,(high-ray)*inverse);
    let near=max(max(t0.x,t0.y),max(t0.z,0.0));let far=min(min(t1.x,t1.y),t1.z);
    if(far<near||near>nearest){continue;}
    let info=textureLoad(contents,vec2i(i32(node%cw),i32(node/cw)),0).xy;
    if((info.x&0xffff0000u)!=0u){
      let count=info.x&0xffffu;
      for(var triangle=info.y;triangle<info.y+count;triangle+=1u){
        let face=textureLoad(indices,vec2i(i32(triangle%iw),i32(triangle/iw)),0).xyz;
        let va=textureLoad(positions,vec2i(i32(face.x%pw),i32(face.x/pw)),0).xyz;
        let vb=textureLoad(positions,vec2i(i32(face.y%pw),i32(face.y/pw)),0).xyz;
        let vc=textureLoad(positions,vec2i(i32(face.z%pw),i32(face.z/pw)),0).xyz;
        let e1=vb-va;let e2=vc-va;let normal=cross(e1,e2);let det=-dot(direction,normal);
        if(abs(det)<1e-10){continue;}
        let ao=ray-va;let dao=cross(ao,direction);let u=dot(e2,dao)/det;let v=-dot(e1,dao)/det;
        let distance=dot(ao,normal)/det;
        if(min(min(u,v),1-u-v)>=-1e-5&&distance>=0&&distance<nearest){
          nearest=distance;hitNormal=normalize(select(normal,-normal,dot(normal,direction)>0));found=true;
          hitColor=textureLoad(colors,vec2i(i32(face.x%aw),i32(face.x/aw)),0)*(1-u-v)
            +textureLoad(colors,vec2i(i32(face.y%aw),i32(face.y/aw)),0)*u
            +textureLoad(colors,vec2i(i32(face.z%aw),i32(face.z/aw)),0)*v;
        }
      }
    }else{pointer+=1;stack[pointer]=node+1u;pointer+=1;stack[pointer]=node+info.y;}
  }
  if(!found){return vec3f(0);}
  let hp=ray+direction*nearest;var albedo=hitColor.rgb;
  if(hitColor.a>.5){
    let an=abs(hitNormal);let uv=select(select(hp.xy,hp.zy,an.x>.6),hp.xz,an.y>.6)*4;
    let edge=min(fract(uv),1-fract(uv));let grout=1-smoothstep(.012,.03,min(edge.x,edge.y));
    let variation=fract(sin(dot(floor(uv),vec2f(12.9898,78.233)))*43758.5453);
    albedo*=mix(vec3f(.94+variation*.1),vec3f(.64),grout)*(1-.12*exp(-max(hp.y,0.0)*2.5));
  }
  var color=vec3f(.015,.022,.028);
  for(var i=0;i<lampCount;i++){
    let light=lamps[i].xyz-hp;let d2=dot(light,light);let distance=sqrt(d2);let ld=light/max(distance,.001);
    let ndl=max(dot(hitNormal,ld),0.0);if(ndl<=0){continue;}
    var shadow=1.0;
    if(voxelReady>.5){for(var j=1;j<=12;j++){
      let uv=(hp+ld*mix(1.5,distance-.6,f32(j)/12)-voxelOrigin)/extent;
      if(any(uv<vec3f(0))||any(uv>vec3f(1))){continue;}
      if(textureSampleLevel(a,s,uv,0).a>.5){shadow=0;break;}
    }}
    color+=lampColors[i].rgb*(lamps[i].w/(d2+3))*ndl*shadow*albedo;
  }
  if(voxelReady>.5){color+=poolIndirect(a,b,c,d,s,hp,hitNormal,voxelOrigin,extent)*mix(vec3f(1),albedo*1.8,.5);}
  return color;
}`,[cone]);

const projectedNormal=N.wgslFn(`
fn poolProjectedNormal(p:vec3f,n:vec3f,uv:vec2f,sample:vec3f,scale:vec2f)->vec3f {
  let q0=dpdx(p);let q1=dpdy(p);let st0=dpdx(uv);let st1=dpdy(uv);
  let a=cross(q1,n);let b=cross(n,q0);
  let t=a*st0.x+b*st1.x;let bitangent=a*st0.y+b*st1.y;
  let inv=inverseSqrt(max(max(dot(t,t),dot(bitangent,bitangent)),1e-12));
  let map=sample*2-1;
  return normalize(t*inv*map.x*scale.x+bitangent*inv*map.y*scale.y+n*map.z);
}`);

const portalVisible=N.wgslFn(`fn poolPortalVisible(p:vec3f,n:vec3f,light:vec3f)->f32 {
  let surface=p+n*.04;let cell=floor((surface.xz+16)/32);let delta=light-surface;
  for(var axis=0;axis<2;axis++){
    let dc=select(delta.x,delta.z,axis==1);let sc=select(surface.x,surface.z,axis==1);
    let cc=select(cell.x,cell.y,axis==1);let boundary=cc*32+select(-16.0,16.0,dc>0);
    let t=(boundary-sc)/select(.001,dc,abs(dc)>.001);
    if(t>0&&t<1){let hit=surface+delta*t;let along=select(hit.z,hit.x,axis==1);
      let local=along+16-floor((along+16)/32)*32-16;
      if(abs(local)>4||hit.y>5.4){return 0;}
    }
  }return 1;
}`);

function tileCoordinates(){
  const p=N.positionWorld,face=N.normalWorldGeometry.abs();
  const plane=face.y.greaterThan(.6).select(p.xz,face.x.greaterThan(.6).select(p.zy,p.xy));
  const uv=N.vec2(plane.x.add(plane.y),plane.y.sub(plane.x)).mul(.707107*1.2);
  const wet=p.y.sub(.32).max(0).mul(-.8).exp();
  const drip=plane.x.mul(8).add(plane.x.mul(2.3).sin()).add(plane.y.mul(.6).sin().mul(.3)).sin().mul(.5).add(.5);
  return {p,plane,uv,wet,drip};
}
function wetRoughness(map:T.Texture,uv:Graph,wet:Graph,drip:Graph){
  return N.texture(map,uv).g.mul(.28).add(.08).sub(wet.mul(.065)).sub(drip.mul(.025)).clamp(.09,.38);
}
function tileNormal(map:T.Texture,scale:T.Vector2,uv:Graph){
  const normal=projectedNormal(N.positionWorld,N.normalWorldGeometry,uv,N.texture(map,uv).xyz,N.vec2(scale));
  return N.cameraViewMatrix.mul(N.vec4(normal,0)).xyz.normalize();
}

function causticLight(u:Uniforms){
  const floor=legacyTexture(u.poolCaustics) as Graph,wall=legacyTexture(u.poolCausticsWalls) as Graph,gain=ref(u,'causticGain');
  return N.Fn(()=>{
    const p=N.positionWorld,n=N.normalWorld,light=N.vec3(0).toVar();
    const uv=p.xz.div(32).add(.5),border=uv.min(uv.oneMinus()),edge=border.x.min(border.y);
    N.If(n.y.greaterThan(.5).and(p.y.lessThan(.25)).and(p.y.greaterThan(-.8)).and(edge.greaterThan(0)),()=>{
      light.assign(floor.sample(uv).rgb.mul(gain).mul(n.y.max(0)).mul(edge.smoothstep(0,.04)));
    }).ElseIf(n.y.abs().lessThan(.45).and(p.y.greaterThan(-.75)).and(p.y.lessThan(14.5)),()=>{
      const ex=N.float(15.7).sub(p.x.abs()).abs(),ez=N.float(15.7).sub(p.z.abs()).abs(),side=ex.lessThan(ez);
      const id=side.select(p.x.greaterThan(0).select(0,1),p.z.greaterThan(0).select(2,3));
      const x=side.select(p.z,p.x).add(16).div(32),y=p.y.add(.75).div(15.25).clamp();
      const fade=side.select(ex,ez).smoothstep(.02,.08).oneMinus()
        .mul(x.smoothstep(0,.025)).mul(x.smoothstep(.975,1).oneMinus())
        .mul(y.smoothstep(0,.002)).mul(y.smoothstep(.998,1).oneMinus());
      light.assign(wall.sample(N.vec2(x,id.add(y).mul(.25))).rgb.mul(gain).mul(fade));
    });
    return light;
  })();
}

/** Native node counterparts of the scene's onBeforeCompile material hooks. */
export function extendSceneMaterial(node:NodeMaterial,source:T.Material){
  const material=node as Graph,data=source.userData;
  if(data.poolWetOccluder){
    material.fog=false;material.fragmentNode=N.vec4(N.normalView.mul(.5).add(.5),0);return node;
  }
  if(data.poolWetNormals){
    const {roughness,normal,scale}=data.poolWetNormals,{p,uv,wet,drip}=tileCoordinates();
    material.normalNode=tileNormal(normal,scale,uv);
    material.fog=false;
    material.fragmentNode=N.vec4(N.normalView.mul(.5).add(.5),p.y.greaterThan(.325).select(wetRoughness(roughness,uv,wet,drip),0));
    return node;
  }
  if(data.poolAged){
    const [color,normal,roughness]=data.poolAged.textures as T.Texture[];
    const {p,uv,wet,drip}=tileCoordinates(),sample=N.texture(color,uv).rgb;
    const luma=sample.dot(N.vec3(.2126,.7152,.0722));
    const stain=p.x.mul(1.7).add(p.z.mul(.8).sin()).sin().mul(p.y.mul(3.1).add(p.z).sin());
    const line=p.y.sub(.36).abs().mul(-10).exp().mul(stain.mul(.035).add(.07));
    material.colorNode=N.reference('color','color',source).mul(N.mix(N.vec3(luma.pow(.72)),sample,.035)).mul(1.08)
      .mul(N.mix(N.vec3(1),N.vec3(.64,.71,.56),line));
    material.roughnessNode=wetRoughness(roughness,uv,wet,drip);
    material.normalNode=tileNormal(normal,(source as T.MeshPhysicalMaterial).normalScale,uv);
    material.clearcoatNormalNode=tileNormal(normal,(source as T.MeshPhysicalMaterial).clearcoatNormalScale,uv);
  }
  const voxel=data.poolVoxel,receiver=data.poolCaustics;
  const voxelMaps:Graph[]=voxel?['vct0','vct1','vct2','vct3'].map(key=>liveTexture(voxel.uniforms[key],true)):[];
  if(voxel||receiver){
    let gi:Graph=N.vec3(0);
    if(voxel){
      const u=voxel.uniforms as Uniforms;
      const maps=voxelMaps;
      gi=N.Fn(()=>{
        const light=N.vec3(0).toVar();
        N.If(ref(u,'vctReady').greaterThan(.5).and(ref(u,'vctStrength').greaterThan(0)),()=>{
          light.assign(cone(maps[0],maps[1],maps[2],maps[3],N.sampler(maps[0]),N.positionWorld,N.normalWorld,
            ref(u,'vctOrigin','vec3'),ref(u,'vctExtent','vec3')).mul(ref(u,'vctStrength')).mul(Math.PI));
        });return light;
      })();
    }
    if(receiver)gi=gi.add(causticLight(receiver));
    const lighting=material.setupLightingModel.bind(material);
    material.setupLightingModel=(builder:Graph)=>{
      const model=lighting(builder),indirect=model.indirect.bind(model),direct=model.direct.bind(model);
      model.indirect=(b:Graph)=>{b.context.irradiance.addAssign(gi);indirect(b);};
      model.direct=(input:Graph,b:Graph)=>{
        const specular=data.poolAged?input.reflectedLight.directSpecular.toVar():null,
          coat=data.poolAged?model.clearcoatSpecularDirect?.toVar():null;
        if(voxel&&input.lightNode?.light?.isPointLight){
          input={...input,lightColor:input.lightColor.mul(portalVisible(N.positionWorld,N.normalWorld,N.lightPosition(input.lightNode.light)))};
        }
        direct(input,b);
        if(specular)input.reflectedLight.directSpecular.assign(specular);
        if(coat)model.clearcoatSpecularDirect.assign(coat);
      };
      return model;
    };
  }
  if(data.poolDrop){
    const u=data.poolDrop as Uniforms,scene=liveTexture(u.sceneColor);
    const lighting=material.setupLightingModel.bind(material);
    material.setupLightingModel=(builder:Graph)=>{
      const model=lighting(builder),finish=model.finish.bind(model);
      model.finish=(b:Graph)=>{
        finish(b);
        const f=N.normalView.dot(N.positionViewDirection).clamp().oneMinus().pow(5).mul(.979627).add(.020373);
        const size=N.varying(N.Fn((_:unknown,v:Graph)=>N.instancedBufferAttribute(v.object.instanceMatrix,'mat4').element(0).xyz.length().mul(2))());
        const bend=N.vec2(N.normalView.x,N.normalView.y.negate()).mul(size).mul(.15).div(N.positionView.z.negate().max(.15));
        const uv=N.screenUV.add(bend).clamp(.001,.999);
        const spec=b.context.reflectedLight.directSpecular.add(b.context.reflectedLight.indirectSpecular);
        N.If(ref(u,'sceneReady').greaterThan(.5).and(ref(u,'renderOptics').greaterThan(.5)),()=>{
          b.context.outgoingLight.assign(scene.sample(uv).rgb.mul(f.oneMinus()).add(spec));
        }).Else(()=>{
          N.diffuseColor.a.assign(f.clamp(.06,.9));
          b.context.outgoingLight.assign(spec.div(N.diffuseColor.a.max(.001)));
        });
      };
      return model;
    };
  }
  if(data.poolRt&&voxel){
    const u=data.poolRt as Uniforms,v=voxel.uniforms as Uniforms;
    const bvh=bvhTextures(u),colors=liveTexture({get value(){
      const texture=u.rtColor.value as T.DataTexture;texture.internalFormat=null;return texture;
    }});
    const maps=voxelMaps;
    const lamps=N.uniformArray(u.rtLampA.value,'vec4'),lampColors=N.uniformArray(u.rtLampB.value,'vec3');
    const lighting=material.setupLightingModel.bind(material);
    material.setupLightingModel=(builder:Graph)=>{
      const model=lighting(builder),finish=model.finish.bind(model);
      model.finish=(b:Graph)=>{
        finish(b);
        const view=N.cameraPosition.sub(N.positionWorld).normalize(),n=N.normalWorld;
        const fresnel=view.dot(n).clamp().oneMinus().pow(5);
        const strength=N.mix(N.mix(.025,.55,N.metalness),.65,fresnel).mul(N.roughness.oneMinus().pow(2));
        N.If(ref(u,'rtReady').greaterThan(.5).and(strength.greaterThan(.02)),()=>{
          b.context.outgoingLight.addAssign(reflection(...bvh,colors,...maps,N.sampler(maps[0]),lamps,lampColors,ref(u,'rtLampCount','int'),
            N.positionWorld,n,view,ref(v,'vctOrigin','vec3'),ref(v,'vctExtent','vec3'),ref(v,'vctReady')).mul(strength));
        });
      };
      return model;
    };
  }
  return node;
}
