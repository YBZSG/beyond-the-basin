# 原生光追恒定发光材质修复（2026-10-25）

症状：参考翼开光追后灯罩变暗，地面与柱面缺少灯的倒影。

已核对固定引擎 `135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`：
`render_raytracing.cpp` 只在存在 `texture_emission` 时设置 `RT_MAT_FLAG_HAS_EMISSION_TEX`；
`scene_raytracing_raygen.glsl` 只在此标记存在时计算标准材质的 emission。
因此，无发光贴图、仅有颜色和强度的 StandardMaterial3D 在光追路径中丢失自发光。

修复在 `scripts/rendering/rt_material_refresh.gd`：
- 光追开启时，为启用了发光且没有自定义发光贴图的 BaseMaterial3D 提供共享的 1×1 白色纹理，使用乘法模式。
- 原发光颜色、能量、模型、材质实例和自定义贴图保持原样。一个共享像素不会增加灯数量或绘制调用。
- 关闭光追时恢复无贴图状态及原发光运算模式；新载入房间沿用现有增量转换流程。
- 不调整曝光、粗糙度、法线、NR、采样数或反弹数，不改水体。

验证：使用本机 RTX 5070 Laptop GPU、现有 4.8-dev 定制引擎、真实 colonnade 模型及生产材质转换器，固定机位/曝光做光栅、修复前RT、修复后RT、关闭RT恢复四次截图。保持 1 spp / 3 bounces，关闭 NR 来隔离修复。9 项检查通过；人工查看截图确认灯罩及地面/柱面灯影恢复。未运行整图游玩或帧率基准。
测试退出时引擎报告 Texture RID 清理警告，未把它描述为全程零警告或全游戏验收。

可复现脚本：`tests/reference_wing/rt_emission_review.gd`。原生带GPU运行，加 `-- --review-out=<目录>` 可指定截图/报告位置；headless 仅检查材质状态，不能证明视觉效果。
证据：工作区外层 `evidence/rt-emission-20261025/`。

本地运行包以用户当前 PoolCore.pck 为基底，由 Godot PCKPacker 只替换上述一个脚本；逐文件校验全部486项，其他485项保留原字节。更新后 PCK SHA-256：
`b82d22570e663842606a2437b8961371eb32b8024ae84806a918d12a1e176ffa`。
未提交、未推送、未发布。