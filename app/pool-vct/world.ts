import * as T from 'three';

export const ROOM = 32;
export type Solid = { min: T.Vector3; max: T.Vector3; color: T.Color; radius?: number };
export type Lamp = { position: T.Vector3; color: T.Color; power: number };
export function randomFor(x: number, z: number, seed: number) {
  let s = (Math.imul(x, 73856093) ^ Math.imul(z, 19349663) ^ seed) >>> 0;
  return () => { s += 0x6d2b79f5; let t = Math.imul(s ^ s >>> 15, 1 | s); t ^= t + Math.imul(t ^ t >>> 7, 61 | t); return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}
// Every edge has an eight metre opening, so independently generated neighbours agree.
// Corruption deepens with exploration distance: the pool complex stays pristine
// near the spawn room and decays further out (lights fail, tiles stain, signs
// turn wrong). It is a pure function of room coordinates, so streamed
// regeneration of the same room always reproduces the same decay.
export function corruptionLevel(x: number, z: number) {
  const d = Math.max(Math.abs(x), Math.abs(z));
  return d <= 1 ? 0 : d <= 3 ? 1 : d <= 6 ? 2 : 3;
}
export function roomLayout(x: number, z: number, seed: number) {
  const rng = randomFor(x, z, seed);
  const anchors:Record<string,number>={'0,0':0,'0,-1':3,'-1,0':6,'1,0':5,'0,1':4,'1,1':7};
  return { variant: anchors[`${x},${z}`] ?? Math.floor(rng() * 8), tint: rng(), ducks: 8 + Math.floor(rng() * 14), corrupt: corruptionLevel(x, z) };
}
export function blocked(position: T.Vector3, solids: Solid[]) {
  return solids.some(b => b.min.y < 1.7 && b.max.y > 0.65 && position.x > b.min.x - .28 && position.x < b.max.x + .28 && position.z > b.min.z - .28 && position.z < b.max.z + .28);
}

/** Static diffuse VCT: voxel occupancy + shadowed direct radiance injection on CPU,
 * premultiplied radiance/opacity mip pyramid, hemispherical cone integration on GPU.
 * The moving 96m volume is rebuilt across frames with a millisecond budget so
 * crossing a doorway never freezes the render loop. */
export class VoxelField {
  textures: T.Data3DTexture[] = [];
  uniforms = {
    vct0: { value: null as T.Data3DTexture | null }, vct1: { value: null as T.Data3DTexture | null },
    vct2: { value: null as T.Data3DTexture | null }, vct3: { value: null as T.Data3DTexture | null },
    vctOrigin: { value: new T.Vector3() }, vctExtent: { value: new T.Vector3(96, 24, 96) },
    vctStrength: { value: 1.8 }, poolTime: { value: 0 }, vctReady: { value: 0 },
  };
  private job: { data: Uint8Array; occupancy: Uint8Array; colors: Float32Array; cells: Int32Array; cursor: number; lamps: Lamp[]; origin: T.Vector3 } | null = null;
  constructor() {
    // Bind empty 1x1x1 levels so sampler3D uniforms stay valid before the first finish().
    const empty = new T.Data3DTexture(new Uint8Array(4), 1, 1, 1);
    empty.format = T.RGBAFormat; empty.type = T.UnsignedByteType;
    empty.minFilter = empty.magFilter = T.LinearFilter; empty.unpackAlignment = 1; empty.needsUpdate = true;
    this.textures.push(empty);
    this.uniforms.vct0.value = empty; this.uniforms.vct1.value = empty;
    this.uniforms.vct2.value = empty; this.uniforms.vct3.value = empty;
  }
  begin(solids: Solid[], lamps: Lamp[], cx: number, cz: number) {
    const nx = 128, ny = 32, nz = 128, cell = .75;
    const origin = new T.Vector3(cx * ROOM - 48, -1.5, cz * ROOM - 48);
    const occupancy = new Uint8Array(nx * ny * nz);
    const colors = new Float32Array(occupancy.length * 3);
    for (const b of solids) {
      const lo = b.min.clone().sub(origin).divideScalar(cell).floor();
      const hi = b.max.clone().sub(origin).divideScalar(cell).floor();
      for (let z = Math.max(0, lo.z); z <= Math.min(nz - 1, hi.z); z++)
        for (let y = Math.max(0, lo.y); y <= Math.min(ny - 1, hi.y); y++)
          for (let x = Math.max(0, lo.x); x <= Math.min(nx - 1, hi.x); x++) {
            const i = x + nx * (y + ny * z); occupancy[i] = 1;
            colors[i * 3] = b.color.r; colors[i * 3 + 1] = b.color.g; colors[i * 3 + 2] = b.color.b;
          }
    }
    let occupied = 0;
    for (let i = 0; i < occupancy.length; i++) if (occupancy[i]) occupied++;
    const cells = new Int32Array(occupied);
    for (let i = 0, k = 0; i < occupancy.length; i++) if (occupancy[i]) cells[k++] = i;
    // A new job replaces a half-finished one; the previous levels keep rendering until finish().
    this.job = { data: new Uint8Array(occupancy.length * 4), occupancy, colors, cells, cursor: 0, lamps, origin };
  }
  stepRadiance(budgetMs: number): boolean {
    const job = this.job; if (!job) return true;
    const { data, colors, cells, occupancy, lamps, origin } = job;
    const ox = origin.x, oy = origin.y, oz = origin.z;
    // Flat numeric lamp records avoid property chasing in the hot loop.
    const ls: number[] = [];
    for (const l of lamps) ls.push(l.position.x, l.position.y, l.position.z, l.color.r, l.color.g, l.color.b, l.power);
    const start = performance.now();
    let cursor = job.cursor;
    while (cursor < cells.length) {
      const i = cells[cursor];
      const x = i % 128, y = (i / 128 | 0) % 32, z = (i / 4096) | 0;
      const px = ox + (x + .5) * .75, py = oy + (y + .5) * .75, pz = oz + (z + .5) * .75;
      let r = .018, g = .026, b = .035;
      for (let k = 0; k < ls.length; k += 7) {
        const dx = ls[k] - px, dy = ls[k + 1] - py, dz = ls[k + 2] - pz;
        const d2 = dx * dx + dy * dy + dz * dz; if (d2 > 324) continue;
        const d = Math.sqrt(d2);
        let visible = true;
        // 8× DDA march: each step is one eighth of a cell, so samples stay
        // grid-aligned and a ray can never stride over a one-voxel-thin wall
        // (the old .8m step was wider than a .75m cell). Eight consecutive
        // samples usually share a cell, so only cell crossings retest occupancy.
        const dirx = dx / d, diry = dy / d, dirz = dz / d, dda = .75 / 8;
        let last = -1;
        for (let t = 1.6; t < d - .9; t += dda) {
          const sx = ((px + dirx * t - ox) * 1.3333333) | 0, sy = ((py + diry * t - oy) * 1.3333333) | 0, sz = ((pz + dirz * t - oz) * 1.3333333) | 0;
          if (sx < 0 || sy < 0 || sz < 0 || sx > 127 || sy > 31 || sz > 127) continue;
          const idx = sx + 128 * (sy + 32 * sz);
          if (idx !== last) { if (occupancy[idx]) { visible = false; break; } last = idx; }
        }
        if (visible) { const e = ls[k + 6] / (d2 + 3); r += ls[k + 3] * e; g += ls[k + 4] * e; b += ls[k + 5] * e; }
      }
      data[i * 4] = Math.min(255, r * colors[i * 3] * 255);
      data[i * 4 + 1] = Math.min(255, g * colors[i * 3 + 1] * 255);
      data[i * 4 + 2] = Math.min(255, b * colors[i * 3 + 2] * 255);
      data[i * 4 + 3] = 255;
      cursor++;
      if ((cursor & 511) === 0 && performance.now() - start > budgetMs) break;
    }
    job.cursor = cursor;
    return cursor >= cells.length;
  }
  finish(): boolean {
    const job = this.job; if (!job) return true;
    this.dispose();
    const nx = 128, ny = 32, nz = 128;
    let data = job.data, w = nx, h = ny, d = nz;
    for (let level = 0; level < 4; level++) {
      const texture = new T.Data3DTexture(data, w, h, d);
      texture.format = T.RGBAFormat; texture.type = T.UnsignedByteType;
      texture.minFilter = texture.magFilter = T.LinearFilter; texture.unpackAlignment = 1; texture.needsUpdate = true;
      this.textures.push(texture);
      if (level === 3) break;
      const next = new Uint8Array(w / 2 * h / 2 * d / 2 * 4);
      for (let z = 0; z < d / 2; z++) for (let y = 0; y < h / 2; y++) for (let x = 0; x < w / 2; x++) {
        for (let c = 0; c < 4; c++) {
          let sum = 0;
          for (let dz = 0; dz < 2; dz++) for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) sum += data[((x * 2 + dx) + w * (y * 2 + dy + h * (z * 2 + dz))) * 4 + c];
          next[(x + w / 2 * (y + h / 2 * z)) * 4 + c] = Math.round(sum / 8);
        }
      }
      data = next; w /= 2; h /= 2; d /= 2;
    }
    this.uniforms.vct0.value = this.textures[0]; this.uniforms.vct1.value = this.textures[1];
    this.uniforms.vct2.value = this.textures[2]; this.uniforms.vct3.value = this.textures[3];
    this.uniforms.vctOrigin.value.copy(job.origin);
    this.uniforms.vctReady.value = 1;
    this.job = null;
    return true;
  }
  rebuild(solids: Solid[], lamps: Lamp[], cx: number, cz: number) {
    this.begin(solids, lamps, cx, cz);
    while (!this.stepRadiance(1e9));
    this.finish();
  }
  dispose() { for (const t of this.textures) t.dispose(); this.textures = []; }
  apply(material: T.MeshStandardMaterial, tiles = false, twoTone = false) {
    material.onBeforeCompile = shader => {
      Object.assign(shader.uniforms, this.uniforms);
      shader.vertexShader = 'varying vec3 vPoolWorld; uniform float poolTime;\n' + shader.vertexShader;
      shader.vertexShader = shader.vertexShader.replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\n vec4 poolPosition=vec4(transformed,1.0);\n #ifdef USE_INSTANCING\n poolPosition=instanceMatrix*poolPosition;\n #endif\n vPoolWorld = (modelMatrix * poolPosition).xyz;');
      shader.fragmentShader = `
        varying vec3 vPoolWorld;
        uniform highp sampler3D vct0; uniform highp sampler3D vct1;
        uniform highp sampler3D vct2; uniform highp sampler3D vct3;
        uniform vec3 vctOrigin; uniform vec3 vctExtent; uniform float vctStrength; uniform float vctReady;
        vec4 voxelSample(vec3 p, float lod) {
          vec3 uv = (p-vctOrigin)/vctExtent;
          if(any(lessThan(uv,vec3(0.0)))||any(greaterThan(uv,vec3(1.0)))) return vec4(0.0);
          if(lod<1.0) return mix(texture(vct0,uv),texture(vct1,uv),lod);
          if(lod<2.0) return mix(texture(vct1,uv),texture(vct2,uv),lod-1.0);
          return mix(texture(vct2,uv),texture(vct3,uv),clamp(lod-2.0,0.0,1.0));
        }
        vec3 traceCone(vec3 p,vec3 dir) {
          vec4 accum=vec4(0.0); float distance=1.05;
          for(int i=0;i<16;i++) {
            float diameter=max(.75,distance*.65);
            vec4 sampleV=voxelSample(p+dir*distance,clamp(log2(diameter/.75),0.0,3.0));
            accum += (1.0-accum.a)*sampleV;
            distance+=diameter*.7;
            if(accum.a>.95 || distance>23.0) break;
          }
          return accum.rgb;
        }
        vec3 coneDiffuse(vec3 p,vec3 n) {
          vec3 t=normalize(cross(n,abs(n.y)<.95?vec3(0,1,0):vec3(1,0,0)));
          vec3 b=cross(n,t); p+=n*.85;
          return traceCone(p,n)*.28 + .18*(traceCone(p,normalize(n+t))+traceCone(p,normalize(n-t))+traceCone(p,normalize(n+b))+traceCone(p,normalize(n-b)));
        }
        // __POOL_RT_HOOK__
      ` + shader.fragmentShader;
      shader.fragmentShader = shader.fragmentShader.replace('#include <lights_fragment_maps>', `#include <lights_fragment_maps>
        if(vctStrength>0.0&&vctReady>0.5) irradiance += coneDiffuse(vPoolWorld,inverseTransformDirection(normal,viewMatrix))*vctStrength*3.14159;`);
      // Exact intersections with the streamed room's regular portal walls.
      // Local fixtures retain shadow maps; this prevents unshadowed neighbouring
      // lamps bleeding through solid shared walls without per-pixel BVH rays.
      shader.fragmentShader=shader.fragmentShader.replace('#include <lights_fragment_begin>',
        T.ShaderChunk.lights_fragment_begin.replace('getPointLightInfo( pointLight, geometryPosition, directLight );',`
          getPointLightInfo( pointLight, geometryPosition, directLight );
          {
          vec3 lp=cameraPosition+inverseTransformDirection(pointLight.position,viewMatrix)*length(pointLight.position);
          vec3 surface=vPoolWorld+inverseTransformDirection(normal,viewMatrix)*.04;
          vec2 cell=floor((surface.xz+16.0)/32.0);
          vec3 delta=lp-surface;
          for(int axis=0;axis<2;axis++){
            float dc=axis==0?delta.x:delta.z;
            float sc=axis==0?surface.x:surface.z;
            float cc=axis==0?cell.x:cell.y;
            float boundary=cc*32.0+(dc>0.0?16.0:-16.0);
            float t=(boundary-sc)/(abs(dc)>.001?dc:.001);
            if(t>0.0&&t<1.0){
              vec3 hit=surface+delta*t;
              float along=axis==0?hit.z:hit.x;
              float local=mod(along+16.0,32.0)-16.0;
              if(abs(local)>4.0||hit.y>5.4)directLight.color=vec3(0.0);
            }
          }
          }
        `));
      if (tiles) {
        shader.fragmentShader = shader.fragmentShader.replace('#include <color_fragment>', `#include <color_fragment>
          vec3 wn=abs(normalize(cross(dFdx(vPoolWorld),dFdy(vPoolWorld))));
          vec2 tileUv=wn.y>.6?vPoolWorld.xz:(wn.x>.6?vPoolWorld.zy:vPoolWorld.xy);
          vec2 grid=tileUv*4.0; vec2 edge=min(fract(grid),1.0-fract(grid));
          vec2 aa=max(fwidth(grid),vec2(.003));
          float grout=1.0-smoothstep(.018-aa.x*.4,.025+aa.x*.6,min(edge.x,edge.y));
          float variation=fract(sin(dot(floor(grid),vec2(12.9898,78.233)))*43758.5453);
          float damp=1.0-.12*exp(-max(vPoolWorld.y,0.0)*2.5);
          diffuseColor.rgb*=mix(.94+variation*.10,.64,grout)*damp;
          if(${twoTone?'true':'false'} && wn.y<.6) {
            float upper=smoothstep(1.72,1.76,vPoolWorld.y);
            diffuseColor.rgb=mix(diffuseColor.rgb,vec3(.70,.73,.66)*mix(.94+variation*.10,.64,grout),upper);
          }
          float stain=sin(tileUv.x*2.4+sin(tileUv.y*.8))*sin(tileUv.y*1.7+tileUv.x*.6);
          float waterline=exp(-abs(vPoolWorld.y-.32)*8.0);
          diffuseColor.rgb=mix(diffuseColor.rgb,diffuseColor.rgb*vec3(.58,.56,.36),waterline*(.08+.04*stain));
          diffuseColor.rgb*=1.0-.025*smoothstep(.2,.9,stain);
        `);
        // Glazed ceramic: low base roughness with per-tile variation, glossier inside
        // the damp band near the water.
        shader.fragmentShader = shader.fragmentShader.replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n float wetBand=exp(-max(vPoolWorld.y,0.0)*1.2);\n roughnessFactor=clamp(mix(.30,.82,grout)-.10*wetBand,.16,1.0)*(0.96+variation*.12);');
        // Procedural tile relief: grout recessed, tile faces slightly crowned.
        shader.fragmentShader = shader.fragmentShader.replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
        {
          vec2 te=min(fract(tileUv*4.0),1.0-fract(tileUv*4.0));
          float gh=smoothstep(.0,.05,min(te.x,te.y));
          float crown=sin(te.x*3.14159)*sin(te.y*3.14159);
          float h=-.12*(1.0-gh)+.008*crown;
          float dhx=dFdx(h),dhy=dFdy(h);
          vec3 dpx=dFdx(vPoolWorld),dpy=dFdy(vPoolWorld);
          vec3 wNrm=normalize(cross(dpx,dpy));
          vec3 r1=cross(dpy,wNrm),r2=cross(wNrm,dpx);
          float det=dot(dpx,r1);
          vec3 deltaW=(sign(det)*(r1*dhx+r2*dhy))/max(abs(det),1e-8)*.008;
          normal=normalize(normal+(viewMatrix*vec4(-deltaW,0.0)).xyz);
        }`);
      }
    };
    material.customProgramCacheKey = () => `pool-vct-6-${tiles}-${twoTone}`;
  }
}
