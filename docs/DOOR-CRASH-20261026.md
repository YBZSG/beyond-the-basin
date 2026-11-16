# 相邻房间门口崩溃：本地调查与修复

用户报告参考翼走过门口进入相邻房间时闪退。2026-10-26 的两次 Windows
Application Error 记录及 `profile/PoolCore.log` 指向 NVIDIA Vulkan 驱动中的
access violation，后一次在 `(0,-1)` 暗柱水厅进入 `(0,0)` 釉光阶厅后发生。
没有对应的 GDScript 报错。运行设置为原生 RT、DLSS Balanced、NR 单层、FG 关闭。

使用现有编译对象重新链接出符号表，确认其 `.text` SHA-256 与原可玩 EXE
完全一致：`472383f494ef9f9acf1cf0f9ac008b5459482118189a33d532102d15e2435e5e`。
因此可以把原始返回地址可靠地映射为：

```
RenderingDeviceDriverVulkan::command_pipeline_barrier + 0x7d3
RenderingDevice::_end_frame + 0x214
RenderingDevice::swap_buffers + 0x277
RenderingServerDefault::_draw
```

原始转储中的同步批次包含 6 个 VkImageMemoryBarrier，均为 11 mip 的分层
纹理上传转换：第一个指向旧图像的 layer 4，后五个指向另一图像的 layer 0–4。
这与 1024 方形房间 Cubemap 的生成和失效路径一致。该记录是纹理上传生命周期
问题的证据，不足以把所有驱动崩溃归为同一原因。

## 修改

`tools/dlss/engine-texture-upload-retirement.patch` 在引擎延迟销毁纹理时，按
现有锁顺序，从各上传 worker 和全局待提交列表移除引用该 driver texture ID
的同步记录，再释放底层纹理。纹理的既有延迟释放与帧 fence 保持不变；没有增加
GPU 等待、关闭光追或删除水波。`build_nr.py --apply` 已纳入补丁。

背景音乐另按用户要求替换，来源与处理见 `assets/sfx/MUSIC_SOURCE.md`。

## 验证边界

原始版本的自动行走已实际跨门，四次带视角转动的往返没有再次崩溃；独立的
Cubemap 创建/立即废弃检查也未稳定复现。首次较短测试没有走到门线，不能当作
跨门通过；另一次长测试后半段因失焦暂停，也未计为实际跨门。

因此这是根据真实崩溃栈与资源生命周期实施的针对性修复，不宣称已经获得
“修复前必崩、修复后必过”的确定性复现。最终运行记录、编译日志、PCK 校验和
原配置哈希对比保存在工作区外层 `evidence/door-crash-20261026`。

最终修复版在 RTX 5070 Laptop、1920×1080、原生 RT + DLSS Balanced + NR
单层下完成四次实际穿门，过程中视角持续转动，NR 最终成功帧数 1504。
新音乐 50.118667 秒，播放与循环标志有效，并观察到跨循环点。535 个 PCK
资源逐项哈希通过，只替换 1 个导入后的音频资源，其余 534 个保留。
用户原 profile 的 7 个 cfg/json/bak 文件哈希均未改变。

仍存在原有 `OpTypeForwardPointer` 提示和退出时 7 个 Texture RID 警告；本轮
没有把它们称为已解决，也没有进行全地图、FG 或手机验收。

已同步的本地可玩文件：

- `PoolCore.exe` SHA-256：`909a6c24c7e7762dd316ade8fcc064a7a054b502451e090a14e6fb4516a751e9`
- `PoolCore.pck` SHA-256：`52a84412bb85a5810000e2283502f29eb057268fda115a210d6a30c1b21880b1`

本轮仅更新本地文件与 MANIFEST；未提交、推送或发布。
