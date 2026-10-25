# Reference Wing 资源闭包与可移植性

## 结论

2026-10-24 21:37 UTC 独立只读检查通过。五个正式房间均具备有效 GLB、几何 JSON 和可编辑 Blender 源；十张新贴图的大小与哈希匹配清单，未发现必需运行时输入缺失或源文件依赖工作目录的绝对图像路径。

本检查是源文件/资源闭包验证，不是模型接缝、碰撞、材质外观、NVIDIA/定制 Godot 4.8 或 Windows 效果验收。最终画面由用户在本机测试。未修改生产资产、原引擎、原水体或导出配置，未运行共享项目的 Godot 导入，也未进行 GPU 渲染。

## 五套正式资产

每项的运行时文件位于 `assets/models/reference_wing/`，包含同名 `.glb` 与 `.geometry.json`：

| 房间 | GLB 网格总数 | 可见网格节点 / 碰撞网格节点 | Blender 源路径 |
| --- | ---: | ---: | --- |
| stair_gallery | 105 | 7 / 98 | tools/blender/reference_wing/stair_gallery/source/stair_gallery.blend |
| colonnade | 130 | 74 / 56 | tools/blender/reference_wing/water_sources/colonnade.blend |
| cyan_corridor | 217 | 122 / 95 | tools/blender/reference_wing/water_sources/cyan_corridor.blend |
| octagonal_bath | 528 | 284 / 244 | tools/blender/reference_wing/water_sources/octagonal_bath.blend |
| ball_lounge | 94 | 94 / 0 | tools/blender/reference_wing/lounge_sources/ball_lounge.blend |

这里的 GLB 总数包含导出的碰撞代理，不等于可见绘制对象数。阶厅按材质合批后只有七个可见网格节点，但包含 98 个可检查的碰撞网格；其总 primitive 数为 106（一个网格含两个材质 primitive），其余四个 GLB 的 primitive 数分别为 130、217、528、94。休息室的碰撞体来自几何 JSON，不以独立 `COLLISION_` 网格导出。不能把作者源中的独立构件数、GLB 网格数和实际运行时绘制调用数混为一谈。

- 五个 GLB 均为完整 GLB 2.0：头部/文件长度、二进制块边界、bufferView 范围、图像/accessor 的 bufferView 索引与非空场景图通过检查。
- 五个 GLB 均不含外部 buffer/image URI，也不含图像。运行时釉面贴图由 Reference Wing 材质脚本赋予，而非依赖丢失的 glTF 外部文件。
- 五个 JSON 均可解析，具备碰撞代理、通道和固定相机数据；其源文件、生成器等文件路径存在。
- 对应文件 SHA-256 和字节数在 `tests/reference_wing/portability_report.json` 中。

## Blender 独立复制验证

使用已有 Blender 4.3.2、单线程、禁用自动脚本执行，仅打开文件，不保存、渲染或导出：

1. 打开五个真实源文件。
2. 将且仅将五个源文件和十张新 PNG 图复制至全新临时目录，保留相对层级。
3. 再打开五个复制件，逐项检查图像、链接库、字体、声音、影片、体积和缓存文件依赖。
4. 所有未打包依赖必须使用 `//` 相对路径、在复制目录内部解析且实际存在。绝对路径即使能在原机器找到，也不能通过。

原件与独立复制件的依赖结果完全一致：

| 房间 | 外部图像数 | 精确依赖（位于 assets/materials/reference_wing/） |
| --- | ---: | --- |
| stair_gallery | 7 | full_normal_gl_16.png、glaze_orm_2k.png、ref5_crown_normal_gl_16.png、四张 ref_tile_*_albedo_2k.png |
| colonnade | 4 | full_normal_gl_16.png、glaze_orm_2k.png、ref_tile_dark_teal_albedo_2k.png、ref_tile_teal_albedo_2k.png |
| cyan_corridor | 3 | full_normal_gl_16.png、glaze_orm_2k.png、ref_tile_teal_albedo_2k.png |
| octagonal_bath | 3 | full_normal_gl_16.png、glaze_orm_2k.png、ref_tile_pink_albedo_2k.png |
| ball_lounge | 0 | 无 |

共 17 条图像依赖，每条均为未打包的、存在于复制目录内部的相对文件。五个源均无链接 Blender 库，也没有其他被扫描的外部字体、声音、影片、体积或缓存依赖。阶厅路径为 `//../../../../../assets/materials/reference_wing/...`，水厅路径为 `//../../../../assets/materials/reference_wing/...`。

十张图全部位于 `assets/materials/reference_wing/`：

- ref_tile_pearl_albedo_2k.png
- ref_tile_teal_albedo_2k.png
- ref_tile_pink_albedo_2k.png
- ref_tile_dark_teal_albedo_2k.png
- bevel_slope_rg_2k.png
- glaze_orm_2k.png
- full_normal_gl_16.png
- bevel_normal_gl_16.png
- height_16.png
- ref5_crown_normal_gl_16.png

