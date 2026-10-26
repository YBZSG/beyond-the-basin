# Beyond the Basin · Godot 版本

本仓库以 **Godot 版为开发主线**，默认分支 `main` 即完整 Godot 工程，根目录的 `project.godot` 是入口。原 Web 版保留在 [`legacy/web-20261026`](https://github.com/YBZSG/beyond-the-basin/tree/legacy/web-20261026) 分支；Godot 工程无需 npm 或 Web 构建流程。

`main` 已包含六章机关、中文交互界面，以及水面光栅折射与倒影抗闪烁修复。当前安装包仍为下面的 0.6.13；体验这些后续更新请按下方步骤运行最新源码。旧 `godot/waterfeel-20261023` 分支保留，后续更新以 `main` 为准。

当前 Windows 版本为 **0.6.13（2026-10-26）**：六章探索主线、参考翼、球池与软垫互动、青绿柔光镜头、水波、手电筒和人物切换。原池保持浅水，本版没有新增深水区或游泳动作。

**[下载 Windows 安装包](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.13-pc-20261026)** · [本版说明与验证范围](docs/releases/0.6.13.md)

工程包含 **天玑 8400 / 12GB Android 适配**：移除手机版立体水花管线，保留动态水面、折射、焦散与倒影；减少常驻房间、限制高分屏像素预算，默认 High / 30 FPS 上限。已用 Godot 4.7 实际导出并校验 ARM64 APK，说明与验证边界见 [Android 8400 移植](docs/ANDROID-8400-20261023.md)。APK 与图形日志位于 `output/`；此目录不提交 Git。

最新 `0.6.4-mobile-8400-avatar` 已修复手机版人物被桌面条件挡住的问题，恢复人物、服装和动画；请安装 `PoolCore-Mobile-8400-AvatarFix.apk`。详见 [人物恢复更新](docs/ANDROID-AVATAR-FIX-20261023.md)。

**[下载安卓 APK（0.6.4，人物恢复版）](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.4-android/PoolCore-Mobile-8400-AvatarFix.apk)** · [GitHub 发布页与安装说明](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.4-android)

## 安装并玩游戏

下载发布页中的 **PoolCore-PC-0.6.13-Setup.exe**，运行安装后从桌面或开始菜单打开 **PoolCore**。GitHub 自动生成的 Source code ZIP 只有源码，不是游戏安装包。安装包含游戏、资源、定制引擎与 DLL，无需另装 Godot、Blender、Python 或 Node.js。

要求 Windows 10/11 x64 和支持 Vulkan 的显卡。实际图形检查使用 RTX 5070 Laptop，其他硬件未逐一验证。首次使用 High 画质，实验光追、NR 和帧生成默认关闭，支持的 NVIDIA GPU 可在画质菜单启用。帧生成仍可能有果冻感；NR 与帧生成互斥。首次启动请等待着色器编译和场景准备。

默认安装到 `%LOCALAPPDATA%\Programs\PoolCore`，无需管理员权限。存档在安装目录的 `profile\Godot\app_userdata\BEYOND THE BASIN - PoolCore Native`；升级不覆盖、卸载不主动删除这个目录。旧免安装版用户可在退出两边游戏后复制旧包的 `profile` 到新目录，覆盖前先备份。安装包不包含开发者存档。

## 另一台电脑下载源码后怎么运行

1. 安装同一发布页的 **PoolCore-PC-0.6.13-Setup.exe**。安装目录中提供 **PoolCoreEditor.exe**，它是本工程使用的定制 Godot 4.8-dev 编辑器，所需 DLL 已随包提供。
2. 下载默认 **main** 分支的 [源码 ZIP](https://github.com/YBZSG/beyond-the-basin/archive/refs/heads/main.zip)，完整解压到可写目录，例如 `D:\PoolCoreSource`。也可执行：

   ```powershell
   git clone https://github.com/YBZSG/beyond-the-basin.git PoolCoreSource
   cd PoolCoreSource
   ```

   默认进入 `main`，后续可用 `git pull --ff-only` 更新。只有需要复现 0.6.13 安装包对应源码时，才执行 `git checkout v0.6.13-pc-20261026`；这会切回该旧版本。
3. 双击源码根目录 **Open-Editor.cmd**。如果游戏装在自定义目录，将该目录的 **PoolCoreEditor.exe** 拖到 CMD 上；保留编辑器旁的 DLL，不要只复制 EXE。
4. 等待首次资源导入结束，然后按 **F5** 运行工程，主场景是 `scenes/main.tscn`。完成首次导入后，也可以双击 **Run-Source.cmd** 运行源码。

PowerShell 手动打开示例：

```powershell
& "$env:LOCALAPPDATA\Programs\PoolCore\PoolCoreEditor.exe" --editor --path "D:\PoolCoreSource"
```

辅助 CMD 将源码存档放到 `%LOCALAPPDATA%\PoolCore\SourceProfile`，与安装版分开。不要用 `PoolCore.exe` 打开源码：旁边的 `PoolCore.pck` 会接管资源，使源码修改不生效。不要复制别的电脑的 `.godot` 缓存，使用本版编辑器重新导入。

旧文档中官方 Godot 4.6/4.7 的说明不再是本版推荐基线；官方版没有本项目的原生光追、DLSS/NR 接口。运行不需要 Blender，编辑 `.blend` 或重建几何才需要。保留 `native/source_water/bin` 下的平台辅助库。

### 可选人物与排错

- Git 包含完整原探索者与场景。ithappy 第三方原模型、贴图不作为独立素材公开到 Git；源码默认使用原探索者。有权使用素材的协作者可把已有 `ithappy_explorer.glb` 与相邻贴图放入 `assets/models/avatar/`，重新导入后切换。缺少可选模型会保留原人物，仍可玩。见 [来源记录](source_provenance/ithappy/README.md)。
- 安装版人物切换：**Esc → 右侧「探索设置」顶部「角色选择」**。F 切换镜头滤镜，不是第三人称。
- 找不到引擎：先安装本版，再双击 CMD；自定义安装路径使用拖入编辑器 EXE 的方式指定。
- 首次载入慢：等待导入、着色器编译和场景准备，不在同一工程同时运行两个编辑器。
- 光追或 DLSS 不可选：检查 NVIDIA 显卡、驱动、定制引擎和 DLL；可先用普通画质。日志在安装目录 `profile/PoolCore.log`。

## 自行编译带 NR 的引擎

NR 需要打补丁的 NVIDIA 引擎分支。Windows 安装包已提供预编译编辑器和运行库；只有修改引擎本身才需要下面的编译流程。SDK 头文件、静态库、DLL 和 EXE/PCK 不提交 Git。NVIDIA RTX SDKs 许可允许集成应用，商业发布前需要通知 NVIDIA，完整条款见随包许可。

### 需要自己准备的外部文件

| 用途 | 来源 | 必需内容 |
| --- | --- | --- |
| 引擎源码 | [NVIDIA-RTX/godot](https://github.com/NVIDIA-RTX/godot/tree/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76)，提交 `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`（`nvidia-pt-dlss`，Godot 4.8-dev） | 完整源码树（含 `SConstruct`）。源码归档 SHA-256：`8f9d9604270ccca92d14cc57afca142079476cbe050e0486a90b84da17ce907a` |
| NGX 基础头文件与静态库 | NVIDIA/DLSS 提交 `9981c6350dc58c0ce21f024fd65e31e851c31689` | `<ngx-base>/include/`：`nvsdk_ngx.h`、`nvsdk_ngx_defs.h`、`nvsdk_ngx_defs_vk.h`、`nvsdk_ngx_helpers_vk.h`、`nvsdk_ngx_params.h`、`nvsdk_ngx_vk.h`；`<ngx-base>/lib/nvsdk_ngx_s.lib`（3,782,490 字节，SHA-256 `7b9a5239c1145af5f645ab472aa066f9ea79db36ac819562312aae69d65f3765`） |
| NR SDK `rtx-remix-ngx_sdk_dlnr@2` | 官方 Remix Packman 地址（记录在 [`tools/dlss/NR_DEPENDENCIES.json`](tools/dlss/NR_DEPENDENCIES.json)） | `<nr-sdk>/include/` 必须含 `nvsdk_ngx_helpers_dlssnr_vk.h`（同包的 `nvsdk_ngx_defs_dlssnr.h`、`nvsdk_ngx_helpers_dlssnr.h` 等一并保留）；运行时在 `<nr-sdk>/lib/Windows_x86_64/rel/nvngx_dlssnr.dll`（266,424,944 字节，SHA-256 `2bc19bc09a7b89dd44f73e2ac0108fcc586e2154bdd0830f242f4f040e28789f`） |
| Streamline 运行时 v2.14.16 | [NVIDIA-RTX/Streamline v2.14.16](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16) | `sl.interposer.dll`、`sl.common.dll`、`sl.dlss.dll`、`sl.dlss_d.dll`、`sl.dlss_g.dll`、`sl.nis.dll`、`sl.pcl.dll`、`sl.reflex.dll`、`NvLowLatencyVk.dll`，以及 `nvngx_dlss.dll`、`nvngx_dlssd.dll`、`nvngx_dlssg.dll` |
| 编译工具链 | 本机安装 | Python 3.13、SCons 4.11.1、Visual Studio 2026 x64 C++ 工具（MSVC 14.5）、Windows SDK 10.0.26100.0、Git。NR SDK 可参考 `NR_DEPENDENCIES.json` 中的地址和校验值自行下载，并放在本工程目录之外 |

### 编译引擎

```powershell
# 1. 取固定提交的引擎源码（也可用同提交的源码归档）
git clone https://github.com/NVIDIA-RTX/godot.git engine
git -C engine checkout 135dff3887a3d2ccf45cafbd9bdffa7b718e1e76

# 2. 第一次：打补丁并编译编辑器
python tools/dlss/build_nr.py `
  --engine <引擎目录> `
  --nr-sdk <nr-sdk 目录> `
  --ngx-sdk <ngx-base 目录> `
  --apply

# 之后增量重编：去掉 --apply
python tools/dlss/build_nr.py --engine <引擎目录> --nr-sdk <nr-sdk> --ngx-sdk <ngx-base>
```

脚本会按顺序应用 `engine-taa-rg16f.patch`、`engine-fg-rt.patch`、`engine-camera-visibility.patch`、`engine-scene-retirement.patch`、`engine-dlss-nr.patch`、`engine-dlss-nr-controls.patch`，再通过进程内的 `POOLCORE_NR_SDK` / `POOLCORE_NGX_SDK` 把两个 SDK 传给 SCons。补丁只对上面这个固定提交有效，不要套到其他 Godot 版本。没有 NR SDK 时仍能编译，但那只是空实现 stub，菜单里不会出现可用的 NR。

产物在 `<引擎目录>/bin/`：

- `godot.windows.editor.x86_64.exe` —— 本工程的本地实验运行程序就是它（可改名 `PoolCore.exe`）
- `godot.windows.editor.x86_64.console.exe`

要发布正式包时，还需要在同样的环境变量下再编发行模板：

```powershell
$env:POOLCORE_NR_SDK = "<nr-sdk>"
$env:POOLCORE_NGX_SDK = "<ngx-base>"
python -m SCons platform=windows target=template_release arch=x86_64 d3d12=no accesskit=no use_streamline=yes dev_build=no debug_symbols=no optimize=speed -j12
```

### 导出 PCK 并放置 DLL

```powershell
<引擎目录>\bin\godot.windows.editor.x86_64.exe --path <本工程> --export-pack "Windows Desktop" PoolCore.pck
```

用这个编辑器首次打开工程完成导入，再导出，别用官方 4.6/4.7 编辑器的导入缓存混编。把 `PoolCore.pck`、`nvngx_dlssnr.dll`、上表列出的全部 Streamline/DLSS DLL 和对应许可文件放到 EXE 同目录。缺少 `nvngx_dlssnr.dll` 时画质菜单的 NR 项会被禁用，不会假装支持。

### 运行与自检

- NR 用环境变量 `POOLCORE_DLSS_NR=1` 打开（[`tools/dlss/Launch-PoolCore-NR.cmd`](tools/dlss/Launch-PoolCore-NR.cmd) 和 `Start-PoolCore-Scene.ps1` 已设置），NR 与帧生成互斥，开启 NR 会强制关闭 FG。
- 只有日志出现 `PoolCore NR dispatch OK` 才代表 NR 真正执行；菜单勾选、能力查询成功、驱动加载成功都不算。
- `POOLCORE_NR_PRESET=B` 可选轻量档；默认单层，1–4 层属于实验项。
- SDK 版本、许可和验证命令（`run_qa.py` 的 timing/controls/对照基线）见 [`tools/dlss/NR_README.md`](tools/dlss/NR_README.md)。

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

原探索者是项目自制的程序化模型，新人物为用户提供的 ithappy 素材；两者都不是扫描人物。布料 GLB 的最终材质由 Godot 脚本/shader 绑定，独立模型查看器不会自动复现全部效果。修改池底、碰撞或水深后，需要重新生成匹配地形缓存并检查实际行走。

## 当前已知问题

- 从主页实时切换世界时出现黑色/荧光绿画面的根因尚未确认，不能称为已修复。分阶段退场与保护已集成，但不等于目标设备问题已通过。
- “重启到所选世界”是可选的完整退出/重开方式，只在有完整启动参数契约的交付启动器下支持。直接从编辑器运行时会拒绝并提示，不会猜测启动参数或自动重启。
- 本版已在 Windows / RTX 5070 Laptop 进行对应修改的定向运行与显示检查；未做全地图、全部显卡或完整主线通关验收。
- 仍有既存 OpTypeForwardPointer 和退出 Texture RID 清理诊断；帧生成果冻感未宣称解决。NR 是实验功能，不保证所有场景及硬件兼容。
- Android 本地适配已恢复并构建新 APK，Mobile 渲染路径和程序驱动的交互检查通过；当前未连接 Android 真机，不能据此保证手机帧率或驱动兼容性。

## 来源与许可

源项目基线：[66a4543602d9e774db07c2da12ce1d40d522532c](https://github.com/YBZSG/beyond-the-basin/tree/66a4543602d9e774db07c2da12ce1d40d522532c)。水体移植保留原 SWE、细波、APIC-MPM 和光子焦散算法的来源及说明，不把简化滚动贴图当成原算法。

资产与第三方代码许可见 `CREDITS.md`、`docs/licenses/`、`docs/SOURCE_LIQUID_LICENSES.md` 及各资源 NOTICE。没有复制 POOLS 游戏资产，也不为原项目或用户提供的音效擅自添加新的整体开源许可证。

## PC visual and wind refinements (2026-10-23)

The delivered PC shadow/avatar refinements, clearer basin grout, and adjustable optical wind ripples are integrated on top of the existing Android work. See [PC feature guide and verification scope](docs/PC-VISUAL-WIND-20261023.md) and [wind optical model](docs/wind_water_optics.md). This source integration does not replace or rebuild the published Android APKs.

