import { Fn, If, Loop, cameraPosition, cameraProjectionMatrix, cameraProjectionMatrixInverse, cameraViewMatrix, cameraWorldMatrix, dot, float, fract, getViewPosition, length, max, normalize, pow, screenCoordinate, sin, smoothstep, texture, uniform, uv, vec2, vec3, vec4 } from 'three/tsl';
import type { TextureNode } from 'three/webgpu';

/**
 * Node-graph port of the Tyndall raymarch (the old `ShaderPass` in engine.ts).
 *
 * This is a deliberate line-for-line port rather than a swap to three's
 * `godrays()` node. The two do not mean the same thing:
 *
 *  - `godrays()` derives visibility from the *shadow map* (`lightShadowMatrix`
 *    plus a compare against `light.shadow.map.depthTexture`). Its beams are
 *    literally the shadow-casting geometry's silhouette; it requires the full
 *    shadow setup (renderer shadows on, casters, a shadow-casting light) and
 *    renders at half resolution through its own denoise material.
 *  - This pass fakes the shaft as an *analytic cone* around a fixed sun axis
 *    (radius `spread = 5.4 * (1 + along * .028)`), softens the edge over the
 *    inner 55%, gates it against the scene depth buffer, and tints it
 *    (.62, .78, .84) with a drifting humidity term and a `pow(mu, 5)`
 *    forward-scattering phase.
 *
 * Swapping one for the other would change the look: harder-edged shafts, a
 * colder/greyer cast, and - because the cone is gone - a completely different
 * beam shape in the room. The whole point of the port is that the pixels stay
 * put while the *backend* changes, so each line is carried over.
 *
 * Semantics preserved exactly:
 *  - the march starts at `dt * (i + jitter)` where `dt = 36 / STEPS`, so it
 *    never samples the camera position itself, and `jitter` is a per-pixel
 *    hash of `gl_FragCoord` (`screenCoordinate` in TSL) that hides banding.
 *  - steps past `p.y < .32` stop contributing (below the water surface there
 *    is no humid air).
 *  - `clip.w <= 0` and an off-screen projection only skip that step, which the
 *    nested-`If` form expresses without an early exit from the loop.
 *  - the composite is `base + acc * intensity`, never a blend.
 *
 * Camera matrices come from TSL's built-ins instead of the six matrices the
 * old ShaderPass copied in from JS every frame. Same values, but they stay
 * correct even if the camera changes between setup and render.
 */

/** Steps in the raymarch. Mirrors the GLSL `const int STEPS = 20`. */
export const TYNDALL_STEPS = 20;
/** March length in metres. Mirrors `dt = 36. / float(STEPS)`. */
export const TYNDALL_MARCH_LENGTH = 36;
/** Sun direction, normalised at build time (GLSL constants cannot call normalize()). */
export const SUN_DIR = [.274, -.913, .274] as const;
/** Beam tint the accumulation is multiplied into. */
export const SUN_TINT = [.62, .78, .84] as const;

export type TyndallUniforms = {
  intensity: { value: number };
  time: { value: number };
  /** Cone radius at the skylight, in metres. */
  spread: { value: number };
  /** How fast the shaft widens per metre travelled along the axis. */
  spreadGrow: { value: number };
  /** Fraction of the radius that is solid before the soft edge starts. */
  edge: { value: number };
};

export type TyndallPass = {
  /** Returns the colour with the shafts added. `input` is the upstream colour. */
  apply(input: TextureNode): TextureNode;
  uniforms: TyndallUniforms;
};

export type TyndallPassOptions = {
  /** Scene depth, sampled for per-step occlusion. */
  sceneDepth: TextureNode;
  /** Skylight position the cone axis passes through. Defaults to `(0, 15, 0)`. */
  lightPos?: [number, number, number];
};

/** Wraps a TSL uniform in the plain `{ value }` box the engine already writes to. */
function box<T extends { value: unknown }>(node: T): { value: T['value'] } {
  return {
    get value() { return node.value; },
    set value(v: T['value']) { node.value = v; },
  };
}

