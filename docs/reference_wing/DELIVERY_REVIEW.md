# SOURCE 更新交付审查

审查日期：2026-10-24。基线：`351fcd6f8f2bb5fe21851482e2526dfa262ef406`。

## 当前结论

安装器和准备器的现有 38 项模拟测试、独立 18 项对抗测试、紧凑交付 30 项测试全部通过，共 86 项。另以只读方式，将保留的干净项目逐文件 SHA256 与该 Git 提交的完整 archive 比对，1,018 个文件一致。

**这不是最终更新包验收。** 当前只对小型模拟夹具制包，没有生成最终资产包，也没有将最终资产应用到干净基线，没有运行 Godot、Blender 或 Windows CMD。最终清单冻结后仍须执行下面的真实基线安装测试。

本轮新增紧凑入口、无损 ZIP 构建器与基线依赖生成器，并更新 CMD、准备器复制入口和相关测试/说明。`update_source.py` 原安装核心逐字节未变；没有修改运行脚本、资产或干净基线。

## 已验证的行为

- 所有载荷 SHA256 与目标旧值先检查后写入；错误版本、损坏/缺失载荷、新路径冲突、目录/文件冲突均安全拒绝。
- 原文件备份、持久收据、每个文件的原子替换和恢复流程工作正常。独立测试在四个模拟载荷文件的每个替换边界强制结束子进程，均能从收据回退。
- 模拟写入错误覆盖每个载荷边界；成功恢复后原源码字节和权限一致。
- 完整安装后的后续修改、删除，以及用户手动将单个文件改回旧值，均阻止整次回退；拒绝时不改动其他源码或收据。
- 无关文件、用户后来新增的文件与空目录保留；未列入清单的额外 payload 文件不会复制。
- 重复应用、重复回退、干净回退后再应用的行为已覆盖。不伪造手动覆盖项目的旧版本备份。
- 路径检查覆盖穿越、绝对路径、Windows 保留名、控制字符、大小写/Unicode 归一化重名、文件/目录前缀冲突、符号链接与悬空符号链接。
- Python CLI 的中文、空格、`&`、括号、百分号与感叹号路径通过本机测试。这是 argv 行为测试，**不是 Windows CMD 执行验证**。
- 收据篡改、丢失备份、损坏备份、同一更新 ID 对应不同清单和不完整备份准备均拒绝。

## 单 ZIP 紧凑入口与必要基线资源

`compact_source_update.py` 自动准备内部 `payload.tar.xz`，再调用不变的原安装核心。外层 ZIP 只含九个普通文件：manifest、安装说明、核心、入口、两个 CMD、压缩载荷、紧凑元数据、基线必要资源清单。无需用户手工解开内部压缩包。

严格 USTAR 普通文件检查、精确 tar 长度、压缩 SHA256、每个文件大小/SHA256、完整闭包、XZ 256 MiB 解码内存上限和展开字节上限均在项目安装前生效。PAX/GNU 扩展、链接、设备、重复/额外/缺失成员、越界路径、尾部隐藏数据和损坏压缩流均拒绝。失败的唯一暂存目录保留供检查；不递归清理未知目录。重复准备只核对已存在的完整 payload，缺少 compact descriptor 不静默降级。

准备锁只保护互相配合的入口，不保证对抗外部并发目录改动；所有命令都要求停止这种改动。包与项目必须为互不包含的独立目录，确保 `check` 准备包时仍不改项目。

基线依赖清单使用最终 portability report 的 303 个字面量/展开动态种子，加上全局类、递归资源/目录前缀、GLB 外部 URI、扩展描述符以及绑定原文件 SHA256 的 Godot 二进制依赖查询结果。当前只读预览得到 234 个必要不可变基线文件，185 个可再生 `.import`/`.uid` 元数据不作哈希门槛。最终数量须以冻结包报告为准。旧值与从 351f archive 验证得到的 1,018 文件 inventory 核对，不从任意当前副本推测。

测试明确区分：缺失/改动必要 GLB、shader 等原始资源会在写项目之前拒绝；用户无关文件不受约束；编辑器重写基线导入元数据可接受。新随包提供的 import 配置仍受严格 payload/回退哈希约束。回退不需要 archive、payload 或必要基线检查通过，仍由原核心保护后续修改。

## 安装说明与范围核对

`INSTALL-源码更新.md` 明确交付为一次累计 **SOURCE 更新**，不是完整项目、PCK、可执行文件、引擎或 Android 包，也不依赖以前的中间补丁。

说明要求用户已有完整 351f 基线和其定制 Godot 4.8；安装器只校验清单与锚点，不能证明用户的整个项目都是该提交。最终画面、NR/RT、Windows/NVIDIA 与性能由用户在本机验证，不把云端安装测试或官方 4.6 headless/CPU 证据说成目标 4.8 图形验收。

CLI 示例保留路径引号；CMD 拖放使用 `%~1`，交互输入说明要求不要再加外层引号。CMD 关闭 delayed expansion 并引用项目/脚本路径。原生 `cmd.exe`、Windows 文件占用语义、junction 与 reparse point 实测仍未进行。

更新期间必须关闭编辑器并停止并发修改。安装器锁只约束另一个安装器，不能锁住所有外部编辑器或目录链接变更；不能宣称任意并发修改下绝无竞态。回退保护验证针对操作前已有后续改动及已覆盖的受控中断，不是操作系统级整包事务。