十张图的字节数与 SHA-256 均符合 `material_manifest.json`。五个源、五个 GLB、五个 JSON 和十张贴图共 25 个受监视生产文件，检查前后的哈希一致。复制所用精确列表见 `tests/reference_wing/portability_source_manifest.json`。不要展平目录结构。此探针验证文件依赖及可打开的场景，不宣称逐像素解码全部纹理或完成材质外观验收。

## Godot 资源闭包与导出

由新翼脚本、着色器和三个集成入口递归扫描，共检查 123 个文本资源、265 条字面资源引用，另展开 38 个房间、材质和声音动态路径。必需输入缺失数为零；字面引用按出现次数计，不是去重文件数。着色器对原水体与近场反射 include 的依赖也包含在扫描内，因此新目录不能脱离原项目独立运行。准确结果见本次 `portability_report.json`。

有八条明确排除记录，不作为缺失输入误报：

- 五条 `res://output/...` 为已有截图/诊断的写入目标，不是输入资源。
- 两条声音 `%s` 模板按 `CLIP_NAMES` / `GAIT_CLIPS` 全部展开验证。
- 原有 `scripts/art_pass/character/natural_pool_avatar.gd` 的可选默认路径 `res://assets/character_refinement/model_contract.json` 在基线即不存在。已有逻辑检查导入场景内嵌合约并保留原模型回退；回退模型文件存在。该继承问题没有被伪报为新翼新增缺失文件，也未擅自修补原角色。

另有此前的官方 Godot 4.6.3 独立导出探针：在极小临时项目中复制现有 Windows 导出预设，导出 PCK 后从空目录启动检查，五个 `.geometry.json` 全部能够由 FileAccess 读取。追加显式 JSON include_filter 的对照包结果相同，当前预设没有已证实的 JSON 丢失问题。该探针不导入真实项目、不使用生产缓存，也不代表完整 Windows/定制引擎导出验证。本次只读源闭包复核未重新执行该导出探针。

证据：`tests/reference_wing/portability_export_report.json` 与对应导出/运行日志。

## 建议交付清单

机器可读的逐文件建议清单与哈希：`tests/reference_wing/portability_delivery_manifest.json`。本次包含三个集成改动、78 个运行时新增文件和 70 个作者源/脚本文件。作者清单显式包含生产必需的 `water_rooms_joint_manifest.json`，不以通配方式接纳其他候选 JSON。它是闭包建议清单，不是最终打包授权或最小文件清单；最终交付应另用经过审查的明确 allowlist。

建议以原项目提交 `351fcd6f8f2bb5fe21851482e2526dfa262ef406` 为完整基线，加入：

1. `assets/models/reference_wing/`：五个 GLB、五个几何 JSON 和新模型的 `.import` 配置。
2. `assets/materials/reference_wing/`：十张 PNG、`material_manifest.json` 和新图的 `.import` 配置。保留新图导入配置，避免数据图被重新猜作普通法线/透明贴图。
3. `scripts/reference_wing/`、`shaders/reference_wing/`：正式运行时脚本、着色器及其新 UID。
4. 上表五个 `.blend`、各源目录 `.gdignore`、正式生成/检查脚本，以及 `tools/materials/reference_wing/`。源文件用于编辑；游戏运行不要求安装 Blender。
5. 仅三个已允许的原文件集成改动：`scripts/main.gd`、`scripts/app/world_restart.gd`、`scripts/rendering/rt_material_refresh.gd`。
6. 定稿后的新翼说明和必要 QA 证据，独立作为交付说明，不替代运行时资源。

排除：`.godot/`、Python 缓存、`.blend1` 备份、临时渲染与未批准候选。特别不接受 `colonnade_pier_teal_candidate.blend` 或 `water_rooms_pier_candidate.py` 进入正式源交付清单；候选通过批准并正式替换后须重跑本检查。

## 作者源重建入口与最小依赖

以下为静态源码和文件存在性复核；本次未重建生产资产，故不声称重新生成的二进制与当前保存件逐字节相同。三类生产生成器自行创建 `output/` 下的诊断输出目录，不读取既有 QA 图像、候选 `.blend` 或 `output/` JSON 作为建模输入。原参考图名称仅作来源标签，不是生成器要打开的文件依赖。

五个 `.blend` 和上述十张贴图可以独立编辑；若还要从代码重新生成资产，应保留以下精确入口与依赖：

- 阶厅：`tools/blender/reference_wing/stair_gallery/build_stair_gallery.py`、同目录 `stair_crown_bindings.py` 与 `stair_diagnostic_camera.py`。
- 三个水厅：`tools/blender/reference_wing/water_rooms_build.py`、同目录 `water_rooms_joint_helpers.py`、`water_rooms_joint_manifest.json`、`water_rooms_lighting_helpers.py`。
- 休息室：`tools/blender/reference_wing/lounge_build.py`；它不导入其他项目 Python 模块，也不读取外部贴图。
- 阶厅和水厅共有：`tools/materials/reference_wing/blender_materials.py`、`assets/materials/reference_wing/material_manifest.json`，以及七张作者材质输入：`full_normal_gl_16.png`、`glaze_orm_2k.png`、`ref5_crown_normal_gl_16.png` 和四张 `ref_tile_*_albedo_2k.png`。共享材质工厂初始化全套角色，所以生成器的输入集合比部分已保存水厅的实际依赖更多。
- 重新生成全部十张贴图及共享数学 shader include：`tools/materials/reference_wing/generate.py` 和 `surface_math.py`；需要 Python 的 NumPy 与 Pillow。生产 crown 数学已在 `surface_math.py`，不依赖历史 `crown_trial_math.py` 或候选生成脚本。

