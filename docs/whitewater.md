# 浪花与浮沫重做

更新：2026-09-15。本地 Three.js / WebGL2 渲染，局部液体使用 WebGPU。

## 采用的算法

主水面继续由现有浅水方程和细波场计算，负责传播、绕流、浮力和尾流；强冲击处使用局部三维 MLS-MPM / APIC 液体域，次级水滴和连续浮沫分别处理。

- 主液体：压力、重力、初始水流与运动碰撞体决定形状，没有预制水片或固定波峰数量。局部域以 1/720 秒子步推进，显示在相邻 GPU 读回之间插值。
- 表面重建：邻域协方差生成各向异性椭球核，实际几何绘制深度，再经 Narrow-Range 过滤重建法线并合成折射与反射。
- 飞沫：稀疏粒子从 MPM 中移除，转为实例椭球几何；运动线段与动态水面检测接触，回水一次产生一次微小涟漪。
- 气泡：水流拖曳和浮力使其上浮，出水消失，不变成水面白球。
- 浮沫：浅水状态纹理 alpha 中的连续密度，随速度平流、扩散与衰减；活动凸波峰和强入水生成，微弱回水不持续制造白斑。多尺度值噪声随流移动，细化连续覆盖。
- 遮挡：水下气泡进入折射场景，主水面之后复制颜色再合成液体与水滴，避免读写反馈。

预算为 3 个局部域，每域最多 18,000 粒子和 80³ 网格；另有最多 1,024 个次级水滴／气泡。无 WebGPU 时保留原水面，不恢复模板水片。

## 物体边界

圆柱半径从房间实体保留到水体碰撞体，避免额外方形障碍堵住圆柱外的四角。泡沫平流忽略干格并重新归一化，扩散采用无通量边界，物体边不再额外消耗泡沫。渲染在交界处使用湿样本的归一化三次插值，由真实几何深度确定可见轮廓；不按二值网格裁切水面，也不设置离岸排斥带。接触细亮线依据场景深度厚度。

CPU 物理读回纹理的 alpha 仍为完整性哨兵 1，不是浮沫。

## 在线核对的来源与采用边界

1. Ihmsen, M., Akinci, N., Akinci, G., Teschner, M. **Unified Spray, Foam and Air Bubbles for Particle-Based Fluids** (2012). [DOI](https://doi.org/10.1007/s00371-012-0697-9)，[作者公开全文](https://cg.informatik.uni-freiburg.de/publications/2012_CGI_sprayFoamBubbles.pdf)。本次核对了正文的生成势、能量加权、粒子采样、状态运动和消散方法，尤其是式 (8) 和 §3.2。当前采用的是适配高度场的二次粒子模型，不是原文完整 SPH 邻域算法和离线体积光线投射器。
2. SideFX **Whitewater Source / Whitewater Solver** 当前官方文档（页面显示 Houdini 22.0）。[生成器](https://www.sidefx.com/docs/houdini/nodes/sop/whitewatersource.html)，[求解器](https://www.sidefx.com/docs/houdini/nodes/sop/whitewatersolver.html)。核对了速度、曲率与运动驱动的生成、按深度区分状态、平流、浮力、寿命和表面附着机制。未实现 Houdini 的 PBF 密度约束、repellants 或完整三维 SDF/FLIP 耦合。
3. Matsuoka [**Splash**](https://github.com/matsuoka-601/Splash)：核对并改编其 MLS-MPM 计算流程与屏幕空间液体渲染，MIT 许可保留于 [licenses/Splash-MIT.txt](licenses/Splash-MIT.txt)。相关介绍：[WebGPU Fluid Simulations（2025-02-26）](https://tympanus.net/codrops/2025/02/26/webgpu-fluid-simulations-high-performance-real-time-rendering/)。另参考 [Narrow-Range Filter 论文](https://ttnghia.github.io/pdf/NarrowRangeFilter.pdf)，当前深度过滤不等同于完整论文基准复现。

这是有预算的局部三维液体与高度场混合模拟，水下域使用近似静水支撑，并非全池三维流体。屏幕重建、粒子分辨率和读回仍限制薄片与细丝的真实感；未验证摄影级效果或稳定 60 FPS。

## 验证

使用本地 Edge 和 RTX 5070 Laptop GPU 检查。自动测试涵盖飞沫回落、泡沫随流与消散、气泡转态、陆地阻隔、粒子预算及场景重定位。GPU 场测试检查小扰动不生成泡沫、强入水只在局部留下白水、静止消散，以及三个水面分辨率的稳定性。

边界回归见 `tests/pool-water-boundary-gpu.mjs`：三个分辨率下圆柱／斜墙边的泡沫保持、圆周各方向的渲染覆盖，以及房间汇总后的实际圆柱轮廓。`tests/pool-liquid-gpu.mjs` 检查重力、惯性、表面核和压力；`tests/pool-whitewater-browser.mjs` 使用真实键盘与鼠标检查涉水、拾取投掷和回水。

视觉验收需同时观察起溅、回落、残留泡沫和静止水面，单个计数或静态截图不能证明完整动态观感。
