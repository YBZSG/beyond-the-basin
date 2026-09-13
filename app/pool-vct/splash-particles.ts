import * as T from 'three';

const MAX_PARTICLES = 512;
type Particle = {
  x:number;y:number;z:number;vx:number;vy:number;vz:number;
  life:number;max:number;kind:number;seed:number;size:number;
};

/** Splash droplets and air bubbles, one THREE.Points pool for both. Droplets
 * arc under gravity and die re-entering the water; bubbles buoy upward,
 * wobble, and pop at the surface. Both hand a tiny ripple to the shallow-water
 * field on death, so the solver stays the single source of surface motion.
 * Pure CPU integration - a few hundred particles are nothing next to the sim. */
export class SplashParticles {
  points: T.Points;
  /** Live particle count, for tests. */
  get count() { return this.parts.length; }
  /** Read-only view of the live particles, for tests. */
  get live() { return this.parts; }
  ripples = 0;
  private parts: Particle[] = [];
  private positions = new Float32Array(MAX_PARTICLES * 3);
  private datas = new Float32Array(MAX_PARTICLES * 2);
  private geometry = new T.BufferGeometry();
  constructor() {
    this.geometry.setAttribute('position', new T.BufferAttribute(this.positions, 3).setUsage(T.DynamicDrawUsage));
    this.geometry.setAttribute('aData', new T.BufferAttribute(this.datas, 2).setUsage(T.DynamicDrawUsage));
    this.geometry.setDrawRange(0, 0);
    const material = new T.ShaderMaterial({
      transparent: true, depthWrite: false,
      vertexShader: `
        attribute vec2 aData;varying float vKind;
        void main(){vKind=aData.y;vec4 mv=modelViewMatrix*vec4(position,1.0);
          gl_PointSize=clamp(aData.x*(320.0/max(.1,-mv.z)),1.0,48.0);gl_Position=projectionMatrix*mv;}`,
      fragmentShader: `
        varying float vKind;
        void main(){
          vec2 q=gl_PointCoord*2.0-1.0;float r=length(q);
          float a;vec3 col=vec3(.86,.95,1.0);
          if(vKind<.5)a=(1.0-smoothstep(.3,1.0,r))*.9;
          else a=smoothstep(.5,.78,r)*(1.0-smoothstep(.82,1.0,r))*.8;
          if(a<.01)discard;
          gl_FragColor=vec4(col,a);}`,
    });
    this.points = new T.Points(this.geometry, material);
    this.points.frustumCulled = false;
    this.points.renderOrder = 2;
  }

  private add(p: Particle) {
    if (this.parts.length >= MAX_PARTICLES) this.parts.shift();
    this.parts.push(p);
  }

  /** A crown of droplets thrown outward by an impact of the given power. */
  splash(x: number, y: number, z: number, power: number) {
    const n = Math.min(40, Math.round(6 + power * 60));
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, sp = (.5 + 2.2 * power) * (.4 + .6 * Math.random());
      this.add({ x, y, z, vx: Math.cos(a) * sp, vz: Math.sin(a) * sp,
        vy: (1.1 + 2.2 * power) * (.5 + .7 * Math.random()),
        life: 0, max: 2.5, kind: 0, seed: Math.random() * 7, size: .05 + .09 * Math.random() });
    }
  }

  /** A burst of air carried under the surface by a body entering the water. */
  bubbles(x: number, y: number, z: number, count: number) {
    for (let i = 0; i < count; i++) {
      this.add({ x: x + (Math.random() - .5) * .5, y: y - .15 - Math.random() * .5, z: z + (Math.random() - .5) * .5,
        vx: (Math.random() - .5) * .4, vy: .2, vz: (Math.random() - .5) * .4,
        life: 0, max: 4, kind: 1, seed: Math.random() * 7, size: .03 + .06 * Math.random() });
    }
  }

  /** A dive: droplet crown above, bubble burst dragged below. */
  dive(x: number, y: number, z: number, power: number) {
    this.splash(x, y, z, power);
    this.bubbles(x, y, z, Math.min(30, 10 + Math.round(power * 30)));
  }

  update(dt: number, surface: (x: number, z: number) => number, ripple: (x: number, z: number, strength: number) => void) {
    const list = this.parts;
    let w = 0;
    for (let r = 0; r < list.length; r++) {
      const p = list[r];
      p.life += dt;
      let dead = p.life > p.max;
      if (p.kind === 0) p.vy -= 9.81 * dt;
      else {
        p.vy += (.65 - p.vy) * 2.2 * dt;
        p.x += Math.sin(p.life * 8 + p.seed) * .12 * dt;
        p.z += Math.cos(p.life * 7.3 + p.seed) * .12 * dt;
      }
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      const s = surface(p.x, p.z);
      if (!dead) {
        if (p.kind === 0 && p.vy < 0 && p.y <= s) { if (-p.vy > 1) { ripple(p.x, p.z, .02); this.ripples++; } dead = true; }
        else if (p.kind === 1 && p.y >= s - .02) { ripple(p.x, p.z, .015); this.ripples++; dead = true; }
      }
      if (dead) continue;
      list[w++] = p;
    }
    list.length = w;
    for (let i = 0; i < w; i++) {
      const p = list[i];
      this.positions[i * 3] = p.x; this.positions[i * 3 + 1] = p.y; this.positions[i * 3 + 2] = p.z;
      this.datas[i * 2] = p.size; this.datas[i * 2 + 1] = p.kind;
    }
    this.geometry.setDrawRange(0, w);
    (this.geometry.attributes.position as T.BufferAttribute).needsUpdate = true;
    (this.geometry.attributes.aData as T.BufferAttribute).needsUpdate = true;
  }

  dispose() {
    this.geometry.dispose();
    (this.points.material as T.Material).dispose();
  }
  rebase(shift:T.Vector3){for(const p of this.parts){p.x-=shift.x;p.y-=shift.y;p.z-=shift.z;}}
}
