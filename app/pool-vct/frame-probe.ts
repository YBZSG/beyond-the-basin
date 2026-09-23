/**
 * Zero-cost-when-off frame stage profiler.
 *
 * `mark()` is a pair of `performance.now()` reads guarded by an `on` flag, so
 * when the debug panel is closed the only cost is one predictable branch per
 * stage. Readings are exponentially smoothed per stage so a single GC pause or
 * shader compile does not dominate the number you read off the panel.
 *
 * GPU work is asynchronous: `mark()` around a render call measures only the
 * CPU-side command encoding, which for Three.js is genuinely the submission
 * cost. When a stage is GPU-bound the driver will stall at the *next* sync
 * point instead, so the numbers here are "CPU time attributed to this stage"
 * and they will still point at the right culprit once one stage starts
 * blocking.
 */

const SMOOTH = 0.82;

/** Stages we care about, in frame order. */
export type Stage =
  | 'props'
  | 'liquid'
  | 'particles'
  | 'water'
  | 'capture'
  | 'composer'
  | 'misc';

const STAGES: Stage[] = ['props', 'liquid', 'particles', 'water', 'capture', 'composer', 'misc'];

export interface FrameProbe {
  /** Enable/disable collection. Disabling clears the accumulators. */
  set enabled(value: boolean);
  get enabled(): boolean;
  /** Enter a stage. Returns a token for `end`, or 0 when disabled. */
  begin(stage: Stage): number;
  /** Leave a stage. */
  end(stage: Stage, token: number): void;
  /** Smoothed milliseconds per stage, plus `total` and `probe` overhead. */
  snapshot(): Record<Stage, number> & { total: number; probe: number };
  /** Drop-in replacement for `report()`: merges probe fields into the payload. */
  merge<T extends Record<string, unknown>>(payload: T): T & { timings?: Record<string, number> };
}

export function createFrameProbe(): FrameProbe {
  const smoothed = new Map<Stage, number>();
  let on = false;
  let probeNs = 0;
  let probeSmooth = 0;
  let intervals = 0;

  const add = (stage: Stage, ms: number) => {
    const prev = smoothed.get(stage);
    smoothed.set(stage, prev === undefined ? ms : prev * SMOOTH + ms * (1 - SMOOTH));
  };

  return {
    get enabled() {
      return on;
    },
    set enabled(value: boolean) {
      on = value;
      if (!value) {
        smoothed.clear();
        probeNs = 0;
        probeSmooth = 0;
        intervals = 0;
      }
    },
    begin(stage) {
      if (!on) return 0;
      const t = performance.now();
      add(stage, 0); // ensure the stage exists even if it never runs
      return t;
    },
    end(stage, token) {
      if (!on || !token) return;
      const now = performance.now();
      add(stage, now - token);
      probeNs += now - token;
      intervals++;
    },
    snapshot() {
      const out = { total: 0, probe: 0 } as Record<Stage, number> & {
        total: number;
        probe: number;
      };
      for (const stage of STAGES) {
        const v = smoothed.get(stage) ?? 0;
        out[stage] = v;
        out.total += v;
      }
      out.probe = probeSmooth;
      return out;
    },
    merge(payload) {
      if (!on) return payload;
      const snap = this.snapshot();
      // Rough probe overhead: total time spent inside mark pairs divided by
      // the number of smoothed intervals we have accumulated. It is reported
      // so the reader can tell whether the instrument itself is the story.
      probeSmooth = probeSmooth * 0.9 + (probeNs / Math.max(1, intervals)) * 0.1;
      probeNs = 0;
      intervals = 0;
      const timings: Record<string, number> = {};
      for (const stage of STAGES) timings[stage] = +snap[stage].toFixed(2);
      timings.total = +snap.total.toFixed(2);
      timings.probe = +probeSmooth.toFixed(3);
      return { ...payload, timings };
    },
  };
}
