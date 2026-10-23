# 原仓库体积光束与距离雾恢复

2026-10-21。源提交：`66a4543602d9e774db07c2da12ce1d40d522532c`。

这次恢复的是源项目的实际雾算法，不是把 Godot 的普通雾调浓、添加透明光柱模型，或把 `FogExp2` 称作完整体积雾。原画面有两个独立组成：

1. 不透明材质的 Three.js `FogExp2` 距离雾。
2. 水面、液片和白水之后的 Tyndall 屏幕空间体积光线步进。

此前 Godot 版本只有通用 froxel 体积雾，密度 `.0025/.0035` 等既不等于原 `FogExp2`，也没有原 Tyndall 光束。此次增加独立的原生 RenderingDevice 效果，正式新增房间继续使用原先的原生光照与雾，不强行套用原房型算法。

## 来源与对应文件

| 来源 | 原生实现 | 范围 |
| --- | --- | --- |
| `app/pool-vct/engine.ts:722–773` | `shaders/source_fog/tyndall.frag` | 原 Tyndall 片元算法 |
| `engine.ts:953–971` | `scripts/rendering/source_volumetric_fog.gd` | 房型、衰败、过渡、时间、重定位 |
| `engine.ts:66,71,949–952` 与 Three.js `fog_fragment` | `source_distance_fog.gd`、`shaders/source_fog/distance.frag` | 独立平方指数距离雾 |
| `scene-pass.ts`、`water-optics.ts:185–189` | 不透明雾在屏幕复制之前；Tyndall 在水与白水之后 | 避免折射缺雾或重复加雾 |

`source_provenance/beyond-the-basin-66a4543/app/pool-vct/` 内的来源保留原文。对照 `git show 66a4543:app/pool-vct/engine.ts` 的 SHA-256 与该副本一致：

- engine.ts：`8aed8400d63eab4ba49918efccadf24ec969719c8a58908d974a23275cc21678`
- scene-pass.ts：`56948671d1f7afc25934df6a4869a72ea660a162ac5daf3c114ea4173361d11a`
- water-optics.ts：`71897573642eb4605ed819b5672f4d16215c75ea83e2c6c1e3ee12ac7b40800b`

迁移不更换原项目的许可。Three.js/Godot 第三方声明沿用 `CREDITS.md`、`docs/SOURCE_LIQUID_LICENSES.md` 与 `docs/licenses/`。

## Tyndall：没有降级的源算法

保留全部源常量和分支：

- 每像素 **20 步、36 m**，步长 **1.8 m**。任何质量档均不减少步数或距离。
- `SUN = (.274, -.913, .274)`，保留源字面值，不重新归一化。
- 静态像素抖动：`fract(sin(dot(pixel,(12.9898,78.233)))*43758.5453)`。
- 低于 `.32 m` 水面立即停止；相机背面、屏外、被已绘制不透明深度遮挡的样本跳过。
- 源归一化深度偏移 `.0015`，不是误换成世界坐标米数。
- 斜向轴范围：`along = dot(p-lightPos,SUN)`，半径 `5.4*(1+along*.028)`，边缘 `1-smoothstep(spread*.55,spread,radial)`。
- 漂移空气密度：`.72+.28*sin(p.x*.9+time*.32+sin(p.z*.7-time*.21)*1.4)`。
- 前向散射：`.16+1.5*pow(max(dot(dir,-SUN),0),5)`。
- RGB：`(.62,.78,.84)`；叠加强度 `.05*level`。
- 仅源房型 **3、5、6** 且 `corrupt<2` 自动开启。普通 `daylight` 标签不会凭空给其他房型开启光束。
- 过渡：`level+=(target-level)*min(1,dt*1.4)`；源时间与过渡均保留 `.2 s` 的 dt 上限。
- 源房型 3 锚点高度 15 m；其他源房型 10.2 m，包括源房型 6。没有擅自改成原生房间的实际天花板高度。
- 源 `shaftsForced` 对应显式 `forced` QA 开关，正常游玩默认关闭。

这仍是原作的屏幕空间体积近似：只测试观察射线上的不透明深度，不新增太阳到每个空气样本的阴影追踪，不声称是完整物理参与介质求解器。

### 原生适配，而非算法替换

Godot 的原生投影有反向 Z 和帧缓冲 Y 翻转。源深度 `d_source = 1 - d_native`，所以源遮挡判断被严格变换为 `sample_native < opaque_native - .0015`。近/远面重建分别改用 1/0。输入投影只校正一次。

WebGL 的 `gl_FragCoord` 原点在下方；原生片元坐标转换回 `(x,height-y)` 后才计算相同抖动。驱动的浮点正弦实现可能让 hash 末位不同，不能据此声称逐像素完全一致。

