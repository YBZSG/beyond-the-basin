# Beyond the Basin 性能优化与 WebGPU 迁移设计

> **2026-09-22 实施状态：** 本轮已完成现有 WebGL 主路径主要优化，实测完整涉水投掷为 52.66 FPS，60 FPS 验收尚未全部达标；完整 WebGPU 迁移随后独立推进。当前实现、真实 Edge 验证、基准命令及未达标项见 [High 60 FPS 实施与验收记录](docs/performance-2026-09-22.md)。手持道具进入折射画面已加入回归；固定 3 ms 调度预算以延长慢机器过渡完成时间换取更小的单帧后台开销。以下 2026-09-17 内容保留为历史设计，不能将其中的建议或预计收益视为已完成或已验证。

> 仓库：`inin-long/beyond-the-basin`  
> 基线：Three.js `^0.185.1`，React 19，当前主渲染器为 `WebGLRenderer`，局部 MLS-MPM 已直接使用 WebGPU Compute。  
> 文档日期：2026-09-17  
> 优化目标：**在尽量保持现有 High 画质、光照、水体与白水表现不变的前提下，降低平均帧耗时和帧时间尖峰，使目标笔记本更稳定地维持 60 FPS。**

---

## 1. 结论与总体策略

当前项目并不是一个普通 Three.js 展示场景，而是一条接近小型游戏引擎的实时渲染管线，同时包含：

- 九宫格流式房间与大量静态建筑；
- 27 个动态点光源槽位，其中 4 个 PointLight 开启 1024² cubemap 阴影；
- Voxel Cone Tracing 间接光；
- BVH 单次反射；
- 768² High 档浅水方程；
- 768² 细波高度场；
- 1024² 动态焦散；
- 768² 平面反射；
- 0.8× drawing buffer 的折射场景抓帧；
- WebGPU MLS-MPM 局部三维液体；
- 白水、气泡、水滴与屏幕空间液面重建；
- Tyndall 体积光；
- Bloom、Film、Output 等后处理。

因此，当前“不稳定 60 FPS”的主要问题不能简单归结为 WebGL 性能不足。更准确地说，是当前一帧中同时存在：

1. **重复场景渲染；**
2. **大范围阴影无效更新；**
3. **GPU → CPU → GPU 数据往返；**
4. **大尺寸全屏/全网格 pass 数量较多；**
5. **缺少真实 GPU 时间测量，导致优化依据不够精确。**

WebGPU 值得迁移，但不应把“替换 Renderer”当作优化本身。项目真正适合 WebGPU 的原因是：**可以把浅水、细波、MLS-MPM、白水生成、物理采样和最终绘制留在同一个 GPU 数据域中，减少 CPU 同步和 API 之间的数据搬运。**

推荐顺序：

```text
P0  正确测量 GPU 时间
 ↓
P1  删除重复场景渲染
 ↓
P1  精细化阴影失效
 ↓
P1  清理现有全屏 pass / 几何 batching
 ↓
P2  TSL / WebGPURenderer 渐进迁移
 ↓
P2  MLS-MPM 全 GPU resident
 ↓
P2  浅水与物理查询 GPU 化
 ↓
P3  Clustered Lighting / 更深层 GPU-driven 优化
```

不建议一开始就重写全部 shader。先优化当前 WebGL 路径，可以获得更低风险的性能收益，同时建立迁移前后的基准。

---

# 2. 建立可用的性能基线

## 2.1 当前问题：`frame-probe.ts` 测到的主要是 CPU 提交时间

当前：

`app/pool-vct/frame-probe.ts`

使用：

```ts
const t = performance.now();
fn();
const elapsed = performance.now() - t;
```

并将帧划分为：

```ts
'props'
'liquid'
'particles'
'water'
'capture'
'composer'
```

这种测量对 JavaScript、物理计算、Three.js render list 构建、command submission 很有价值，但它**不能准确表示 GPU 真正完成这些工作的耗时**。

GPU 是异步执行的：

```text
JavaScript
   │
   ├── renderer.render(...)
   │       ↓
   │    提交 GPU 命令
   │
   ├── 下一阶段
   │
   └── 某个同步点才可能等待 GPU
```

因此一个真正 GPU-bound 的阶段，CPU 侧可能只显示 0.3 ms。

---

## 2.2 优化方案：CPU Profiler 与 GPU Profiler 分离

建议新增：

```text
app/pool-vct/perf/
├── cpu-profiler.ts
├── webgl-gpu-profiler.ts
├── webgpu-gpu-profiler.ts
└── perf-types.ts
```

定义统一接口：

```ts
export type GpuStage =
  | 'shadow'
  | 'opaque'
  | 'water-sim'
  | 'caustics'
  | 'refraction'
  | 'liquid-depth'
  | 'liquid-filter'
  | 'whitewater'
  | 'tyndall'
  | 'bloom'
  | 'final';

export interface GpuFrameTimings {
  frame: number;
  stages: Partial<Record<GpuStage, number>>;
  total: number;
}
```

### WebGL2 路径

使用：

```ts
EXT_disjoint_timer_query_webgl2
```

不要在同一帧调用同步 `getQueryParameter(...QUERY_RESULT...)` 等待结果，而应该维护 query ring。

示意：

```ts
type PendingQuery = {
  stage: GpuStage;
  query: WebGLQuery;
  frame: number;
};

export class WebGLGpuProfiler {
  private gl: WebGL2RenderingContext;
  private ext: EXT_disjoint_timer_query_webgl2;
  private pending: PendingQuery[] = [];
  private active = new Map<GpuStage, WebGLQuery>();

  begin(stage: GpuStage) {
    const query = this.gl.createQuery();
    if (!query) return;

    this.gl.beginQuery(this.ext.TIME_ELAPSED_EXT, query);
    this.active.set(stage, query);
  }

  end(stage: GpuStage, frame: number) {
    const query = this.active.get(stage);
    if (!query) return;

    this.gl.endQuery(this.ext.TIME_ELAPSED_EXT);
    this.pending.push({ stage, query, frame });
    this.active.delete(stage);
  }

  resolve() {
    const disjoint = this.gl.getParameter(this.ext.GPU_DISJOINT_EXT);
    if (disjoint) return [];

    const results: Array<{ stage: GpuStage; frame: number; ms: number }> = [];

    this.pending = this.pending.filter(item => {
      const ready = this.gl.getQueryParameter(
        item.query,
        this.gl.QUERY_RESULT_AVAILABLE,
      );

      if (!ready) return true;

      const ns = this.gl.getQueryParameter(
        item.query,
        this.gl.QUERY_RESULT,
      ) as number;

      results.push({
        stage: item.stage,
        frame: item.frame,
        ms: ns / 1_000_000,
      });

      this.gl.deleteQuery(item.query);
      return false;
    });

    return results;
  }
}
```

注意：一个 `TIME_ELAPSED_EXT` query 不能任意嵌套。实际实现中应按渲染阶段串行包裹，或者为重点阶段建立更粗粒度区间。

### `engine.ts` 接入

当前：

```ts
probeTick('water', () => waterSystem.render(renderer, time));
```

建议演进为：

