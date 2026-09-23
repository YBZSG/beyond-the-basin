import { Fn, If, float, floor, fract, mix, smoothstep, texture, vec2, vec3, vec4 } from 'three/tsl';
import type { IUniform, Texture } from 'three';

/**
 * TSL port of the `WATER_WAVES` GLSL prelude in `water-optics.ts`.
 *
 * Why a separate module: the GLSL prelude is pasted into four `ShaderMaterial`s
 * in `water-system.ts` plus the liquid composite. Those materials are going away
 * one at a time, and a straight copy of the wave field into each TSL port would
 * mean four copies that drift. This module is the single TSL home for the field,
 * so the liquid pass and the later water-optics port share one implementation.
 *
 * Fidelity notes - the points that are easy to get wrong:
 *
 *  - `poolDepth` is NEAREST filtered and doubles as a hard land mask. The GLSL
 *    samples it raw in `poolRestDepth`, and hand-bilinears it in
 *    `poolRestDepthSmooth` because nearest-quantising a depth-derived value
 *    tiles the waterline into 0.125 m blocks along columns and step edges.
 *    Both behaviours are reproduced: raw for the mask, manual bilinear for
 *    shading.
 *  - `texture()` in TSL is the `texture2D` equivalent, and the hand-bilinear
 *    needs explicit texel-centre offsets (`i + vec2(.5)`), not `i`.
 *  - The GLSL `if (ripplesOn < .5) return 0.0;` becomes `select`-style branching
 *    inside `Fn`; an early `return` in a node graph is expressed as a
 *    conditional expression, because the whole graph is evaluated as one value.
 *  - `microSlope` has the same guard on `microOn`.
 *  - `simulationSlope` reads `poolRestDepth(...) > 0.` as a land mask and falls
 *    back to the centre height for dry neighbours, which is what keeps the
 *    normal flat at the waterline instead of tilting off the solver's sentinel.
 */

/**
 * The loose node type used instead of three's `Node`.
 *
 * Three's own `Node` is the *widened* base: assigning a `vec2()` to it drops
 * `.add`, `.mul`, `.x`, `.normalize` and every other swizzle helper, because
 * those live on the concrete node type. Declaring parameters and returns as
 * `Vec` keeps the call sites readable while still allowing the chained maths.
 *
 * `any` is deliberate here rather than an oversight - see the module comment.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Vec = any;

/** The uniform bag the existing water materials already expose. */
export type WaveUniforms = Record<string, IUniform>;

/**
 * Reads a uniform as a TSL node, or returns `fallback` when it is absent.
 *
 * No return annotation: three's node types carry the vector methods on the
 * concrete node type, and widening to `Node` erases them (`.add`, `.mul`,
 * `.swizzle`) for every caller downstream.
 */
function u(uniforms: WaveUniforms, name: string, fallback: number) {
  const entry = uniforms[name];
  if (entry === undefined || entry.value === undefined) return float(fallback);
  return float(entry.value as number);
}

/**
 * A `sampler2D` uniform as a TSL texture node.
 *
 * Throws rather than substituting a placeholder: every texture this module reads
 * (`poolSurface`, `poolDepth`, `poolDetail`) is wired up by the engine before the
 * first frame, so an absent one is a wiring bug, and a silently blank texture
 * would surface as "the water is flat" rather than as an error.
 *
 * Callers resolve this *before* opening their `Fn()`. Inside an `Fn` body the
 * lookup is deferred until the shader is built, which turns an immediate,
 * attributable failure into a distant one - and `detailHeight`, reachable both
 * directly and through `detailSlope`/`poolHeightSmooth`, would then report the
 * problem from three different stack depths depending on the call path.
 */
function tex(uniforms: WaveUniforms, name: string) {
  const entry = uniforms[name];
  if (entry === undefined) throw new Error(`water-waves-tsl: missing '${name}' uniform`);
  return texture(entry.value as Texture);
}