原游戏每次跨房间把当前房间重定位到零。原生世界保留绝对房间坐标，因此相机平移减去 `coord*32`，并据此生成 view 矩阵。这样斜轴、空气漂移和几何深度都保持源相对关系。

最终使用 RGB `ONE+ONE` 加法混合，数学上等于源 `base+acc*intensity`，无需再复制一张全屏 HDR 纹理。保留原生目标 alpha。只装在主相机；源 Tyndall 本来也不进入镜面或房间 cubemap 的场景捕获。

## FogExp2：独立的不透明距离雾

源密度是 `[.036,.043,.053,.066]`，按衰败等级取目标，以 `min(1,dt*.6)` 过渡。颜色始终是源 `#22343d`，转换为线性 RGB。不要拿房型目录的美术 fog 值替换运行时源值。

因子是 `1-exp(-density*density*view_depth*view_depth)`；使用相机轴向深度 `-view.z`，不是到相机的欧氏距离。背景没有不透明深度，因此不加该材质雾。源水在 `sceneReady>=.5` 时已采样含雾的场景，不应再次覆盖距离雾。

实现按实际后端图阶段选择：Forward+ 使用 `POST_SKY`；Mobile 使用 `PRE_TRANSPARENT`。Mobile 没有 `POST_SKY` 回调，且它的 `PRE_TRANSPARENT` 在屏幕复制之前，与 Forward+ 顺序不同。

- 无 MSAA：对不透明 HDR 颜色按源因子混合。
- 有 MSAA：逐样本读取实际 MSAA 深度、混合到实际 MSAA 颜色，再 resolve 为正常颜色。随后原生透明渲染与最终 resolve 都继承该结果。
- 然后引擎复制屏幕颜色，供源水折射采样。这不是在水面上画全屏距离雾。

在 Forward+ 不能只在 `PRE_TRANSPARENT` 修改已 resolve 的纹理：该后端已在此之前复制了 screen texture，后续 MSAA resolve 还会覆盖这次修改。测试专门覆盖了这个错误容易被忽略的路径。

### 独立高光合并的限制

Godot 的 SSR/SSS 独立高光合并位于 `POST_SKY` 之后。因此源世界模式需要关闭 **Environment SSR 和材质 SSS**，否则本效果的阶段不正确。`configure(true)` 是宿主明确确认这一前提；未确认时距离雾不会执行，不能把禁用状态当作恢复成功。

源水自身的平面反射、折射和液体反射不依赖 Environment SSR，保留不变。正式新增房间维持此前原生 SSR 与雾，不受此路径影响。距离雾进入主视图、平面反射和房间 cubemap；捕获只拷贝主相机当前密度，不能重新积分过渡。

这不是对所有任意透明材质的自动替换。源 `sceneReady<.5` 的低质水回退现已在 `source_water_surface.gdshader` 中恢复相同的材质侧 FogExp2 分支，由运行时同步主相机密度；`debugView>=.5` 与正常已采样场景的水不会重复加雾。该低质分支的整场景验收应查看对应水体测试，不属于下述通用屏幕透射夹具。正式玻璃继续保留原生路径。

## API 与生命周期

主相机已有水/白水 compositor 必须保留：

- `SourceVolumetricFog.new()`，`configure(camera)`，追加到液体/白水之后；逐帧 `frame(delta, coord, layout)`。
- `SourceDistanceFog.new()`，满足图阶段前提后 `configure(true)`；同一 compositor 追加，回调阶段是 Forward+ 的 `POST_SKY` / Mobile 的 `PRE_TRANSPARENT`。
- 捕获相机各自持有距离雾实例，使用 `set_density(main_distance_fog.density, is_formal)`。不添加 Tyndall。
- `set_enabled(bool)` 是 CompositorEffect 原生接口。不能在发布的线程参数内锁存 enabled，否则关闭期间更新一次参数再打开会保持错误禁用。
- 世界重建或退出先 `dispose()`；资源在渲染线程释放。视口/MSAA 改变时引擎可能已经销毁相关 framebuffer/pipeline，释放前检查 RD 实际有效性，不能只看 RID 是否非零。
- `debug_stats()` 包含实际可用性、错误、绘制次数、源参数和正式房间旁路状态。

## Mobile 与颜色编码

这两个效果依赖 RenderingDevice、原生片元着色器及可采样深度，不依赖 Godot 的内置 volumetric fog、法线粗糙度缓冲或 storage image。因此“Mobile 没有内置体积雾”不等于“源 Tyndall 不能运行”。Compatibility 或无图形上下文的 headless 不执行这些 GPU 算法，明确报告 unavailable，不伪造成功。

Godot Mobile 普通 10-bit UNORM HDR 缓冲把线性 0–2 编码到 0–1；float HDR 则使用倍率 1。效果检查实际颜色纹理格式，对 UNORM 编码使用 `.5`，对 float HDR 使用 `1`。`Viewport.use_hdr_2d=true` 会让该视口的 **3D 内部颜色缓冲**也变成 RGBA16F，并非只改变最后的 2D 画布；手机整套水体仍需一致的 HDR 编码，不能只修雾而忽略水的混合。

