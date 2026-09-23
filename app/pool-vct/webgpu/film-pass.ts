import type { Node, TextureNode } from 'three/webgpu';
import { Fn, float, fract, max, min, mix, pow, sin, smoothstep, sqrt, uniform, uv, vec2, vec3, vec4 } from 'three/tsl';

/**
 * Camcorder filter chain: barrel distortion, chromatic fringing, sensor grain,
 * vignette and four graded looks. Ported from the GLSL `ShaderPass` to a TSL
 * node so the same graph drives both the WebGPU backend and the WebGL2
 * fallback - and, more importantly, so it can sit in a `RenderPipeline` chain
 * instead of a classic `EffectComposer`, which cannot drive a node renderer.
 *
 * Porting notes (the parts that are easy to get wrong):
 *  - `vUv` in the GLSL source is the fragment's 0..1 coordinate, which is
 *    exactly what `uv()` gives; nothing had to be rewritten for WebGPU's
 *    different framebuffer origin because the input is normalised already.
 *  - `uniform int filterMode` becomes a float uniform. TSL has no int uniform
 *    plumbing worth the trouble, and the shader only ever compares it against
 *    the constants 0..3, so float equality is exact and sufficient.
 *  - The per-branch `if` statements become a chain of `mix()` between looks.
 *    A node graph is evaluated as one expression, so branching is expressed as
 *    selection; `filterMode` is constant for a whole frame, so the cost is
 *    paid in arithmetic rather than in divergence.
 *  - `sqrt(max(c, 0))` keeps the guard from the original. A negative operand
 *    is undefined and the GPU backend will happily produce NaN and smear it
 *    across the frame.
 *  - The input must already be a real texture, not an arbitrary expression.
 *    The grade resamples its input at *distorted* coordinates, and only a
 *    texture has `sample()`. Callers hand in a pass texture
 *    (`litPass.getTextureNode('output')`); see `film-chain.ts` for why
 *    materialising an expression with `convertToTexture()` is not acceptable
 *    here - that path re-contexts the upstream `Fn` at render time and every
 *    `assign` inside it fails with "No stack defined".
 *    Passing a non-texture is caught below by a clear error rather than the
 *    opaque `input.sample is not a function` it used to produce.
 */
export type FilmUniforms = {
  /** 0 original, 1 CCD, 2 VHS, 3 cold documentary. */
  filterMode: { value: number };
  time: { value: number };
};

export type FilmPassNode = {
  /**
   * Feed the previous stage's colour in and use the result as output.
   * `input` must be a sampleable texture (e.g. a `pass()` texture node); the
   * grade resamples it at warped coordinates.
   */
  apply(input: TextureNode): Node;
  uniforms: FilmUniforms;
};

