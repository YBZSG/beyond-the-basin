# Beyond the Basin

一个还在制作中的泳池空间探索游戏，也叫 **PoolCore**。

沿着水道穿过空荡的池厅、回廊和设备间，听脚步、水声和远处的回响。你可以自由闲逛、拨动水面、搬动物品，也可以进入六章主线，逐步恢复房间里的设施。主线中的空间会随时间变暗、发生异变；想慢慢看风景，可以开启舒缓模式。

项目现在以 **Godot** 为主，`main` 是 Godot 工程。早期 Web 版保留在 [legacy/web-20261026](https://github.com/YBZSG/beyond-the-basin/tree/legacy/web-20261026) 分支。

## 下载

| 平台 | 下载 | 版本 |
| --- | --- | --- |
| Windows x64 | [下载安装包](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.13-pc-20261026/PoolCore-PC-0.6.13-Setup.exe) · [更新说明](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.13-pc-20261026) | 0.6.13 |
| Android ARM64 | [下载 APK](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.4-android/PoolCore-Mobile-8400-AvatarFix.apk) · [安装说明](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.4-android) | 0.6.4 测试版 |
| 源码 | [下载 main 分支](https://github.com/YBZSG/beyond-the-basin/archive/refs/heads/main.zip) | 开发中 |

Windows 安装包包含游戏资源和所需运行库，安装后从桌面或开始菜单打开 PoolCore。需要 Windows 10/11 x64 和支持 Vulkan 的显卡。首次启动会编译着色器、准备场景，需要等一会儿。

Android 版提供触屏控制，默认 High 画质、30 FPS 上限，可以在菜单中调整。为降低开销，手机版去掉了立体水花，保留水面涟漪、折射、焦散和倒影。我的测试手机是天玑 8400、12GB 内存的设备；PC 主要使用 RTX 5070 Laptop 测试。这些是测试设备记录，不是最低配置要求。APK 文件名里的 `8400` 是早期命名。

源码、Windows 安装包和 Android APK 并非同步更新。Android 版早于当前 PC 版；下面的操作按源码版介绍。GitHub 的 **Source code ZIP** 需要用编辑器运行，直接游玩请下载 EXE 或 APK。

## 怎么玩

菜单里的「主线 · 继续旅程」会开始或继续六章流程。自由探索可以选择原泳池、重做主池厅、扩展随机地图、曲廊池区和五境参考场景，也可以输入种子重建随机地图。

房间里的阀门、开关和部分设施可以操作；漂浮物、球池里的球和软垫可以拨动、拿起或投掷。当前地图以浅水探索为主，没有可玩的深水游泳区域。

| PC 操作 | 按键 |
| --- | --- |
| 移动 / 转动视角 | WASD / 鼠标 |
| 奔跑 / 跳跃 | Shift / Space |
| 操作设施 / 阅读主线设备铭牌 | E / Q |
| 抓取 / 蓄力投掷 / 调整距离 | 左键 / 右键 / 滚轮 |
| 手电筒 / 切换镜头滤镜 | L / F |
| 隐藏界面 / 全屏 / 菜单 | H / F11 / Esc |

在暂停菜单中选择角色、调整画质和水体。镜头可以选择青绿柔光，也可以在水体设置中调整交错水波；关闭交错水波仍会有脚步和涉水涟漪。

光追、DLSS、帧生成和神经渲染（NR）是可选的实验功能，需要对应的显卡、驱动和定制引擎支持，首次启动默认关闭光追、帧生成和 NR。水面使用光栅折射与倒影。帧生成仍可能出现拉扯、果冻感，NR 与帧生成不能同时开启。

## 运行源码

日常修改脚本、场景和材质，用安装包附带的编辑器即可。

1. 安装上面的 Windows 版，安装目录内有 **PoolCoreEditor.exe**。它是本项目使用的定制 Godot 4.8-dev 编辑器。
2. 下载源码 ZIP 并完整解压，或克隆仓库：

   ```powershell
   git clone https://github.com/YBZSG/beyond-the-basin.git PoolCoreSource
   cd PoolCoreSource
   ```

3. 双击源码根目录的 **Open-Editor.cmd**。若游戏装在自定义目录，把那里的 `PoolCoreEditor.exe` 拖到这个 CMD 上。
4. 等首次资源导入完成，按 **F5** 运行。以后也可以双击 **Run-Source.cmd**；自定义安装目录同样支持拖入编辑器。

工程入口是 [`project.godot`](project.godot)，主场景是 [`scenes/main.tscn`](scenes/main.tscn)。更新 Git 工作目录可用 `git pull --ff-only`，更新前先提交或备份自己的修改。

编辑器旁的 DLL 要一起保留。`PoolCore.exe` 会优先读取旁边的游戏 PCK，因此编辑源码请使用 `PoolCoreEditor.exe`。换电脑后让编辑器重新导入资源，不要复制旧的 `.godot` 缓存。官方 Godot 不包含这里的原生光追、DLSS 和 NR 接口；需要修改引擎或自行打包时，见 [Windows 引擎编译说明](docs/BUILDING-WINDOWS.md)。

源码包含原探索者。可选 ithappy 人物的原始模型、贴图不随公开 Git 仓库提供；缺少这些素材时仍可使用原角色。资产说明见 [人物来源记录](source_provenance/ithappy/README.md)。

## 存档与常见问题

安装版的存档和设置在安装目录的 `profile` 下，升级保留，卸载也不会主动删除。默认安装位置是 `%LOCALAPPDATA%\Programs\PoolCore`。使用上述 CMD 运行源码时，存档放在 `%LOCALAPPDATA%\PoolCore\SourceProfile`，与安装版分开。迁移旧免安装版存档时，先退出游戏并备份，再复制旧 `profile`。

- **CMD 找不到编辑器**：确认已安装 Windows 版；自定义安装目录可用上面的拖入方式指定编辑器。
- **光追或 DLSS 选项不可用**：查看画质菜单给出的原因，并检查引擎、驱动和 DLL。不是所有 NVIDIA 显卡都支持全部功能。
- **切换世界黑屏、颜色异常或闪退**：这部分仍在修复。可以先退出游戏，从对应场景启动器重新进入。反馈时附上版本、场景、显卡、画质设置和安装目录下的 `profile/PoolCore.log`。

目前仍是开发版本，尚未完成全地图通关检查和跨设备兼容测试。已知的引擎退出资源警告及具体修复记录见 `docs/`。

## 开发资料

| 目录 | 内容 |
| --- | --- |
| `scripts/`、`scenes/`、`shaders/` | 游戏逻辑、场景、材质与后处理 |
| `assets/` | 模型、贴图、音效和运行所需资源 |
| `native/source_water/` | 水体辅助库及源码 |
| `tools/blender/` | Blender 作者文件、生成和导出工具 |
| `tools/dlss/` | 定制引擎补丁、依赖记录与检查工具 |
| `docs/`、`source_provenance/` | 功能说明、开发记录和资源来源 |

`assets/cache/source_terrain/` 是随工程提供的地形加速数据，修改池底、碰撞或水深时需要更新。Blender 只在编辑模型或重新生成几何时使用。

[主线玩法](docs/campaign/README.md) · [水体移植](docs/SOURCE_LIQUID_PORT.md) · [水面闪点修复](docs/RASTER-WATER-RT-NOISE.md) · [Android 开发记录](docs/ANDROID-8400-20261023.md)

## 来源与许可

项目由早期 Web 版继续开发，Godot 工程保留了原水体算法的移植记录。素材和第三方代码各自适用原许可，见 [CREDITS.md](CREDITS.md)、[水体相关许可](docs/SOURCE_LIQUID_LICENSES.md)及资源目录内的 NOTICE。仓库可下载不代表其中所有素材都可以单独提取、再分发。