```ts
cpuProfiler.measure('water', () => {
  gpuProfiler.begin('water-sim');

  waterSystem.render(renderer, time);

  gpuProfiler.end('water-sim', frameId);
});
```

场景渲染进一步拆分：

```ts
gpuProfiler.begin('refraction');
waterSystem.captureScene(...);
gpuProfiler.end('refraction', frameId);

gpuProfiler.begin('final');
composer.render();
gpuProfiler.end('final', frameId);
```

---

## 2.3 HUD 数据结构也需要调整

当前 `Status`：

```ts
timings?: FrameTimings
```

建议改为：

```ts
export type PerfSnapshot = {
  cpu: Record<string, number>;
  gpu: Record<string, number>;
  renderer: {
    calls: number;
    triangles: number;
    points: number;
    lines: number;
    geometries: number;
    textures: number;
  };
  frame: {
    fps: number;
    frameMs: number;
    p95: number;
    p99: number;
  };
};

export type Status = {
  // ...
  perf?: PerfSnapshot;
};
```

每帧保存：

```ts
renderer.info.render.calls
renderer.info.render.triangles
renderer.info.memory.geometries
renderer.info.memory.textures
```

不要每帧通过 React `setState()` 更新完整 profiler。推荐仍保持当前约 350~500 ms 的 UI 刷新频率。

---

## 2.4 验收标准

不要只看平均 FPS。

至少记录：

```text
Average FPS
Average frame time
P95 frame time
P99 frame time
CPU main-thread time
GPU frame time
Draw calls
Triangles
Shadow GPU ms
Water GPU ms
Refraction GPU ms
Post GPU ms
```

60 FPS 的理论预算：

```text
16.67 ms / frame
```

实际应留出余量。目标机器上更合理的目标是让常规场景的 GPU/CPU 主路径都明显低于 16.67 ms，而不是长期贴着 16.5 ms 跑。

---

# 3. 问题一：折射导致场景重复渲染

## 3.1 当前代码

文件：

```text
app/pool-vct/water-system.ts
```

`captureScene()` 当前执行：

```ts
this.waterRef.visible = false;

for (const object of excluded) {
  object.visible = false;
}

renderer.setRenderTarget(this.opaque);
renderer.clear();
renderer.render(scene, camera);
```

随后 `engine.ts` 中：

```ts
waterSystem.captureScene(renderer, scene, camera, ...);

composer.render();
```

而 `EffectComposer` 中的 `RenderPass` 会再次绘制主场景。

所以移动时大致是：

```text
Scene Render #1
    ↓
refraction opaque target

Scene Render #2
    ↓
EffectComposer RenderPass
```

High 档折射尺寸为 drawing buffer 的 80%。

这会显著增加：

- draw call；
- fragment shading；
- VCT shader；
- point light；
- shadow consumer；
- BVH reflection；
- material switching。

这是当前最优先应该删除的重复工作之一。

---

## 3.2 目标架构

应改为：

```text
Opaque Scene
     │
     ▼
Opaque Color + Depth
     │
     ├──────────────► Water shader sampling
     │
     ▼
Water / Transparent
     │
     ▼
Whitewater
     │
     ▼
Post Processing
```

核心原则：

> **折射使用主场景已经产生的 opaque color/depth，而不是为了折射重新 render 整个 scene。**

---

## 3.3 WebGL 阶段推荐改造

新增：

```text
app/pool-vct/render/
├── opaque-scene-pass.ts
├── water-composite-pass.ts
└── render-layers.ts
```

定义 layer：

```ts
export const LAYER_WORLD = 0;
export const LAYER_WHITEWATER = 1;
export const LAYER_WATER = 2;
```

创建水面后：

```ts
water.layers.set(LAYER_WATER);
```

主建筑、道具：

```ts
object.layers.set(LAYER_WORLD);
```

### 第一步：Opaque pass

`opaque-scene-pass.ts`：

```ts
export class OpaqueScenePass extends Pass {
  readonly colorTarget: T.WebGLRenderTarget;

  constructor(
    private scene: T.Scene,
    private camera: T.Camera,
  ) {
    super();

    this.colorTarget = new T.WebGLRenderTarget(1, 1, {
      type: T.HalfFloatType,
      depthBuffer: true,
    });

    this.colorTarget.depthTexture = new T.DepthTexture(1, 1);
  }

  render(renderer: T.WebGLRenderer) {
    const oldMask = this.camera.layers.mask;

    this.camera.layers.set(LAYER_WORLD);

    renderer.setRenderTarget(this.colorTarget);
    renderer.clear();
    renderer.render(this.scene, this.camera);

    this.camera.layers.mask = oldMask;
  }

  setSize(width: number, height: number) {
    this.colorTarget.setSize(width, height);
  }
}
```

### 第二步：Water 不再调用 `captureScene()`

把：

```ts
captureScene(
  renderer,
  scene,
  camera,
  excluded,
)
```

逐步替换成：

```ts
bindOpaqueScene(
  color: T.Texture,
  depth: T.DepthTexture,
  camera: T.PerspectiveCamera,
)
```

例如：

```ts
bindOpaqueScene(
  color: T.Texture,
  depth: T.DepthTexture,
  camera: T.PerspectiveCamera,
) {
  this.optics.sceneColor.value = color;
  this.optics.sceneDepth.value = depth;
  this.optics.cameraNear.value = camera.near;
  this.optics.cameraFar.value = camera.far;
  this.optics.sceneReady.value = 1;
}
```

随后删除或废弃：

```ts
captureScene()
refractionAge
capturePos
captureDir
captureSkips
captureFrames
```

因为折射输入已经是**当前帧** opaque scene，不需要“隔 N 帧抓一次”。

---

## 3.4 避免反馈采样

不能：

```text
从 Target A 采样
同时继续向 Target A 写
```

因此推荐 ping-pong：

```text
OpaqueTarget A
    ↓ sampled by Water
CompositeTarget B
```

不要为此再次渲染场景，只需要一次 fullscreen base copy，或者直接让 water composite shader：

```glsl
if (not_water_pixel) {
    output = opaqueColor;
} else {
    output = waterColor;
}
```

这样：

```text
完整场景重画一次
```

变成：

```text
一次全屏 composite
```

二者成本不是一个数量级。

---

## 3.5 WebGPU 最终形态

Three.js `WebGPURenderer` 的新 `RenderPipeline` 可以直接以 scene pass 的 color/depth 作为后续 node 输入。

迁移完成后目标：

```ts
const scenePass = pass(scene, camera);

const sceneColor = scenePass.getTextureNode('output');
const sceneDepth = scenePass.getTextureNode('depth');

const waterComposite = createWaterNode({
  sceneColor,
  sceneDepth,
  // ...
});

renderPipeline.outputNode = postProcess(waterComposite);
```

此时不要恢复旧式：

```ts
renderer.render(scene, camera);
renderer.render(scene, camera);
```

---

## 3.6 验收

固定：

- 同一 seed；
- 同一相机位置；
- 同一视角；
- High；
- 水面开启折射。

改造前后比较：

```text
refraction scene render count
draw calls / frame
triangles / frame
GPU refraction ms
GPU total ms
```

