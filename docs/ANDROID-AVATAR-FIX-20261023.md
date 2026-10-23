# Android 人物恢复更新

版本：`0.6.4-mobile-8400-avatar`，Android versionCode `20261024`。安装 `PoolCore-Mobile-8400-AvatarFix.apk`，替代上一份 `PoolCore-Mobile-8400-Release.apk`。

## 原因与修复

WaterFeel 原分支在 `scripts/main.gd` 中，用桌面光照实验的 `MainhallPreview.desktop_allowed()` 条件包住了人物创建和人物菜单开关。该条件在 Android 和 `--mobile-preview` 下都返回 false，所以手机版没有创建 `PoolAvatar`，尽管模型资源已经打进 APK。上轮手机优化没有覆盖这个问题。

现在人物创建独立于桌面光照实验：手机版加载与 PC 相同的骨骼模型、服装材质和动画，并提供「显示角色身体」「衣物织纹」开关。相机继续隐藏自身头部、保留身体；平面倒影相机继续包含身体和头部。水花关闭、3×3 常驻、手机网格及像素预算保持。

## 验证

- 实际 Mobile/Vulkan 场景中加载 42 根骨骼，以及 Idle、Walk、Run、Hold、Wade、Swim、Climb 七套动画；两处服装表面材质成功应用。
- 低头截图中，人物显示/隐藏对照有 32,754 个明显变化像素；已经检查实际截图，身体、手和鞋可见。
- 真实控制器的拿起/放下检查通过，Hold 动画权重推进。此检查没有把手掌精确接触物体作为通过条件。
- 含人物的完整手机场景检查再次通过：水面交互、跨入相邻房间、9 房间常驻和合成触控暂停释放输入正常。
- 新 APK 通过 v2/v3 签名、ARM64、ZIP CRC、16KiB ZIP/ELF 对齐、八个核心脚本与源码逐字节一致、人物导入资源存在检查。新旧 APK 的签名证书摘要相同，包名相同且版本号递增，可正常覆盖更新。

上述图形测试设备为本机 RTX 5070 Laptop 的 Godot Mobile 渲染路径；仍未连接 Android 真机。不能视为天玑 8400 的实际帧率或安装验收。此前的模板图标路径提示和退出 Texture RID 警告仍保留。

## 安装包身份

- 包名：`org.poolcore.beyondthebasin.mobile`
- 大小：157,362,648 字节，约 150.1 MiB
- SHA-256：`826f79f9f40611efc632e620dda0b9ce2702a911f72dd4cca7565e06ac530c3d`
- 发行引擎，已有本地测试签名，`debuggable=false`，无应用权限。

将新 APK 复制到手机后打开，覆盖安装上一版，无需先卸载。若此前手动关闭过人物，在 MENU 中启用「显示角色身体」。

源码验证工具为 `tools/android/mobile_avatar_qa.gd`；结果在 `output/android8400/mobile-avatar.json`，截图为同目录的 `mobile-avatar-body.png`、`mobile-avatar-hidden.png` 和 `mobile-avatar-hold.png`。
