# BEYOND THE BASIN | PoolCore

**深水之外** — 一座没有出口的室内泳池。第一人称探索、种子地图、釉面瓷砖、随流漂浮的道具、交互浪花与浮沫，以及带本地时间戳的 CCD 镜头。

## 本地运行

需要 Node.js 22.13 或更新版本，以及启用硬件加速、支持 WebGL2 的桌面浏览器。开发验收使用 Microsoft Edge；画质与帧率依赖 GPU 和分辨率。

局部三维浪花还需要 WebGPU，建议通过 localhost 或 HTTPS 在 Edge 中运行。不支持 WebGPU 时，仍保留浅水水面、波纹与浮沫。

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 3000
```

打开 http://localhost:3000 。生产构建与运行：

```sh
npm run build
npm start
```

## 性能验证

本轮先优化 WebGL 主路径，完整 WebGPU 迁移另行推进。实施状态、固定 3 ms 预算的过渡时间取舍、手持道具折射回归及真实 Edge 基准见 [性能验收记录](docs/performance-2026-09-22.md)。`npm run benchmark:build` 显式生成支持本地 QA 与完整数据导出的优化构建；正常生产构建不开放 QA 接口。

## 手机版（Android APK）

游戏可打包成完全离线的 Android 应用：WebView 壳加载打包进 APK 的静态页面，触屏设备自动启用虚拟摇杆与按键。构建需要 Android SDK（`ANDROID_HOME` 已配置即可）和 JDK 17+（脚本会自动在 `%USERPROFILE%\.jdks` 中寻找，本机已装 `temurin-17`）：

```sh
npm run apk          # vite 打包 web → 写入 APK assets → gradle assembleDebug
```

产物在 `dist-apk/BeyondTheBasin-PoolCore-debug.apk`，安装：`adb install -r dist-apk/BeyondTheBasin-PoolCore-debug.apk`。只重打 web 资产可跑 `npm run apk:web` 后用 `powershell -File build-apk.ps1 -SkipWeb` 收尾。

触屏操作：左侧摇杆移动（推满快走）、右侧滑动转视角、轻点水面/道具互动，「跳」「拿起」「投掷」圆形按键，右上 ☰ 暂停；系统返回键同样呼出暂停菜单。

## 单文件 HTML 版

把整个游戏（JS、CSS、音效、水波纹理）打进一个 HTML 文件，双击即可游玩，也便于直接分发：

```sh
npm run single
```

产物为 `dist-single/BEYOND-THE-BASIN-PoolCore-single.html`。桌面端使用键鼠，手机浏览器自动启用触屏；实际音频和 WebGPU 支持取决于浏览器及运行环境，推荐 Edge。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 / 快走 / 跳跃 | WASD / Shift / 空格 |
| 进入、环视、暂停 | 点击进入水中 / 鼠标 / Esc |
| 扰动水面 | 低头左键点击；涉水移动也会产生波纹 |
| 拖动、拿起、放下 | 左键拖动 / E |
| 投掷、调整持物距离 | 按住右键蓄力、松开投掷 / 滚轮 |
| 攀爬梯子 | 靠近按 E，再按 W/S |
| 镜头、焦散、间接光 | F / C / V |
| 返回起点 | R |

暂停菜单可直接前往旧泳池、高拱门大厅、连通浴池、跳台高廊和夜间浴场；它们也通过门洞相连。周围加载 5×5 个区块，近处 3×3 区块参与主要灯光更新；远处按种子生成、回收。

## 画面与实现

- Three.js / WebGL2、React、Vinext / Vite。
- 瓷砖按非金属釉面着色，粗糙反射采用预过滤环境探针；金属物体另有 BVH 反射。
- 体素锥追踪提供近似静态间接光，区块加载分阶段更新。
- 主水体保留 GPU 浅水求解器，计算传播波、柱子绕流、道具浮力与尾流；独立细波场表现脚步和水滴回落的涟漪。平静时仅保留克制的微表面细节。
- 强冲击产生局部 WebGPU MLS-MPM / APIC 液体域，通过各向异性表面核和 Narrow-Range 深度过滤重建浪花；压力、重力与碰撞决定形状，没有固定数量的模板突起。
- 次级水滴采用真实实例椭球几何，回水产生一次微小涟漪。浮沫是随流平流、扩散和衰减的连续密度场，贴着物体轮廓显示，避免按方形网格排开。
- 水体具有 Low / Medium / High / Ultra 四档质量，以及波高、波速、泡沫存留和光学层调节；静态建筑按材质合批，减少实时阴影的绘制开销。
- 焦散由波面反射、Snell 折射和光束面积变化实时计算，使用渲染目标积累并平滑；不是播放焦散纹样图片。入射段采用建筑遮挡掩码，出射段检查场景三角形。
- CCD 模式包含适度桶形畸变、暗角、轻微偏色与本机实时日期时间。

当前是高度场与有预算的局部三维液体混合模拟，不是全池三维流体求解。局部液体最多同时运行 3 个域，每域最多 18,000 粒子；屏幕空间重建仍受可见内容和分辨率限制。焦散接收范围以所在区块池底及边界墙为主，区块切换存在光照与探针更新成本，帧率依赖设备。

水体结构见 [水体增量升级](docs/water-upgrade.md)，浪花算法、泡沫边界及来源见 [浪花与浮沫](docs/whitewater.md)。MLS-MPM 参考并改编自 [Splash](https://github.com/matsuoka-601/Splash)，[MIT 许可](docs/licenses/Splash-MIT.txt)随仓库保留。

## 检查

```sh
npm run typecheck
npm run lint
npm test
npm run build
```

单元测试覆盖地图复现、碰撞、抓取投掷、浮力随流、水滴回水、体素更新和波纹衰减。`tests/pool-water-boundary-gpu.mjs` 检查圆柱与斜墙边的泡沫保持和渲染覆盖；`tests/pool-liquid-gpu.mjs` 检查实际 WebGPU 的重力、惯性与压力。这些 GPU 脚本通过本地 headed Edge 的 Playwright CLI 执行，独立于 `npm test`。

## 目录

- `app/pool-vct/engine.ts`：场景、地图、输入、灯光与后处理
- `app/pool-vct/world.ts`：种子布局、体素场、瓷砖着色
- `app/pool-vct/water-system.ts`：交互波面、焦散与光线遮挡
- `app/pool-vct/shallow-water.ts`、`water-optics.ts`：浅水求解、连续浮沫与水面光学
- `app/pool-vct/liquid-mpm.ts`、`liquid-mpm-shader.ts`：局部三维液体计算
- `app/pool-vct/liquid-surface-pass.ts`、`splash-particles.ts`：液体表面重建与次级水滴
- `app/pool-vct/physics.ts`：玩家与道具物理
- `app/pool-vct/rt.ts`：BVH 反射
- `app/pool-vct/PoolVCT.tsx`：菜单与摄像机界面
- `tests/`：自动化检查

本仓库发布当前 Web 主版本；旧实验入口、UE 工程、本地部署配置、备份与工具缓存不包含在内。第三方来源见 [ATTRIBUTIONS.md](ATTRIBUTIONS.md)。