画质验收必须包含：

- 水边；
- 道具穿越水面；
- 近距离柱子；
- 房间门洞；
- 高对比灯光；
- 白水与透明物体。

---

# 4. 问题二：PointLight 阴影失效粒度过粗

## 4.1 当前结构

`app/pool-vct/room-lights.ts`：

```ts
const SHADOW_MAP_SIZE = 1024;
```

27 个灯槽中：

```ts
light.castShadow = i < 4;
```

PointLight 阴影是 cubemap：

```text
4 shadow lights
× 6 cube faces
× 1024²
≈ 25.2 M shadow pixels
```

当前已经实现阴影缓存，这是正确方向。

问题出在 `engine.ts`：

```ts
let propsMoved = false;

propsMoved = props.update(...);

if (propsMoved) {
  roomLights.invalidate();
}
```

即：

> 任意物理物体移动 → 四个 shadow slot 全部 dirty。

场景中的鸭子和球可能因为浮力或水流持续小幅移动。

---

## 4.2 改造 `PropPhysics.update()`

不要只返回：

```ts
boolean
```

改成：

```ts
export interface MovedShadowCaster {
  body: PropBody;
  previous: T.Vector3;
  current: T.Vector3;
  radius: number;
}

export interface PropUpdateResult {
  moved: MovedShadowCaster[];
  anyMoved: boolean;
}
```

在更新位置之前保存：

```ts
const previous = body.position.clone();
```

但不要每帧创建大量 `Vector3`。

推荐直接给 `PropBody` 增加复用字段：

```ts
type PropBody = {
  // ...
  position: T.Vector3;

  previousShadowPosition: T.Vector3;
  shadowRadius: number;
};
```

每个 step 结束：

```ts
const dx = body.position.x - body.previousShadowPosition.x;
const dy = body.position.y - body.previousShadowPosition.y;
const dz = body.position.z - body.previousShadowPosition.z;

const moved =
  dx * dx +
  dy * dy +
  dz * dz > SHADOW_MOVE_EPSILON_SQ;
```

只有真正跨过阈值才加入列表。

例如：

```ts
const SHADOW_MOVE_EPSILON = 0.005;
```

阈值应通过视觉回归确定；也可以严格设为极小值，优先保证画质一致。

---

## 4.3 `RoomLights` 改成 per-slot dirty

当前：

```ts
private dirty = true;
```

改成：

```ts
private shadowDirty = [true, true, true, true];
```

source reassignment：

```ts
for (let i = 0; i < shadowCount; i++) {
  if (this.shadowSources[i] !== this.sources[i]) {
    this.shadowSources[i] = this.sources[i];
    this.shadowDirty[i] = true;
  }
}
```

---

## 4.4 根据物体运动范围精确失效

新增：

```ts
invalidateBodies(moved: MovedShadowCaster[]) {
  for (let i = 0; i < 4; i++) {
    const source = this.sources[i];
    if (!source) continue;

    for (const caster of moved) {
      if (this.affectsLight(caster, source)) {
        this.shadowDirty[i] = true;
        break;
      }
    }
  }
}
```

灯影响测试：

```ts
private affectsLight(
  caster: MovedShadowCaster,
  light: T.PointLight,
) {
  const r = caster.radius;

  const oldDx = caster.previous.x - light.position.x;
  const oldDy = caster.previous.y - light.position.y;
  const oldDz = caster.previous.z - light.position.z;

  const newDx = caster.current.x - light.position.x;
  const newDy = caster.current.y - light.position.y;
  const newDz = caster.current.z - light.position.z;

  const range = light.distance + r;
  const rangeSq = range * range;

  const oldInside =
    oldDx * oldDx +
    oldDy * oldDy +
    oldDz * oldDz <= rangeSq;

  const newInside =
    newDx * newDx +
    newDy * newDy +
    newDz * newDz <= rangeSq;

  return oldInside || newInside;
}
```

最后：

```ts
for (let i = 0; i < 4; i++) {
  if (!this.shadowDirty[i]) continue;

  this.lights[i].shadow.needsUpdate = true;
  this.shadowDirty[i] = false;
}
```

---

## 4.5 更进一步：区分“不影响可见阴影”的物体

可以给 body 增加：

```ts
castsDynamicShadow: boolean
```

例如极小水滴根本不进入 shadow map；没有必要触发阴影更新。

对未来新增粒子系统尤其重要。

---

## 4.6 验收

测试：

1. 当前房间鸭子移动；
2. 隔壁房间球移动；
3. 玩家投球穿过灯下；
4. 视角快速转向导致 shadow slot source reassignment；
5. 物体进入/离开 PointLight range。

必须保证：

```text
该更新的阴影一定更新；
不受影响的 slot 不更新。
```

HUD 新增：

```text
Shadow slots updated: 0/4
Shadow cube faces rendered: 0/24
Shadow GPU ms
```

---

# 5. 问题三：MLS-MPM 存在 WebGPU → CPU → WebGL 往返

## 5.1 当前数据路径

文件：

```text
app/pool-vct/liquid-mpm.ts
```

当前 MLS-MPM 已使用 WebGPU：

```ts
navigator.gpu.requestAdapter(...)
adapter.requestDevice()
```

每个 patch 最大：

```ts
LIMIT = 18000
MAX_PATCHES = 3
```

即最高约：

```text
54,000 particles
```

计算之后：

```ts
encoder.copyBufferToBuffer(
  patch.buffers[3],
  0,
  patch.buffers[5],
  0,
  patch.count * 80,
);
```

随后：

```ts
patch.buffers[5].mapAsync(GPUMapMode.READ)
```

读回：

```ts
patch.data.set(
  new Float32Array(
    patch.buffers[5].getMappedRange(),
  ),
);
```

下一帧 CPU 又：

```ts
for (let i = 0; i < patch.count; i++) {
  // ...
  this.mesh.setMatrixAt(visible++, this.transform);
}

this.mesh.instanceMatrix.needsUpdate = true;
```

于是形成：

```text
WebGPU Compute
      ↓
GPU particle state
      ↓
GPU → CPU readback
      ↓
JavaScript loop
      ↓
instanceMatrix
      ↓
CPU → WebGL upload
      ↓
WebGL rasterization
```

这条链路非常容易制造 frame-time spike。

---

## 5.2 当前 WebGL 阶段不要强行“零拷贝”

WebGPU buffer 与 WebGL buffer 没有通用的直接共享机制。

因此，只要主渲染仍是 WebGL，想彻底消除：

```text
WebGPU → CPU → WebGL
```

并不现实。

不要为此引入复杂 native bridge。

当前阶段应该：

- 保持已有异步 `mapAsync()`；
- 避免任何 `device.queue.onSubmittedWorkDone()` 式帧内同步；
- 不在渲染主线程主动等待 MPM；
- 将真正零拷贝放到统一 WebGPU renderer 阶段。

---

# 6. WebGPU 核心改造：让 MPM 全程 GPU resident

这是整个 WebGPU 迁移最有价值的一项。

## 6.1 不再由 `LiquidMPM` 自己创建第二个 `GPUDevice`

当前：

