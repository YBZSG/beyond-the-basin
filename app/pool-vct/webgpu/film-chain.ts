import * as T from 'three';
import { NodeMaterial, RenderPipeline } from 'three/webgpu';
import { bloom } from 'three/examples/jsm/tsl/display/BloomNode.js';
import { add, mrt, output, pass, vec4 } from 'three/tsl';
import type { Node, Renderer as NodeRenderer, TextureNode } from 'three/webgpu';
// Extensions are required: `node --experimental-strip-types` loads these modules
// through the native ESM resolver, which never guesses extensions. The bundler
// would resolve the bare specifier, but the contract tests would not.
import { createFilmPass, type FilmPassNode } from './film-pass.ts';
import { createTyndallPass, type TyndallPass } from './tyndall-pass.ts';

/**
 * Node-graph replacement for the classic `EffectComposer` chain.
 *
 * Why this exists: `EffectComposer` is documented as WebGLRenderer-only and
 * reaches into `renderer.state.buffers.stencil`, `WebGLRenderTarget` and
 * classic `ShaderMaterial` full-screen quads. None of that exists on the node
 * renderer, so committing the backend switch is impossible while the frame graph
 * is built out of EffectComposer passes. This module is the bridge.
 *
 * Stage order mirrors the composer chain it replaces:
 *
 *   pass(scene) ─┬─ sceneColor ─┬─ tyndall ─ bloom (additive) ─ film ─ output
 *                └─ sceneDepth ─┘   (and the later composites)
 *
 * The Tyndall raymarch sits between the scene and bloom because that is where
 * the old composer had it: `RenderPass → liquid → whitewater → tyndall → bloom
 * → OutputPass → film`. Bloom must see the shafts so it blooms them, and the
 * grade must come last so the shafts are graded along with everything else.
 * Note the depth the raymarch occludes against is the *scene* depth, captured
 * by the scene pass' MRT before any of this runs - not a post-liquid depth.
 *
 * Tone mapping is the subtle part. In the composer chain the last pass was
 * `OutputPass`, which reads `renderer.toneMapping` / `outputColorSpace` and
 * bakes the matching defines into its own material - so the engine's ACES
 * setting was being applied there, not by the renderer's canvas. The node
 * pipeline expresses the same thing as `outputColorTransform = true`, which
 * wraps the output node in `renderOutput(node, toneMapping, outputColorSpace)`.
 * Turning it OFF would skip tone mapping altogether and hand back an
 * ungraded linear image, so it must stay on (the default).
 *
 * Still unported (each needs its own TSL graph before `EffectComposer` can be
 * dropped for good): the liquid and whitewater composites, and the water optics.
 */
export type FilmChain = {
  pipeline: RenderPipeline;
  film: FilmPassNode;
  /** Tyndall shafts. `apply` is already wired into the chain; the uniforms are live. */
  tyndall: TyndallPass;
  /** Bloom strength / radius / threshold, mirrored as plain value boxes. */
  bloom: {
    strength: { value: number };
    radius: { value: number };
    threshold: { value: number };
  };
  /** The scene under the grade. Held so the depth node can be read by later stages. */
  scenePass: ReturnType<typeof pass>;
  /** Scene colour as a texture node, pre-effect and pre-grade. */
  sceneColor: TextureNode;
  /** Scene depth as a texture node, for occlusion tests in later stages. */
  sceneDepth: TextureNode;
  /** Scene colour after the Tyndall raymarch and bloom, before the grade. */
  lit: Node;
  setSize(width: number, height: number): void;
  dispose(): void;
};

/** Bloom defaults, matching the `UnrealBloomPass` this replaces. */
export const BLOOM_STRENGTH = .045;
export const BLOOM_RADIUS = .25;
export const BLOOM_THRESHOLD = 1.6;

