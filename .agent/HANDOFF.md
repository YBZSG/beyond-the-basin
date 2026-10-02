# 下次继续

先核对本仓库 Git 状态和 AGENTS.md。Web 工作从 `G:\beyond-the-basin` 继续，不能回到旧 `G:\MCC` Web。

执行 `npm run dev -- --port 3001`，打开 `http://localhost:3001/pool-vct`。生产版本可用 `npm run build` 和 `npm start -- --port 3003`。本轮服务会随用户要求的关机而停止。

参考效果为旧白瓷、湿润反光、重复低拱廊及浅青水面，明亮而压迫。当前帧屏幕空间反射在 `app/pool-vct/wet-reflections.ts`，离屏部分仍使用环境探针。素材来源和处理见 `public/assets/textures/aged-tiles/README.md`。

最终验收和已知限制见 `docs/aged-pool-validation-2026-10-03.md`；截图在 `output/playwright/`。没有待解决的构建或已核验交互失败。若继续提升视觉，先在实际 Edge 画面核验，避免以材质参数或构建结果替代视觉证据。
