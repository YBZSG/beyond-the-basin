# Beyond the Basin (PoolCore)

**语言 / Language**：[简体中文](README.md) · [English](README.en.md)

> 一个开发中的泳池空间探索游戏，也叫 **PoolCore**。  
> *A pool-space exploration game in development, also known as **PoolCore**.*

沿着水道穿过空荡的池厅、回廊与设备间，聆听脚步、水声与远处的回响。你可以在这里自由漫游、拨动水面、搬运物品，也可以进入六章主线流程，逐步恢复各个房间的设施。主线中的空间会随时间逐渐变暗并发生异变；如果只想静静游览风景，随时可以开启**舒缓模式**。

本项目目前以 **Godot** 引擎开发为主，`main` 分支为 Godot 工程；早期 Web 版本保留在 [legacy/web-20261026](https://github.com/YBZSG/beyond-the-basin/tree/legacy/web-20261026) 分支。

---

## 下载与游玩

| 平台 | 获取方式 | 当前版本 |
| --- | --- | --- |
| **Windows x64** | [下载免安装版 (ZIP)](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.14-pc-20261116/PoolCore-Windows-0.6.14.zip) · [更新说明](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.14-pc-20261116) · [itch.io 页面](https://ybzsg.itch.io/beyond-the-basin) | `0.6.14` |
| **Android ARM64** | [下载 APK](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.4-android/PoolCore-Mobile-8400-AvatarFix.apk) · [安装说明](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.4-android) | `0.6.4` 测试版 |
| **工程源码** | [下载 main 分支 ZIP](https://github.com/YBZSG/beyond-the-basin/archive/refs/heads/main.zip) | 开发中 |

> **提示**：GitHub 提供的 **Source code ZIP** 仅包含源码，需要通过编辑器运行；直接游玩请下载上方的 **Windows 免安装版** 或 **Android APK**。

### Windows 版说明

- **启动方式**：压缩包已包含游戏资源与所需运行库，请**完整解压**后运行 `Launch-PoolCore.cmd`；如需体验连续双厅预览（连接悬手浅池、检修连廊与水族中庭），请运行 `Launch-Connected-Halls.cmd`。
- **语言切换**：在主页右上角点击「语言 / Language」即可切换简体中文与 English，设置会自动保存。
- **运行环境**：需要 **Windows 10/11 x64** 及支持 **Vulkan** 的显卡。首次启动会编译着色器并准备场景，等待片刻即可。
- **当前版本内容（0.6.14）**：包含当前主页、15 张独立地图、中英双语界面，以及 10 月 31 日修复汇总中的 20 项更新。

### Android 版说明

- **操控与画质**：提供触屏控制，默认 **High** 画质、**30 FPS** 上限，可在菜单中自由调整。
- **移动端优化**：为降低性能开销，手机版移除了立体水花，保留水面涟漪、折射、焦散与倒影效果。当前保持原有发布版本。
- **测试设备参考**：个人测试设备为天玑 8400（12GB 内存）手机与 RTX 5070 Laptop（PC），以上仅为测试记录，**并非最低配置要求**。APK 文件名中的 `8400` 属于早期命名沿用。

---

## 玩法与操作

### 探索与交互

- **自由探索与主线模式**：从主页可直接进入 **15 个独立池区世界**与**连续双厅**，也可点击「开始游戏 / 主线」体验六章流程，按目标推进并逐步恢复房间设施。
- **环境互动**：房间内的阀门、开关及部分设施均可操作；漂浮物、球池球与软垫支持拨动、抓取或蓄力投掷。
- **水域范围**：当前地图以浅水涉水探索为主，暂不含可游玩的深水游泳区域。

### PC 键鼠操作

| 操作功能 | 按键 |
| --- | --- |
| 移动 / 转动视角 | `WASD` / 鼠标 |
| 奔跑 / 跳跃 | `Shift` / `Space` |
| 操作设施 / 阅读主线设备铭牌 | `E` / `Q` |
| 抓取 / 蓄力投掷 / 调整抓取距离 | 鼠标左键 / 鼠标右键 / 滚轮 |
| 手电筒 / 切换镜头滤镜 | `L` / `F` |
| 查看文字提示 | 按住 `Tab`（松开隐藏） |
| 隐藏界面 / 全屏切换 / 菜单 | `H` / `F11` / `Esc` |

### 画面、镜头与实验特性

- **个性化设置**：可在主页「设置」中选择角色，并调整画质与水体参数。
- **镜头与环境细节**：模拟摄像机滤镜带有光晕、色散与日期时间戳（画面中的 `REC` 仅为取景装饰，不会实际录屏）；大波纹支持单独开关，关闭后仍保留脚步与涉水涟漪；室外草地被踩踏后会随时间逐渐恢复。
- **实验渲染功能**：光追、DLSS、帧生成与神经渲染（NR）均为可选实验特性，依赖对应显卡、驱动及定制引擎支持。首次启动默认关闭光追、帧生成与 NR；水面采用光栅折射与倒影实现。
  - 已知限制：开启帧生成时可能出现画面拉扯或果冻感；**NR 与帧生成不可同时开启**。

---

## 运行源码

日常修改脚本、场景与材质，请继续使用定制版 Godot 编辑器（基于定制 Godot 4.8-dev 引擎）：

1. **获取编辑器**：使用已有的 `PoolCoreEditor.exe`，或从 [0.6.13 安装包](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.13-pc-20261026/PoolCore-PC-0.6.13-Setup.exe) 获取。
2. **获取源码**：下载源码 ZIP 并完整解压，或通过 Git 克隆仓库：

```powershell
git clone https://github.com/YBZSG/beyond-the-basin.git PoolCoreSource
cd PoolCoreSource
```

3. **打开工程**：双击源码根目录下的 `Open-Editor.cmd`。如果游戏安装在自定义目录，直接将对应目录中的 `PoolCoreEditor.exe` 拖到该 CMD 文件上即可启动。
4. **运行调试**：等待首次资源导入完成后，按 `F5` 运行。后续也可直接双击 `Run-Source.cmd` 快速启动（同样支持拖入自定义路径的编辑器）。

### 开发注意事项

- **工程入口**：配置文件为 [project.godot](https://www.google.com/search?q=project.godot)，主场景为 [scenes/main.tscn](https://www.google.com/search?q=scenes/main.tscn)。
- **编辑器与依赖**：请完整保留编辑器同目录下的 DLL 文件。由于 `PoolCore.exe` 会优先加载旁边的游戏 PCK，调试源码请务必使用 `PoolCoreEditor.exe`。
- **更新与迁移**：拉取最新代码前请先提交或备份本地修改，推荐使用 `git pull --ff-only`。更换设备后请让编辑器重新导入资源，**不要直接复制旧的 `.godot` 缓存目录**。
- **定制引擎编译**：官方版 Godot 不包含本项目的原生光追、DLSS 与 NR 接口；如需修改引擎源码或自行打包，请参阅 [Windows 引擎编译说明](https://www.google.com/search?q=docs/BUILDING-WINDOWS.md)。
- **角色素材说明**：公开源码包含原探索者角色；可选 ithappy 人物的原始模型与贴图不随公开 Git 仓库分发（缺少这些素材时仍可正常使用原角色），详情见 [人物来源记录](https://www.google.com/search?q=source_provenance/ithappy/README.md)。

---

## 存档与常见问题

### 存档与配置路径

| 运行方式 | 存档与设置路径 | 备注 |
| --- | --- | --- |
| **Windows 免安装版** | 游戏目录下的 `profile` | 迁移旧免安装版存档时，请先退出游戏并备份，再复制旧 `profile` |
| **旧安装版** | 安装目录下的 `profile`（默认 `%LOCALAPPDATA%\Programs\PoolCore`） | 升级时保留，卸载不会主动删除 |
| **源码 CMD 启动** | `%LOCALAPPDATA%\PoolCore\SourceProfile` | 与安装版存档相互独立 |

### 常见问题

- **运行 CMD 提示找不到编辑器**：请确认已安装 Windows 版；若安装在自定义路径，可将 `PoolCoreEditor.exe` 直接拖到 `Open-Editor.cmd` 或 `Run-Source.cmd` 上启动。
- **光追或 DLSS 选项不可用**：请查看画质菜单内显示的具体原因，并检查定制引擎、显卡驱动与同目录 DLL 是否完整。并非所有 NVIDIA 显卡都支持全部特性。
- **切换世界时黑屏、色彩异常或闪退**：该问题仍在持续排查修复中。遇到时可先退出游戏，再通过对应场景启动器重新进入。反馈问题请附上**版本号、所在场景、显卡型号、画质设置**以及 `profile/PoolCore.log`。

> 本项目目前仍处于开发阶段，尚未完成全地图通关检查与跨设备兼容测试。已知的引擎退出资源警告及详细修复记录请查阅 `docs/` 目录。

---

## 项目结构与开发资料

| 目录 | 说明 |
| --- | --- |
| `scripts/`、`scenes/`、`shaders/` | 游戏逻辑、场景、材质与后处理着色器 |
| `assets/` | 模型、贴图、音效与运行所需资源 |
| `native/source_water/` | 水体辅助库及原生源码 |
| `tools/blender/` | Blender 工程文件、场景生成与导出工具 |
| `tools/dlss/` | 定制引擎补丁、依赖记录与检查工具 |
| `docs/`、`source_provenance/` | 功能说明、开发记录与素材来源 |

- `assets/cache/source_terrain/` 为随工程提供的地形加速数据，修改池底、碰撞或水深后需同步更新。
- 仅在编辑模型或重新生成几何体时需要使用 Blender。

**延伸文档**：[主线玩法](https://www.google.com/search?q=docs/campaign/README.md) · [水体移植](https://www.google.com/search?q=docs/SOURCE_LIQUID_PORT.md) · [水面闪点修复](https://www.google.com/search?q=docs/RASTER-WATER-RT-NOISE.md) · [Android 开发记录](https://www.google.com/search?q=docs/ANDROID-8400-20261023.md)

---

## 来源与许可

本项目由早期 Web 版本演进而来，Godot 工程中保留了原水体算法的移植记录。项目内使用的各类素材与第三方代码分别适用其原始许可协议，详情请查阅：

- [CREDITS.md](CREDITS.md)
- [水体相关许可](https://www.google.com/search?q=docs/SOURCE_LIQUID_LICENSES.md)
- 各资源目录下的 `NOTICE` 文件

> 仓库公开可供下载，并不代表其中所有素材均可单独提取或再分发。