```ts
const adapter = await navigator.gpu.requestAdapter(...);
const device = await adapter.requestDevice();
```

如果主渲染器迁移为 `WebGPURenderer`，不能继续把 MPM 当成一个完全独立 GPU 子系统。

否则可能形成：

```text
Three WebGPURenderer Device A
Raw MPM Device B
```

不同 GPUDevice 之间不能直接共享普通 GPUBuffer。

推荐将 MPM 重写到 Three.js TSL compute / storage buffer 体系。

---

## 6.2 新目录

```text
app/pool-vct/webgpu/
├── liquid-mpm.ts
├── liquid-buffers.ts
├── liquid-render.ts
├── liquid-events.ts
├── shallow-water.ts
├── ripple-detail.ts
└── water-query.ts
```

当前已有：

```text
webgpu/ripple-detail.ts
```

可以作为迁移模式参考。

---

## 6.3 使用 StorageBufferNode / instanced storage

概念上：

```ts
import {
  Fn,
  instancedArray,
  instanceIndex,
} from 'three/tsl';

const particlePosition = instancedArray(
  MAX_PARTICLES,
  'vec4',
);

const particleVelocity = instancedArray(
  MAX_PARTICLES,
  'vec4',
);

const computeStep = Fn(() => {
  const p = particlePosition.element(instanceIndex);
  const v = particleVelocity.element(instanceIndex);

  // MLS-MPM update...
})().compute(MAX_PARTICLES);
```

渲染直接使用：

```ts
material.positionNode =
  particlePosition.toAttribute();
```

最终变成：

```text
Compute
   ↓
StorageBuffer
   ├────► 下一次 Compute
   └────► Render
```

不经过 CPU。

---

## 6.4 不要把全部 particle state 回读

CPU 真正需要的不是每个粒子的完整 80 bytes state。

只需要少量事件，例如：

```ts
type LiquidEvent =
  | {
      type: 'return';
      x: number;
      z: number;
      power: number;
    }
  | {
      type: 'drop';
      x: number;
      y: number;
      z: number;
      vx: number;
      vy: number;
      vz: number;
    };
```

GPU 中建立 compact event buffer：

```text
Atomic event counter
+
Event storage buffer
```

只读取：

```text
eventCount
event[0..N]
```

而不是 54,000 粒子的完整状态。

---

## 6.5 最终 `LiquidMPM` API

旧：

```ts
liquid.update(
  dt,
  surface,
  depth,
  drop,
  ripple,
);
```

目标：

```ts
liquid.compute({
  dt,
  waterField,
  colliderBuffer,
});

liquid.render({
  sceneColor,
  sceneDepth,
  waterField,
});

const events =
  liquid.pollEvents();
```

`pollEvents()` 必须异步、非阻塞。

没有结果时：

```ts
return [];
```

而不是等待 GPU。

---

# 7. 问题四：浅水方程读取整张 384² CPU 物理场

## 7.1 当前实现

`shallow-water.ts`：

主模拟 High 为：

```text
768²
```

物理读回：

```ts
SW_PHYS = 384
```

每次：

```ts
this.draw(renderer, this.down, this.physTarget);
this.requestReadback(renderer);
```

然后：

```ts
renderer.readRenderTargetPixelsAsync(
  this.physTarget,
  0,
  0,
  SW_PHYS,
  SW_PHYS,
  job.buffer,
);
```

CPU 解析：

```ts
for (...) {
  this.physicsEta[i] = ...
  this.physicsU[i] = ...
  this.physicsV[i] = ...
}
```

而这些数据主要被：

- 浮力；
- 水流；
- slopeAt；
- crest/foam 检测；

使用。

---

## 7.2 为什么不能现在简单删除整图 readback

当前：

```ts
crestSpray()
```

直接扫描：

```ts
physicsEta
physicsU
physicsV
```

所以如果立刻只回读几十个物体采样点，会破坏浪尖检测。

正确迁移顺序应该是：

```text
先把 crest detection 搬 GPU
              ↓
再把物体 water query 搬 GPU
              ↓
最后删除 384² full-field CPU readback
```

---

# 8. GPU 化 Crest Detection

当前：

```text
64 × 64 nearby cells
= 4096 CPU probes
30 Hz
```

在 WebGPU 中改成 compute：

```text
water state texture/buffer
       ↓
Crest Detect Compute
       ↓
Candidate Buffer
       ↓
Prefix/Atomic Compact
       ↓
Crest Event Buffer
```

示意：

```ts
const crestCandidates = instancedArray(
  MAX_CREST_EVENTS,
  'vec4',
);

const crestCounter = ...;

const detectCrests = Fn(() => {
  // 读取 eta / u / v
  // 检查 local maximum
  // curvature
  // Froude / convergence
  // 满足条件后 atomicAdd(counter)
  // 写入 crestCandidates
})();
```

CPU 不需要 4096 个格点。

只在真正需要触发 MPM / 飞沫时读取很小的事件列表，甚至如果 MPM 也在同一 WebGPU device 中，可以：

```text
Crest Compute
     ↓
直接写 MPM source buffer
```

连事件都不需要回 CPU。

---

# 9. GPU 化物体水体查询

当前 `PropPhysics` 调用：

```ts
heightAt(x, z)
flowAt(x, z)
slopeAt(x, z)
```

理想架构不是：

```text
384² GPU field
      ↓
整张读 CPU
      ↓
查询几十个对象
```

而是：

```text
几十个 object query
      ↓
GPU sample water field
      ↓
几十个结果
```

定义：

```ts
type WaterProbe = {
  x: number;
  z: number;
  radius: number;
};

type WaterProbeResult = {
  height: number;
  flowX: number;
  flowZ: number;
  slopeX: number;
  slopeZ: number;
};
```

每帧把 active dynamic objects 填进 probe storage：

```ts
waterQueries.write(
  props.getWaterProbePositions(),
);
```

Compute：

```text
ProbeBuffer
   +
Water State
   ↓
Sample Compute
   ↓
ResultBuffer
```

CPU 最多读取几十到几百个 result。

如果未来物理本身也 GPU 化，则无需 readback。

---

# 10. 问题五：High 水体每帧存在大量全网格 pass

High：

```text
simulation 768²
ripple     768²
solverSteps 最大 8
rippleSteps 最大 8
```

浅水每个 substep 至少：

```text
velocity pass
height pass
```

理论最大：

```text
768² × 2 × 8
≈ 9.44 M cell updates / frame
```

这还没有算：

- texture fetch；
- foam；
- advection；
- viscosity；
- wall loss；
- source；
- downsample。

---

## 10.1 不建议通过降低分辨率解决

因为本文目标是不牺牲 High 画质。

所以不以：

```text
768 → 384
solverSteps 8 → 4
```

作为默认优化方案。

这些可以保留为用户显式质量档位，但不算本轮“无损优化”。

---

## 10.2 WebGPU Compute 化

当前浅水使用 fragment shader + ping-pong render target。

WebGPU 目标：

```text
Storage Texture / Storage Buffer A
              ↓
Velocity Compute
              ↓
Storage B
              ↓
Height Compute
              ↓
Storage A
```

