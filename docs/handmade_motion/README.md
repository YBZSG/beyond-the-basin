# 手工动作补充：源码检查点

本次不是重新制作整个人物，也没有替换成下载角色。沿用已验收的 natural_hand_finish 54 骨骼人物及原有 14 段真实动画，新增 3 段 Blender 手工编排、逐帧烘焙的动作：

- Pickup：约 0.48 秒，伸手并向胸前收拢，包含手指从张开到握持的过渡。
- SetDown：约 0.47 秒，松手后的手臂与手指回收。物品依旧在原控制器同一帧释放；这不是等待动画结束后才释放的放置机制。
- WadeRest：2.8 秒循环，涉水静止时轻微平衡动作。保留下肢原姿态，不让脚因这段动画离地。

原来的 Idle、Walk、Run、Hold、Wade、Swim、Climb、SwimIdle、JumpRise、JumpAir、Land、ThrowCharge、ThrowRelease、ThrowRecover 均保留，并非本次重新制作。

## 接入与边界

桌面原自然人物入口选择 handmade_pool_avatar.gd。仅在原人物骨骼合同通过且原动作存在时加载补充动画库；库缺失时回退原动作。启动参数 `--legacy-handmade-motion` 可停用补充动作。原手机和旧人物路径不变。

运行时只额外加载约 111 KB 的动画库，不实例化第二套人体网格。每段动画导入后含 42 条上身旋转轨道，包括 30 条手指轨道；没有 Root/Hips 位移或下肢轨道。最终手掌接触 IK 和物品控制仍由原系统负责。实际位移驱动的步频、涉水/游泳状态、碰撞、拾取与投掷物理、GPU 水体、NR 和光追均未修改。

动作事件由物理步观察，渲染只采样。投掷优先于拾取和松手，瞬移/暂停造成的 epoch 变化取消当前小动作，恢复后不重播。仅物品被销毁而没有真实 drop 事件时不伪造放手动画。

## 可编辑资产

- tools/blender/handmade_motion/explorer_handmade_motion.blend：可编辑角色及三段 Action。
- author_handmade_motion.py：以原 natural_hand_finish GLB 为种子的生成脚本。
- render_pose_previews.py：Blender CPU 姿势检查，不是 Godot 实机画面。
- assets/character_refinement/handmade_motion/explorer_handmade_motion.glb：制作链路中间资产，不在游戏中重复实例化。
- handmade_actions.tres：Godot 实际使用的补充 AnimationLibrary。
- build_animation_library.gd：骨骼一致性检查并提取纯旋转动画。

Blender 4.3.2 制作，Godot 4.6.3 官方版进行 CPU 验证。骨骼全局 rest 最大差约 0.00000166，WadeRest 起止旋转闭合误差为 0。Pickup/SetDown 是非循环动作，权重平滑淡入淡出。

## 已执行验证

日志保存在 evidence/，测试源在 tests/handmade_motion/：

- 状态合同：24 项通过，含 5/15/30/60/120 Hz 时间推进、重复事件、暂停/瞬移、投掷优先、陈旧 drop 元数据。
- 实际人物与动画图：457 项通过，含 54 骨骼、42×3 条轨道目标、原动作保留、手指策略、手掌 IK、下肢不被补充轨道覆盖。
- 实际 CharacterBody3D 控制器 + 人物 + RigidBody3D 道具：7 项通过，含拾取/松手动作、同 tick 投掷释放和暂停取消。
- 原控制器回归：15、60、120 Hz 均通过，覆盖实际碰撞中的涉水/游泳切换、跳跃、拾取、滚轮和投掷。这不是目标 GPU 帧率测试。
- 缺失补充库时安全回退；原人物选择验收继续通过。
- 三张 Blender 实际姿势图已检查，修正过初版垂腕方向，图上明确标注不是 Godot 游戏截图。

## 未完成的视觉验收

当前环境没有目标 NVIDIA GPU 或匹配的 Windows 自定义 NR 引擎。本次不能证明最终游戏中的自然度、手臂全运动包络不穿模、持物接触完全准确、GPU 水面互动或目标帧率已经合格。现有人物外形也没有变成照片级人体。请在目标版本中检查正面/侧面拾取、不同形状道具、近墙游泳和低帧率转身。CPU 合同和 Blender 姿势图不替代这些验收。

## 来源与许可

补充姿势、生成脚本及接入代码为本次原创。人体/手部继续沿用项目已有资产及其许可记录，见 CREDITS.md 与 natural_hand_finish 中的资产说明。本次没有引入第三方下载动画。
