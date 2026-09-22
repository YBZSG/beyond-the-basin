/**
 * Shared shapes for the measurement layer.
 *
 * The optimisation work in `beyond-the-basin-performance-optimization.md` is
 * organised around one rule: measure first, then remove work. These types are
 * the contract between the profilers (below) and whoever displays or logs the
 * numbers - the HUD, the QA hook, an automated acceptance run.
 *
 * GPU availability is explicit. Numeric placeholders must never be displayed
 * or accepted as a measured zero when the extension/sample is unavailable.
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
  /** CPU submission and completed GPU stages, with issuing frame identity. */
  stages: {cpu:Record<string,number>;cpuMs:number;gpu:Record<string,{frame:number;ms:number;ageFrames:number}>};
  transfer: {readbackBytes:number;uploadBytes:number;shallowReadbackBytes?:number};
  frameBudgetMs: number;
}