export function createFilmPass(): FilmPassNode {
  const filterModeU = uniform(1, 'float');
  const timeU = uniform(0, 'float');
  const uniforms: FilmUniforms = {
    filterMode: {
      get value() { return filterModeU.value as number; },
      set value(v: number) { filterModeU.value = v; },
    },
    time: {
      get value() { return timeU.value as number; },
      set value(v: number) { timeU.value = v; },
    },
  };

  const isCcd = filterModeU.equal(1).select(1, 0);
  const isVhs = filterModeU.equal(2).select(1, 0);
  const isCold = filterModeU.equal(3).select(1, 0);
  const anyFilter = filterModeU.greaterThan(0).select(1, 0);

  // The body MUST be inside `Fn()`: `toVar()`/`assign()` have no meaning
  // outside a function stack, and without the wrapper every one of them throws
  // "No stack defined for assign operation" at build time.
  const applyBody = Fn(([input]: [TextureNode]) => {
    const p = uv().sub(.5).toVar();
    const r2 = p.dot(p).toVar();

    // Barrel / wide-converter distortion from a consumer CCD camcorder.
    // The GLSL is `uv = .5 + p * (1.0 + .28*r2)` - a scale about the CENTRE,
    // not an offset from the current uv. Writing `uv().add(...)` here shifted
    // the whole image by half a screen, because `uv()` is `vUv` and the pivot
    // has to be `.5` explicitly.
    const distorted = uv().toVar();
    distorted.assign(mix(
      distorted,
      vec2(.5).add(p.mul(r2.mul(.28).add(1))),
      isCcd,
    ));
    // VHS tape wobble, horizontal only.
    distorted.x.addAssign(sin(uv().y.mul(390).add(timeU.mul(4))).mul(.0006).mul(isVhs));

    const fringe = isVhs.mul(.002).add(isCcd.mul(r2.mul(.0008)));
    const graded = vec3(
      input.sample(distorted.add(p.mul(fringe))).r,
      input.sample(distorted).g,
      input.sample(distorted.sub(p.mul(fringe))).b,
    ).toVar();

    // Deterministic hash grain, matching the original constants exactly.
    const grain = fract(sin(
      uv().mul(vec2(1536, 864)).floor().dot(vec2(12.9898, 78.233)).add(timeU.mul(24).floor()),
    ).mul(43758.5453)).sub(.5);
    graded.addAssign(grain.mul(isVhs.mul(.025).add(isCcd.mul(.003)).add(isCold.mul(.003))));
    // One vignette term for every filtered look: the original only applied the
    // CCD border clamp to look 1, but the falloff itself was shared.
    graded.mulAssign(mix(vec3(1), vec3(1).sub(p.length().pow(1.6).mul(.48)), anyFilter));

    // Look 1: desaturate, warm the highlights, lift the shadows slightly.
    const luma1 = graded.dot(vec3(.2126, .7152, .0722));
    const ccd = mix(vec3(luma1), graded, .82).mul(vec3(1.025, 1.012, .972))
      .add(vec3(.009, .015, .017).mul(smoothstep(0, .32, luma1).oneMinus()));
    const ccdFinal = mix(ccd, sqrt(max(ccd, vec3(0))), .045);

    // Look 2: scanline banding, then a crushed-to-cool grade.
    const scan = graded.mul(.97).mul(vec3(1).add(vec3(.03).mul(sin(uv().y.mul(1086).mul(Math.PI)))));
    const vhsFinal = pow(max(scan, vec3(0)), vec3(.94)).mul(vec3(.98, 1.02, .97));

    // Look 3: partial desaturation pushed cold.
    const luma3 = graded.dot(vec3(.2126, .7152, .0722));
    const coldFinal = mix(vec3(luma3), graded, .55).mul(vec3(.78, .96, 1.14));

    const look = mix(
      mix(mix(graded, ccdFinal, isCcd), vhsFinal, isVhs),
      coldFinal,
      isCold,
    );

    // The CCD look bows inward and leaves black at the frame edge. This is a
    // vignette, not a distance-to-the-far-edge: the GLSL takes the *minimum*
    // of the four edge distances, so the term is 0 on any edge and grows to 1
    // well inside the frame, then `smoothstep(0, .018, ...)` spends its whole
    // range in the outermost 1.8% band. The previous `max()` formulation was
    // the opposite of that - it collapsed to 0 in the middle and 1 at the
    // corners, which drew a dark frame around a fully-covered centre.
    const edgeDistance = min(
      min(distorted.x, distorted.y),
      min(distorted.x.oneMinus(), distorted.y.oneMinus()),
    );
    const border = mix(vec3(1), vec3(smoothstep(float(0), float(.018), edgeDistance)), isCcd);
    return vec4(look.mul(border), 1);
  });

  return {
    apply: (input: TextureNode) => {
      // Fail loudly and specifically. Without this the body throws
      // `input.sample is not a function`, and the opaque errors that follow
      // bury the real cause.
      if (typeof (input as unknown as { sample?: unknown })?.sample !== 'function') {
        throw new TypeError(
          'createFilmPass().apply expects a texture node (e.g. a pass() texture); '
          + 'got an expression, which cannot be resampled. Materialise it through a '
          + 'full-screen quad pass first - see film-chain.ts.',
        );
      }
      return applyBody(input);
    },
    uniforms,
  };
}
