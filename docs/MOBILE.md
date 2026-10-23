# Android：原仓库水体测试版（当前源码）

> **2026-10-23 当前更新**：本地天玑 8400 / 12GB 适配已按用户要求移除手机版立体水花及专用环境立方体，降低水体、倒影、常驻范围和高分屏预算，并用 Godot 4.7 导出新 APK。以 [本轮说明](ANDROID-8400-20261023.md) 为准。下文为此前保留完整 MPM 水花的历史设计和旧 APK 记录，其中天玑 9400、4.6.3 和冻结包信息不代表本轮结果。

本目录针对 CURRENT `source_water_runtime.gd`，不是之前近似水体的 APK。Android 仍使用同一套原仓库浅水求解（SWE）、APIC-MPM 水花、光子焦散、白水与平面反射。原仓库场景默认，菜单也能选择重做主池厅。PC 默认 Forward+ 和 High 保持不变。

## 操作

- 横屏。左侧浮动摇杆移动，轻推慢走，推满奔跑。右侧空白区域滑动视角。
- 「拿起 / 放下」点按保持持物，右拇指可离开按钮瞄准。
- 「投掷」按住蓄力，松手投出，使用 PC 原控制器的 1.1 秒蓄力。
- 「拉近 / 推远」调用实际 PC 滚轮事件路径，每次 0.2 m，范围 0.75–3 m，不再使用旧版循环距离。
- 「跳跃 / 扶梯 / 拍水」独立按钮。MENU 或 Android 返回键暂停。
- 切后台、取消触摸或退出会释放所有输入，取消蓄力并放下物体，不会误投。一个按钮只接受一个手指，避免第二根手指触发提前投掷。
- 游戏时禁用触摸鼠标模拟，菜单时启用，避免双重抓取。

## 可调画质

独立保存于应用的 `mobile_settings.cfg`，不会覆盖 PC 的画质文件。

| 预设 | 3D 比例 | 后期抗锯齿 | 阴影图 | SWE 网格 | 水面细分密度/96m | 细波网格 | 平面反射图 | 焦散图 | 光子网格 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Low | 67% | 关 | 512，阴影关 | 384 | 96 | 192，外观关 | 256，反射关 | 关闭 | 关闭 |
| Medium | 85% | FXAA | 1024 | 384 | 192 | 384 | 384 | 768 | 192 |
| High（默认） | 100% | SMAA | 2048 | 768 | 384 | 768 | 768 | 1024 | 256 |
| Ultra | 125% | SMAA + 超采样 | 4096 | 1152 | 512 | 1152 | 1536 | 2048 | 384 |

可另调 50–125% 3D 分辨率、实时阴影、反射探针和原版平面反射、FXAA/SMAA、原版焦散更新间隔、帧率上限与触摸灵敏度。High 的焦散跳帧间隔为原始值 2；Low/Medium/Ultra 分别为 6/4/1。更新间隔跳过若干帧并复用上一帧的真实光子结果，不换成循环贴图。帧率上限默认 60，可选 30/45/60/90/120/不限；这是上限，不是设备能达到的承诺。

Low 保留主浅水和 APIC-MPM 物理，但明示关闭细波、微法线、泡沫、焦散、倒影等外观层。原仓库 20 步光束雾是独立 CompositorEffect，分辨率缩放降低像素成本，不降低其算法步数。它不是 Godot 原生体积雾。

## 真正的兼容性门槛

- arm64-v8a；官方模板 minSdk24（Android7）、targetSdk36。系统版本只是最低安装门槛。
- Vulkan 的 RenderingDevice、原版计算着色器及 32 位整数 storage-buffer atomicAdd/atomicExchange 必须能实际运行。未使用浮点 atomics 或 64 位 atomics。
- SWE 使用 4 个 storage image 槽位，RGBA16F/R32F 图像存储与采样；MPM 使用至少 128 个计算线程/工作组、4000 个 X 工作组及 4 个 storage buffer 槽位。每个原始 MPM 网格为 80³ 整数单元，不会为手机偷换模拟器。
- 光子和液面需要 RGBA16F/RGBA32F 渲染目标、D32F 深度、浮点混合、白水 4×MSAA 和异步读回。所有着色器编译、目标分配、实际绘制与真机驱动仍需成功。
- Mobile 支持 compute、CompositorEffect、屏幕颜色/深度和反射探针，但不支持 Godot SDFGI、SSAO、SSIL、引擎 SSR、TAA 或原生体积雾。没有在菜单伪造这些开关，也不把常规雾称作原版光束雾。
- 启动的能力检查和运行时错误检查在必要组件失败时明确显示原因并禁止继续，不静默回退到 Compatibility/假水。