迁移第一阶段不要修改数学模型，只修改执行后端。

保持：

```text
同样的网格
同样的 dt
同样的 CFL
同样的阻尼
同样的 advection
同样的 foam
```

这样容易做数值回归。

---

## 10.3 第二阶段：Workgroup tiling

浅水 stencil 主要读取当前格点及附近邻居：

```text
west
east
south
north
```

这是典型 stencil compute。

最终可按：

```text
8×8
16×16
```

workgroup tile 加 halo，把邻居先加载进 workgroup shared memory，再反复使用。

概念：

```text
Global GPU Memory
      ↓
Workgroup tile + 1 cell halo
      ↓
多个邻域计算
      ↓
Global GPU Memory
```

这可以减少重复 global texture/buffer fetch。

是否使用 TSL 或 raw WGSL，应以实现复杂度和 Three.js 当前 API 能力为准；不要仅为了“纯 TSL”牺牲可维护性。

---

# 11. 问题六：`LiquidSurfacePass` 全屏工作量偏高

文件：

```text
app/pool-vct/liquid-surface-pass.ts
```

当前一次有效白水液体表面渲染包含：

```text
1. 粒子深度 raster
2. filter horizontal
3. filter vertical
4. filter horizontal
5. filter vertical
6. copy 当前 background
7. fullscreen liquid shade
```

也就是：

- 一次 particle geometry pass；
- 四次 full-screen filter；
- 一次 full-screen copy；
- 一次 full-screen shade。

---

## 11.1 先删除 `background` copy

当前：

```ts
this.copy.uniforms.image.value = read.texture;

renderer.setRenderTarget(this.background);
this.quad.render(renderer);
```

随后 shade 读取：

```ts
background: {
  value: this.background.texture,
}
```

原因是当前 pass：

```ts
this.needsSwap = false;
```

并直接写回 `read`，因此不能同时采样 `read.texture`。

改造思路：

```text
read  = input scene
write = output liquid-composited scene
```

把：

```ts
this.needsSwap = false;
```

改为：

```ts
this.needsSwap = true;
```

然后让 `shade`：

```ts
background.value = read.texture;
renderer.setRenderTarget(write);
this.quad.render(renderer);
```

Shader 不应该在非液体区域 `discard`，而应该：

```glsl
float d = texture2D(fluidDepth, vUv).r;

if (d > 9000.0) {
    gl_FragColor = texture2D(background, vUv);
    return;
}
```

于是：

```text
copy background
+
liquid shade
```

合并成一个 pass。

可以直接删除：

```ts
private background = ...
```

以及 dispose 中对应 target。

---

## 11.2 修改后的 render 骨架

```ts
render(
  renderer: T.WebGLRenderer,
  write: T.WebGLRenderTarget,
  read: T.WebGLRenderTarget,
) {
  if (!this.mesh.count) {
    // 让 composer 正常处理 swap。
    this.copyReadToWrite(renderer, read, write);
    return;
  }

  // 1. particle depth
  renderer.setRenderTarget(this.depth);
  renderer.render(this.fluidScene, this.camera);

  // 2. narrow-range filter
  // 保持现有四次算法，先不改画质。

  // 3. 一次性：
  // read scene + filtered liquid -> write
  this.shade.uniforms.background.value = read.texture;
  this.shade.uniforms.fluidDepth.value = source;

  renderer.setRenderTarget(write);
  this.quad.material = this.shade;
  this.quad.render(renderer);
}
```

后续再评估是否将四轮 filter 用 WebGPU compute 优化。

第一阶段不要改变 Narrow-Range Filter 次数，避免引入液体边缘画质变化。

---

# 12. 问题七：WhitewaterPass 仍有额外 full-screen copy

文件：

```text
app/pool-vct/whitewater-pass.ts
```

当前：

```ts
this.copy.uniforms.image.value = read.texture;

renderer.setRenderTarget(this.target);
this.quad.render(renderer);

renderer.setRenderTarget(read);
renderer.render(this.scene, this.camera);
```

这也是为了避免透明材质读取正在写入的 render target。

短期可以保留，因为它保证正确的 transmission 输入。

但迁移 render graph 后应该改成显式：

```text
Read Target
   │
   ├── sample by whitewater material
   │
   ▼
Write Target
```

即：

```ts
this.needsSwap = true;
```

目标是不再需要私有：

```ts
private target = new T.WebGLRenderTarget(...)
```

而是让 compositor/pipeline 分配 ping-pong target。

WebGPU `RenderPipeline` 最终应把 whitewater 作为显式 composite node，而不是旧 `Pass`。

---

# 13. 问题八：静态建筑 batching 强制 `toNonIndexed()`

文件：

```text
app/pool-vct/static-geometry.ts
```

当前：

```ts
const geometry =
  mesh.geometry.index
    ? mesh.geometry.toNonIndexed()
    : mesh.geometry.clone();
```

这能让几何合并简单化，但会让 indexed geometry 展开。

例如 BoxGeometry 原本大量顶点可复用，一旦 non-indexed：

```text
index reuse
   ↓
被展开为独立 triangle vertices
```

影响：

- vertex buffer 大小；
- vertex shader invocations；
- shadow pass vertex workload；
- BVH 构建输入；
- cache locality。

---

## 13.1 无损修改：按 indexed / non-indexed 分批

当前 batch key：

```ts
[
  object.material.uuid,
  object.castShadow,
  object.receiveShadow,
  object.renderOrder,
  object.layers.mask,
]
```

加入：

```ts
object.geometry.index ? 'indexed' : 'non-indexed'
```

修改：

```ts
const key = [
  object.material.uuid,
  object.castShadow,
  object.receiveShadow,
  object.renderOrder,
  object.layers.mask,
  object.geometry.index ? 1 : 0,
].join('/');
```

然后：

```ts
const geometry = mesh.geometry.clone();

geometry.applyMatrix4(
  inverse.clone().multiply(mesh.matrixWorld),
);
```

不要：

```ts
toNonIndexed()
```

`mergeGeometries()` 在同一个 batch 内会得到一致的 indexed 状态。

代价只是：

> 某些 material 可能从 1 个 batch 变为 2 个 batch。

通常比把整座房间展开成 non-indexed 更合理。

---

## 13.2 需要测量

加入统计：

```ts
function geometryStats(root: T.Object3D) {
  let vertices = 0;
  let triangles = 0;
  let meshes = 0;

  root.traverse(o => {
    if (!(o instanceof T.Mesh)) return;

    meshes++;

    const geometry = o.geometry;
    vertices += geometry.attributes.position?.count ?? 0;

    triangles += geometry.index
      ? geometry.index.count / 3
      : (geometry.attributes.position?.count ?? 0) / 3;
  });

  return {
    meshes,
    vertices,
    triangles,
  };
}
```

batch 前后打印一次开发日志即可，不要进入生产帧循环。

---

# 14. 问题九：VCT fragment shader 成本很高

文件：

```text
app/pool-vct/world.ts
```

核心：

```glsl
vec3 traceCone(...)
```

最大：

```glsl
for (int i = 0; i < 16; i++)
```

而：

```glsl
coneDiffuse(...)
```

会调用：

