PoolCore 原场景恢复与交互修复

1. 完整解压本 ZIP，不要在压缩包预览里运行。
2. 将官方 Godot Windows EXE 拖到 Launch-PoolCore.cmd；或把唯一 Godot EXE 放在同目录，再运行 CMD。兼容带空格/中文的路径。
3. 引擎将加载同目录 PoolCore-Source-Water.pck。我们测试的是 Godot 4.6.3 Standard / Forward+；你的 Godot 4.6 可以通过此脚本运行并保留具体版本/显卡日志。没有 Windows 目标GPU验收，不把版本差异当故障结论。
4. 首次默认原仓库场景。在 Esc 菜单“出生地”选择原仓库场景或重做主池厅，再点“在此出生”。保存选择；不删除任一世界。
5. 冷启动先构建原水体光学数据，菜单会显示准备状态；首次着色器编译可能较久。

WASD移动，鼠标视角，Shift跑，Space跳，E/左键拾取，滚轮上推远/下拉近，右键按住蓄力/松开投掷，Esc菜单，G诊断，H隐藏UI。

脚本不下载、不安装、不修改安全设置、不自动上传。窗口退出后保留两个诊断日志，若仍异常可发给我们。
具体改动与已知限制见 ORIGINAL-RESTORATION-RELEASE.md。

This package contains the actual PCK, not the Godot engine. Use your official local Godot EXE. No network access, installation, or security-policy change is performed by the launcher.