export function createTyndallPass(options: TyndallPassOptions): TyndallPass {
  const lightPos = options.lightPos ?? [0, 15, 0];

  const intensity = uniform(0);
  const time = uniform(0);
  const spread = uniform(5.4);
  const spreadGrow = uniform(.028);
  const edgeFraction = uniform(.55);

  const lightPosNode = vec3(lightPos[0], lightPos[1], lightPos[2]);
  const sun = vec3(SUN_DIR[0], SUN_DIR[1], SUN_DIR[2]);
  const tint = vec3(SUN_TINT[0], SUN_TINT[1], SUN_TINT[2]);

  const steps = TYNDALL_STEPS;
  const dt = TYNDALL_MARCH_LENGTH / steps;

  function apply(input: TextureNode): TextureNode {
    if (typeof (input as unknown as { sample?: unknown })?.sample !== 'function') {
      throw new TypeError('createTyndallPass().apply expects a texture node (a pass() texture).');
    }
    // The body MUST be inside `Fn()`. `toVar()`/`assign()` have no meaning
    // outside a function stack - without the wrapper every one of them throws
    // "No stack defined for assign operation" at build time.
    const graph = Fn(() => {
      const color = input.sample(uv()).toVar('tyndallColor');
      const base = color.rgb.toVar('tyndallBase');
      const acc = vec3(0, 0, 0).toVar('tyndallAcc');

      // World-space view ray. `getViewPosition` handles the WebGPU-vs-WebGL
      // depth-range flip for us; the old GLSL hardcoded the GL convention.
      // A far-plane sample gives a point on the same ray, and the direction is
      // simply the camera-to-that-point vector.
      const farViewPos = getViewPosition(uv(), float(1), cameraProjectionMatrixInverse);
      const farWorldPos = cameraWorldMatrix.mul(vec4(farViewPos, 1)).xyz.toVar('tyndallFarPos');
      const camPos = cameraPosition.toVar('tyndallCamPos');
      const dir = normalize(farWorldPos.sub(camPos)).toVar('tyndallDir');

      // Per-pixel jitter, same hash as the GLSL so the banding pattern matches.
      const jitter = fract(sin(dot(screenCoordinate, vec2(12.9898, 78.233))).mul(43758.5453)).toVar('tyndallJitter');

      Loop(steps, ({ i }) => {
        const p = camPos.add(dir.mul(i.toFloat().add(jitter).mul(dt))).toVar('tyndallP');

        // Shafts live between the clerestory and the water surface only; below
        // .32 there is no humid air left to scatter.
        If(p.y.greaterThanEqual(.32), () => {
          // Occlusion: geometry already drawn in front of this sample blocks it.
          const clip = cameraProjectionMatrix.mul(cameraViewMatrix).mul(vec4(p, 1)).toVar('tyndallClip');
          If(clip.w.greaterThan(0), () => {
            const suv = clip.xy.div(clip.w).mul(.5).add(.5).toVar('tyndallSuv');
            const onScreen = suv.x.greaterThanEqual(0).and(suv.x.lessThanEqual(1))
              .and(suv.y.greaterThanEqual(0)).and(suv.y.lessThanEqual(1));
            If(onScreen, () => {
              // The +.0015 bias matches the GLSL: without it the sample's own
              // surface depth rejects the beam and the shaft self-occludes.
              const sampleDepth = clip.z.div(clip.w).mul(.5).add(.5);
              If(sampleDepth.lessThanEqual(texture(options.sceneDepth, suv).x.add(.0015)), () => {
                // Inside the slanted shaft? Distance to the axis through the skylight.
                const rel = p.sub(lightPosNode);
                const along = dot(rel, sun);
                If(along.greaterThanEqual(0), () => {
                  const radius = spread.mul(along.mul(spreadGrow).add(1)).toVar('tyndallRadius');
                  const radial = length(rel.sub(sun.mul(along)));
                  If(radial.lessThanEqual(radius), () => {
                    const soft = smoothstep(radius.mul(edgeFraction), radius, radial).oneMinus();
                    // Humid air: slow drifting density so the beams read as air, not glass.
                    const drift = sin(p.x.mul(.9).add(time.mul(.32)).add(sin(p.z.mul(.7).sub(time.mul(.21))).mul(1.4)))
                      .mul(.28).add(.72);
                    // Forward scattering: looking up toward the sun brightens the shafts.
                    const mu = max(dot(dir, sun.negate()), 0);
                    const phase = pow(mu, 5).mul(1.5).add(.16);
                    acc.addAssign(tint.mul(soft).mul(drift).mul(phase).mul(dt));
                  });
                });
              });
            });
          });
        });
      });

      color.assign(vec4(base.add(acc.mul(intensity)), 1));
      return color;
    });

    return graph() as never as TextureNode;
  }

  return {
    apply,
    uniforms: {
      intensity: box(intensity),
      time: box(time),
      spread: box(spread),
      spreadGrow: box(spreadGrow),
      edge: box(edgeFraction),
    },
  };
}
