import * as TSL from 'three/tsl';
import { UnsignedIntType, type IUniform, type Texture, type DataTexture } from 'three';
import { liveTexture } from './legacy-texture.ts';

// Same texture layout as MeshBVHUniformStruct; the worker and its streamed
// uploads remain shared with the original renderer.
const visible = TSL.wgslFn(`
fn poolRayVisible(bounds: texture_2d<f32>, contents: texture_2d<u32>,
  indices: texture_2d<u32>, positions: texture_2d<f32>,
  origin: vec3f, direction: vec3f, limit: f32, ready: f32) -> f32 {
  if (ready < 0.5) { return 0.0; }
  let bw = textureDimensions(bounds).x;
  let cw = textureDimensions(contents).x;
  let iw = textureDimensions(indices).x;
  let pw = textureDimensions(positions).x;
  let ray = origin + direction * 0.025;
  let inverse = 1.0 / direction;
  var stack: array<u32, 60>;
  stack[0] = 0u;
  var pointer = 0i;
  loop {
    if (pointer < 0 || pointer >= 58) { break; }
    let node = stack[pointer]; pointer -= 1;
    let lowIndex = node * 2u;
    let low = textureLoad(bounds, vec2i(i32(lowIndex % bw), i32(lowIndex / bw)), 0).xyz;
    let highIndex = lowIndex + 1u;
    let high = textureLoad(bounds, vec2i(i32(highIndex % bw), i32(highIndex / bw)), 0).xyz;
    let t0 = min((low-ray)*inverse, (high-ray)*inverse);
    let t1 = max((low-ray)*inverse, (high-ray)*inverse);
    let near = max(max(t0.x,t0.y),max(t0.z,0.0));
    let far = min(min(t1.x,t1.y),t1.z);
    if (far < near || near > limit-0.065) { continue; }
    let info = textureLoad(contents, vec2i(i32(node % cw),i32(node / cw)),0).xy;
    if ((info.x & 0xffff0000u) != 0u) {
      let count = info.x & 0xffffu;
      for (var triangle=info.y; triangle<info.y+count; triangle+=1u) {
        let face=textureLoad(indices,vec2i(i32(triangle%iw),i32(triangle/iw)),0).xyz;
        let a=textureLoad(positions,vec2i(i32(face.x%pw),i32(face.x/pw)),0).xyz;
        let b=textureLoad(positions,vec2i(i32(face.y%pw),i32(face.y/pw)),0).xyz;
        let c=textureLoad(positions,vec2i(i32(face.z%pw),i32(face.z/pw)),0).xyz;
        let e1=b-a; let e2=c-a; let normal=cross(e1,e2);
        let det=-dot(direction,normal);
        if (abs(det)<1e-10) { continue; }
        let ao=ray-a; let dao=cross(ao,direction);
        let u=dot(e2,dao)/det; let v=-dot(e1,dao)/det;
        let distance=dot(ao,normal)/det;
        if (min(min(u,v),1.0-u-v)>=-1e-5 && distance>=-1e-5 && distance<limit-0.065) { return 0.0; }
      }
    } else {
      pointer+=1; stack[pointer]=node+1u;
      pointer+=1; stack[pointer]=node+info.y;
    }
  }
  return 1.0;
}`);

export function bvhTextures(uniforms:Record<string,IUniform>){
  const bvh = uniforms.rtBvh.value as Record<string,Texture>;
  const tex = (name:string) => {
    const normalize=()=>{
      const value=bvh[name] as DataTexture;
      if((name==='index'||name==='bvhContents')&&value.type!==UnsignedIntType){
        value.image.data=new Uint32Array(value.image.data!);value.type=UnsignedIntType;value.needsUpdate=true;
      }
      value.internalFormat=null;return value;
    };
    return liveTexture({get value(){return normalize();}});
  };
  return [tex('bvhBounds'),tex('bvhContents'),tex('index'),tex('position')];
}

export function waterVisibility(uniforms: Record<string,IUniform>) {
  const [bounds,contents,indices,positions]=bvhTextures(uniforms);
  const ready=TSL.reference('value','float',uniforms.rtReady);
  return (origin:never,direction:never,limit:never)=>visible(bounds,contents,indices,positions,origin,direction,limit,ready);
}
