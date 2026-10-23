# Native gait derivatives

These five PCM WAVs derive only from the existing user-supplied OGGs in the parent sfx directory, copied from source commit 66a4543602d9e774db07c2da12ce1d40d522532c. Original OGGs remain unchanged. This work asserts no new ownership or redistribution license for those recordings. No external sound library or paid asset was used.

Rebuild with `python tests/native_gait_audio_assets.py --build` (ffmpeg, NumPy, SciPy). The tile files remove noisy pre-roll, high-pass DC/sub-bass, soften high-frequency energy and exceptional transient peaks, and add short attack/release envelopes. The two water loops use the original source's 200 ms head/tail splice to prevent discontinuities. Water synthesis and simulation math are not changed.
