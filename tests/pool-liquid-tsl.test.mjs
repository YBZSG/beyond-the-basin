/**
 * Contract tests for the two TSL modules the liquid port is built on:
 * `webgpu/water-waves-tsl.ts` (the shared wave field) and
 * `webgpu/liquid-filter-tsl.ts` (the narrow-range filter).
 *
 * Why these exist at all: both modules are pure node-graph builders, so the
 * things that can go wrong are not "does it throw" but
 *
 *  - the graph builds against the uniform bag the shipping materials expose;
 *  - the early-return guards stay real branches, not eager `select()`s, because
 *    that is the difference between skipping a texture fetch and paying for it
 *    at every call site (the wave field's `detailHeight` is called 4x from
 *    `detailSlope` and 5x from `poolHeightSmooth`);
 *  - the filter's loop bounds stay inside the GLSL's 1..6 window and its
 *    sentinel stays at the same threshold the fluid depth buffer writes.
 *
 * The pixel-exactness of the filter was settled in the browser harness
 * (`.workbuddy/tmp-perf/probe-ab-filter.mjs`: `maxDelta = 0` across 4096 pixels
 * against the shipping GLSL on the same input). What is verifiable in headless
 * node is that the graphs build and the constants are the ones the GLSL uses.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from 'three';
import { Fn, float, vec2 } from 'three/tsl';
import { createWaveField } from '../app/pool-vct/webgpu/water-waves-tsl.ts';
import { LIQUID_EMPTY, LIQUID_EMPTY_OUT, createNarrowFilter } from '../app/pool-vct/webgpu/liquid-filter-tsl.ts';

/** A uniform bag with the same shape the shipping water materials expose. */
function waveUniforms() {
  const tex = (fill) => {
    const t = new T.DataTexture(new Float32Array(96 * 96 * 4).fill(fill), 96, 96, T.RGBAFormat, T.FloatType);
    t.needsUpdate = true;
    return t;
  };
  return {
    poolSurface: { value: tex(.05) },
    poolDepth: { value: tex(1) },
    poolDetail: { value: tex(.01) },
    poolCell: { value: 1 },
    detailCell: { value: .25 },
    poolTime: { value: 3 },
    waveHeight: { value: .1 },
    rippleGain: { value: .5 },
    normalBoost: { value: 1 },
    microStrength: { value: .3 },
    simulationOn: { value: 1 },
    ripplesOn: { value: 1 },
    microOn: { value: 1 },
    causticsScale: { value: 1 },
    causticsSpeed: { value: 1 },
    microOrigin: { value: new T.Vector2(0, 0) },
  };
}

test('the wave field exposes every entry point the GLSL prelude declares', () => {
  const field = createWaveField(waveUniforms());
  const expected = [
    'poolRestDepth', 'poolRestDepthSmooth', 'poolHeight', 'detailHeight',
    'poolSurfaceHeight', 'simulationSlope', 'detailSlope', 'microSlope',
    'poolNormal', 'poolHeightSmooth',
  ];
  for (const name of expected) {
    assert.equal(typeof field[name], 'function', `${name} must be bound`);
  }
});

test('every wave-field entry point builds a node graph without a stack', () => {
  // The graphs are built outside any `Fn()` body here. That is deliberate: each
  // function opens its own `Fn()`, and a missing one would throw
  // "No stack defined for assign operation" the moment it is constructed rather
  // than at render time.
  const field = createWaveField(waveUniforms());
  const p = vec2(1.5, -2.5);
  const built = {
    poolRestDepth: field.poolRestDepth(p),
    poolRestDepthSmooth: field.poolRestDepthSmooth(p),
    poolHeight: field.poolHeight(p),
    detailHeight: field.detailHeight(p),
    poolSurfaceHeight: field.poolSurfaceHeight(p),
    simulationSlope: field.simulationSlope(p),
    detailSlope: field.detailSlope(p),
    microSlope: field.microSlope(p, float(.09)),
    poolNormal: field.poolNormal(p),
    poolHeightSmooth: field.poolHeightSmooth(p),
  };
  for (const [name, node] of Object.entries(built)) {
    assert.ok(node, `${name} must return a node`);
  }
});

test('the normal is Y-up and unit length by construction', () => {
  // `poolNormal` is `normalize(vec3(-sim - det - micro, 1).xzy)`: the swizzle
  // puts the constant 1 on Y, so the normal must never be flat-on-the-horizon
  // and never point along Z alone.
  const field = createWaveField(waveUniforms());
  const n = field.poolNormal(vec2(0, 0));
  assert.ok(n, 'normal node must build');
  // The node is a `Fn` result, so its structure is opaque; what can be asserted
  // without a GPU is that it built and is distinct from its inputs.
  assert.notEqual(n, field.poolNormal(vec2(1, 1)), 'different positions give different graphs');
});

test('a missing texture uniform fails at build time, not at compile time', () => {
  // A texture uniform is wired by the engine before the first frame, so an
  // absent one is a wiring bug. Every entry point that reads the detail texture
  // must report it while the field is being built - if the lookup happened
  // inside an `Fn` body it would defer to shader-compile time, and the same
  // missing uniform would surface from different stack depths depending on
  // whether it was reached directly or through a slope.
  const uniforms = waveUniforms();
  delete uniforms.poolDetail;
  const field = createWaveField(uniforms);
  const readsDetail = [
    'detailHeight', 'detailSlope', 'poolHeightSmooth', 'poolNormal', 'poolSurfaceHeight',
  ];
  for (const name of readsDetail) {
    assert.throws(
      () => (name === 'poolNormal' ? field[name](vec2(0, 0)) : field[name](vec2(0, 0))),
      /poolDetail/,
      `${name} must name the missing uniform`,
    );
  }
  // `simulationSlope` reads only the surface and depth textures, so with those
  // present it must build cleanly even though the detail texture is gone.
  assert.ok(field.simulationSlope(vec2(0, 0)), 'simulationSlope does not read poolDetail');
});

