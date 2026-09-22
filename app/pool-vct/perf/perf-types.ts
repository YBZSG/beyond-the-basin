/**
 * Shared shapes for the measurement layer.
 *
 * The optimisation work in `beyond-the-basin-performance-optimization.md` is
 * organised around one rule: measure first, then remove work. These types are
 * the contract between the profilers (below) and whoever displays or logs the
 * numbers - the HUD, the QA hook, an automated acceptance run.
 *
 * Everything here is optional-by-construction: a missing GPU extension or a
 * disabled profiler yields zeroes rather than throwing, so the measurement
 * layer can never take down a frame.
 */

/** What the renderer actually submitted last frame. */
export interface RendererMetrics {
  /** Draw calls. The single best proxy for CPU-side submission cost. */
  calls: number;
  triangles: number;
  points: number;
  lines: number;
  /** Live shader programs; a rising number means shader recompiles. */
  programs: number;
  geometries: number;
  textures: number;
}

/**
 * Distribution of wall-clock frame intervals.
 *
 * The mean hides jank: a scene that runs 8 ms for 99 frames and 80 ms for one
 * has a 8.7 ms mean and a p99 of 80 ms. p99 is the number players feel, so it
 * is the number the HUD leads with.
 */
export interface FrameTimeStats {
  p50: number;
  p95: number;
  p99: number;
  mean: number;
  worst: number;
  /** Frames in the current window (caps at the ring size). */
  samples: number;
  /** 1000 / mean, smoothed like `fps` elsewhere. 0 until we have samples. */
  fps: number;
}

/** Asynchronous GPU timing from `EXT_disjoint_timer_query_webgl2`. */
export interface GpuTiming {
  /** False when the extension is missing (most browsers, most of the time). */
  supported: boolean;
  /** True when the GPU was interrupted mid-measurement; discard the sample. */
  disjoint: boolean;
  /** Most recent completed GPU time in ms. */
  last: number;
  /** Smoothed GPU time in ms. */
  average: number;
}

export interface PerfSnapshot {
  frame: FrameTimeStats;
  gpu: GpuTiming;
  render: RendererMetrics;
  /** Shadow cube maps rebuilt last frame (0..4 slots). */
  shadowSlots: number;
  /**
   * Default budget for a single full-screen stage at this resolution, in ms.
   *
   * Derived from a hardcoded 100 Mpx/s fill estimate and the canvas size, so it
   * is heavily machine-dependent - a software rasterizer will blow through it.
   * It is only ever used to colour a bar orange, never to make a decision, and
   * a load-time calibration overwrites it with `measured` when one is
   * available.
   */
  budget: StageBudget;
}

/** Replace the modelled stage budget with one calibrated on this machine. */
export interface StageBudget {
  /** Modelled fill budget for one full-screen stage, in ms. */
  perStage: number;
  /** 1080p-equivalent megapixels per millisecond; 0 until calibrated. */
  fillRate: number;
  /** True once `fillRate` came from a real measurement instead of the model. */
  measured: boolean;
}
