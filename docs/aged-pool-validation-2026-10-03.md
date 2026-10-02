# 旧白瓷泳池本地验收

本轮工作从 `YBZSG/beyond-the-basin` 的 main `66a4543602d9e774db07c2da12ce1d40d522532c` 开始，分支为 `cde/aged-pool-arcade`。按用户参考图和后续修正，实现旧白瓷、湿釉反光、重复低拱廊、冷白壁灯、淹水台阶及更自然的水面扰动。未推送、未部署。

## 实际核验

- `npm run typecheck`、`npm run lint`、`npm test`（115 项）及 `git diff --check` 通过。
- `npm run build` 成功，生产 `/pool-vct` 页面实际运行；`window.__poolQA` 在生产页面为 `undefined`。
- `npm run benchmark:build` 成功，用同一实现的本地 QA 构建检查几何、反射和涉水交互。
- Microsoft Edge 154，1672×941，NVIDIA RTX 5070 Laptop GPU / ANGLE D3D11，High 水体质量。实际画面可进入，鼠标锁定、W 移动及 Esc 返回暂停菜单通过。
- 沿中间拱廊实际从 `[0,1.65,8]` 走到 `[0,1.321,-10.2]`，越过两面拱墙，水面交互增加到 12；BVH worker 错误为空，`gl.getError()` 为 0。
- 砖面实时反射开/关对比确认：台阶上的小黄鸭只有开启该反射时出现对应的倒影。将道具从 x=12.3 移到 x=13.1 后，倒影同步向右移动；移动相机后的倒影透视随之改变。源图来自当前帧场景颜色和深度，不是预绘制的反光贴图。
- 最终生产页面的短时走动中 HUD 从 75 FPS 升至 129 FPS。这是特定设备和视角下的短样本，不能作为所有场景或设备的性能保证。
- 生产控制台仅见 favicon 404 和 Windows 忽略 WebGPU powerPreference 的提示，未见场景 shader、WebGL 或初始化错误。

## 本地截图

截图保存在 `output/playwright/`（本地验收文件，不纳入 Git）：

- `pool-vct-production-final.png`：最终生产页面。
- `wet-ssr-v5-on.png` / `wet-ssr-v5-off.png`：相同视角的反射开关对比。
- `wet-reflection-prop-moved.png`：道具和倒影同步移动。
- `wet-reflection-camera-moved.png`：移动视角后的倒影透视。

## 边界

屏幕空间反射只能命中当前画面可见的表面。屏幕外、遮挡后的内容以及未命中的射线仍由房间环境探针补光；这不是完整场景路径追踪，边缘和薄小物体可能发生反射缺失。画面按参考图尽量接近，同时遵循后续指定的旧白瓷要求，没有声称逐像素复刻。

Godot 保留在原目录：对清理前记录的 213 个文件再次计算 SHA256，全部相同。旧 Web 已移出原目录并备份；永久删除曾被自动审核拒绝，不能视为永久删除成功。