实际 Mobile 测试发现主视口 MSAA 无法给原液面/光束合成器提供解析后的深度，因此主视口固定单采样，改用真实 FXAA/SMAA。High 默认 SMAA，Ultra 为 SMAA + 125% 超采样；原始白水内部独立 4×MSAA 不变。旧版保存的 MSAA 偏好会迁移为对应后期抗锯齿，不会伪装成仍支持主画面 MSAA。PC 的 MSAA 不变。

Android 主视口启用 HDR，使 Mobile 内部3D颜色与原有 HDR 平面/立方体抓帧保持同一线性范围，避免只给光束调亮度而水花仍亮度错配。此开关不是手机屏幕的 HDR 输出模式；会增加颜色缓冲带宽。

用户提供的芯片为天玑9400。官方资料对应 Immortalis-G925 MC12，但具体手机型号、Android版本、驱动和散热未验证。不能仅按芯片名称保证 Ultra 流畅，也不把云电脑 Vulkan 测试当作手机性能测试。

## 构建及签名

安装 Godot4.6.3、匹配官方导出模板、OpenJDK17或较新受支持版本、官方 Android SDK。当前云构建使用 JDK21、Build Tools36.0.0、Platform Tools37.0.1。预编译 APK 模板路径不需要 Gradle/NDK/CMake。

`tools/android/export-test-apk.sh` 只接受已存在的测试签名密钥，不自行生成凭证、不安装、不上架。环境变量为 DEBUG_KEYSTORE、ANDROID_SDK_ROOT、JAVA_HOME、GODOT_TEMPLATES_DIR，后者目录含 android_debug.apk 和 version.txt。密钥不得放入工程、源码压缩包或 APK。当前新测试签名已单独获得授权，只用于本次测试 APK。

导出为官方 debug 引擎的调试 APK，不是冒充 release 的上架包。未申请网络、位置、相机、麦克风或外部存储权限；数据只在应用自身目录。若设备上存在不同签名的同包名旧应用，Android 会拒绝覆盖安装，不应绕过安全检查。

## 验证范围和限制

- CPU：mobile_controls_test、mobile_multitouch_test、mobile_source_contract、mobile_lifecycle_test（明确的生命周期测试替身）。覆盖输入、多点视角、真实滚轮距离、蓄力/中断、设置持久化、源代码入口、明确的水体错误报告。
- GPU：mobile_hdr_color_probe 已在云端实际 Mobile/Vulkan 上确认主3D缓冲由 RGB10A2（格式63）切换为 RGBA16F（格式96）；mobile_source_gpu_smoke 运行真实 Mobile 原场景、SWE/MPM/光子/合成和正式场景切换。必须用有 Vulkan 上下文的窗口运行；headless 不算 GPU 通过。
- `tools/android/test-mobile.sh` 默认只执行 CPU 测试；加 --gpu 才运行完整 Mobile GPU 验证。
- 截图读取实际 HDR Image 格式；RGBH/RGBAH/RGBF/RGBAF 在线性浮点颜色转换为 sRGB 后才量化保存 PNG，避免把过暗的线性 PNG 当作显示结果。
- 导出的 APK 必须另外检查 apksigner v2/v3、zipalign 16KiB、ZIP完整性、清单和原水体资源。正式交付结果以同批次验证报告为准，不沿用旧 APK 的测试成绩。
- 官方模板保留一条未使用 themed_icon 路径警告，未手工篡改清单。云环境没有连接 Android 真机，因此未声称安装、触屏硬件、手机帧率、热稳定性已验证。

如需分卷传输，运行 tools/android/package_apk_parts.py。它自动按当前 APK 大小生成若干ZIP和 SHA-256 manifest，不再假设固定三卷。解压全部卷到同一目录，重组工具逐块和整包核验，不联网、不安装、不覆盖不同内容的同名文件。

## 官方依据

- https://docs.godotengine.org/en/4.6/tutorials/shaders/compute_shaders.html
- https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html
- https://docs.godotengine.org/en/4.6/tutorials/3d/volumetric_fog.html
- https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html
- https://godotengine.org/download/archive/4.6.3-stable/
- https://www.mediatek.com/products/smartphones/mediatek-dimensity-9400

## 本次冻结构建

最终文件位于 `output/android/final/PoolCore-Source-Water-Android-Test.apk`，46,288,784字节，SHA-256：`8e732159d85618b4ee7c87dce021ff3821be14eb18e9299c2f3f972393095456`。已通过 v2/v3 签名、16KiB ZIP 对齐、ZIP CRC、arm64 清单、无权限、无签名私钥和当前原始着色器文件一致性验证。四个分卷全部小于15MB，已实际运行重组程序并校验整包一致。GPU运行结果另见同批次报告；此处的APK校验不代表真机安装或性能测试。
