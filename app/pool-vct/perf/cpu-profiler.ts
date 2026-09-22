import type { FrameTimeStats, RendererMetrics } from './perf-types';

/**
 * Frame-interval distribution over a fixed ring.
 *
 * Two deliberate choices:
 *
 *  - The ring is a preallocated `Float64Array`, so sampling never allocates and
 *    the profiler can stay on during normal play without feeding the GC that
 *    would then show up in its own numbers.
 *  - Percentiles are computed lazily, only when someone reads them (the HUD
 *    refreshes a few times a second), not per frame. Sorting 240 numbers on
 *    that cadence is free; doing it 60 times a second would not be.
 */

const RING = 240;

export interface CpuProfiler {
  /** Record one frame interval in milliseconds. */
  sample(ms: number): void;
  /** Percentile view of the current window. */
  stats(): FrameTimeStats;
  /** Forget the window (quality change, room transition, unpause). */
  reset(): void;
}

export function createCpuProfiler(): CpuProfiler {
  const ring = new Float64Array(RING);
  const sorted = new Float64Array(RING);
  let count = 0;
  let head = 0;
  let mean = 0;

  return {
    sample(ms) {
      if (!(ms > 0) || !Number.isFinite(ms)) return;
      const previous = count < RING ? undefined : ring[head];
      ring[head] = ms;
      head = (head + 1) % RING;
      if (count < RING) count++;
      // Incremental mean keeps the cheap number cheap; exact percentiles come
      // from the sort on read.
      if (previous === undefined) mean = count === 1 ? ms : mean + (ms - mean) / count;
      else mean += (ms - previous) / RING;
    },
    stats() {
      if (!count) return { p50: 0, p95: 0, p99: 0, mean: 0, worst: 0, samples: 0, fps: 0 };
      sorted.set(ring.subarray(0, count));
      const view = sorted.subarray(0, count);
      view.sort();
      const at = (q: number) => view[Math.min(count - 1, Math.max(0, Math.round((count - 1) * q)))];
      return {
        p50: at(0.5),
        p95: at(0.95),
        p99: at(0.99),
        mean,
        worst: view[count - 1],
        samples: count,
        fps: mean > 0 ? 1000 / mean : 0,
      };
    },
    reset() {
      count = 0;
      head = 0;
      mean = 0;
    },
  };
}

/**
 * Read `renderer.info` into plain numbers.
 *
 * `WebGLRenderer.info` resets itself at the top of every `render()` call, so in
 * a composer chain it only ever describes the LAST pass. The engine therefore
 * sets `info.autoReset = false` and resets once per frame, which is what makes
 * `calls` here mean "draw calls for the whole frame" - the number worth
 * optimising against.
 */
export function readRendererMetrics(renderer: {
  info: {
    render: { calls: number; triangles: number; points: number; lines: number };
    memory: { geometries: number; textures: number };
    programs?: { length: number } | null;
  };
}): RendererMetrics {
  const { render, memory, programs } = renderer.info;
  return {
    calls: render.calls,
    triangles: render.triangles,
    points: render.points,
    lines: render.lines,
    programs: programs?.length ?? 0,
    geometries: memory.geometries,
    textures: memory.textures,
  };
}