```text
normal
normal + tangent
normal - tangent
normal + bitangent
normal - bitangent
```

即理论最大：

```text
5 × 16
= 80 次 voxel samples / fragment
```

再叠加：

- PBR；
- point lights；
- caustics；
- shadow；
- 某些材质的 BVH reflection；

很容易进入 fragment-bound。

---

## 14.1 不要盲目先改 VCT

VCT 优化很容易改变整体光照风格。

因此它应当排在 GPU profiler 之后。

如果 GPU profiler 表明：

```text
opaque scene GPU ms
```

显著高于其它阶段，再单独拆 shader A/B test。

---

## 14.2 首先做“调用范围”优化，而不是改算法

确保以下对象不进入 VCT material：

- `MeshBasicMaterial`；
- 自发光 fixture；
- debug geometry；
- 极小粒子；
- 不需要间接光的辅助 proxy。

当前已有材质区分，继续保持。

新增材质能力标签：

```ts
type PoolMaterialFlags = {
  vct: boolean;
  caustics: boolean;
  rtReflection: boolean;
};
```

统一由 material factory 创建，避免未来任何 `MeshStandardMaterial` 默认套上所有昂贵 shader hook。

例如：

```ts
createPoolMaterial({
  color: '#...',
  vct: true,
  caustics: true,
  rtReflection: false,
});
```

不要继续散落：

```ts
field.apply(...)
waterSystem.attachReceiver(...)
rt.apply(...)
```

长期应集中到一个材质构建层。

---

# 15. 问题十：BVH Reflection 只应存在于真正需要的材质

目前这一点已经做得比较正确：

```ts
rt.apply(chrome, ...)
rt.apply(red, ...)
```

没有给所有瓷砖启用 per-pixel BVH reflection。

应继续保持。

迁移 WebGPU 时不要为了“统一材质”把 BVH reflection 再加回所有 MeshStandardNodeMaterial。

推荐最终：

```ts
enum ReflectionMode {
  None,
  Environment,
  PlanarWater,
  BVHSingleBounce,
}
```

每类材质明确选择路径。

---

# 16. 问题十一：后处理使用旧 `EffectComposer`

当前 `engine.ts`：

```ts
EffectComposer
RenderPass
UnrealBloomPass
ShaderPass
OutputPass
```

另外 Tyndall fragment shader每像素最多：

```text
20 ray-march steps
```

这部分不一定是最大瓶颈，但具有明显的 full-screen bandwidth 特征。

---

## 16.1 WebGL 阶段

不要马上为了减少 pass 改 Bloom 算法。

先做：

1. GPU timer；
2. LiquidSurfacePass 去一次 copy；
3. refraction 去重复 scene render；
4. 再测 composer。

如果 Film + Output 在目标机器上确实明显，可写一个：

```text
FinalCameraPass
```

把：

- CCD distortion；
- VHS scanline；
- chromatic fringe；
- grain；
- vignette；
- color grading；
- tone mapping；
- output transfer；

合并。

但必须做截图回归，保证 ACES 和 color-space 处理没有发生顺序变化。

---

## 16.2 WebGPU 最终改用 `RenderPipeline`

当前 Three.js 的 WebGPU 后处理不是旧 `EffectComposer`。

目标：

```ts
const renderPipeline =
  new T.RenderPipeline(renderer);

const scenePass =
  pass(scene, camera);

const sceneColor =
  scenePass.getTextureNode('output');

const sceneDepth =
  scenePass.getTextureNode('depth');

const tyndall =
  createTyndallNode(
    sceneColor,
    sceneDepth,
  );

const bloom =
  bloomNode(tyndall);

const film =
  createFilmNode(bloom);

renderPipeline.outputNode = film;
```

新系统支持 node composition，并可以在可行时合并效果，减少旧式 pass 链中的额外 framebuffer 往返。

---

# 17. 问题十二：主 `WebGPURenderer` 迁移不能直接替换一行代码

仓库当前已经有：

```text
app/pool-vct/backend.ts
```

其中：

```ts
new WebGPURenderer({
  antialias,
  alpha: false,
  forceWebGL: !available,
});
```

并且已经有：

```text
app/pool-vct/webgpu/ripple-detail.ts
```

说明项目已经处于 WebGPU 渐进迁移阶段。

但是主：

```text
engine.ts
```

仍然直接：

```ts
const renderer =
  new T.WebGLRenderer(...);
```

---

## 17.1 不能直接替换的模块

以下代码依赖旧 WebGL shader 路线：

```text
world.ts
    VoxelField.apply()
    onBeforeCompile()

rt.ts
    BVH GLSL injection

water-system.ts
    ShaderMaterial
    onBeforeCompile()

liquid-surface-pass.ts
    ShaderMaterial
    legacy Pass

whitewater-pass.ts
    legacy Pass

engine.ts
    EffectComposer
    ShaderPass
    UnrealBloomPass
```

Three.js `WebGPURenderer` 不支持把这些旧 `ShaderMaterial` / `onBeforeCompile()` 路线原样当成 WebGPU shader。

需要逐项 TSL / NodeMaterial 化。

---

# 18. 推荐 WebGPU 迁移顺序

## Phase W0：Backend 真正接入主引擎

将：

```ts
export function createPool(...)
```

改成异步：

```ts
export async function createPool(...)
```

内部：

```ts
const backend =
  await createBackend(!touch);

const renderer =
  backend.renderer;
```

但是这一阶段可以：

```ts
forceWebGL: true
```

先验证 Node/TSL 代码能在 WebGL2 backend 正常工作。

这相当于：

```text
先迁 Three.js 新 renderer abstraction
后打开真正 WebGPU backend
```

比一次性跨两层风险更低。

---

## Phase W1：迁移细波

你已经有：

```text
webgpu/ripple-detail.ts
```

优先完成它与 `InteractiveWater` 的实际接线。

把：

```ts
import { RippleDetail }
  from './ripple-detail';
```

逐步切成统一接口：

```ts
interface RippleSolver {
  impact(...): void;
  rebase(...): void;
  frame(...): void;
  dispose(): void;
}
```

WebGL / WebGPU 实现共享上层 API。

---

## Phase W2：迁移 Final Film / 简单后处理

因为逻辑相对独立：

```text
Film
Vignette
Color grading
```

比 VCT、BVH 和水体 shader 更适合作为 TSL 入门迁移。

---

## Phase W3：迁移水体材质

将：

```text
WATER_WAVES
WATER_FRAGMENT
onBeforeCompile
```

拆成 TSL function：

```text
waterHeight()
waterNormal()
waterFresnel()
waterRefraction()
waterAbsorption()
waterReflection()
waterFoam()
```

不要复制一整段巨大 node graph。

目标结构：

```ts
export const waterHeightNode = Fn(...);
export const waterNormalNode = Fn(...);
export const waterOpticsNode = Fn(...);
```

这样：

- water mesh；
- floater；
- caustics；
- liquid surface；

可以共享节点函数。

---

## Phase W4：迁移 VCT

把：

```glsl
voxelSample()
traceCone()
coneDiffuse()
```

分别改为：

