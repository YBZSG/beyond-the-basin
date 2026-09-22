import BvhWorker from './rt-worker?worker&inline';
import { advanceTask } from './perf/task-budget';
import * as T from 'three';
import { MeshBVH, MeshBVHUniformStruct, FloatVertexAttributeTexture, shaderStructs, shaderIntersectFunction } from 'three-mesh-bvh';
import type { Lamp } from './world';
import type { PackedRtTexture, ReflectionTextureFields } from './rt-packing';

export const RT_LAMP_CAP = 18;

export type RtItem = { geometry: T.BufferGeometry; matrix: T.Matrix4; color: T.Color; tile: number };

/** Ray-traced reflections for the tiled surfaces: a BVH of the streamed static
 * geometry (plus low-poly proxies of the floating props near the player) is
 * intersected per pixel inside the material shader, so the walls mirror the
 * actual room with correct parallax and real object colors. Each hit carries a
 * per-vertex material color; flagged tile hits additionally receive the
 * procedural grout/waterline pattern, and the hit point is shaded with
 * voxel-shadowed direct lamps plus the voxel cone-traced indirect field. This
 * is geometrically exact one-bounce ray tracing with approximate hit shading —
 * not a path tracer; held/thrown props snapshot per crossing. */
export class ReflectionField {
  private worker:Worker|null=null;
  private version=0;
  private packing:Generator<void,void>|null=null;
  private ready:{version:number;positions?:Float32Array;colors?:Float32Array;serialized:ReturnType<typeof MeshBVH.serialize>;textures?:PackedRtTexture[];error?:string}|null=null;
  private uploading:PackedRtTexture[]|null=null;
  private lamps:Lamp[]=[];
  private waiting=false;
  private destroyed=false;
  error='';
  beginRebuild(items:RtItem[],lamps:Lamp[]){
    const version=++this.version;this.lamps=lamps;this.ready=null;this.uploading=null;this.waiting=true;this.error='';
    // Cancel obsolete work instead of allowing a queue of full BVH builds.
    this.worker?.terminate();this.worker=new BvhWorker();
    this.worker.onmessage=event=>{if(!this.destroyed&&event.data.version===this.version)this.ready=event.data;};
    this.worker.onerror=event=>{if(version===this.version){this.error=event.message;this.waiting=false;}};
    const worker=this.worker;
    this.packing=(function*(){
      const snapshots=[];const transfers:ArrayBuffer[]=[];
      for(const item of items){
        const attribute=item.geometry.getAttribute('position');if(!attribute)continue;
        const position=new Float32Array(attribute.count*3);
        for(let i=0;i<attribute.count;i++){position[i*3]=attribute.getX(i);position[i*3+1]=attribute.getY(i);position[i*3+2]=attribute.getZ(i);if((i&2047)===2047)yield;}
        const source=item.geometry.index,index=source?new Uint32Array(source.array):null;
        snapshots.push({position,index,matrix:item.matrix.toArray(),color:item.color.toArray(),tile:item.tile});
        transfers.push(position.buffer);if(index)transfers.push(index.buffer);yield;
      }
      worker.postMessage({version,items:snapshots},transfers);
    })();
  }
  stepRebuild(budgetMs:number,renderer?:Pick<T.WebGLRenderer,'initTexture'>){
    if(this.packing){if(advanceTask(this.packing,budgetMs)?.done)this.packing=null;return false;}
    if(this.uploading){
      if(budgetMs<=0)return false;
      // One native upload per frame; no synchronous repacking of all BVH arrays.
      const packed=this.uploading.shift()!;
      const texture=packed.key==='color'?this.uniforms.rtColor.value:(this.uniforms.rtBvh.value as unknown as ReflectionTextureFields)[packed.key];
      texture.dispose();texture.image={data:packed.data,width:packed.width,height:packed.height};
      texture.format=packed.format;texture.type=packed.type;texture.internalFormat=packed.internalFormat;
      texture.minFilter=texture.magFilter=T.NearestFilter;texture.generateMipmaps=false;texture.needsUpdate=true;
      renderer?.initTexture(texture);
      if(this.uploading.length)return false;
      this.uploading=null;this.setLamps(this.lamps);this.uniforms.rtReady.value=1;return true;
    }
    if(!this.waiting)return true;
    if(!this.ready||budgetMs<=0)return false;
    const result=this.ready;this.ready=null;this.waiting=false;
    if(result.version!==this.version)return false;
    if(result.error){this.error=result.error;return true;}
    if(result.textures){this.uploading=result.textures;return false;}
    const geometry=new T.BufferGeometry();geometry.setAttribute('position',new T.BufferAttribute(result.positions!,3));
    const bvh=MeshBVH.deserialize(result.serialized,geometry);
    this.uniforms.rtBvh.value.updateFrom(bvh);
    this.uniforms.rtColor.value.updateFrom(new T.BufferAttribute(result.colors!,4));
    geometry.dispose();this.setLamps(this.lamps);this.uniforms.rtReady.value=1;return true;
  }
  private setLamps(lamps:Lamp[]){
    const a=this.uniforms.rtLampA.value,b=this.uniforms.rtLampB.value,count=Math.min(lamps.length,RT_LAMP_CAP);
    for(let i=0;i<count;i++){a[i].set(lamps[i].position.x,lamps[i].position.y,lamps[i].position.z,95);b[i].set(lamps[i].color.r,lamps[i].color.g,lamps[i].color.b);}
    this.uniforms.rtLampCount.value=count;
  }
  uniforms = {
    rtBvh: { value: new MeshBVHUniformStruct() },
    rtColor: { value: new FloatVertexAttributeTexture() },
    rtLampA: { value: Array.from({ length: RT_LAMP_CAP }, () => new T.Vector4(0, 0, 0, 0)) },
    rtLampB: { value: Array.from({ length: RT_LAMP_CAP }, () => new T.Vector3()) },
    rtLampCount: { value: 0 },
    rtReady: { value: 0 },
  };