/**
 * The pool's rest depth at world XZ `p`, in metres. Zero means dry land.
 *
 * `poolDepth` is nearest-filtered on purpose: it is the solver's hard land mask,
 * so this is sampled without any interpolation.
 */
export function poolRestDepth(uniforms: WaveUniforms, p: Vec) {
  const poolDepth = tex(uniforms, 'poolDepth');
  return poolDepth.sample(p.add(float(48)).div(float(96))).r;
}

/**
 * Bilinear rest depth, for shading only.
 *
 * The solver needs the nearest-filtered mask, but anything *shaded* from depth
 * quantises to the 0.125 m cell grid, which is what used to tile the waterline
 * into screen-space blocks hugging columns and step edges. So it is bilineared
 * by hand from the four surrounding texel centres.
 */
export function poolRestDepthSmooth(uniforms: WaveUniforms, p: Vec) {
  const poolDepth = tex(uniforms, 'poolDepth');
  const poolCell = u(uniforms, 'poolCell', 1);
  const g = vec2(p.add(float(48)).div(poolCell).sub(float(.5)));
  const i = floor(g);
  const f = fract(g);
  const inv = poolCell.div(float(96));
  const d00 = poolDepth.sample(i.add(vec2(.5, .5)).mul(inv)).r;
  const d10 = poolDepth.sample(i.add(vec2(1.5, .5)).mul(inv)).r;
  const d01 = poolDepth.sample(i.add(vec2(.5, 1.5)).mul(inv)).r;
  const d11 = poolDepth.sample(i.add(vec2(1.5, 1.5)).mul(inv)).r;
  return mix(mix(d00, d10, f.x), mix(d01, d11, f.x), f.y);
}

/** Raw simulation height at world XZ `p` (before `waveHeight` scaling). */
export function poolHeight(uniforms: WaveUniforms, p: Vec) {
  const poolSurface = tex(uniforms, 'poolSurface');
  return poolSurface.sample(p.add(float(48)).div(float(96))).r;
}

/**
 * Ripple detail height. Zero when ripples are off.
 *
 * The GLSL early-returns (`if (ripplesOn < .5) return 0.0;`), so when the term is
 * disabled the detail texture is never fetched. That matters: `select()` would
 * still *build* the sample node and hoist the fetch above the branch, costing a
 * texture read per call site - and `detailSlope`/`poolHeightSmooth` call this
 * four and five times respectively. `If()` emits a real `if` block, so the fetch
 * lives inside it and the disabled path costs nothing.
 *
 * The `toVar()` accumulator is required by `If()`: the stack has no return
 * value, so the body assigns into a variable that outlives the branch.
 */
export function detailHeight(uniforms: WaveUniforms, p: Vec) {
  const poolDetail = tex(uniforms, 'poolDetail');
  const ripplesOn = u(uniforms, 'ripplesOn', 0);
  const rippleGain = u(uniforms, 'rippleGain', 0);
  return Fn(() => {
    const out = float(0).toVar();
    If(ripplesOn.greaterThanEqual(.5), () => {
      const uv = p.add(float(24)).div(float(48));
      const edge = uv.x.min(uv.y).min(uv.x.oneMinus()).min(uv.y.oneMinus());
      // Fade the detail field out at its own borders so the finite ripple grid
      // does not end in a visible hard edge.
      const sampled = poolDetail.sample(uv.clamp(vec2(0), vec2(1))).r;
      out.assign(sampled.mul(smoothstep(float(0), float(.045), edge)).mul(rippleGain).mul(ripplesOn));
    });
    return out;
  })();
}

/** Simulation + detail height, already scaled into metres. */
export function poolSurfaceHeight(uniforms: WaveUniforms, p: Vec) {
  const waveHeight = u(uniforms, 'waveHeight', 0);
  const simulationOn = u(uniforms, 'simulationOn', 1);
  // Probes resolved before the `Fn` opens, so a missing detail texture is
  // reported when the field is built rather than when the shader compiles.
  const sim = poolHeight(uniforms, p).mul(waveHeight).mul(simulationOn);
  const detail = detailHeight(uniforms, p);
  return Fn(() => sim.add(detail))();
}

