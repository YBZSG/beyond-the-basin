import * as T from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// The egg-boy prop (蛋小黄): a chunky bathtub-float mascot converted from the
// Maya project in 蛋小黄/ into public/assets/models/egg-boy/egg-boy.glb.
//
// The GLB keeps every rig leaf as its own named mesh (18 of them: hands, legs
// and socks are additionally split left/right), so the runtime can animate the
// parts independently instead of needing a skeleton. Each part carries the
// hinge point it should rotate about, in template space (metres, feet at y=0).
export type EggRole = 'static' | 'antenna' | 'arm' | 'leg' | 'foot' | 'eye';
export type EggBoyPart = {
  name: string;
  role: EggRole;
  geometry: T.BufferGeometry;
  material: T.MeshStandardMaterial;
  /** Rotation hinge in template space. Unused for `static` parts. */
  pivot: T.Vector3;
};
export type EggBoyTemplate = { parts: EggBoyPart[]; height: number; center: number };

// The Maya model stands 2.42 m tall; shrink it to a bathtub float that rides
// chest high beside the player (eye height 1.64 m, collider radius .42 m).
const TARGET_HEIGHT = 1.06;

function classify(name: string): EggRole {
  if (name === 'antenna') return 'antenna';
  if (name.startsWith('hand_')) return 'arm';
  if (name.startsWith('leg_')) return 'leg';
  if (name.startsWith('socks_')) return 'foot';
  if (name.startsWith('eye_')) return 'eye';
  return 'static';
}

// Hinge heuristics, all derived from the part's own bounding box. The model is
// symmetric about x=0 and faces +z, so "the end nearest the centreline" is a
// reliable shoulder/hip for an outstretched limb.
function pivotFor(role: EggRole, box: T.Box3, out: T.Vector3) {
  const mn = box.min, mx = box.max;
  switch (role) {
    case 'antenna': out.set((mn.x + mx.x) / 2, mn.y, (mn.z + mx.z) / 2); break; // base
    case 'arm':
    case 'leg':
      // Shoulder / hip: the end of the limb nearest the centreline, at the top.
      box.getCenter(out);
      out.set(Math.abs(mn.x) < Math.abs(mx.x) ? mn.x : mx.x, mx.y, out.z);
      break;
    case 'foot': box.getCenter(out); out.y = mx.y; break;                       // knee
    // 'eye' and 'static' keep whatever was already in `out`
  }
}

export function loadEggBoyTemplate(anisotropy: number): Promise<EggBoyTemplate> {
  return new Promise((resolve, reject) => {
    new GLTFLoader().load('/assets/models/egg-boy/egg-boy.glb', gltf => {
      gltf.scene.updateMatrixWorld(true);
      const parts: EggBoyPart[] = [];
      const boxes: T.Box3[] = [];
      const box = new T.Box3();
      gltf.scene.traverse(o => {
        if (!(o instanceof T.Mesh)) return;
        const material = o.material as T.MeshStandardMaterial;
        material.envMapIntensity = .7;
        if (material.map) material.map.anisotropy = anisotropy;
        o.geometry.applyMatrix4(o.matrixWorld);
        const local = new T.Box3().setFromBufferAttribute(o.geometry.attributes.position as T.BufferAttribute);
        box.expandByObject(o);
        const name = o.name;
        parts.push({ name, role: classify(name), geometry: o.geometry, material, pivot: new T.Vector3() });
        boxes.push(local);
      });
      if (!parts.length) { reject(new Error('egg-boy: template has no meshes')); return; }

      const size = new T.Vector3(); box.getSize(size);
      // Uniform scale; normals survive it, so the parts stay correctly lit.
      // The per-part boxes are scaled too, so every hinge below comes out in
      // the same (final) template space and must NOT be scaled again.
      const scale = TARGET_HEIGHT / size.y;
      for (const part of parts) part.geometry.scale(scale, scale, scale);
      for (const b of boxes) { b.min.multiplyScalar(scale); b.max.multiplyScalar(scale); }

      // Eyeball, pupil and lash of one side must turn about the SAME point or
      // the pupil drifts out of the eye, so union the ball+pupil boxes (the
      // lash sits above the eye and would skew the centre) and share it.
      for (const side of ['L', 'R']) {
        const union = new T.Box3();
        for (let i = 0; i < parts.length; i++) {
          const p = parts[i];
          if (p.role !== 'eye' || !p.name.startsWith('eye_' + side)) continue;
          if (!/ball|pupil/.test(p.name)) continue;
          union.union(boxes[i]);
        }
        if (union.isEmpty()) continue;
        const c = new T.Vector3(); union.getCenter(c);
        for (const p of parts) if (p.role === 'eye' && p.name.startsWith('eye_' + side)) p.pivot.copy(c);
      }
      for (let i = 0; i < parts.length; i++) pivotFor(parts[i].role, boxes[i], parts[i].pivot);
      // centre = shell centre height relative to the feet; the prop visual is
      // shifted down by it so the collider sphere wraps the round body, leaving
      // the head above the waterline and the legs paddling below.
      resolve({ parts, height: size.y * scale, center: (box.min.y + size.y / 2) * scale });
    }, undefined, reject);
  });
}