  rebuild(items: RtItem[], lamps: Lamp[]): boolean {
    const positions: number[] = [], colors: number[] = [];
    const v = new T.Vector3();
    for (const item of items) {
      const pos = item.geometry.attributes.position;
      if (!pos) continue;
      const index = item.geometry.index;
      const push = (i: number) => {
        v.fromBufferAttribute(pos, i).applyMatrix4(item.matrix);
        positions.push(v.x, v.y, v.z);
        colors.push(item.color.r, item.color.g, item.color.b, item.tile);
      };
      if (index) { for (let i = 0; i < index.count; i++) push(index.getX(i)); }
      else { for (let i = 0; i < pos.count; i++) push(i); }
    }
    if (positions.length === 0) return true;
    const geometry = new T.BufferGeometry();
    geometry.setAttribute('position', new T.Float32BufferAttribute(positions, 3));
    const colorAttr = new T.Float32BufferAttribute(colors, 4);
    geometry.setAttribute('rtColorData', colorAttr);
    this.uniforms.rtBvh.value.updateFrom(new MeshBVH(geometry));
    this.uniforms.rtColor.value.updateFrom(colorAttr);
    const a = this.uniforms.rtLampA.value, b = this.uniforms.rtLampB.value;
    const count = Math.min(lamps.length, RT_LAMP_CAP);
    for (let i = 0; i < count; i++) {
      a[i].set(lamps[i].position.x, lamps[i].position.y, lamps[i].position.z, 95);
      b[i].set(lamps[i].color.r, lamps[i].color.g, lamps[i].color.b);
    }
    this.uniforms.rtLampCount.value = count;
    this.uniforms.rtReady.value = 1;
    return true;
  }
  invalidate() { this.version++;this.packing=null;this.ready=null;this.uploading=null;this.waiting=false;this.worker?.terminate();this.worker=null;this.uniforms.rtReady.value = 0; }

