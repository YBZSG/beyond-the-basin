# BEYOND THE BASIN · PoolCore Native

**Godot 4.6.3 / PC Forward+ + Android Mobile / 初始原生移植版，0.5.0。**

这是根据原 PoolCore V4.1 源码移植的可玩原生项目，不是网页封装，也不是另做的一间演示房。原 Three 项目保留在另一目录，未被替换；此交付没有向 GitHub 推送。

## 快速开始

1. 使用官方 Godot **4.6.3 Standard**（不需要 .NET）：https://godotengine.org/download/archive/4.6.3-stable/
2. 解压完整项目，在 Godot 项目管理器中导入本目录的 `project.godot`。
3. 等待首次纹理/GLB 导入完成，按 **F5** 运行主场景。主场景是 `scenes/main.tscn`。
4. 保持 **Forward+**。High 已启用原生间接光、空间反射、4× MSAA 和 TAA；Ultra 使用 8× MSAA 和更高水面/光学采样。CCD/VHS 默认关闭。

项目需要支持 Godot Forward+ 的原生 PC 图形设备。若自动回退 Compatibility，游戏会保留提示，不能把回退画面视为预期画质。首次着色器编译和GI建立需要时间。

## 操作

- WASD 移动，Shift 奔跑，Space 跳跃。
- E 拿起/放下物体或攀爬附近扶梯；W/S 攀爬。
- 左键拖动物体、轻点水面；右键按住蓄力再松开投掷；滚轮调持物距离。
- R 放下物体并返回起点。Esc 暂停/菜单。
- 菜单可重建种子、选择全部 11 类房型、切换音效/底噪和画质，并调整原生水体参数。
- H 隐藏界面，G 诊断，V 间接光，C 焦散，F 循环原始/CCD/VHS/冷色镜头，F11 全屏。

## 已移植

- 原源码的种子随机序列、11类房型、九个锚定房间、柱阵WFC、探索衰变、5×5流式场景。
- 天光环庭、穹顶泳廊、更衣回廊的原始 GLB，含原建模细节、道具和原生碰撞。
- 原生第一人称、阶梯/扶梯/滑梯、漂浮鸭子/鸡蛋/球、拿取/拖动/蓄力投掷、浮力与水面联动。
- 真实2K陶瓷颜色/法线/粗糙度贴图，4米重复尺度与源码一致；原来是灰泥的拱券/顶面仍为灰泥。
- Godot原生 SDFGI、SSIL、SSAO、阴影、房间反射探针、SSR、体积雾与色调映射。
- 连通水面、高度/流速场、波纹、折射、吸收、反射、飞溅、泡沫和气泡。
- 原有17个OGG录音、空间音效、干湿脚步、混响、独立环境底噪、种子与设置保存。

## 重要区别，不作过度承诺

这是**原生移植初版，不是写实画质已经完成**。实际效果需要继续做房间美术、灯光校准与目标PC验证。

- Godot/Jolt物理替代原自定义积分器，接触与运动轨迹不是逐数值一致。
- 原 WebGL/WebGPU 的高分辨率SWE、细节流体、MPM液片、光子焦散和完整平面反射管线没有逐算法迁移。现在使用原生连通CPU水场、解析细波、屏幕深度折射/反射、房间探针与原生粒子；完整对照见 `docs/native-parity-review.md`。
- 原三维体素/GI/实验烘焙贴图没有冒充 Godot GI。旧的有瑕疵烘焙资源不参与运行。
- 目前没有浮动原点重定位；极远坐标可能有单精度物理/着色误差，不宣称无限距离精度不变。
- Android 在同一源码项目中新增独立触控和可调画质；使用 Mobile 渲染器，不能获得桌面全部 GI/后期效果。浏览器后端选择和原GPU阶段记录工具未移植。
- 云端验证使用 Linux Godot + Mesa 软件 Vulkan，**不是用户Windows显卡真机测试**。音效资源和路由已测，云端使用Dummy音频，最终听感仍需本机确认。

## Windows 导出和PCK

正式导出使用官方 4.6.3 Windows x64 release 模板，输出 `PoolCore-Native.exe` 和同名 `.pck`，两者必须在同一文件夹。

完整EXE运行时体积较大。若收到的是 `Native-Game-Pack` 包，它含同一导出的PCK及启动脚本，需要用官方Godot可执行文件启动，不包含伪造的小EXE。完整可编辑项目不依赖PCK或另一个资产包。

Windows构建未签名。若系统拦截，优先用官方Godot打开源码项目，不要为此关闭系统安全功能。此环境能成功导出Windows格式，但未实际运行WindowsEXE。

重新导出：通过 Godot “管理导出模板”安装匹配的4.6.3模板，使用本项目 Windows Desktop 预设。不要使用云端绝对路径；交付中的预设已清空定制模板路径。

## 检查与来源

- `tests/integration_native_game.gd`：实际主场景生命周期和功能集成回归。
- `tests/world_*.gd`、`tests/player_controller_test.gd`、`tests/water_contract.gd`、`tests/rendering_contract_test.gd`：源码参考、碰撞、水体及材质灯光检查。
- `docs/native-parity-review.md`：逐系统保留项、替换项、遗漏和验证边界。
- `docs/QA.md`：运行证据与导出检查。
- `assets/models/README.md`：可编辑GLB与原建模角色。
- `CREDITS.md` 和 `docs/licenses`：资产、声音和引擎授权说明。

参考源码：YBZSG/beyond-the-basin，本地V4.1快照 `5be0b54fc2af24f023c00a698ae6d8d9ceca1305`；该快照不是已发布的GitHub提交。本交付不改变原仓库授权。

## Android 附加移植

同一个完整种子世界，不是另做一间房。Android 使用横屏多点触控：左摇杆模拟移动、右侧滑动视角、拿取/放下、蓄力投掷、跳跃、扶梯、拍水、持物距离及暂停。

菜单中的“手机版画质”提供 Low / Medium / High / Ultra、50–125% 渲染比例、阴影、反射、MSAA和视角灵敏度，并独立保存。默认High，不改PC画质。Mobile不支持SDFGI、SSAO、SSIL、引擎SSR、体积雾和TAA；采用原生灯光、反射探针、普通雾，以及水材质自带的屏幕深度反射/折射。水面反射仍需手机GPU验证。

APK为ARM64 Android测试构建，尚未在真实手机安装或运行，不承诺兼容所有Android设备或具体帧率。详见 `docs/MOBILE.md`。如果收到三个APK分块压缩包，必须先按说明在PC重建并校验完整APK；单独分块不能安装。重建工具只拼接和校验文件，不执行或安装APK。