## 冻结后的最终清单门槛

旧 `portability_delivery_manifest.json` 只是较早的建议，不能直接作为最终清单。最终 payload 应来自同一次冻结状态，至少覆盖：

1. 五房间各自的 `.glb`、`.glb.import`、`.geometry.json`。
2. 五份最终可编辑 `.blend` 与三个源码目录的 `.gdignore`，保留目录结构，避免 Godot 自动导入作者文件而要求 Blender。
3. 生产 `scripts/reference_wing/`、`shaders/reference_wing/`、材质图和导入设置、必要的原项目集成文件。
4. 重建脚本实际依赖的本地 Python helper 与数据，例如水房接缝 helper/JSON、新阶厅 crown 绑定 helper、材质生成与数学源。若保留对应角色，也应包含其新 normal 图。
5. 最终安装说明、范围与验收限制。排除 `.godot`、缓存、输出、旧包、候选资产、`.blend1`、参考照片、凭证、无关原资产的自动 import 改动及 Android 改动。

检查脚本会解析源文件中的本地 Python imports 和相邻 JSON 数据，并检查字面量 `res://` 资源可由 payload 或完整基线满足。原脚本中 `res://output/` 下的运行生成日志/截图目标会单独记录，不错当作待交付的输入资源。动态拼接的五房间与材质资源由明确目录/房间列表补充检查。五个 GLB 的 JSON chunk 还会检查无遗漏的外部 buffer/image URI。

该静态检查不代替 Blender 内部图片链接与可重建结果验证，也不代替 Godot 运行或视觉验收。

仅有三条明确的测试夹具排除：`ui_contract.gd` 中引用的 `ui_host.gd`、`ui_desktop_settings.gd`、`ui_sources.json` 由随包的 `ui_run_contract.py` 在独立临时项目中写入，不是生产资源。校验器核对这三个精确写入目标，并在报告中逐项记录来源/生成器。对生产代码的相同引用、其他缺失路径、未交付或不再写入全部三项的生成器，不适用此排除。回归测试实际执行了 Python 夹具生成阶段，并以 mock 阻止 Godot 子进程运行。

## 冻结后执行顺序

集成负责人先确认最终清单并生成唯一候选目录。之后执行：

```sh
PYTHONDONTWRITEBYTECODE=1 python tests/reference_wing/delivery_review/verify_final_package.py \
  --package "最终未压缩更新包目录" \
  --baseline "保留的干净351f完整项目目录" \
  --report "tests/reference_wing/delivery_review/final_preflight.json"
```

默认对项目仅检查并输出报告，不应用更新；紧凑包可能在自己的独立目录展开 payload。它还在报告旁输出完整 `.baseline_inventory.json`，供紧凑构建器使用。它重新核对完整基线、清单旧值、当前冻结源的新值、包装内安装器与说明，以及资源依赖。如果任何最终文件又变了，必须重新冻结、准备清单和验证，不能沿用早前通过记录。

得到真实包测试授权后，增加一个尚不存在的测试复制目录：

```sh
PYTHONDONTWRITEBYTECODE=1 python tests/reference_wing/delivery_review/verify_final_package.py \
  --package "最终未压缩更新包目录" \
  --baseline "保留的干净351f完整项目目录" \
  --exercise-copy "tests/reference_wing/delivery_review/exercise-final-唯一标识" \
  --report "tests/reference_wing/delivery_review/final_actual_base.json"
```

它只在新复制目录测试，原始基线不改动。顺序为：

1. `check` 为 `ready`，文件字节、权限与修改时间不变。
2. `apply` 为 `installed`；完整源树恰好等于原基线加 allowlist，没有无关变动。
3. 再次 `apply` 为 `already_applied`，连收据和修改时间都不重写；`status` 全部匹配。
4. 在复制目录制造一处后续修改，确认整次回退拒绝且所有文件保持原样，再撤销这处测试修改。
5. `rollback` 为 `rolled_back`；所有原文件字节/权限恢复，新增 payload 消失，本地备份/收据保留。
6. 再次回退为 `already_rolled_back` 且不改文件；再次核对原始干净基线没有变化。

测试复制目录含整个基线和本地备份，**不得放进交付包**。失败时保留它与报告供检查，不盲目删除或强制覆盖。

## 证据与复现

- `tests/reference_wing/delivery_review/review_status.json`：本轮结果、未运行项与被审查安装器的 SHA256。
- `existing_synthetic_tests.log`：现有 38 项测试日志。
- `adversarial_tests.log`：独立 18 项测试日志。
- `compact_tests.log`：紧凑交付 30 项测试日志。
- `all_delivery_tests.log`：独立与紧凑合计 48 项测试日志。
- `compact_review_notes.md`：独立代码审查、内存探针、修复事项与限制。
- `test_adversarial_delivery.py`：独立模拟用例，不修改生产或干净基线。
- `verify_final_package.py`：冻结后预检/真实基线复制测试工具，目前只在独立模拟夹具上验证其测试流程，包含冷启动紧凑包。

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests/reference_wing -p 'install_test*.py' -v
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests/reference_wing/delivery_review -p 'test_*.py' -v
```

若安装器内容变化，重新运行两组测试并更新审查哈希。只有最终包报告实际通过后，才能宣称“该最终 SOURCE 包在完整 351f 基线上的安装与回退通过”。