  /** Patch a material that already went through VoxelField.apply (the RT GLSL is
   * inserted after the cone-tracing helpers via the hook marker). */
  apply(material: T.MeshStandardMaterial, cacheKey: string) {
    const before = material.onBeforeCompile;
    material.onBeforeCompile = (shader, renderer) => {
      before.call(material, shader, renderer);
      Object.assign(shader.uniforms, this.uniforms);
      const hook = '// __POOL_RT_HOOK__';
      const rtFunctions = `
        uniform BVH rtBvh;
        uniform highp sampler2D rtColor;
        uniform vec4 rtLampA[${RT_LAMP_CAP}];
        uniform vec3 rtLampB[${RT_LAMP_CAP}];
        uniform int rtLampCount;
        uniform float rtReady;
        vec4 rtFetchV(uint i) {
          int w = int(textureSize(rtColor, 0).x);
          return texelFetch(rtColor, ivec2(int(i) % w, int(i) / w), 0);
        }
        vec4 rtHitColor(uvec4 fi, vec3 bc) {
          return rtFetchV(fi.x) * bc.x + rtFetchV(fi.y) * bc.y + rtFetchV(fi.z) * bc.z;
        }
        // Procedural grout/variation pattern matching the direct tile shading.
        vec3 rtTileFactor(vec3 P, vec3 n) {
          vec3 an = abs(n);
          vec2 tuv = an.y > .6 ? P.xz : (an.x > .6 ? P.zy : P.xy);
          vec2 grid = tuv * 4.0;
          vec2 edge = min(fract(grid), 1.0 - fract(grid));
          float grout = 1.0 - smoothstep(.012, .03, min(edge.x, edge.y));
          float variation = fract(sin(dot(floor(grid), vec2(12.9898, 78.233))) * 43758.5453);
          float damp = 1.0 - .12 * exp(-max(P.y, 0.0) * 2.5);
          vec3 f = mix(vec3(.94 + variation * .10), vec3(.64), grout);
          return f * damp;
        }
        // Direct lamps with a voxel-occupancy shadow march plus cone-traced indirect,
        // evaluated at the reflected hit point with its real material color.
        vec3 rtShade(vec3 HP, vec3 hn, vec3 albedo) {
          vec3 col = vec3(.015, .022, .028);
          for (int i = 0; i < rtLampCount; i++) {
            vec3 L = rtLampA[i].xyz - HP;
            float d2 = dot(L, L);
            float d = sqrt(d2);
            vec3 ld = L / d;
            float ndl = max(dot(hn, ld), 0.0);
            if (ndl <= 0.0) continue;
            float sh = 1.0;
            for (int s = 1; s <= 12; s++) {
              vec3 sp = HP + ld * mix(1.5, d - .6, float(s) / 12.0);
              vec3 uvw = (sp - vctOrigin) / vctExtent;
              if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) continue;
              if (texture(vct0, uvw).a > 0.5) { sh = 0.0; break; }
            }
            col += rtLampB[i] * (rtLampA[i].w / (d2 + 3.0)) * ndl * sh * albedo;
          }
          col += coneDiffuse(HP, hn) * mix(vec3(1.0), albedo * 1.8, .5);
          return col;
        }
        vec3 rtReflect(vec3 P, vec3 N) {
          vec3 V = normalize(cameraPosition - P);
          vec3 R = reflect(-V, N);
          uvec4 fi = uvec4(0u);
          vec3 fn = vec3(0.0), bc = vec3(0.0);
          float side = 0.0, dist = 0.0;
          bvhIntersectFirstHit(rtBvh, P + N * .03, R, fi, fn, bc, side, dist);
          if (fi.w == 0u || dist > 60.0) return vec3(0.0);
          vec3 hn = normalize(dot(fn, R) > 0.0 ? -fn : fn);
          vec3 HP = P + N * .03 + R * dist;
          vec4 mc = rtHitColor(fi, bc);
          vec3 albedo = mc.rgb;
          if (mc.a > .5) albedo *= rtTileFactor(HP, hn);
          return rtShade(HP, hn, albedo);
        }
      `;
      shader.fragmentShader = shader.fragmentShader.replace(hook, `${hook}\n${shaderStructs}\n${shaderIntersectFunction}\n${rtFunctions}`);
      shader.fragmentShader = shader.fragmentShader.replace('#include <opaque_fragment>', `
        {
          vec3 rtN = inverseTransformDirection(normal, viewMatrix);
          vec3 rtV = normalize(cameraPosition - vPoolWorld);
          float rtFres = pow(1.0 - clamp(dot(rtV, rtN), 0.0, 1.0), 5.0);
          float rtStrength = mix(mix(.025, .55, metalness), .65, rtFres) * pow(1.0 - roughnessFactor, 2.0);
          if (rtReady > 0.5 && rtStrength > .02) outgoingLight += rtReflect(vPoolWorld, rtN) * rtStrength;
        }
        #include <opaque_fragment>`);
    };
    material.customProgramCacheKey = () => cacheKey;
    material.needsUpdate = true;
  }
  dispose() {
    this.destroyed=true;this.invalidate();
    this.uniforms.rtBvh.value.dispose?.();
    this.uniforms.rtColor.value.dispose?.();
  }
}
