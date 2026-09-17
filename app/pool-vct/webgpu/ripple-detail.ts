import * as T from 'three';
import { NodeMaterial, WebGPURenderer } from 'three/webgpu';
import {
  Discard, Fn, If, Loop, clamp, exp, float, ivec2, mix, positionLocal, select,
  smoothstep, texture, textureLoad, uv, varying, vec2, vec4,
} from 'three/tsl';
import { floatUniform, vec2Uniform, vec4Attribute, type PoolRenderer, type ScalarUniform, type Vec2Uniform } from '../backend';

export const DETAIL_DOMAIN = 48;
const STEP = 1 / 120, MAX_SOURCES = 128;

/** Independent centimetre-scale height field. It adds visual wave energy,
 * never momentum to the shallow solver or buoyancy readback.
 *
 * Ported from GLSL to TSL so one graph serves both the WebGPU backend and the
 * WebGL2 fallback. Cell coordinates come from `uv()` instead of the fragment
 * coordinate, so both backends agree on where the domain origin sits. */
export class RippleDetail {
  readonly size: number;
  readonly cell: number;
  frequency = 22;
  private a: T.RenderTarget;
  private b: T.RenderTarget;
  private source: T.RenderTarget;
  private current: T.RenderTarget;
  readonly uniform: { value: T.Texture };
  private depthBox: { value: T.Texture };
  private scene = new T.Scene();
  private camera = new T.Camera();
  private quad = new T.PlaneGeometry(2, 2);
  private mesh: T.Mesh;
  private updateMaterial: NodeMaterial;
  private copyMaterial: NodeMaterial;
  private emitMaterial: NodeMaterial;
  private sourceScene = new T.Scene();
  private sourceGeometry = new T.InstancedBufferGeometry();
  private sources = new Float32Array(MAX_SOURCES * 4);
  private queued: number[] = [];
  private acc = 0;
  private quiet = 10;
  private initialized = false;
  private needsClear = true;
  private shift = new T.Vector2();
  private sourceOn: ScalarUniform;
  private frequencyU: ScalarUniform;
  private shiftU: Vec2Uniform;
  private fieldNode: ReturnType<typeof texture>;
  private depthNode: ReturnType<typeof texture>;
  private sourceTextureNode: ReturnType<typeof texture>;