/**
 * The concrete node type for the three slope terms.
 *
 * `vec2()` is a plain factory, not a type: `ReturnType<typeof vec2>` resolves to
 * `VarNode<...>` (the `toVar()`-wrapped form), which is *not* what `.add()`
 * returns - `.add()` yields `Node<"vec2">`. Annotating with the `VarNode` form
 * makes every `.add()` chain fail to assign, so `SlopeNode` names the arithmetic
 * result instead. It also widens `Node`'s vector methods away, which is why it
 * is `any` rather than three's own `Node`.
 */
type SlopeNode = Vec;

/**
 * Central-difference slope of the simulation field.
 *
 * Dry neighbours fall back to the centre height rather than to the sentinel, so
 * the normal stays flat at the waterline instead of tilting off it.
 *
 * `Fn<SlopeNode>` pins the return type: left bare, `Fn` infers it from the body
 * and the `.add()`/`.mul()` chain widens to `Node<"vec2" | "vec3">`, which then
 * has no matching `vec3(slope, float)` overload at the `poolNormal` call site.
 */
export function simulationSlope(uniforms: WaveUniforms, p: Vec): SlopeNode {
  const poolCell = u(uniforms, 'poolCell', 1);
  const waveHeight = u(uniforms, 'waveHeight', 0);
  const normalBoost = u(uniforms, 'normalBoost', 1);
  const simulationOn = u(uniforms, 'simulationOn', 1);
  const e = poolCell;
  // Probe the four neighbours and the centre outside the `Fn`, so the texture
  // lookups happen while the field is built.
  const h = poolHeight(uniforms, p);
  const pick = (offset: Vec, restDepth: Vec) => restDepth.greaterThan(0).select(poolHeight(uniforms, p.add(offset)), h);
  const w = pick(vec2(e.negate(), 0), poolRestDepth(uniforms, p.sub(vec2(e, 0))));
  const r = pick(vec2(e, 0), poolRestDepth(uniforms, p.add(vec2(e, 0))));
  const b = pick(vec2(0, e.negate()), poolRestDepth(uniforms, p.sub(vec2(0, e))));
  const n = pick(vec2(0, e), poolRestDepth(uniforms, p.add(vec2(0, e))));
  return Fn<SlopeNode>(() =>
    vec2(r.sub(w), n.sub(b)).div(e.mul(2)).mul(waveHeight).mul(normalBoost).mul(simulationOn))();
}

/**
 * Central-difference slope of the ripple detail field.
 *
 * The four `detailHeight` probes are built *before* the `Fn` opens, not inside
 * it. Two reasons: `detailHeight` reads the detail texture, and resolving a
 * texture uniform is a wiring check that belongs at build time rather than at
 * shader-compile time; and each probe opens its own `Fn`, which would otherwise
 * nest four stack scopes inside this one for no benefit.
 */
export function detailSlope(uniforms: WaveUniforms, p: Vec): SlopeNode {
  const detailCell = u(uniforms, 'detailCell', 1);
  const e = detailCell;
  const xp = detailHeight(uniforms, p.add(vec2(e, 0)));
  const xn = detailHeight(uniforms, p.sub(vec2(e, 0)));
  const yp = detailHeight(uniforms, p.add(vec2(0, e)));
  const yn = detailHeight(uniforms, p.sub(vec2(0, e)));
  return Fn<SlopeNode>(() => vec2(xp.sub(xn), yp.sub(yn)).div(e.mul(2)))();
}