```ts
const voxelSample = Fn(...);
const traceCone = Fn(...);
const coneDiffuse = Fn(...);
```

保持输入：

```text
vct0
vct1
vct2
vct3
origin
extent
strength
```

不先修改算法。

---

## Phase W5：迁移 BVH reflection

这是难度较高的一层。

如果当前 `three-mesh-bvh` TSL / WebGPU 路线不足以等价实现现有 shader-side BVH，需要：

1. 保留环境反射作为临时 fallback；
2. 单独验证 TSL BVH 支持；
3. 不要阻塞前四阶段。

BVH reflection 只影响少数金属材质，因此不应让它成为整个 WebGPU 迁移的第一阻塞项。

---

## Phase W6：MLS-MPM 与浅水 Compute 全 GPU resident

这是 WebGPU 迁移真正产生架构收益的阶段。

目标：

```text
Shallow Water Compute
        │
        ├── Water Rendering
        ├── Buoyancy Queries
        ├── Crest Detection
        └── Caustics Input

MLS-MPM Compute
        │
        ├── Surface Reconstruction
        ├── Droplets
        └── Final Rendering
```

都在同一个 renderer/device 数据域内。

---

# 19. Clustered Lighting：后期值得做，但不是第一阶段

当前拥有大量 PointLight slot。

传统 forward renderer 对每个 fragment 处理固定 light array。

WebGPU 后可考虑：

```text
Depth / Camera
      ↓
Cluster Build Compute
      ↓
Light Index Buffer
      ↓
Fragment 只处理当前 cluster 的 lights
```

例如：

```text
screen X: 16 tiles
screen Y: 9 tiles
depth:    24 slices
```

每个 cluster 存：

```ts
offset
count
```

全局 light index buffer：

```text
[4, 9, 13, ...]
```

fragment 不再循环整个可用灯列表。

这不会要求删除灯光，因此属于“画质保持、减少无关计算”的优化。

但实现成本较高，应当等 P0/P1 项完成后，根据 profiler 决定是否需要。

---

# 20. Shader Compilation Stutter

稳定 60 FPS 不只是平均耗时。

房间切换、质量切换、首次出现材质时可能触发 shader compile。

主 renderer 初始化完成后建议预编译当前场景：

```ts
await renderer.compileAsync(
  scene,
  camera,
);
```

WebGPU Compute 迁移后：

```ts
await renderer.compileComputeAsync([
  shallowWaterCompute,
  rippleCompute,
  liquidCompute,
]);
```

不要在玩家第一次跳水时才第一次编译 MPM / liquid reconstruction shader。

---

# 21. 房间流式加载期间的 CPU Spike

当前 VoxelField 已经用：

```ts
stepRadiance(budgetMs)
```

跨帧构建，这是正确做法。

应继续统一所有重建任务：

```text
Voxel rebuild
BVH rebuild
Caustic occlusion mask
Room geometry batching
Probe capture
```

为：

```ts
interface IncrementalJob {
  step(budgetMs: number): boolean;
}
```

统一任务调度器：

```ts
class FrameBudgetScheduler {
  enqueue(job: IncrementalJob): void;
  frame(budgetMs: number): void;
}
```

例如每帧：

```ts
scheduler.frame(1.5);
```

而不是各子系统分别无协调地消费：

```text
1 ms
2 ms
1 ms
...
```

这样可以减少“单个模块都没超预算，但总和超预算”的问题。

---

# 22. 建议的最终 Frame Graph

目标架构：

```text
┌──────────────────────────────┐
│ CPU Gameplay / Input         │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ GPU Compute                  │
│                              │
│ Shallow Water                │
│ Ripple                       │
│ Crest Detection              │
│ MLS-MPM                      │
│ Particle / Whitewater Update │
│ Light Clustering             │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Shadow Update                │
│ only dirty light slots       │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Opaque Scene Pass            │
│ Color + Depth                │
└──────────────┬───────────────┘
               │
          ┌────┴─────┐
          │          │
          ▼          ▼
     Refraction   Tyndall input
          │
          ▼
┌──────────────────────────────┐
│ Water Composite              │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Liquid / Whitewater          │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Bloom / Film / Output        │
│ RenderPipeline / TSL         │
└──────────────┬───────────────┘
               │
               ▼
             Screen
```

最重要的是：

```text
Opaque scene 只画一次
```

以及：

```text
Water / MPM / particles
尽量不离开 GPU
```

---

# 23. 建议的实际提交拆分

不要做一个“WebGPU mega commit”。

推荐：

## Commit 1

```text
perf: add asynchronous GPU timing infrastructure
```

涉及：

```text
frame-probe.ts
perf/*
PoolVCT.tsx
```

---

## Commit 2

```text
perf: report renderer and frame-time metrics
```

增加：

```text
draw calls
triangles
p95
p99
shadow updates
```

---

## Commit 3

```text
perf: invalidate point-light shadows per slot
```

涉及：

```text
physics.ts
room-lights.ts
engine.ts
```

---

## Commit 4

```text
perf: preserve indexed static geometry batches
```

涉及：

```text
static-geometry.ts
tests
```

---

## Commit 5

```text
perf: reuse opaque scene for water refraction
```

这是第一项较大的 render graph 改造。

涉及：

```text
engine.ts
water-system.ts
render/opaque-scene-pass.ts
render/water-composite-pass.ts
```

---

## Commit 6

```text
perf: remove liquid surface background copy
```

涉及：

```text
liquid-surface-pass.ts
```

---

## Commit 7

```text
refactor: centralize renderer backend
```

正式让：

```text
backend.ts
```

进入 engine 创建路径。

---

## Commit 8

```text
refactor: migrate film pipeline to TSL
```

---

## Commit 9

```text
refactor: migrate water optics to TSL
```

---

## Commit 10

```text
perf: keep MLS-MPM particles GPU resident
```

这是 WebGPU 迁移的关键收益点。

---

## Commit 11

```text
perf: move water queries and crest detection to GPU
```

删除 full field CPU dependency。

---

## Commit 12

```text
perf: migrate shallow water solver to compute
```

最后再逐步引入 workgroup 优化。

---

# 24. 性能测试场景

必须固定测试输入，否则 FPS 数据不可比较。

建议新增：

```text
tests/perf/
├── idle-room.ts
├── walk-room.ts
├── turn-camera.ts
├── water-impact.ts
├── throw-props.ts
├── heavy-whitewater.ts
└── transition-room.ts
```

至少覆盖：

### Scene A：静止

```text
High
默认房间
无交互
相机不动
```

用于验证：

- shadow cache；
- caustic cache；
- refraction reuse / 新 render graph；
- idle GPU floor。

### Scene B：持续走动

用于放大：

- refraction；
- opaque render；
- room lights；
- visibility；
- fragment workload。

### Scene C：持续快速转头

用于测试：

- view-dependent lights；
- shadow slot reassignment；
- refraction；
- VCT/BVH fragment cost。

### Scene D：大型入水

用于测试：

- Shallow Water；
- Ripple；
- MLS-MPM；
- LiquidSurfacePass；
- Whitewater。

### Scene E：多个动态道具

用于测试：

- PropPhysics；
- shadow invalidation；
- water query；
- instance upload。

