# Beyond the Basin · Godot 版本

这是独立的 Godot 工程分支。仓库根目录的 `project.godot` 是入口；原 Web 游戏保留在 `main` 分支，不需要 npm、浏览器壳或 Web 构建流程。

当前代码对应 **WaterFeel 0.6.2（2026-10-23）+ SeedGuard1**。这是开发候选版本，不是已通过目标 Windows 显卡验收的稳定版，也没有达到照片级写实目标。

当前本地分支新增 **天玑 8400 / 12GB Android 适配**：移除手机版立体水花管线，保留动态水面、折射、焦散与倒影；减少常驻房间、限制高分屏像素预算，默认 High / 30 FPS 上限。已用 Godot 4.7 实际导出并校验 ARM64 APK，说明与验证边界见 [Android 8400 移植](docs/ANDROID-8400-20261023.md)。APK 与图形日志位于 `output/`；此目录不提交 Git。

最新 `0.6.4-mobile-8400-avatar` 已修复手机版人物被桌面条件挡住的问题，恢复人物、服装和动画；请安装 `PoolCore-Mobile-8400-AvatarFix.apk`。详见 [人物恢复更新](docs/ANDROID-AVATAR-FIX-20261023.md)。

**[下载安卓 APK（0.6.4，人物恢复版）](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.4-android/PoolCore-Mobile-8400-AvatarFix.apk)** · [GitHub 发布页与安装说明](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.4-android)

## 打开和运行

1. 下载或克隆本分支，使用 Godot **4.6 Standard** 打开根目录 `project.godot`。实际验证基准为 **4.6.3**，不要把允许尝试其他版本理解成已验证兼容。
2. 等待首次资源导入，再运行主场景。PC 使用 Forward+，需要支持对应图形后端的设备。
3. 保留 `native/source_water/` 下的描述文件与平台辅助库。它们加速原有 CPU 工作，不替换水体方程。缺失或不支持时有 GDScript 回退，但编辑器可能报告扩展载入错误。

本源码不附带 Godot 编辑器、Windows 游戏 EXE/PCK 或 APK。Windows 导出配置已保留；需安装匹配的官方导出模板。运行游戏读取 GLB，不要求安装 Blender；编辑模型与重建几何的基准为 Blender 4.3.2。

## 世界与交互

- 首次默认原仓库的种子随机场景。主页可选择 Original、Expanded 或 Formal，并保存出生地。
- Expanded 保留新增设施房间；Formal 保留连接的主池厅、回廊、侧池、露台和圆浴池。
- WASD 移动，鼠标视角，Shift 快走/跑，Space 跳，E 交互，左键拖动物品，右键投掷，滚轮上推远、下拉近，Esc 菜单，H 隐藏界面。
- 主菜单包含画质和水体设置。侧池/圆浴池有可操作的回水阀；它们是可选探索内容，不要求开启才能通行。
- SeedGuard1 对三个主页种子入口统一检查有符号 64 位整数，错误输入会提示而不是改变当前世界。

## 编辑入口

- `scripts/`、`shaders/`、`scenes/`：Godot 逻辑、原水体算法的引擎适配、角色、UI。
- `assets/`：正式 GLB、贴图、音效与必要资源。`assets/cache/source_terrain/` 是匹配几何的运行加速数据，不是 `.godot` 临时缓存。
- `tools/blender/`：可编辑 Blend、生成器、参考图和导出工具。各 `.gdignore` 是有意隔离作者文件。
- `native/source_water/`：CPU 辅助库、C 源码、构建方法与许可。
- `docs/`：功能、资产和验证边界。历史候选报告不代表本次整套游戏验收。

人物仍是项目自制的程序化模型，带骨架、蒙皮与动画，不是扫描人物。布料 GLB 的最终材质由 Godot 脚本/shader 绑定，独立模型查看器不会自动复现全部效果。修改池底、碰撞或水深后，需要重新生成匹配地形缓存并检查实际行走。

## 当前已知问题

- 从主页实时切换世界时出现黑色/荧光绿画面的根因尚未确认，不能称为已修复。分阶段退场与保护已集成，但不等于目标设备问题已通过。
- “重启到所选世界”是可选的完整退出/重开方式，只在有完整启动参数契约的交付启动器下支持。直接从编辑器运行时会拒绝并提示，不会猜测启动参数或自动重启。
- 最终完整封包的两次云端图形启动在就绪前被外部终止。精确封包 CPU、受控人物和局部源工程水体检查通过，不能代替完整 Windows 图形验证。
- 云端 llvmpipe 的耗时不是 Windows 显卡或手机帧率。浅水边缘、动作、光照和材质仍有继续改进空间。
- Android 本地适配已恢复并构建新 APK，Mobile 渲染路径和程序驱动的交互检查通过；当前未连接 Android 真机，不能据此保证手机帧率或驱动兼容性。

## 来源与许可

源项目基线：[66a4543602d9e774db07c2da12ce1d40d522532c](https://github.com/YBZSG/beyond-the-basin/tree/66a4543602d9e774db07c2da12ce1d40d522532c)。水体移植保留原 SWE、细波、APIC-MPM 和光子焦散算法的来源及说明，不把简化滚动贴图当成原算法。

资产与第三方代码许可见 `CREDITS.md`、`docs/licenses/`、`docs/SOURCE_LIQUID_LICENSES.md` 及各资源 NOTICE。没有复制 POOLS 游戏资产，也不为原项目或用户提供的音效擅自添加新的整体开源许可证。

## PC visual and wind refinements (2026-10-23)

The delivered PC shadow/avatar refinements, clearer basin grout, and adjustable optical wind ripples are integrated on top of the existing Android work. See [PC feature guide and verification scope](docs/PC-VISUAL-WIND-20261023.md) and [wind optical model](docs/wind_water_optics.md). This source integration does not replace or rebuild the published Android APKs.