export function createFilmChain(renderer: NodeRenderer, scene: T.Scene, camera: T.Camera): FilmChain {
  // One scene pass, sampled by everything downstream. `pass()` renders the scene
  // into its own target; nothing needs the composer's ping-pong buffers.
  const scenePass = pass(scene, camera);
  // MRT: colour plus depth out of the same rasterisation, so downstream stages
  // (liquid occlusion, Tyndall) never need a second scene render or a captured
  // copy of the depth buffer.
  scenePass.setMRT(mrt({ output, depth: scenePass.getTextureNode('depth') }));

  const sceneColor = scenePass.getTextureNode('output');
  const sceneDepth = scenePass.getTextureNode('depth');

  // Tyndall first, matching the composer order. It reads the scene depth the
  // MRT just produced, so the shafts stop at walls instead of shining through.
  const tyndall = createTyndallPass({ sceneDepth });
  const withShafts = tyndall.apply(sceneColor);

  // Bloom is additive: `bloom()` returns only the blurred high-pass, and the
  // official composition is `sceneColor.add(bloomPass)`. That is exactly the
  // behaviour `UnrealBloomPass` had when it drew on top of the read buffer.
  // It samples the shafts so the beams bloom along with the lamps.
  const bloomNode = bloom(withShafts as never, BLOOM_STRENGTH, BLOOM_RADIUS, BLOOM_THRESHOLD);
  // `add()` is the TSL operator, not a method on the node: the typings drop
  // vector methods once a value is widened to plain `Node`.
  const lit = add(withShafts as never, bloomNode as never);

  const film = createFilmPass();
  // The grade resamples its input at *distorted* coordinates (barrel warp,
  // per-channel fringing), so it needs a real texture - an expression has no
  // `sample()`.
  //
  // `convertToTexture(expression)` is NOT a valid way to get one here. It wraps
  // the expression in an `RTTNode`, and `RTTNode.setup()` re-contexts its input
  // (`this.node.context(...)`) at RENDER time. The upstream expression contains
  // `bloom()`, which is internally a `Fn`: re-contexting it makes every
  // `assign` inside that `Fn` lose its stack. The symptom is
  // "No stack defined for assign operation" at frame time - non-deterministic,
  // because it depends on whether the frame that triggers it is the one that
  // first sets the graph up.
  //
  // So the colour is materialised the explicit way instead: a full-screen quad
  // carrying `lit`, drawn through `pass()`, exactly like the scene itself. It
  // costs one extra full-screen draw and, unlike the RTT path, it is stable.
  const litMaterial = new NodeMaterial();
  litMaterial.colorNode = lit as never;
  litMaterial.depthTest = false;
  litMaterial.depthWrite = false;
  const litQuad = new T.Mesh(new T.PlaneGeometry(2, 2), litMaterial);
  const litScene = new T.Scene();
  litScene.add(litQuad);
  // An orthographic camera with the quad already spanning NDC: no projection
  // maths, and the plane's own uv is the screen uv the grade expects.
  const litCamera = new T.Camera();
  const litPass = pass(litScene, litCamera);
  const graded = film.apply(litPass.getTextureNode('output') as never);

  const pipeline = new RenderPipeline(renderer as never, graded as never);
  // Keep the colour transform ON: it is what applies the renderer's tone mapping
  // (`renderer.toneMapping`) and output colour space to the final image, the job
  // `OutputPass` used to do. See the module comment.
  pipeline.outputColorTransform = true;

  const bloomUniforms = {
    strength: {
      get value() { return (bloomNode.strength as unknown as { value: number }).value; },
      set value(v: number) { (bloomNode.strength as unknown as { value: number }).value = v; },
    },
    radius: {
      get value() { return (bloomNode.radius as unknown as { value: number }).value; },
      set value(v: number) { (bloomNode.radius as unknown as { value: number }).value = v; },
    },
    threshold: {
      get value() { return (bloomNode.threshold as unknown as { value: number }).value; },
      set value(v: number) { (bloomNode.threshold as unknown as { value: number }).value = v; },
    },
  };

  return {
    pipeline,
    film,
    tyndall,
    bloom: bloomUniforms,
    scenePass,
    sceneColor,
    sceneDepth,
    lit,
    // Both passes own render targets, and `pass()` does NOT resize them for us
    // when the viewport changes - an unsynced `litPass` keeps the previous
    // resolution and the grade samples a stale-size texture.
    setSize: (width: number, height: number) => {
      scenePass.setSize(width, height);
      litPass.setSize(width, height);
    },
    // `pass()` owns its render target; RenderPipeline owns its own resources.
    // `litMaterial` / `litQuad` / `litScene` are plain three objects with no
    // GPU resources of their own, but the material does hold the compiled
    // shader, so it is disposed alongside.
    dispose: () => {
      scenePass.dispose();
      litPass.dispose();
      litMaterial.dispose();
      litQuad.geometry.dispose();
      pipeline.dispose();
    },
  };
}

/** A pass-through chain used when nothing but the scene itself is wanted. */
export function createPassthroughChain(renderer: NodeRenderer): RenderPipeline {
  return new RenderPipeline(renderer as never, vec4(0, 0, 0, 1) as never);
}