/**
 * Two-scale analytic micro-normal detail.
 *
 * Band-limited by `footprint` so subpixel frequencies are suppressed without a
 * TAA history - the two wave vectors are unrelated in scale and direction, and
 * each fades out once its period approaches the pixel footprint.
 *
 * Like `detailHeight`, the GLSL early-returns when `microOn < .5`, so the whole
 * body sits in an `If()` and the disabled path costs nothing. The trailing
 * `* microOn` is kept rather than being folded into the branch condition: GLSL
 * scales by the uniform's actual value, which need not be exactly 0 or 1.
 */
export function microSlope(uniforms: WaveUniforms, p: Vec, footprint: Vec): SlopeNode {
  const microOn = u(uniforms, 'microOn', 0);
  const poolTime = u(uniforms, 'poolTime', 0);
  const causticsSpeed = u(uniforms, 'causticsSpeed', 1);
  const causticsScale = u(uniforms, 'causticsScale', 1);
  const microStrength = u(uniforms, 'microStrength', 0);
  const pack = uniforms.microOrigin;
  const microOrigin = pack === undefined ? vec2(0, 0) : (pack.value as { x: number; y: number });
  return Fn<SlopeNode>(() => {
    const out = vec2(0).toVar();
    If(microOn.greaterThanEqual(.5), () => {
      const pShifted = p.add(vec2(microOrigin.x, microOrigin.y));
      const t = poolTime.mul(causticsSpeed);
      const k1 = vec2(8.1, 5.7).mul(causticsScale);
      const k2 = vec2(-20.3, 27.1).mul(causticsScale);
      const largeFade = smoothstep(float(.7), float(2.4), footprint.mul(k1.length())).oneMinus();
      const smallFade = smoothstep(float(.7), float(2.4), footprint.mul(k2.length())).oneMinus();
      // A slow third scale warps the phase of the first, so the two bands do not
      // beat into a visible repeating interference pattern.
      const phase = pShifted.dot(vec2(.47, -.31)).add(t.mul(.04)).sin().mul(.35);
      const s1 = k1.mul(pShifted.dot(k1).add(t.mul(.18)).add(phase).cos()).mul(.00020).mul(largeFade);
      const s2 = k2.mul(pShifted.dot(k2).sub(t.mul(.11)).cos()).mul(.000045).mul(smallFade);
      out.assign(s1.add(s2).mul(microStrength).mul(microOn));
    });
    return out;
  })();
}

/**
 * Shading normal. `poolNormal` in the GLSL, with the `.xzy` swizzle preserved.
 *
 * The GLSL is `normalize(vec3(-simulationSlope(p) - detailSlope(p) -
 * microSlope(p, .09), 1.0).xzy)`. Each term carries its own unary minus, so the
 * three are negated individually before summing rather than negating the total:
 * `-a-b-c` and `-(a+b+c)` agree numerically, but negating the sum leaves the
 * sign of the result to however TSL distributes `negate()` across an `add()`
 * chain, and the generated GLSL for the combined form is hard to verify by eye.
 * Negating each term keeps the expression a literal transliteration.
 *
 * The terms are added directly rather than re-wrapped in `vec2()`: the wrap is a
 * runtime no-op, but `vec2()`'s signature has a single `Node<"vec2">` branch and
 * an inferred `vec2 | vec3` has no matching overload.
 */
export function poolNormal(uniforms: WaveUniforms, p: Vec, footprint: Vec = float(.09)): SlopeNode {
  // The three slope probes are built before the `Fn` opens, so a missing texture
  // uniform surfaces here rather than at shader-compile time.
  const slope: SlopeNode = simulationSlope(uniforms, p).negate()
    .add(detailSlope(uniforms, p).negate())
    .add(microSlope(uniforms, p, footprint).negate());
  return Fn<SlopeNode>(() => {
    // `vec3(-sx, -sy, 1).xzy` is `(-sx, 1, -sy)` - i.e. the result is Y-up.
    return vec3(slope, float(1)).xzy.normalize();
  })();
}

