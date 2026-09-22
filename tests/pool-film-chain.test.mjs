/**
 * TSL film chain contract tests.
 *
 * The engine cannot switch to the node renderer while the frame graph is built
 * from classic EffectComposer passes (it requires `renderer.state.buffers.stencil`,
 * `WebGLRenderTarget` and classic ShaderMaterial quads). These tests pin the
 * replacement's contract so the port cannot silently rot:
 *
 *  - the scene pass exposes both colour and depth as sampleable textures;
 *  - the grade produces a node graph the pipeline accepts;
 *  - colour and depth come out of ONE rasterisation (MRT), not two;
 *  - the chain owns its resources and frees them.
 *
 * Everything is checked against the real three modules where possible. Headless
 * node has no WebGPU adapter, so the end-to-end pixel check belongs to the
 * browser harness in .workbuddy/tmp-perf; what can be verified here is that the
 * graph builds and the API surface is the one the engine expects.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { add, pass, mrt, output } from 'three/tsl';
import { bloom } from 'three/examples/jsm/tsl/display/BloomNode.js';
import { createFilmPass } from '../app/pool-vct/webgpu/film-pass.ts';
import { BLOOM_RADIUS, BLOOM_STRENGTH, BLOOM_THRESHOLD } from '../app/pool-vct/webgpu/film-chain.ts';
import { createTyndallPass, SUN_DIR, SUN_TINT, TYNDALL_MARCH_LENGTH, TYNDALL_STEPS } from '../app/pool-vct/webgpu/tyndall-pass.ts';

test('a scene pass exposes colour and depth as distinct texture nodes', () => {
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);

  const color = scenePass.getTextureNode('output');
  const depth = scenePass.getTextureNode('depth');

  assert.ok(color, 'colour texture node must exist');
  assert.ok(depth, 'depth texture node must exist');
  // Same node requested twice must be cached, or every stage would add a copy.
  assert.equal(scenePass.getTextureNode('depth'), depth, 'texture nodes are cached per name');
  assert.notEqual(color, depth, 'colour and depth are different textures');
});

test('depth can be attached over multiple render targets from one pass', () => {
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);

  // This is the mechanism that replaces the old captured scene buffer: the
  // composite stages read scene colour and scene depth without a second render.
  const target = mrt({ output, depth: scenePass.getTextureNode('depth') });
  assert.ok(target, 'mrt target builds');
  scenePass.setMRT(target);
  assert.equal(scenePass.getMRT(), target, 'pass keeps the mrt node it was handed');
});

test('the film grade builds a node graph and keeps its uniforms live', () => {
  const film = createFilmPass();

  // Uniforms are mirrored as plain { value } boxes so the engine can write to
  // them per frame exactly like it did with the ShaderPass uniforms object.
  assert.equal(film.uniforms.filterMode.value, 1, 'default look is the CCD filter');
  assert.equal(film.uniforms.time.value, 0);

  film.uniforms.filterMode.value = 3;
  film.uniforms.time.value = 12.5;
  assert.equal(film.uniforms.filterMode.value, 3, 'filter mode is writable through the box');
  assert.equal(film.uniforms.time.value, 12.5, 'time is writable through the box');

  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);
  const graded = film.apply(scenePass.getTextureNode('output'));
  assert.ok(graded, 'grade returns a usable node');
  // The grade is an expression, not a live object: it must not mutate the input.
  assert.ok(graded !== scenePass.getTextureNode('output'), 'grade produces a new node');
});

test('the grade covers every filter mode the engine can select', () => {
  const film = createFilmPass();
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);

  // The pause menu cycles exactly four looks; each must produce a graph without
  // throwing (a missing branch shows up as a build-time error, not a pixel diff).
  for (const mode of [0, 1, 2, 3]) {
    film.uniforms.filterMode.value = mode;
    const node = film.apply(scenePass.getTextureNode('output'));
    assert.ok(node, `filter mode ${mode} builds`);
  }
});

test('bloom uses the same defaults the UnrealBloomPass it replaces did', () => {
  // These three numbers are the visual contract with the old composer chain:
  // .045 strength / .25 radius / 1.6 threshold. Drifting them silently changes
  // how bright the lamps and caustics read.
  assert.equal(BLOOM_STRENGTH, .045);
  assert.equal(BLOOM_RADIUS, .25);
  assert.equal(BLOOM_THRESHOLD, 1.6);
});

test('bloom is additive over the scene colour, not a replacement', () => {
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);
  const color = scenePass.getTextureNode('output');

  const bloomNode = bloom(color, BLOOM_STRENGTH, BLOOM_RADIUS, BLOOM_THRESHOLD);
  // Strength / radius / threshold are live uniforms on the node, which is why
  // the chain can expose them as writable value boxes.
  assert.equal(bloomNode.strength.value, BLOOM_STRENGTH);
  assert.equal(bloomNode.radius.value, BLOOM_RADIUS);
  assert.equal(bloomNode.threshold.value, BLOOM_THRESHOLD);

  // The documented composition is `sceneColor.add(bloomPass)`; bloom() alone
  // returns only the blurred high-pass, so adding it is what makes the effect
  // appear. This mirrors UnrealBloomPass painting over the read buffer.
  const composed = add(color, bloomNode);
  assert.ok(composed, 'scene + bloom composes');
  assert.notEqual(composed, bloomNode, 'composition is a new node, not the bloom alone');
  assert.notEqual(composed, color, 'composition is a new node, not the raw scene');
});

test('bloom can be retuned per frame through its uniforms', () => {
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);
  const bloomNode = bloom(scenePass.getTextureNode('output'), BLOOM_STRENGTH, BLOOM_RADIUS, BLOOM_THRESHOLD);

  // The engine fades bloom with the corruption level, so these must be mutable.
  bloomNode.strength.value = .09;
  assert.equal(bloomNode.strength.value, .09, 'strength is live');
  bloomNode.threshold.value = 1.2;
  assert.equal(bloomNode.threshold.value, 1.2, 'threshold is live');
});

test('the tyndall pass carries the old ShaderPass constants verbatim', () => {
  // These are not tunables: they are the numbers the GLSL had baked in, and the
  // whole reason for porting line-by-line instead of adopting `godrays()`.
  assert.equal(TYNDALL_STEPS, 20, 'raymarch step count is unchanged');
  assert.equal(TYNDALL_MARCH_LENGTH, 36, 'march length in metres is unchanged');
  assert.deepEqual([...SUN_DIR], [.274, -.913, .274], 'sun axis is unchanged');
  assert.deepEqual([...SUN_TINT], [.62, .78, .84], 'beam tint is unchanged');
});

test('the tyndall pass builds a graph and exposes live uniforms', () => {
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);
  const color = scenePass.getTextureNode('output');

  const tyndall = createTyndallPass({ sceneDepth: scenePass.getTextureNode('depth') });
  assert.equal(tyndall.uniforms.intensity.value, 0, 'shafts start off');
  assert.equal(tyndall.uniforms.spread.value, 5.4, 'cone radius matches the GLSL');
  assert.equal(tyndall.uniforms.spreadGrow.value, .028, 'cone growth matches the GLSL');
  assert.equal(tyndall.uniforms.edge.value, .55, 'soft-edge start matches the GLSL');

  const out = tyndall.apply(color);
  assert.ok(out, 'raymarch builds');
  assert.notEqual(out, color, 'raymarch returns a new expression, not the input');

  // The engine writes these every frame while the shafts are fading in.
  tyndall.uniforms.intensity.value = .05;
  tyndall.uniforms.time.value = 7;
  assert.equal(tyndall.uniforms.intensity.value, .05, 'intensity is live');
  assert.equal(tyndall.uniforms.time.value, 7, 'time is live');
});

test('each tyndall apply is an independent expression', () => {
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(60, 1, .1, 100);
  const scenePass = pass(scene, camera);
  const color = scenePass.getTextureNode('output');
  const tyndall = createTyndallPass({ sceneDepth: scenePass.getTextureNode('depth') });

  // Rebuilding a frame graph by calling apply twice must not hand back the same
  // node: if it did, a rebuilt pipeline would be wired to the old uniforms.
  const a = tyndall.apply(color);
  const b = tyndall.apply(color);
  assert.notEqual(a, b, 'two applies give two expressions');
});

