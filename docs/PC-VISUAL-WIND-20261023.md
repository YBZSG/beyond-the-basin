# PC 阴影、动作、池底与风纹更新（2026-10-23）

本次更新仅进入独立 Godot 工程分支，保留该分支较新的 Android 改动，不修改原 Web 的 `main` 分支。

## 功能范围

- 阴影：PC Forward+ 的近景级联按 5 / 14 / 60 / 120 米分配，保留原有 120 米覆盖、太阳大小和偏置。High / Ultra 提高软阴影采样，可能增加 GPU 负担。
- 人物：Explorer 增加起停、转向、呼吸及涉水的局部身体动作，保留距离驱动步态、脚部轨迹和最后执行的持物手部 IK。不会移动相机或碰撞体。
- 池底：调整正式池底材质的砖缝颜色，提高可读性；不修改池底几何、碰撞或水深。
- 风纹：增加可保存的开关、强度、传播方向和细密度，可单独恢复默认值。三个连续相位的解析波叠加到水面光学法线，参与原有反射、折射、Fresnel 和高光。

默认风纹强度为 0.18，等效光学起伏约 0.73 毫米，最高档的解析高度上界为 6 毫米。方向表示波峰传播方向：0° 为世界 +X，90° 为 +Z。方向采用最短转向；关闭风纹不关闭原有水面交互。

风纹不改变物理水面高度、浮力、原求解器、粒子或光子焦散，也不新增逐帧 GPU 读回。Android、iOS 及移动预览不启用这层新增风纹。模型和边界详见 [风纹光学说明](wind_water_optics.md)。

## 源码与二进制的关系

累计更新涉及 11 个运行时源文件，其中 9 个与已交付源码完全一致。`scripts/main.gd` 和 `scripts/water/source_water_runtime.gd` 合并了较新 Godot 分支的 Android 改动，因此这两个文件不是旧补充包的直接覆盖件。合并基线为 `4161dc377926d719e8d7e5b447c1a9ff99064cb0`。合并后的源码已另行执行下述 CPU 回归，不能用原交付包的哈希代替验证。

本次发布不重新生成或替换既有 PC EXE / PCK、Android APK，也不承诺从当前源码导出的二进制与此前 PC 风纹包逐字节相同。请使用本分支完整工程，不要向较新的分支套用针对旧提交的覆盖说明。

## 合并后的源码复核

本次合并后在 Godot 4.6.3 无图形模式重新执行：

- 控制器契约：20 项通过。
- 设置/UI 契约：170 项通过。
- 独立数值/API 契约及材料参数快照所有权：通过。
- 现有移动预算契约：PC 与 `--mobile-preview` 各 54 项通过。

本轮没有重新执行图形场景、Windows 游戏或 Android 导出。上述结果只覆盖源码集成与无图形回归，不延伸为完整图形或设备验收。

## 已交付功能的验证与限制

此前交付的控制器数值、设置/UI 保存重载、材料参数快照所有权检查通过，其中设置契约覆盖 170 项检查。原生 Vulkan / llvmpipe 受控场景检查覆盖普通视角、掠角、方向变化及与原生冲击波共存；最终连续采样为 25 帧。两秒演示使用 12 fps 固定时间采样，不代表实时游戏帧率。

以上证据属于已交付功能及其限定夹具，不能替代合并后的整套游戏验收。未完成 Windows 启动器执行、目标显卡性能、全世界连续游玩或真实人物涉水验收。主页切换世界的黑色/荧光绿问题不在本次修复承诺内。光照、材质与整体写实程度仍有改进空间。

## 打开、构建与 CPU 检查

使用 Godot **4.6.3 Standard** 打开根目录 `project.godot`，先完成资源导入。PC 正常运行使用 Forward+；导出需要匹配版本的官方模板，按项目已有导出预设操作。源仓库不附带编辑器或新导出的游戏包。

以下检查从工程根目录执行，要求 Linux、Python 3.10+，且 `godot` 指向 Godot 4.6.3。设置测试使用独立临时目录，不覆盖日常游戏偏好。

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --rendering-method gl_compatibility --script res://tests/wind_water/controller_contract.gd
godot --headless --path . --rendering-method gl_compatibility --script res://tests/wind_water/native_controller_contract.gd
python3 tests/wind_water/settings_run.py
godot --headless --path . --rendering-method gl_compatibility --script res://tests/wind_water/uniform_snapshot_contract.gd
godot --headless --path . --rendering-method gl_compatibility --script res://tests/mobile_budget_contract.gd
godot --headless --path . --rendering-method gl_compatibility --script res://tests/mobile_budget_contract.gd -- --mobile-preview
```

- 控制器契约检查边界、相位连续性、解析导数、精确归零及原运行时/着色器加载。
- 独立数值契约检查输入异常、最短转向、参数平滑、波长滤波及已绑定参数的不可变快照。
- 设置契约调用实际界面回调和配置存储路径，检查保存、迁移、重载、重置及画质设置保留。
- 材料快照契约检查推进控制器不会意外修改已经绑定的水面参数。

这些命令不验证最终 GPU 画面、完整游戏流程或手机/PC 帧率。测试报告是本地产物，不应作为源文件提交。
