import { Break, Fn, If, Loop, exp, float, max, min, texture, uv, vec2, vec4 } from 'three/tsl';
import type { IUniform, Texture } from 'three';

/**
 * TSL port of `LiquidSurfacePass`'s narrow-range filter material.
 *
 * Truong & Yuksel / Splash narrow-range filtering: walk outwards along one axis
 * and reject foreground discontinuities, so the surface is smoothed without
 * pulling a distant sample forward into a thick blurred blob.
 *
 * Why it lives here rather than inline in the pass: the pass runs it four times
 * with alternating axes, and the filter itself is the part most worth reading on
 * its own. The four passes stay in the pass.
 *
 * Fidelity notes - the details that are easy to lose in translation:
 *
 *  - The GLSL walks `for (int side = -1; side <= 1; side += 2)`, i.e. -1 then +1.
 *    A TSL `Loop(2)` gives `i = 0, 1`; `side = i * 2 - 1` reproduces the order
 *    exactly. Order matters: `lo`/`hi` slide and `sum`/`weight` accumulate.
 *  - `lo` and `hi` are re-seeded *inside* the side loop but `sum`/`weight` are
 *    not, so the two sweeps share one accumulator and each gets a fresh window.
 *  - `break` on `d < lo` and on `k > radius` are real `Break()` statements, not
 *    conditionals. `float(k) > radius` compares the loop counter to a float.
 *  - The `d > hi` branch clamps `d` to `centre + .012` instead of rejecting the
 *    sample - that is the "clamped rather than pulled backwards" behaviour.
 *  - `centre > 9000.` (the no-liquid sentinel) short-circuits to `10000` before
 *    any of this; the sentinel is written, not the filtered value.
 *  - `radius = clamp(projectionScale * .018 / centre, 1., 6.)`, so the kernel is
 *    always at least 1 and at most 6 texels wide.
 */

/** The no-liquid sentinel shared by the fluid depth buffer and this filter. */
export const LIQUID_EMPTY = 9000;
/** Value written where there is no liquid, so downstream tests stay true. */
export const LIQUID_EMPTY_OUT = 10000;

/** Uniform bag for one filter pass. */
export type NarrowFilterUniforms = {
  /** Input depth texture (`fluidDepth`). */
  source: IUniform;
  /** `1 / resolution`, for the neigbour step. */
  texel: IUniform;
  /** Walk axis: `(1, 0)` for horizontal, `(0, 1)` for vertical. */
  direction: IUniform;
  /** `height * projectionMatrix[5] * .5`, i.e. how many texels span the near plane. */
  projectionScale: IUniform;
};

/**
 * The filter, as a node graph over `uv()`.
 *
 * Returns a `vec4` with the filtered depth in `.r`, matching the GLSL's
 * `vec4(value, 0, 0, 1)` and the sentinel's `vec4(10000, 0, 0, 1)`.
 */
export function createNarrowFilter(uniforms: NarrowFilterUniforms) {
  const source = uniforms.source.value as Texture;
  const texel = () => uniforms.texel.value as { x: number; y: number };
  const direction = () => uniforms.direction.value as { x: number; y: number };
  const projectionScale = () => uniforms.projectionScale.value as number;

  return Fn(() => {
    // `centre > 9000.` is the no-liquid case: write the sentinel and stop.
    // Modelled as If/Else rather than a select so the filter body is not even
    // built on that path - the GLSL returns there.
    const out = vec4(LIQUID_EMPTY_OUT, 0, 0, 1).toVar();

    const centre = texture(source, uv()).r;
    If(centre.lessThanEqual(LIQUID_EMPTY), () => {
      const radius = float(projectionScale()).mul(.018).div(centre).clamp(float(1), float(6)).toVar();
      const sum = centre.toVar();
      const weight = float(1).toVar();
      const dir = vec2(direction().x, direction().y).toVar();
      const step = vec2(texel().x, texel().y).toVar();

      Loop(2, ({ i }) => {
        // `side = -1` then `+1`; TSL's index is 0-based.
        const side = float(i).mul(2).sub(1).toVar();
        // Re-seeded per side, matching where the GLSL declares them.
        const lo = centre.sub(.035).toVar();
        const hi = centre.add(.035).toVar();
        Loop(6, ({ i: k }) => {
          // `k` is 0-based; GLSL counts from 1.
          const kk = float(k).add(1).toVar();
          If(kk.greaterThan(radius), () => Break());
          const d = texture(source, uv().add(dir.mul(step).mul(kk).mul(side))).r.toVar();
          If(d.lessThan(lo), () => Break());
          const w = exp(float(k).add(1).mul(float(k).add(1)).negate().div(radius.mul(radius).mul(.5)));
          If(d.greaterThan(hi), () => {
            d.assign(centre.add(.012));
          }).Else(() => {
            lo.assign(min(lo, d.sub(.035)));
            hi.assign(max(hi, d.add(.035)));
          });
          sum.addAssign(w.mul(d));
          weight.addAssign(w);
        });
      });

      out.assign(vec4(sum.div(weight), 0, 0, 1));
    });

    return out;
  })();
}