Mobile 的 compositor 不支持请求 MSAA 深度 resolve，直接保留 `access_resolved_depth=true` 会产生明确警告，不能将其当作可用深度。手机主视图使用真实非 MSAA 深度，主视图抗锯齿改用原生后处理 AA/分辨率；PC 主视图 MSAA 和内部白水自有 4x MSAA 保留。Tyndall 对意外启用的 Mobile 主视图 MSAA 报配置错误，不悄悄跳过遮挡。距离雾本身直接读取 MSAA 样本，所以没有隐式 resolve 请求，捕获视图仍可保留 MSAA。

质量档通过实际视口分辨率改变总像素成本，不偷偷减少光线步数；是否运行稳定、真实手机帧率与发热，必须由目标设备另行验证。

## 验证与边界

- `tests/source_fog_reference.py`：CPU 来源审计通过。从源文件和原生 shader 各自抽取边缘、扩散、漂移及相位表达式，4,004 次数值对照一致；SHA-256、原遮挡不等式和距离雾固定值记录于 `tests/source_fog_reference.json`。
- `tests/source_fog_contract.gd`：headless 通过。测试源启用条件、过渡、dt 上限、锚点、房间平移、正式房间旁路、源常量和投影适配。深度映射最大误差 `3.7253e-8`，视线重建最大误差 `8.4294e-8`。这不是 GPU 验证。
- `tests/source_fog_pixels.gd`：真实 RenderingDevice 测试生产效果。包括 FogExp2 数值、MSAA off/4x、透明屏幕采样、背景不受雾、Tyndall 亮度、独立源方程 RGB 范围、实际几何遮挡、房间重定位、正式房间旁路。
- 首轮 Forward+ 原生 GPU 测试：FogExp2 四个 MSAA/透射组合均通过，显示量化后的最大线性 RGB 误差约 `.002835`，天空不变。该轮同时发现并修复了开关锁存及视口切换后重复释放 RID 的缺陷。首轮失败日志保留，不能当作整套通过。
- 修复后完整 Forward+ GPU 复测 **11/11 通过、exit 0、无错误**，记录为 `docs/verification/source-fog-pixels-native.log`。Tyndall 实测红通道增益 `.243163`，位于独立源方程遍历所有抖动值的范围内；不透明遮挡后增益为 `0`；平移到 `(64,0,-96)` 后像素一致；正式房间旁路正确。四个距离雾 MSAA/屏幕透射组合均通过，最大线性显示误差 `.002835`。
- **Vulkan Mobile GPU 复测同样 11/11 通过、exit 0**，记录 `docs/verification/source-fog-mobile-native.log`。FogExp2 最大线性误差 `.00017223`；Tyndall 红通道增益 `.241665`，在同一独立源方程范围内；不透明遮挡后增益约 `1.79e-7`，房间重定位像素一致。该测试包含 HDR2D float 路径；距离雾 MSAA off/4x 均通过，Tyndall 使用非 MSAA 主视图。没有效果或 shader 错误；日志保留一条 Linux 项目启动时的 TAA/非 Forward+ 警告，不隐瞒该警告。
- 两种实测后端均运行于 **llvmpipe LLVM 19.1.7**。这验证了真实原生 shader/compositor 路径，不是目标 Windows 显卡或 Android 真机的性能证明。首轮失败日志 `source-fog-pixels-first-toggle-failure.log` 保留以说明修复经过。整场景、低质水材质侧回退、长期运行仍需各自的实际记录，不能由上述独立夹具代替。

底层算法与控制参数恢复，不表示最终整帧与 Three.js 逐像素等价。Godot 的材质光照、间接光、TAA、glow、曝光/tonemapping 以及设备浮点仍影响最终画面。

## 原生图阶段依据

- [Godot 4.6 compositor](https://docs.godotengine.org/en/4.6/tutorials/rendering/compositor.html)
- [RenderSceneBuffersRD MSAA/深度接口](https://docs.godotengine.org/en/4.6/classes/class_renderscenebuffersrd.html)
- [Forward+ 渲染次序源码，2035–2169 行](https://github.com/godotengine/godot/blob/4.6-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L2035-L2169)
- [内部 HDR 缓冲配置与亮度倍率源码](https://github.com/godotengine/godot/blob/4.6-stable/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp#L138-L178)
- [HDR 格式选择](https://github.com/godotengine/godot/blob/4.6-stable/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.h#L177)

- [Mobile 实际回调/屏幕复制次序及不支持隐式深度 resolve 的检查](https://github.com/godotengine/godot/blob/4.6-stable/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L1172-L1225)
