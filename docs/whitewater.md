# 浪花与浮沫重做

更新：2026-09-14。本地 WebGL2 / Three.js 实现，未部署。

## 采用的算法

采用独立于主体水量求解的二次白水粒子。水面继续由现有浅水方程和细波场计算；白水根据局部水深与速度，在飞沫、水下气泡、表面泡沫三种状态下运动。

- 飞沫：不规则小粒子束，继承局部水流初速度，重力和空气阻力控制回落。水滴回水只产生很弱的涟漪，不循环生成白沫。
- 气泡：入水时在局部体积中采样；水流拖曳和浮力使其上浮，到水面转成少量泡沫。
- 泡沫：3–13 mm 的离散空气体积，随局部水流移动，粒径和可见度随寿命下降。生成量由强度控制；没有全水面 Voronoi 网纹、白色蒙版或规则圆环网格。
- 浪尖生成：能量乘以夹气/凸波峰生成势。网格实现用速度平方、汇聚、局部曲率和正水位近似；只压缩水流或静止的尖锐表面不会独立产生飞沫。
- 渲染：按实际世界尺寸投影的球面/拉长粒子，解析表面法线与深度、Fresnel、局部屏幕颜色折射。泡沫使用体积不透明度近似 `1-exp(-opticalDepth)`。小于像素的粒子按面积衰减，避免远处变成满屏白点。
- 接触与遮挡：泡沫顶点采样与水面相同的平滑高度；不越过水深掩码中的陆地，场景深度遮挡水线附近的泡沫。水下气泡先进入折射场景，飞沫和泡沫在主水面之后渲染，避免读写同一个场景纹理。

最多 4096 粒子，共用几何缓冲，两次粒子绘制（水下和水上）。没有新增依赖或外部贴图。

## 在线核对的来源与采用边界

1. Ihmsen, M., Akinci, N., Akinci, G., Teschner, M. **Unified Spray, Foam and Air Bubbles for Particle-Based Fluids** (2012). [DOI](https://doi.org/10.1007/s00371-012-0697-9)，[作者公开全文](https://cg.informatik.uni-freiburg.de/publications/2012_CGI_sprayFoamBubbles.pdf)。本次核对了正文的生成势、能量加权、粒子采样、状态运动和消散方法，尤其是式 (8) 和 §3.2。当前采用的是适配高度场的二次粒子模型，不是原文完整 SPH 邻域算法和离线体积光线投射器。
2. SideFX **Whitewater Source / Whitewater Solver** 当前官方文档（页面显示 Houdini 22.0）。[生成器](https://www.sidefx.com/docs/houdini/nodes/sop/whitewatersource.html)，[求解器](https://www.sidefx.com/docs/houdini/nodes/sop/whitewatersolver.html)。核对了速度、曲率与运动驱动的生成、按深度区分状态、平流、浮力、寿命和表面附着机制。未实现 Houdini 的 PBF 密度约束、repellants 或完整三维 SDF/FLIP 耦合。
3. Matsuoka **Splash / WebGPU-Ocean**，在线核对 README。 [Splash](https://github.com/matsuoka-601/Splash)，[WebGPU-Ocean](https://github.com/matsuoka-601/WebGPU-Ocean)。这条现代浏览器路线采用 MLS-MPM 和屏幕空间流体渲染，Splash 加入 Narrow-Range Filter；其链接的技术文章发表于 2025-02-26。完整接入需要替换主体求解与渲染管线。当前没有移植 MLS-MPM、Narrow-Range Filter，也没有拷贝项目代码，不能把本次改动称作这两个算法的复现。

这次检索支持上述工程选择，但不支持“全球最好”或“最新论文已经完整复现”的结论。当前仍是实时局部白水近似，无法形成三维翻卷、破碎的大体积液片。

## 验证

使用本地 Edge 和 RTX 5070 Laptop GPU 检查。自动测试涵盖飞沫回落、泡沫随流与消散、气泡转态、陆地阻隔、粒子预算及场景重定位。GPU 场测试检查小扰动不生成泡沫、强入水只在局部留下白水、静止消散，以及三个水面分辨率的稳定性。

视觉验收需同时观察起溅、回落、残留泡沫和静止水面，单个计数或静态截图不能证明完整动态观感。