// ---- procedural rig ------------------------------------------------------
// No skeleton, no clips: every part is a rigid chunk, so animating it is just
// "rotate about its hinge". Because the parts are only linked by maths, a foot
// composes its knee bend on top of the thigh's kick instead of inheriting it.

export type EggRigPart = { role: EggRole; pivot: T.Vector3; phase: number };
export type EggRig = { parts: EggRigPart[]; seed: number; base: T.Matrix4 };

export function createEggRig(template: EggBoyTemplate, seed: number): EggRig {
  return {
    // Paired limbs are exactly half a cycle apart, so the arms paddle and the
    // legs kick in alternation instead of flapping in lockstep. Eyes share the
    // seed with no side offset because both look the same way.
    parts: template.parts.map(p => ({
      role: p.role,
      pivot: p.pivot.clone(),
      phase: seed + (p.role === 'eye' || p.pivot.x >= 0 ? 0 : Math.PI),
    })),
    seed,
    // Every part hangs the same distance below the collider centre.
    base: new T.Matrix4().makeTranslation(0, -template.center, 0),
  };
}

const _to = new T.Matrix4(), _fro = new T.Matrix4();
const _q = new T.Quaternion(), _e = new T.Euler();
const _legR = new T.Matrix4(), _legL = new T.Matrix4(), _bend = new T.Matrix4();

/** out = translate(pivot) · rotate(rx,ry,rz) · translate(-pivot). */
function about(pivot: T.Vector3, rx: number, ry: number, rz: number, out: T.Matrix4) {
  _q.setFromEuler(_e.set(rx, ry, rz, 'XYZ'));
  out.makeRotationFromQuaternion(_q);
  _to.makeTranslation(pivot.x, pivot.y, pivot.z);
  _fro.makeTranslation(-pivot.x, -pivot.y, -pivot.z);
  return out.premultiply(_to).multiply(_fro);
}

/**
 * Rewrite every part's local matrix for one frame.
 * `speed` is the body's velocity magnitude: a thrown egg-boy flails harder.
 */
export function tickEggRig(rig: EggRig, time: number, speed: number, targets: T.Matrix4[]) {
  const t = time;
  const flail = Math.min(1, Math.max(0, (speed - .45) / 2.6));
  const amp = 1 + flail * 1.7, w = 1.5 + flail * 3.2;
  _legR.identity(); _legL.identity();

  // Thighs first: the feet compose their knee bend on top of the kick.
  for (const p of rig.parts) {
    if (p.role !== 'leg') continue;
    const s = p.pivot.x >= 0 ? 1 : -1;
    about(p.pivot, 0, 0, s * .20 * amp * Math.sin(t * w * .85 + p.phase), s > 0 ? _legR : _legL);
  }

  for (let i = 0; i < rig.parts.length; i++) {
    const p = rig.parts[i], m = targets[i];
    if (!m) continue;
    const s = p.pivot.x >= 0 ? 1 : -1;     // +1 for the +x side of the body
    const ph = p.phase; // already carries the half-cycle offset for -x limbs
    // Hinges live in template space, so the part is rotated FIRST and only then
    // dropped onto the collider by `base`. Reversing the two would pivot every
    // limb about a point half a body below the model.
    switch (p.role) {
      case 'static': m.copy(rig.base); break;
      case 'antenna':
        about(p.pivot, .10 * amp * Math.sin(t * 1.31 + ph), 0, .15 * amp * Math.sin(t * 1.93 + ph), m).premultiply(rig.base);
        break;
      case 'arm': {
        // Circular paddle: rotation about z lifts the outstretched arm, about y
        // sweeps it fore/aft, a quarter cycle apart.
        const rz = s * (.10 + .13 * amp * Math.sin(t * w + ph));
        about(p.pivot, 0, .15 * amp * Math.cos(t * w + ph), rz, m).premultiply(rig.base);
        break;
      }
      case 'leg':
        m.copy(s > 0 ? _legR : _legL).premultiply(rig.base);
        break;
      case 'foot':
        // Knee bend on top of the thigh kick: the foot's matrix is applied
        // first, then the leg's rotation carries the whole lower limb.
        about(p.pivot, 0, 0, s * .16 * amp * Math.sin(t * w * .85 + ph - .7), _bend);
        m.multiplyMatrices(s > 0 ? _legR : _legL, _bend).premultiply(rig.base);
        break;
      case 'eye': {
        // Both eyes share a target so the pair tracks together; slow saccades.
        const ry = .20 * Math.sin(t * .61 + rig.seed * 1.7);
        const rx = .11 * Math.sin(t * .47 + rig.seed * 2.3);
        about(p.pivot, rx, ry, 0, m).premultiply(rig.base);
        break;
      }
    }
  }
}