---

# 25. 视觉回归测试

“不牺牲画质”必须可验证。

建议建立：

```text
tests/visual/
```

固定：

```text
seed
camera position
camera quaternion
time
water settings
room coordinate
```

保存 reference screenshot。

每次核心渲染改造后执行：

```text
before.png
after.png
diff.png
```

对于：

- TSL shader 重写；
- Film pass 合并；
- Water composite；
- Shadow cache；

尤其需要视觉回归。

水体是动态系统，需要允许非常小的浮点误差，但不能允许：

- 波峰形状明显变化；
- 焦散分辨率下降；
- 阴影缺失；
- 折射错误；
- 白水轮廓变化；
- 灯光能量变化。

---

# 26. 优化优先级最终表

| 优先级 | 问题 | 文件 | 改造性质 | 画质风险 | 预期价值 |
|---|---|---|---|---|---|
| P0 | GPU 性能数据缺失 | `frame-probe.ts`, `engine.ts` | instrumentation | 无 | 必须 |
| P1 | 折射导致 scene 重画 | `water-system.ts`, `engine.ts` | render graph | 低 | 极高 |
| P1 | 动态物体导致 4 灯全部阴影失效 | `room-lights.ts`, `physics.ts` | cache invalidation | 低 | 极高 |
| P1 | MPM GPU→CPU→WebGL | `liquid-mpm.ts` | 架构迁移 | 中 | 极高 |
| P1 | LiquidSurface 背景重复 copy | `liquid-surface-pass.ts` | pass cleanup | 低 | 中高 |
| P1 | 静态 batching 展开 index | `static-geometry.ts` | geometry | 极低 | 中 |
| P2 | 384² 水场完整 CPU readback | `shallow-water.ts` | GPU query | 中 | 高 |
| P2 | CPU crest scan | `water-system.ts` | compute | 中 | 高 |
| P2 | 浅水多次全网格 raster pass | `shallow-water.ts` | compute | 中 | 高 |
| P2 | 旧 EffectComposer 多 pass | `engine.ts` | RenderPipeline | 中 | 中高 |
| P2 | shader compile stutter | `engine.ts` | warmup | 无 | 稳定性高 |
| P3 | VCT 5×16 cone samples | `world.ts` | shader algorithm | 高 | 视 profiling 而定 |
| P3 | Forward PointLight 扩展性 | `engine.ts`, lighting | clustered lighting | 中高 | 高 |
| P3 | 更深层 portal / occlusion | room streaming | culling | 中 | 中 |

---

# 27. 最建议立即执行的三项

如果当前目标是尽快把笔记本上的帧率稳定下来，而不是马上完成 WebGPU 重构，建议依次做：

## 第一项：真实 GPU profiler

没有它之前，不再根据 CPU `performance.now()` 猜 GPU 瓶颈。

## 第二项：折射复用 opaque scene

这是当前代码中最明显的重复渲染。

目标：

```text
2 × scene render
→
1 × scene render + 1 × cheap composite
```

## 第三项：PointLight per-slot shadow invalidation

目标：

```text
任何 prop 移动
→ 24 cube faces potentially dirty
```

改为：

```text
只更新真正受该 prop 影响的 light slot
```

完成这三项后重新采样 GPU profile，再决定：

```text
Water
VCT
Post
MPM
```

下一步谁优先。

---

# 28. WebGPU 是否值得迁移

答案是：**值得，但理由不是“WebGPU 天生比 WebGL 快”。**

这个项目尤其适合 WebGPU，是因为它已经存在大量 GPU simulation：

```text
Shallow Water
Ripple
MLS-MPM
Particles
Crest Detection
Caustics
Lighting
```

目前最大的架构问题之一是：

```text
不同计算阶段之间
仍然经常借 CPU 做数据中转
```

WebGPU 迁移真正应该实现的是：

```text
Compute Buffer
     ↓
Render Buffer
```

而不是：

```text
Compute GPU
     ↓
CPU
     ↓
WebGL GPU
```

所以 WebGPU 迁移的成功标准不应是：

> “`WebGPURenderer` 跑起来了。”

而应该是：

> “主水体、细波、MLS-MPM、白水与相关查询在同一个 GPU 数据域完成，并显著减少 readback、重复 render 与同步点。”

---

# 29. Three.js 当前迁移约束

Three.js 当前 `WebGPURenderer`：

- 默认优先 WebGPU，可回落 WebGL2；
- 使用 TSL / NodeMaterial；
- 旧 `ShaderMaterial`、`RawShaderMaterial`、`onBeforeCompile()` 不能直接按旧方式迁移；
- 旧 `EffectComposer` 需要迁到新的 `RenderPipeline`；
- 新后处理支持 MRT 与 node composition；
- TSL 已提供 compute node；
- StorageBufferNode / StorageInstancedBufferAttribute 可以让 compute 结果直接成为渲染 attribute；
- `compileAsync()` / `compileComputeAsync()` 可用于减少首次 shader 编译卡顿。

因此本项目现有：

```text
backend.ts
webgpu/ripple-detail.ts
```

方向正确，但下一阶段重点应从“建立 WebGPU backend”转向：

```text
统一 render graph
+
统一 GPU data ownership
```

---

# 30. 参考

Three.js WebGPU Renderer：

https://threejs.org/manual/en/webgpurenderer.html

Three.js WebGPU Post Processing：

https://threejs.org/manual/en/webgpu-postprocessing.html

Three.js RenderPipeline：

https://threejs.org/docs/pages/RenderPipeline.html

Three.js Renderer / Compute API：

https://threejs.org/docs/pages/Renderer.html

Three.js StorageBufferNode：

https://threejs.org/docs/pages/StorageBufferNode.html

Three.js TSL：

https://threejs.org/docs/pages/TSL.html

仓库中与本文直接相关的主要文件：

```text
app/pool-vct/engine.ts
app/pool-vct/backend.ts
app/pool-vct/frame-probe.ts
app/pool-vct/room-lights.ts
app/pool-vct/static-geometry.ts
app/pool-vct/world.ts
app/pool-vct/rt.ts
app/pool-vct/shallow-water.ts
app/pool-vct/ripple-detail.ts
app/pool-vct/water-system.ts
app/pool-vct/water-settings.ts
app/pool-vct/liquid-mpm.ts
app/pool-vct/liquid-surface-pass.ts
app/pool-vct/whitewater-pass.ts
app/pool-vct/webgpu/ripple-detail.ts
```

---

## 最终原则

本项目下一轮性能优化应始终遵循三个约束：

1. **先测量，再优化。** CPU 提交时间不能替代 GPU 时间。
2. **优先删除无效工作，而不是降低质量。** 先处理重复 scene render、无效 shadow refresh、GPU/CPU 往返和多余 full-screen copy。
3. **WebGPU 的核心价值是数据驻留与 compute/render 协同，而不是 Renderer 名称发生变化。**

在这套原则下，即使最终 WebGPU 相比 WebGL 的单次 draw call 并没有巨大性能差距，整个应用仍能因为更合理的 Frame Graph 和 GPU 数据流获得明显更稳定的帧时间。