  constructor(size: number, depth: { value: T.Texture }) {
    this.size = size;
    this.cell = DETAIL_DOMAIN / size;
    this.depthBox = depth;
    const target = () => new T.RenderTarget(size, size, { type: T.HalfFloatType, depthBuffer: false });
    this.a = target(); this.b = target(); this.source = target(); this.current = this.a;
    this.uniform = { value: this.current.texture };

    const sizeF = float(size), cellF = float(this.cell), LAST = float(size - 1);
    this.fieldNode = texture(this.a.texture);
    this.depthNode = texture(depth.value);
    this.sourceTextureNode = texture(this.source.texture);
    this.sourceOn = floatUniform(0);
    this.frequencyU = floatUniform(this.frequency);
    this.shiftU = vec2Uniform(this.shift);

    this.updateMaterial = new NodeMaterial();
    this.updateMaterial.depthTest = false;
    this.updateMaterial.depthWrite = false;
    this.updateMaterial.toneMapped = false;
    this.updateMaterial.vertexNode = vec4(positionLocal.xy, 0, 1);
    this.updateMaterial.fragmentNode = Fn(() => {
      const here = uv().mul(sizeF).floor().toVar();
      const c = ivec2(clamp(here, vec2(0), LAST));
      // A cell counts as water when it is inside the domain and the coarse
      // mask says there is depth there; dry neighbours fall back to the centre.
      const wetHere = (ox: number, oy: number) => {
        const q = here.add(vec2(ox, oy));
        const inside = q.x.greaterThanEqual(0).and(q.y.greaterThanEqual(0))
          .and(q.x.lessThan(sizeF)).and(q.y.lessThan(sizeF));
        const uvDepth = q.add(.5).mul(cellF).sub(DETAIL_DOMAIN / 2).add(DETAIL_DOMAIN).div(DETAIL_DOMAIN * 2);
        return inside.and(texture(this.depthNode, uvDepth).r.greaterThan(0));
      };
      const out = vec4(0).toVar();
      If(wetHere(0, 0), () => {
        const s = textureLoad(this.fieldNode, c).rg.toVar();
        const centre = s.r.toVar();
        const neighbour = (ox: number, oy: number) => select(
          wetHere(ox, oy),
          textureLoad(this.fieldNode, ivec2(clamp(here.add(vec2(ox, oy)), vec2(0), LAST))).r,
          centre,
        );
        const mx = here.x.min(LAST.sub(here.x));
        const my = here.y.min(LAST.sub(here.y));
        const edge = mx.min(my).mul(cellF);
        const damp = exp(float(-STEP).mul(float(1.3).add(float(5).mul(float(1).sub(smoothstep(0, 2, edge))))));
        const speed2 = (STEP * .85 * .85) / (this.cell * this.cell);
        const neighbours = neighbour(-1, 0).add(neighbour(1, 0)).add(neighbour(0, 1)).add(neighbour(0, -1));
        const v = s.g.add(float(speed2).mul(neighbours.sub(centre.mul(4)))).mul(damp);
        const h = s.r.add(float(STEP).mul(v)).add(textureLoad(this.sourceTextureNode, c).r.mul(this.sourceOn.node));
        out.assign(vec4(clamp(h, -.012, .012), clamp(v, -.15, .15), 0, 0));
      });
      return out;
    })();

    this.copyMaterial = new NodeMaterial();
    this.copyMaterial.depthTest = false;
    this.copyMaterial.depthWrite = false;
    this.copyMaterial.toneMapped = false;
    this.copyMaterial.vertexNode = vec4(positionLocal.xy, 0, 1);
    this.copyMaterial.fragmentNode = Fn(() => {
      const here = uv().mul(sizeF).floor().toVar();
      const shifted = here.add(this.shiftU.node).div(sizeF).toVar();
      const uvDepth = here.add(.5).mul(cellF).sub(DETAIL_DOMAIN / 2).add(DETAIL_DOMAIN).div(DETAIL_DOMAIN * 2);
      const inside = shifted.x.greaterThanEqual(0).and(shifted.y.greaterThanEqual(0))
        .and(shifted.x.lessThanEqual(1)).and(shifted.y.lessThanEqual(1));
      const has = inside.and(texture(this.depthNode, uvDepth).r.greaterThan(0));
      return select(has, texture(this.fieldNode, shifted), vec4(0));
    })();

    this.mesh = new T.Mesh(this.quad, this.updateMaterial);
    this.mesh.frustumCulled = false;
    this.scene.add(this.mesh);

    // Instanced splats: one quad per impact, drawn additively into `source`.
    this.sourceGeometry.index = this.quad.index;
    this.sourceGeometry.setAttribute('position', this.quad.attributes.position);
    this.sourceGeometry.setAttribute('splat', new T.InstancedBufferAttribute(this.sources, 4).setUsage(T.DynamicDrawUsage));
    const splatAttribute = vec4Attribute('splat');
    const vSplat = varying(splatAttribute);
    const vPoint = varying(vSplat.xy.add(positionLocal.xy.mul(vSplat.w).mul(3)));

    this.emitMaterial = new NodeMaterial();
    this.emitMaterial.transparent = true;
    this.emitMaterial.depthTest = false;
    this.emitMaterial.depthWrite = false;
    this.emitMaterial.toneMapped = false;
    // Explicit ONE + ONE: RGB energy is independent of alpha=0 in the field.
    this.emitMaterial.blending = T.CustomBlending;
    this.emitMaterial.blendSrc = T.OneFactor;
    this.emitMaterial.blendDst = T.OneFactor;
    this.emitMaterial.vertexNode = vec4(vPoint.div(DETAIL_DOMAIN / 2), 0, 1);
    this.emitMaterial.fragmentNode = Fn(() => {
      const point = vPoint.toVar();
      const origin = vSplat.xy.toVar(), power = vSplat.z.toVar(), radius = vSplat.w.toVar();
      If(texture(this.depthNode, point.add(DETAIL_DOMAIN).div(DETAIL_DOMAIN * 2)).r.lessThanEqual(0), () => { Discard(); });
      // Sample the source-to-pixel segment: no direct splash injection through masonry.
      Loop(12, ({ i }) => {
        const step = mix(origin, point, float(i).add(1).div(12));
        If(texture(this.depthNode, step.add(DETAIL_DOMAIN).div(DETAIL_DOMAIN * 2)).r.lessThanEqual(0), () => { Discard(); });
      });
      const q = point.sub(origin).div(radius);
      const r = q.length().toVar();
      const a = this.frequencyU.node.mul(radius);
      const sinc = select(r.greaterThan(.0001), a.mul(r).sin().div(r), a);
      // ((2+a²-r²)·cos(ar) + (a-2a·r²)·sinc) / (2+2a²)
      const a2 = a.mul(a), r2 = r.mul(r);
      const packet = float(2).add(a2).sub(r2).mul(a.mul(r).cos())
        .add(a.sub(float(2).mul(a).mul(r2)).mul(sinc))
        .div(float(2).add(float(2).mul(a2)));
      return vec4(power.mul(packet).mul(exp(r.mul(r).mul(-.5))), 0, 0, 0);
    })();
    const emitter = new T.Mesh(this.sourceGeometry, this.emitMaterial);
    emitter.frustumCulled = false;
    this.sourceScene.add(emitter);
  }

