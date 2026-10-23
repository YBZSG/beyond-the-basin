PoolCore 原场景水体测试版：Windows 便携包

1. 完整解压 ZIP。不要在压缩包预览中启动，也不要只复制 PCK。
2. 保留 native/source_water/bin/source_water.windows.x86_64.dll 的目录结构。
3. 若同目录有 PoolCore-Source-Water.exe，已包含独立运行引擎，直接双击 Launch-PoolCore.cmd 即可。
   若只有 PCK，或希望使用自己的引擎，将官方 Godot 4.6.x 或 4.7.x Standard Windows x86_64 EXE 拖到 Launch-PoolCore.cmd；
   或将唯一 Godot EXE 放到同目录，双击 CMD。EXE 可以重命名。
   也可以用命令行：Launch-PoolCore.cmd "D:\我的工具\Godot 4.6\任意名字.exe"
4. 不要求 Godot 与游戏在同目录。启动器明确设置包目录，支持带空格、中文的路径。
5. 构建/已核对的引擎基线是 Godot 4.6.3。4.7.x 可以启动，但兼容性尚未完整验证，会提示而不会强制降级；可能触发精确缓存重建，首次准备更慢。
   Windows DLL 为真实交叉编译文件，但未做本机 Windows/GPU 验收；
   Linux 便携路径和原生辅助库的 CPU 启动已验证，不代表 Windows/手机实机验证。
6. 首次启动可能需要编译着色器。失败时窗口会保留，目录里有 diagnostic TXT 和 engine LOG。
   日志含本机路径、引擎版本、显卡信息；不会自动上传。

原生 DLL 只优化精确水体读回的 CPU 解析，不改变水体方程或品质。
缺少辅助库时游戏保留 GDScript 路径，但可能打印扩展加载错误、CPU 开销增大。
不要主动删除 DLL，也不要关闭系统安全功能。启动器不下载、不安装、不改安全设置、不重置存档。

启动器固定 Forward+，不自动降低画质。画质/出生地/性能信息以游戏菜单为准。
常用操作：WASD 移动，鼠标看向，Shift 跑，Space 跳，E/左键拾取，滚轮调距离，
右键蓄力并投掷，Esc 菜单，G 诊断，H 隐藏 UI。

English quick start
Fully extract the package, keeping the native folder. Drag your official Godot 4.6.x or 4.7.x
Standard Windows x86_64 executable onto Launch-PoolCore.cmd. Any filename is accepted;
4.6.3 is the tested build baseline. 4.7.x is allowed with an unverified-version warning, not a forced downgrade.
If PoolCore-Source-Water.exe is present, this is the self-contained edition: double-click
Launch-PoolCore.cmd. Otherwise this is the PCK-only edition and you supply the engine.
A separate engine directory is supported because the launcher binds --path to the package root. Keep all native files.
Native Windows and Android binaries are cross-built/static-audited, not device-executed.

Godot Windows 的小型 _console.exe 是控制台包装器，不是独立引擎；它需要同目录、同版本、匹配名称的主 EXE。若重命名或只复制一个文件，请使用完整的主 Godot EXE。启动器允许主引擎使用任意文件名，但无法改变官方包装器的命名规则。
