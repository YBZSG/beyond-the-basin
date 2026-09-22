import * as T from 'three';
import type { StageBudget } from './perf-types';

/**
 * Fill-rate calibration.
 *
 * The profiler wants to answer "is this stage expensive?" without a table of
 * per-machine constants. Shading cost is dominated by the pixels a pass writes,
 * so a single number - 1080p-equivalent megapixels per millisecond - converts
 * any pass's output size into an expected cost.
 *
 * It is measured, not assumed: a deliberately trivial shader is rendered to a
 * large offscreen target a few times and the GPU timer tells us how long it
 * took. That is nearly pure fill, which is exactly the quantity we want to
 * normalise by.
 *
 * Everything here runs inside the engine's existing *async* GPU profiler jobs,
 * so it needs no `readPixels` and never stalls the pipeline, and it runs once
 * per session rather than in the frame loop.
 */

/** 1080p-equivalent megapixels; the unit `fillRate` is expressed in. */
const REFERENCE_MPX = (1920 * 1080) / 1e6;
/** Side length of the offscreen target the calibration pass renders to. */
export const FILL_PROBE_SIDE = 1024;
/** Samples averaged before the reading is believed. */
export const FILL_PROBE_FRAMES = 6;

export interface BudgetCalibrator {
  /** Feed a raw GPU sample measured around one calibration draw. */
  sample(ms: number): void;
  /** Modelled budget for a canvas of this size, in ms. */
  forCanvas(width: number, height: number): StageBudget;
  /** True once a real measurement replaced the model. */
  readonly measured: boolean;
  dispose(): void;
}

/**
 * Fallback used until (and if) a measurement lands. 100 Mpx/s is roughly a
 * mid-range integrated GPU under WebGL; it is wrong per-machine on purpose -
 * the point is to catch order-of-magnitude outliers, not to be accurate.
 */
const MODELLED_FILL_RATE = 100 / REFERENCE_MPX;

export function createBudgetCalibrator(): BudgetCalibrator {
  let fillRate = MODELLED_FILL_RATE;
  let done = false;
  const samples: number[] = [];

  const forCanvas = (width: number, height: number): StageBudget => {
    const mpx = (width * height) / 1e6;
    return { perStage: mpx / fillRate, fillRate, measured: done };
  };

  return {
    get measured() {
      return done;
    },
    sample(ms) {
      if (done) return;
      // Discard absurd values: a context loss or a disjoint reading would
      // otherwise pin the fill rate for the whole session.
      if (!(ms > 0.02) || ms > 120) return;
      samples.push(ms);
      if (samples.length < FILL_PROBE_FRAMES) return;
      samples.sort((a, b) => a - b);
      // Median, not mean: one odd frame must not move the constant.
      const median = samples[samples.length >> 1];
      fillRate = ((FILL_PROBE_SIDE * FILL_PROBE_SIDE) / 1e6) / median;
      done = true;
      samples.length = 0;
    },
    forCanvas,
    dispose() {
      samples.length = 0;
    },
  };
}

/**
 * A single full-viewport triangle is the cheapest thing that can fill a target:
 * no attributes to fetch, no index buffer, one colour out. Whatever the GPU
 * spends on it is fill cost and almost nothing else.
 */
export function createFillProbeMaterial(): T.Material {
  return new T.RawShaderMaterial({
    glslVersion: T.GLSL3,
    vertexShader: `void main(){gl_Position=vec4(gl_VertexID==1?3.:-1.,gl_VertexID==2?3.:-1.,0.,1.);}`,
    fragmentShader: `precision highp float;out vec4 c;void main(){c=vec4(.5,.5,.5,1.);}`,
    depthTest: false,
    depthWrite: false,
  });
}

/** A scene holding the probe geometry the caller renders into a target. */
export function createFillProbeScene(camera: T.Camera) {
  const scene = new T.Scene();
  scene.add(new T.Mesh(new T.BufferGeometry(), createFillProbeMaterial()));
  return { scene, camera };
}