  get active() { return this.quiet < 8; }

  impact(x: number, z: number, power: number, radius = .16) {
    if (![x, z, power, radius].every(Number.isFinite) || Math.abs(x) > 23 || Math.abs(z) > 23 || power <= 0) return;
    if (this.queued.length >= MAX_SOURCES * 4) return;
    this.queued.push(x, z, Math.min(.006, power), Math.max(this.cell * 2, radius));
    this.quiet = 0;
  }

  rebase(x: number, z: number) {
    this.shift.x += x / this.cell;
    this.shift.y += z / this.cell;
    for (let i = 0; i < this.queued.length; i += 4) { this.queued[i] -= x; this.queued[i + 1] -= z; }
  }

  terrainChanged() { this.initialized = false; }

  frame(renderer: PoolRenderer, dt: number, enabled: boolean) {
    if (this.depthNode.value !== this.depthBox.value) this.depthNode.value = this.depthBox.value;
    const gpu = renderer as unknown as WebGPURenderer;
    const old = gpu.getRenderTarget();
    const color = gpu.getClearColor(new T.Color());
    const alpha = gpu.getClearAlpha();
    const auto = gpu.autoClear;
    gpu.autoClear = false;
    gpu.setClearColor(0, 0);
    try {
      if (this.needsClear) { for (const t of [this.a, this.b, this.source]) { gpu.setRenderTarget(t); gpu.clear(); } this.needsClear = false; }
      if (this.shift.lengthSq() > 0 || !this.initialized) {
        this.fieldNode.value = this.current.texture;
        this.mesh.material = this.copyMaterial;
        const next = this.current === this.a ? this.b : this.a;
        gpu.setRenderTarget(next);
        gpu.render(this.scene, this.camera);
        this.current = next;
        this.shift.set(0, 0);
        this.initialized = true;
      }
      if (!enabled) {
        if (this.active) for (const t of [this.a, this.b]) { gpu.setRenderTarget(t); gpu.clear(); }
        this.queued.length = 0; this.quiet = 10; this.acc = 0; return;
      }
      const wasActive = this.active;
      this.quiet += dt;
      if (!this.active) { if (wasActive) for (const t of [this.a, this.b]) { gpu.setRenderTarget(t); gpu.clear(); } return; }
      this.acc = Math.min(this.acc + Math.min(dt, 8 * STEP), 8 * STEP);
      if (this.acc + 1e-10 < STEP) return;
      gpu.setRenderTarget(this.source);
      gpu.clear();
      const count = this.queued.length / 4;
      if (count) {
        this.sources.set(this.queued);
        this.sourceGeometry.instanceCount = count;
        this.sourceGeometry.attributes.splat.needsUpdate = true;
        this.frequencyU.set(Math.min(this.frequency, Math.PI / (2 * this.cell)));
        gpu.render(this.sourceScene, this.camera);
        this.queued.length = 0;
      }
      let i = 0;
      this.mesh.material = this.updateMaterial;
      while (this.acc + 1e-10 >= STEP && i < 8) {
        this.fieldNode.value = this.current.texture;
        this.sourceOn.set(i === 0 && count ? 1 : 0);
        const next = this.current === this.a ? this.b : this.a;
        gpu.setRenderTarget(next);
        gpu.render(this.scene, this.camera);
        this.current = next;
        this.acc -= STEP;
        i++;
      }
    } finally {
      this.uniform.value = this.current.texture;
      gpu.setRenderTarget(old);
      gpu.setClearColor(color, alpha);
      gpu.autoClear = auto;
    }
  }

  dispose() {
    for (const t of [this.a, this.b, this.source]) t.dispose();
    for (const m of [this.updateMaterial, this.copyMaterial, this.emitMaterial]) m.dispose();
    this.quad.dispose();
    this.sourceGeometry.dispose();
  }
}