/**
 * Wide-kernel height, used by the liquid composite to decide where the
 * reconstructed surface sits relative to the resting water level.
 *
 * The kernel is a 4-4-8 stencil: the centre weighted 4, the four axial
 * neighbours 2 each, the four diagonals 1 each, over 16 - plus a quarter-weighted
 * detail term. Reproduced exactly, because this value feeds a `smoothstep` that
 * decides how much of the composite shows.
 */
export function poolHeightSmooth(uniforms: WaveUniforms, p: Vec) {
  const waveHeight = u(uniforms, 'waveHeight', 0);
  const simulationOn = u(uniforms, 'simulationOn', 1);
  // No `Fn` here: the whole thing is a pure expression over `poolHeight` and
  // `detailHeight`, with no `toVar`/`assign`, so a stack scope would add nothing
  // except another level for a texture-uniform lookup to hide behind.
  let h = poolHeight(uniforms, p).mul(4);
  h = h.add(
    poolHeight(uniforms, p.add(vec2(.22, 0)))
      .add(poolHeight(uniforms, p.sub(vec2(.22, 0))))
      .add(poolHeight(uniforms, p.add(vec2(0, .22))))
      .add(poolHeight(uniforms, p.sub(vec2(0, .22))))
      .mul(2),
  );
  h = h.add(
    poolHeight(uniforms, p.add(vec2(.16, .16)))
      .add(poolHeight(uniforms, p.sub(vec2(.16, .16))))
      .add(poolHeight(uniforms, p.add(vec2(-.16, .16))))
      .add(poolHeight(uniforms, p.add(vec2(.16, -.16)))),
  );
  const d = detailHeight(uniforms, p.add(vec2(.12, 0)))
    .add(detailHeight(uniforms, p.sub(vec2(.12, 0))))
    .add(detailHeight(uniforms, p.add(vec2(0, .12))))
    .add(detailHeight(uniforms, p.sub(vec2(0, .12))))
    .mul(.25);
  return h.div(16).mul(waveHeight).mul(simulationOn).add(d);
}

/**
 * Everything the wave field can offer, built against one uniform bag.
 *
 * The signatures are loose (`Vec` in, inferred node out) on purpose: pinning
 * them to three's `Node` would erase the vector methods every caller needs, and
 * pinning them to the exact concrete node type is not expressible across a
 * record of functions. `Vec` is the widest type that still allows `.add`/`.mul`.
 */
export type WaveField = {
  poolRestDepth(p: Vec): Vec;
  poolRestDepthSmooth(p: Vec): Vec;
  poolHeight(p: Vec): Vec;
  detailHeight(p: Vec): Vec;
  poolSurfaceHeight(p: Vec): Vec;
  simulationSlope(p: Vec): Vec;
  detailSlope(p: Vec): Vec;
  microSlope(p: Vec, footprint: Vec): Vec;
  poolNormal(p: Vec, footprint?: Vec): Vec;
  poolHeightSmooth(p: Vec): Vec;
};

/** Binds the functions to a uniform bag, so callers stop threading it through. */
export function createWaveField(uniforms: WaveUniforms): WaveField {
  return {
    poolRestDepth: (p) => poolRestDepth(uniforms, p),
    poolRestDepthSmooth: (p) => poolRestDepthSmooth(uniforms, p),
    poolHeight: (p) => poolHeight(uniforms, p),
    detailHeight: (p) => detailHeight(uniforms, p),
    poolSurfaceHeight: (p) => poolSurfaceHeight(uniforms, p),
    simulationSlope: (p) => simulationSlope(uniforms, p),
    detailSlope: (p) => detailSlope(uniforms, p),
    microSlope: (p, footprint) => microSlope(uniforms, p, footprint),
    poolNormal: (p, footprint) => poolNormal(uniforms, p, footprint ?? float(.09)),
    poolHeightSmooth: (p) => poolHeightSmooth(uniforms, p),
  };
}

/** Re-exported so callers can build a uniform bag without importing three/tsl. */
export { vec4 };
