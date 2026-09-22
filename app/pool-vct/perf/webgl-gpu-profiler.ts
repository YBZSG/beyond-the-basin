import type { GpuTiming } from './perf-types';

/**
 * Asynchronous GPU timing via `EXT_disjoint_timer_query_webgl2`.
 *
 * Why this exists: every other number in the HUD is CPU time. A pass that got
 * cheaper on the CPU but issued the same megapixels of shading looks like a win
 * there and is a no-op on the GPU. Only a timer query can separate the two, and
 * it is the difference between "we removed a draw call" and "we removed 12 ms".
 *
 * Design notes:
 *
 *  - `TIME_ELAPSED_EXT` queries cannot nest and must not overlap, so at most
 *    one is open at a time and a frame that starts while one is still open is
 *    simply skipped. Missing a frame is fine; corrupting one is not.
 *  - Results land several frames after they were issued, so they are pulled
 *    from an explicit ring rather than blocking on the newest query. Nothing
 *    ever blocks: an unready query means "report the last known value".
 *  - A disjoint event (GPU pre-empted, driver reset, thermal throttle) makes
 *    every in-flight sample meaningless. The spec says results are unreliable
 *    until the flag clears, so the profiler drops the bad samples but keeps
 *    measuring and recovers on the next clean pass. Latching `disjoint` forever
 *    was the original bug: once a GPU hiccupped, GPU time read "sampling
 *    interrupted" for the rest of the session.
 *
 * The extension is absent in Firefox and Safari; `supported` is false there and
 * every method becomes a no-op.
 */

interface TimerExtension {
  TIME_ELAPSED_EXT: number;
  GPU_DISJOINT_EXT: number;
}

const SMOOTH = 0.85;
/** A GPU frame slower than this is not a real reading; see `drain()`. */
const MAX_TRUSTED_MS = 250;
/** Upper bound on retained query objects, so a long session cannot leak. */
const MAX_POOLED = 4;

export interface GpuProfiler {
  readonly supported: boolean;
  /** Open the frame's timer. No-op if unsupported or one is already open. */
  begin(): void;
  /** Close the frame's timer and queue it for collection. */
  end(): void;
  /** Latest resolved GPU time; also drains whatever is ready. */
  snapshot(): GpuTiming;
  dispose(): void;
}

export function createGpuProfiler(gl: WebGL2RenderingContext | WebGLRenderingContext | null): GpuProfiler {
  const ext = (typeof WebGL2RenderingContext !== 'undefined' && gl instanceof WebGL2RenderingContext
    ? gl.getExtension('EXT_disjoint_timer_query_webgl2')
    : null) as TimerExtension | null;

  if (!gl || !ext) {
    return {
      supported: false,
      begin() {},
      end() {},
      snapshot: () => ({ supported: false, disjoint: false, last: 0, average: 0 }),
      dispose() {},
    };
  }

  const context = gl as WebGL2RenderingContext;
  // A Map keyed by object identity: a disposed context can hand back a handle
  // that compares equal to one we are still holding, and a Set would then
  // silently lose membership.
  const queries = new Map<WebGLQuery, true>();
  const pending: WebGLQuery[] = [];
  let active: WebGLQuery | null = null;
  let last = 0;
  let average = 0;
  let disjointSeen = false;
  /** Set when a good reading arrived while the warning was up, so the next
   * drain re-reads the flag instead of clearing it in the same snapshot. */
  let needsRecheck = false;
  let disposed = false;

  // Reuse, never delete-and-reuse. WebGL states that `deleteQuery` invalidates
  // the handle for every future call, so a deleted query returned to the pool
  // is a bug that surfaces as a driver error several frames later. The pool
  // therefore holds live objects and only `dispose()` frees them; it is capped
  // so a long session cannot grow it either.
  const recycle = (query: WebGLQuery) => {
    if (queries.size < MAX_POOLED) queries.set(query, true);
    else context.deleteQuery(query);
  };

  const drain = () => {
    if (context.getParameter(ext.GPU_DISJOINT_EXT)) {
      // The GPU was interrupted: results in flight are unreliable. Drop them,
      // but keep measuring - do NOT latch. One driver hiccup must not disable
      // the meter for the rest of the session.
      disjointSeen = true;
      needsRecheck = false;
      for (const query of pending) recycle(query);
      pending.length = 0;
      return;
    }
    if (needsRecheck) {
      needsRecheck = false;
      disjointSeen = false;
    }
    while (pending.length) {
      const query = pending[0];
      if (!context.getQueryParameter(query, context.QUERY_RESULT_AVAILABLE)) break;
      pending.shift();
      const ns = Math.max(0, context.getQueryParameter(query, context.QUERY_RESULT) as number);
      recycle(query);
      last = ns / 1e6;
      average = average ? average * SMOOTH + last * (1 - SMOOTH) : last;
      // A plausible reading clears the warning, but the flag itself is only
      // re-read on the NEXT drain: clearing it here would report "clean" in the
      // same snapshot as the sample we just dropped. A stale flag must not
      // outlive the numbers it invalidated, though - hence the size check.
      if (last < MAX_TRUSTED_MS && disjointSeen) needsRecheck = true;
    }
  };

  return {
    supported: true,
    begin() {
      if (disposed || active) return;
      let query: WebGLQuery | undefined;
      for (const candidate of queries.keys()) {
        query = candidate;
        break;
      }
      if (query) queries.delete(query);
      else query = context.createQuery() ?? undefined;
      if (!query) return;
      context.beginQuery(ext.TIME_ELAPSED_EXT, query);
      active = query;
    },
    end() {
      if (!active) return;
      context.endQuery(ext.TIME_ELAPSED_EXT);
      pending.push(active);
      active = null;
      // Drain opportunistically so we are never more than a few frames behind.
      drain();
    },
    snapshot() {
      if (!disposed) drain();
      return { supported: true, disjoint: disjointSeen, last, average };
    },
    dispose() {
      disposed = true;
      if (active) {
        context.endQuery(ext.TIME_ELAPSED_EXT);
        active = null;
      }
      for (const query of pending) context.deleteQuery(query);
      pending.length = 0;
      for (const query of queries.keys()) context.deleteQuery(query);
      queries.clear();
    },
  };
}