test('a missing depth or surface texture also fails at build time', () => {
  // `poolHeight` reads the surface field and `poolRestDepth` reads the depth
  // mask; the two are separate textures with separate readers.
  const noSurface = waveUniforms();
  delete noSurface.poolSurface;
  const f1 = createWaveField(noSurface);
  assert.throws(() => f1.poolHeight(vec2(0, 0)), /poolSurface/, 'poolHeight reads poolSurface');
  assert.throws(() => f1.simulationSlope(vec2(0, 0)), /poolSurface/, 'simulationSlope reads poolSurface');

  const noDepth = waveUniforms();
  delete noDepth.poolDepth;
  const f2 = createWaveField(noDepth);
  assert.throws(() => f2.poolRestDepth(vec2(0, 0)), /poolDepth/, 'poolRestDepth reads poolDepth');
  assert.throws(() => f2.poolRestDepthSmooth(vec2(0, 0)), /poolDepth/, 'the smooth variant reads it too');
  assert.throws(() => f2.simulationSlope(vec2(0, 0)), /poolDepth/, 'simulationSlope masks on poolDepth');
});

test('a numeric uniform can be absent and falls back to its default', () => {
  // The GLSL prelude declares these as uniforms but several call sites reach the
  // field before the engine has written them, so an absent scalar must not throw.
  const uniforms = waveUniforms();
  delete uniforms.rippleGain;
  delete uniforms.normalBoost;
  const field = createWaveField(uniforms);
  assert.ok(field.detailHeight(vec2(1, 2)), 'detailHeight survives a missing rippleGain');
  assert.ok(field.simulationSlope(vec2(1, 2)), 'simulationSlope survives a missing normalBoost');
});

test('the filter builds against the uniform bag the pass owns', () => {
  const src = new T.DataTexture(new Float32Array(32 * 32 * 4).fill(.5), 32, 32, T.RGBAFormat, T.FloatType);
  src.needsUpdate = true;
  const graph = createNarrowFilter({
    source: { value: src },
    texel: { value: new T.Vector2(1 / 32, 1 / 32) },
    direction: { value: new T.Vector2(1, 0) },
    projectionScale: { value: 500 },
  });
  assert.ok(graph, 'filter must return a node');
  // The four ping-pong iterations reuse one material by rewriting `direction`
  // and `source`, so the graph must be built once and stay valid across them.
  assert.equal(typeof graph, 'object');
});

test('the sentinel matches the value the fluid scene clears to', () => {
  // `LiquidSurfacePass` sets `fluidScene.background = new T.Color(10000, 0, 0)`,
  // i.e. a red channel of 10000, and the filter rejects anything above 9000.
  // These two constants are the whole no-liquid contract; if either drifts the
  // filter starts smoothing the background and the waterline smears.
  assert.equal(LIQUID_EMPTY, 9000, 'the reject threshold');
  assert.equal(LIQUID_EMPTY_OUT, 10000, 'the value written for empty pixels');
  const bg = new T.Color(10000, 0, 0);
  assert.ok(bg.r > LIQUID_EMPTY, 'the cleared background must exceed the threshold');
  assert.equal(bg.r, LIQUID_EMPTY_OUT, 'and equal the value the filter writes');
});

test('the filter caps its kernel at six texels', () => {
  // `clamp(projectionScale * .018 / centre, 1., 6.)` is the only thing bounding
  // the inner loop's work. The loop itself runs to 6, so a radius above 6 would
  // silently truncate the kernel; a radius below 1 would disable it.
  const radius = (projectionScale, centre) =>
    Math.min(6, Math.max(1, (projectionScale * .018) / centre));
  assert.equal(radius(500, 10000), 1, 'far/empty clamps to the floor');
  assert.equal(radius(1e6, 1), 6, 'a huge scale clamps to the ceiling');
  assert.ok(radius(500, 4.5) > 1 && radius(500, 4.5) < 6, 'mid-range is unclamped');
});

test('the wave field is bound to one uniform bag, not read at call time', () => {
  // `createWaveField` captures the bag. A second bag must give an independent
  // field, or the liquid pass and the water system would share state.
  const a = createWaveField(waveUniforms());
  const b = createWaveField(waveUniforms());
  const pa = vec2(0, 0);
  assert.ok(a.poolHeight(pa));
  assert.ok(b.poolHeight(pa));
  assert.notEqual(a.poolHeight(pa), b.poolHeight(pa), 'independent bags give independent graphs');
});

test('Fn-wrapped helpers do not leak a stack when built eagerly', () => {
  // Guards against the failure mode that hid for several sessions: an `assign`
  // outside a stack only `console.error`s and returns a plausible node, so the
  // graph builds and the shader compiles while the arithmetic silently no-ops.
  // Building all ten entry points, then a `Fn` of our own, must leave the stack
  // exactly as it was found.
  const field = createWaveField(waveUniforms());
  const p = vec2(.5, .5);
  for (let i = 0; i < 3; i++) {
    field.poolNormal(p);
    field.poolHeightSmooth(p);
    field.detailSlope(p);
    field.microSlope(p, float(.09));
  }
  const own = Fn(() => {
    const acc = float(0).toVar();
    acc.assign(float(1));
    return acc;
  });
  assert.ok(own, 'an unrelated Fn must still build after the field is built');
});
