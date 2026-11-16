# 池底余响 — PoolCore 背景音乐

2026-10-26 应用户要求，以本机 YuE2 Studio 3.7.0 / yue2-cpp `quality-q8`
重新生成纯器乐背景音乐。游戏继续使用 `ambience.ogg` 和原有 Ambience
总线、音量、菜单暂停及氛围音乐开关；脚步和淌水音效保持原样。

- Studio song ID：`01a177fc-85bf-7183-a837-e7d02dcbffe7`
- Job ID：`f1d99a109bfc6849`
- Seed：20261026；LM seed：250821；steps：50；CoT：off；无歌词、无参考录音。
- 请求 180 秒，实际生成 FLAC 58.118667 秒，不能按请求时长描述成品。
- 去除头尾各 1 秒，尾首 6 秒交叉淡化，成品循环长 50.118667 秒。
- 48 kHz / 双声道 / Ogg Vorbis q5；35 Hz 高通、-18 LUFS 目标、-2 dBTP 上限。
  滤波时连续处理三个周期并取中间周期，避免滤波启动瞬态破坏循环接缝。
- 最终解码峰值约 -2.24 dBFS；循环接缝样本跳变量 0.00669，小于片内最大相邻样本变化。
- SHA-256：`e65b085279d4880884d83b9ba6c071e07bcd850d7fa7428634859a261b269eac`
- 已进行解码、音量和接缝数值检查；这些检查不代表用户的主观听感认可。

生成提示词：

> Dark ambient, liminal dreamcore, instrumental, slowly evolving warm analog pads,
> deep soft drones, sparse distant glass bells, muted electric piano fragments,
> submerged tape textures, cavernous reverb, empty indoor swimming pool atmosphere,
> nostalgic and quietly unsettling, restrained dynamics, percussionless, 55 BPM