### 核心重建命令（不依赖 Bash 或 Linux 图表工具）

从项目根目录执行。以下命令适合在已把 Blender 4.3.2 与 Python 加入 PATH 的 Windows 命令提示符中手动运行，也可把 `blender` 替换为本机 Blender 的完整可执行文件路径。这里只核对命令及依赖，未在 Windows 执行或验收。

阶厅按顺序运行三步：

```text
blender --background --threads 1 --python-exit-code 1 --python tools/blender/reference_wing/stair_gallery/build_stair_gallery.py
python tools/blender/reference_wing/stair_gallery/inspect_stair_export.py
blender --background --threads 1 --python-exit-code 1 --python tools/blender/reference_wing/stair_gallery/measure_stair_contacts.py
```

其余四个房间的核心入口：

```text
blender --background --threads 1 --python-exit-code 1 --python tools/blender/reference_wing/water_rooms_build.py
blender --background --threads 1 --python-exit-code 1 --python tools/blender/reference_wing/lounge_build.py
```

这些命令不渲染、不启动 Godot，也不需要旧的 `output/` 目录内容。使用已交付贴图即可，不需要先运行贴图生成器。

重要：这是重建流程，不是只读验收。建模步骤会覆盖对应正式 `.blend`、GLB 和几何 JSON；阶厅后两步也会重写几何 JSON，包括浮点数据和诊断字段。应在备份或独立项目副本中运行，不能把“结构检查脚本”一概当成安全的只读验证。重建后须重新检查闭包、哈希和运行时合约；不能沿用本次冻结资产的哈希结论。仅检查现有资源依赖时使用文末 `portability_audit.py`，不要运行上述重建或后处理命令。

### 可选完整 QA 包装器

阶厅完整重建包装器 `tools/blender/reference_wing/stair_gallery/rebuild_stair_gallery.sh` 还顺序调用以下同目录脚本，交付该包装器时不可遗漏：

1. `inspect_stair_export.py`：检查 GLB，并向生产几何 JSON 写入 `runtime_export_summary`，不是严格只读脚本。
2. `measure_stair_contacts.py`：测量支承并更新生产几何 JSON 的支承字段与 `independent_support_measurement`，不是严格只读脚本。
3. `verify_stair_proxy_clearance.py`：生成碰撞净空 QA 报告。
4. `draw_stair_sections.py`、`rasterize_stair_sections.py`、`draw_stair_plan.py`：生成剖面和俯视 QA 图。光栅化读取同一次流程新生成的 SVG，不要求预存 QA；后两个脚本需要 Pillow，且当前写死 Linux DejaVu 字体路径，因此完整图表包装器不能直接宣称 Windows 可移植。核心建模生成器不依赖这些字体或图表。
5. 仅在显式传入 `--render` 时调用 `render_stair_preview.py`，不是无渲染重建的前提。

阶厅主生成器已经内置 17 盏灯的 linear/native spot/radius/angle 字段、750×750 主参考相机构图，以及 crown 和独立诊断相机绑定。`update_stair_light_metadata.py`、`update_stair_square_framing.py` 和 `add_stair_diagnostic_camera.py` 是历史迁移工具，不是当前干净重建的补丁步骤；尤其灯光迁移工具带有旧 GLB 哈希前置条件，不应在新资产上盲目重跑。它们不替代上面两个仍会补写几何 JSON 的正式后处理脚本。

三个源目录中的 `.gdignore` 应一并保留：`stair_gallery/source/.gdignore`、`water_sources/.gdignore`、`lounge_sources/.gdignore`（均相对 `tools/blender/reference_wing/`）。它们让 Godot 忽略作者 `.blend`，不影响 Blender 编辑。

## 原项目保护

与基线相比，28 个原资产 `.import` 的变化属于中央 Godot 4.6 导入产生的噪声，仅报告、不修改；另记录其生成的新 UID、导入 sidecar 和原角色纹理提取文件。

排除这些生成噪声后，受版本管理的改动精确限定为上述三个集成脚本。`project.godot`、`export_presets.cfg`、`native/`、原模型/材质二进制、`scripts/water/`、`shaders/source_water/`、`source_provenance/` 均未被本轮改写。完整噪声清单在报告 `tracked_scope` 中；不要把它们当成新翼修复提交。

## 重复执行

在项目根目录执行：

```sh
python tests/reference_wing/portability_audit.py --blender /usr/bin/blender
python tests/reference_wing/portability_export_probe.py --godot /usr/local/bin/godot
```

第一个命令成功退出要求五套正式资产、贴图校验、资源闭包、独立源复制、基线保护与前后哈希全部通过。第二个命令输出现有预设和显式 JSON 过滤对照的独立 PCK 结果。资产或代码变更后应重新生成证据，不沿用旧哈希结论。
