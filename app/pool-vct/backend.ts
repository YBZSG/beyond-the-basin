import * as T from 'three';
import { WebGPURenderer } from 'three/webgpu';
import { attribute, float, uniform, vec2, vec4 } from 'three/tsl';

/** Which render backend actually ended up driving the frame loop. */
export type BackendKind = 'webgpu' | 'webgl2';

/**
 * Transitional union used while GLSL passes are ported to TSL: the shared
 * helpers below smooth over the API gaps (`capabilities.getMaxAnisotropy`,
 * synchronous readback). Once every module targets the node renderer this
 * collapses back down to plain `WebGPURenderer`.
 */
export type PoolRenderer = T.WebGLRenderer | WebGPURenderer;

export type Backend = {
  /** A ready-to-use renderer: object is created and `init()` has resolved. */
  renderer: WebGPURenderer;
  kind: BackendKind;
  /** Human readable reason for the current choice, shown in the pause menu. */
  reason: string;
};

function webgpuApiAvailable(): boolean {
  return typeof navigator !== 'undefined' && 'gpu' in navigator && navigator.gpu !== undefined;
}

/**
 * A real adapter probe, not just a `"gpu" in navigator` check: browsers can
 * expose the API while refusing to hand out a device (no hardware adapter,
 * blocklisted driver, or a failed page restore after a GPU crash).
 */
export async function probeWebGPU(): Promise<boolean> {
  if (!webgpuApiAvailable()) return false;
  try {
    return (await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' })) !== null;
  } catch {
    return false;
  }
}

/**
 * Creates a node renderer that prefers WebGPU and silently degrades to the
 * WebGL2 backend otherwise. Both paths share one material codebase (TSL), so
 * nothing downstream has to branch on the backend.
 *
 * `WebGPURenderer` also falls back on its own when device creation fails, but
 * probing first lets us report the truth to the UI instead of guessing.
 */
export async function createBackend(antialias: boolean): Promise<Backend> {
  const available = await probeWebGPU();
  const renderer = new WebGPURenderer({ antialias, alpha: false, forceWebGL: !available });
  await renderer.init();
  const kind: BackendKind = available ? 'webgpu' : 'webgl2';
  const reason = available
    ? 'WebGPU · TSL 材质'
    : '未检测到可用 WebGPU 适配器，已自动回落到 WebGL2 后端';
  return { renderer, kind, reason };
}

/** Short label for the pause menu, e.g. `WebGPU` / `WebGL2 回落`. */
export function backendLabel(kind: BackendKind): string {
  return kind === 'webgpu' ? 'WebGPU' : 'WebGL2 回落';
}

/* ---------------------------------------------------------------------------
 * TSL helpers
 *
 * `@types/three` loses the value type through the node factories (`uniform()`
 * comes back as `UniformNode<unknown, unknown>`, `attribute()` as
 * `AttributeNode<string>`), which makes every graph expression a type error.
 * These wrappers do the cast once, in one place, and hand back nodes that can
 * be composed directly. `__TypeScript_NODE_TYPE__` is a phantom marker used
 * only by the typings.
 * ------------------------------------------------------------------------- */

export type FloatNode = ReturnType<typeof float>;
export type Vec2Node = ReturnType<typeof vec2>;
export type Vec4Node = ReturnType<typeof vec4>;

export type ScalarUniform = { node: FloatNode; set(value: number): void };
export type Vec2Uniform = { node: Vec2Node; readonly value: T.Vector2 };

/** A single float uniform with a plain JS setter for per-frame updates. */
export function floatUniform(initial: number): ScalarUniform {
  const raw = uniform(initial, 'float') as unknown as { value: unknown };
  const node = raw as unknown as FloatNode;
  return { node, set: (value: number) => { raw.value = value; } };
}

/** A `vec2` uniform backed by a live `Vector2` the caller can mutate in place. */
export function vec2Uniform(initial: T.Vector2): Vec2Uniform {
  const raw = uniform(initial, 'vec2') as unknown as { value: T.Vector2 };
  return { node: raw as unknown as Vec2Node, value: initial };
}

/** Reads an instanced (or plain) buffer attribute as a typed vector node. */
export function vec4Attribute(name: string): Vec4Node {
  return attribute(name, 'vec4') as unknown as Vec4Node;
}

/**
 * Reads a render target back into CPU memory. The node renderer only offers the
 * async variant, so the legacy synchronous path is wrapped rather than left to
 * stall the WebGL pipeline mid-frame.
 */
export async function readbackTarget(
  renderer: PoolRenderer,
  target: T.RenderTarget | T.WebGLRenderTarget,
  buffer: ArrayBufferView,
  size: number,
): Promise<void> {
  const node = renderer as unknown as {
    readRenderTargetPixelsAsync?: (t: unknown, x: number, y: number, w: number, h: number, i?: number, b?: ArrayBufferView) => Promise<unknown>;
  };
  if (typeof node.readRenderTargetPixelsAsync === 'function') {
    await node.readRenderTargetPixelsAsync(target, 0, 0, size, size, 0, buffer);
    return;
  }
  const legacy = renderer as unknown as {
    readRenderTargetPixels: (t: unknown, x: number, y: number, w: number, h: number, b: ArrayBufferView) => void;
  };
  // Deferred a tick so callers can treat every backend as async without the
  // WebGL path being forced to await anything inside frame budgeting.
  await Promise.resolve();
  legacy.readRenderTargetPixels(target, 0, 0, size, size, buffer);
}

/**
 * The node renderer exposes anisotropy directly instead of through
 * `renderer.capabilities`, and the WebGL2 fallback backend caps it lower.
 */
export function maxAnisotropy(renderer: WebGPURenderer): number {
  try {
    return renderer.getMaxAnisotropy();
  } catch {
    return 4;
  }
}
