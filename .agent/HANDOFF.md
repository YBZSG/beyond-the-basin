# 下次继续

2026-10-04：用户叫停当前代理继续实现，要求推 GitHub 并交待修报告给朋友。先读 `docs/webgpu-handoff-2026-10-04.md`，不要把静态检查通过当作水体/GPU 验收完成。

正确仓库 `G:\beyond-the-basin`；分支 `cde/aged-pool-arcade`；远程 `YBZSG/beyond-the-basin`。`G:\MCC` 只保留 Godot。先看 AGENTS.md、Git 状态和真实源码。

启动 `npm run dev -- --port 3000`，Edge 打开 `http://localhost:3000/pool-vct?qa=1`。前任测试窗口和开发服务可能仍运行，先查状态，避免重复启动或打断用户游戏。

优先核验最后的 `webgpu/materials.ts` RT 修正和 `rt.ts` 整代发布，再恢复参考图的连贯水片、诊断首次冲击和跨房间卡顿。随后做实际鼠标/WASD、道具、水波、湿墙 SSR、焦散/GI、质量/镜头/窗口及快速重建回归。

最终静态检查全部通过（116 项测试、类型、lint、build）。历史五项 GPU 检查通过于最后 RT/预热/BVH 改动之前；最后代码缺完整 GPU 回归。旧 WebGL 验收文件不能证明本次完成。

本机临时证据在 `output/webgpu-repair/`、`output/playwright/`，Git 忽略；可移植结果和用户截图在报告目录。`engine.ts` 开发 QA 的 `renderResources()` 待整理，桥接依赖当前 Three 版本。以源码、测试、真实 GPU 结果为准。
