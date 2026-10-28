# Windows 定制引擎与打包

修改游戏脚本和场景，使用安装包中的 `PoolCoreEditor.exe` 即可，步骤见[首页](../README.md#运行源码)。本文用于重新编译引擎、更新引擎补丁或制作运行包。

游戏源码和引擎是两部分：拉取最新游戏源码不会更新已安装的 EXE。修改引擎补丁后，需要重新编译引擎才能生效。

## 依赖

在工程目录之外准备引擎和 SDK。版本、官方下载地址和文件校验值集中保存在 [NR_DEPENDENCIES.json](../tools/dlss/NR_DEPENDENCIES.json)。SDK 与第三方运行库的使用、分发按各自随附许可处理。

| 依赖 | 本项目使用的版本或布局 |
| --- | --- |
| NVIDIA Godot | [提交 135dff3887a3d2ccf45cafbd9bdffa7b718e1e76](https://github.com/NVIDIA-RTX/godot/tree/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76)，Godot 4.8-dev |
| NGX 基础头文件与静态库 | [NVIDIA/DLSS 提交 9981c6350dc58c0ce21f024fd65e31e851c31689](https://github.com/NVIDIA/DLSS/tree/9981c6350dc58c0ce21f024fd65e31e851c31689)；保留 `include/`，静态库放在 `lib/nvsdk_ngx_s.lib` |
| NR SDK | `rtx-remix-ngx_sdk_dlnr@2`；保留 `include/` 全部头文件及 `lib/Windows_x86_64/rel/nvngx_dlssnr.dll` |
| Streamline | [v2.14.16](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16)，使用生产版 `bin/x64/` 运行库 |
| 编译环境 | 本机使用 Python 3.13、SCons 4.11.1、Visual Studio 2026 x64 C++ 工具（MSVC 14.5）、Windows SDK 10.0.26100.0、Git |

上表的编译工具版本是已使用的环境记录，不是逐项验证过的最低版本要求。专有 SDK 头文件、静态库和运行时 DLL 不在本源码仓库内。

## 编译

以下命令在游戏源码根目录执行，示例路径需换成自己的位置。

```powershell
git clone https://github.com/NVIDIA-RTX/godot.git D:\PoolCoreEngine
git -C D:\PoolCoreEngine checkout 135dff3887a3d2ccf45cafbd9bdffa7b718e1e76

python tools/dlss/build_nr.py `
  --engine D:\PoolCoreEngine `
  --nr-sdk D:\SDK\ngx_sdk_dlnr `
  --ngx-sdk D:\SDK\ngx-base `
  --apply
```

`--apply` 只用于第一次处理干净的固定提交。之后增量编译去掉这个参数。该脚本会检查 SDK 文件，并将位置通过进程环境变量传给 SCons。

脚本按 [`build_nr.py`](../tools/dlss/build_nr.py) 中的顺序应用补丁，这些补丁针对上表的固定引擎提交。不要重复应用 `engine-dispatch-log.patch`，相关内容已包含在 FG/RT 补丁中。

编辑器产物位于 `D:\PoolCoreEngine\bin\godot.windows.editor.x86_64.exe`，另有 console 版本。将编辑器用于源码启动器时，可在独立运行目录中命名为 `PoolCoreEditor.exe`，旁边不放同名 PCK，并配齐下节运行库。

需要发行模板时，在 **引擎目录** 编译，仍使用同一套 SDK：

```powershell
$env:POOLCORE_NR_SDK = 'D:\SDK\ngx_sdk_dlnr'
$env:POOLCORE_NGX_SDK = 'D:\SDK\ngx-base'
Set-Location D:\PoolCoreEngine
python -m SCons platform=windows target=template_release arch=x86_64 d3d12=no accesskit=no use_streamline=yes dev_build=no debug_symbols=no optimize=speed -j12
```

## 导出与运行库

先用这次编译的编辑器打开游戏工程，完成资源导入。在 Windows Desktop 导出预设中选择配套的自定义发行模板；编辑器、模板与导入缓存使用同一引擎版本。

只导出 PCK 的命令示例：

```powershell
& 'D:\PoolCoreEngine\bin\godot.windows.editor.x86_64.exe' `
  --headless --path 'D:\PoolCoreSource' `
  --export-pack 'Windows Desktop' 'D:\PoolCoreBuild\PoolCore.pck'
```

先创建输出目录。游戏 EXE 与 `PoolCore.pck` 同目录，保留原生水体辅助库、下列生产版 DLL 和各自许可证：

```text
sl.interposer.dll    sl.common.dll      sl.dlss.dll
sl.dlss_d.dll        sl.dlss_g.dll       sl.nis.dll
sl.pcl.dll           sl.reflex.dll      NvLowLatencyVk.dll
nvngx_dlss.dll       nvngx_dlssd.dll    nvngx_dlssg.dll
nvngx_dlssnr.dll
```

签名和校验值应与所选 SDK 对应。

## NR 与检查

普通源码启动器会设置 `POOLCORE_DLSS_NR=0`。要调试 NR，可以使用完整运行包中的 NR 启动器，或直接启动编辑器并设置环境变量；不要先设变量再调用会覆盖它的 `Open-Editor.cmd`。

例如，使用单独的开发 profile 运行源码：

```powershell
$env:APPDATA = Join-Path $env:LOCALAPPDATA 'PoolCore\NRDevProfile'
$env:POOLCORE_DLSS_NR = '1'
$env:DISABLE_VK_LAYER_reshade_1 = '1'
$env:VK_LOADER_LAYERS_DISABLE = 'VK_LAYER_reshade'
& 'D:\PoolCoreRuntime\PoolCoreEditor.exe' --path 'D:\PoolCoreSource' `
  --rendering-method forward_plus --rendering-driver vulkan
```

随后在画质菜单启用支持的 DLSS 模式及 NR。NR 与帧生成互斥；`POOLCORE_NR_PRESET=B` 可选择轻量网络预设，多层 NR 会增加开销。

日志中的 `PoolCore NR dispatch OK` 表示实际执行了 NR。能力查询成功或菜单勾选只表示请求成立，不能代替运行检查。

打包前检查实际启动、主要操作、场景切换以及配置保存；性能比较应使用相同场景、视角、分辨率和画质。检查工具与接口记录见 [`tools/dlss/`](../tools/dlss/) 和 [NR controls](../tests/nr_controls/README.md)。旧文档里的单次检查结果应按其日期和范围阅读，不能当作所有补丁、所有显卡都已通过。
