# SOURCE INCREMENTAL UPDATE / 单 ZIP 源码更新

本交付是基于 `351fcd6f8f2bb5fe21851482e2526dfa262ef406` 的一次累计源码更新，包含本轮五个参考场景及其材质、可选镜头滤镜与参考细浪。它不是完整项目、PCK、EXE、Godot 引擎安装包或 Android 包，不依赖任何之前的中间补丁。

必须已经拥有上述基线的完整项目，以及自己使用的定制 Godot 4.8 引擎。本包不安装/下载引擎，不操作 GitHub、不切换 Git 分支、不执行 `git reset`，也不会操作其他电脑。最终画面、NR/RT 和性能由你在本机用原来的定制引擎验证；安装器通过不代表画面通过。

## 最短安装流程

1. 先确认你已有完整的 **351f 基线项目**，复制一份原项目备份，并关闭 Godot、游戏和会改写该项目的编辑器。
2. 把收到的 **一个 ZIP** 完整解压到项目之外的独立普通文件夹。不要把包放到项目里面，也不要手动解开内部 `payload.tar.xz`。
3. 已有 Python 3.9+ 时，把原项目文件夹拖到 `APPLY_SOURCE_UPDATE.cmd` 上，或双击它并输入原项目路径。它会自动校验并准备内部载荷，再安全应用；窗口会显示结果并停留。看到 `installed` 或 `already_applied` 才表示源码已就位。

不需要额外安装解压工具、引擎或 Python 第三方库。没有合适的 Python 时脚本只说明缺少什么，不会自动下载或安装软件。仍使用你原来的定制 Godot 4.8 打开项目；本包没有引擎，也不替你做本机画面验收。

## 安装前

1. 关闭该项目的 Godot 编辑器、游戏和会自动改写源码的编辑器。更新/回退期间不要同时改动项目。
2. 推荐先复制整个原项目做一份个人备份。安装器也会为它实际替换的源码建立本地回退备份，但不会替你备份其他文件。
3. 把单个 ZIP 完整解压到项目目录以外、也不是项目祖先目录的独立普通文件夹。保留其中所有文件；不要先把内部载荷手动覆盖进项目。
4. 准备 Python 3.9 或更新版本。安装器仅使用 Python 标准库，不下载软件，不改变执行策略，不需要管理员权限或账户凭证。
5. 目标目录必须直接包含 `project.godot`。Windows 路径含空格或中文可用，命令行中请保留引号。项目、更新包或备份路径不能穿过符号链接、junction 或其他重解析点；应使用普通目录。

## 先检查，再应用

如果喜欢命令行，在解压后的更新包目录打开终端，使用同一个入口执行：

```text
python compact_source_update.py check "D:\游戏项目\Pool Core"
python compact_source_update.py apply "D:\游戏项目\Pool Core"
```

Windows 也可把项目文件夹拖到 `APPLY_SOURCE_UPDATE.cmd` 上。双击时会询问项目路径；输入路径时不要再加一层引号。命令脚本优先使用 `py -3`，其次 `python`，没有合适的 Python 会说明原因，失败时停留显示错误。不自动安装任何依赖。

`check` 对所选项目只读，不创建项目备份、不改项目文件；但首次运行会在更新包自己的目录中校验并解开内部载荷。包必须位于项目之外，因此这个准备过程不属于项目修改。`apply` 也会自动准备载荷，然后先校验全部载荷 SHA256，再核对未变的 `project.godot` 锚点和每个待替换文件的基线 SHA256。只改清单内的文件。已有文件被你改过、新增路径已有内容、载荷缺失/损坏、路径异常时都拒绝更新，不会强制覆盖。无关文件不会被修改，也不会要求工作区必须全干净。

紧凑包入口还会核对本轮实际依赖、且不会被 payload 替换的基线资源清单：例如原 GLB/PNG、脚本、shader、音频、SCN/EXR 与扩展资源。缺失或内容不符时会在改项目之前拒绝；无关的个人文件和文档不受约束。这个清单绑定在紧凑包元数据中，旧哈希来自完整 351f Git archive，而不是当前编辑器临时导入结果。

基线已有的 `.import` 与 `.uid` 属于编辑器可再生成元数据，不作为这里的不可变哈希门槛；`.godot` 缓存也不要求存在。它们可由你的引擎重新生成，本包不会为了通过检查而删除或覆盖它们。新随包提供的 `.import` 则仍受 payload 的严格哈希检查。

这里校验的是更新清单、必要依赖和锚点，不是证明完整项目每个无关文件都等于该 Git 提交。因此仍须自行确认这是正确的 351f 基线完整项目，而不是其他版本的残缺文件夹。清单中的新增源码、GLB、`.blend`、贴图和相关说明均来自同一个最终累计版本。

成功输出 `installed`。所有目标内容已经一致时输出 `already_applied`，不重复写入。如内容已被其他方式手动覆盖、没有本次安装的本地备份，也可识别内容一致，但不能凭空恢复旧文件。

## 内部载荷如何准备

外层是普通 ZIP，包含清单、说明、安装入口、CMD 脚本与一个 `payload.tar.xz`。内部采用无损压缩；清单中的每个文件都保留，不是删减资产、降低纹理质量或单独的 PCK。Python 标准库自动处理，无须手动再解一层。

入口在解压前核对压缩文件的精确字节数和 SHA256，并将完整 manifest 与精确文件大小表绑定。只接受清单里的普通文件；重复路径、额外/缺失成员、绝对/越界路径、链接、设备文件、稀疏/PAX/GNU 扩展、超出大小限制和校验不符均拒绝。所有文件的大小、SHA256 和完整集合通过后，才发布整个 `payload` 目录，然后调用原安装核心。

准备使用包内唯一暂存目录和进程锁，不覆盖已有 payload。已准备完整时再次运行只校验，不重复解压。若已有 payload 不完整或被改动，会拒绝覆盖；若准备中断，错误会指出 `.poolcore-unpack-*` 暂存目录，保留供检查，不递归清理未知内容。重试会用新暂存目录，不把半成品当成功。

请预留内部文件展开、临时副本和项目备份所需空间；不要只按 ZIP 的大小估算。准备、更新和回退期间，不要同时修改包、项目或目录链接。

## 本地备份与回退

首次应用会在项目内建立：

```text
.poolcore-source-updates/<update_id>/receipt.json
.poolcore-source-updates/<update_id>/originals/...
```

`receipt.json` 记录完整清单、状态和原文件校验值；`originals` 保存被替换文件的原始字节。不要删改这个目录。它不属于交付载荷，不包含凭证，不上传到任何地方。新增的文件只会登记，不会假造原文件备份。

关闭编辑器后执行，或把项目文件夹拖到 `ROLLBACK_SOURCE_UPDATE.cmd`：

```text
python compact_source_update.py rollback "D:\游戏项目\Pool Core"
python compact_source_update.py status "D:\游戏项目\Pool Core"
```

回退直接读取项目内的收据与备份，不需要压缩 archive、已展开的 payload 或基线依赖检查通过。即使它们已丢失，也可保留 `compact_source_update.py` 与 `update_source.py` 两个入口/核心脚本，并使用本地备份中的实际 `update_id`：

```text
python compact_source_update.py rollback "D:\游戏项目\Pool Core" --update-id 实际更新标识
```

回退前会检查全部原文件备份和当前目标文件。对已完成的安装，必须每个目标仍与安装后的 SHA256 一致才会回退；若你之后编辑、删除或换掉了其中任意文件，整个回退会在改源码前拒绝，保留你的后续修改。先另存自己的改动并人工处理冲突，不要删除备份或强行覆盖。没有 `--force` 选项。

这里的“之后改动”也包括 Godot 自动重写：必要的新纹理 `.import` 设置随包提供，其中线性数据图 `bevel_slope_rg_2k.png` 与 `glaze_orm_2k.png` 的 `.import` 必须保持 `compress/mode=0`，不要为缩小包而使用有损/显卡压缩改变其数据。你的定制 4.8 编辑器在打开项目后可能自动改写 `.import` 或 UID 字段。这同样会使严格回退拒绝，即使你没有手工编辑。不要为通过回退而盲目删除或改回这些文件；保留原项目副本和冲突文件供对照。目标定制 4.8 的具体重写行为尚未验证。

回退只恢复清单内原文件并删除本次新增、且仍保持本次原样的文件。只移除本次记录的新建空目录，不递归删除目录。回退完成后备份和收据仍保留；可重复回退，也可以从干净回退状态再次应用同一个更新。

## 中断或失败

每个源码文件通过同目录临时文件、完整写入、同步后原子替换。整包不是操作系统级的单一原子操作，因此另有持久收据覆盖中途退出：

- 普通写入失败会立即尝试恢复原源码，成功时明确输出 `original source files were restored`。
- 强制结束进程/断电可能留下 `prepared`、`applying`、`rolling_back` 或 `rollback_failed` 状态。不要继续手动复制；先查看 `status`，再使用同一个 `rollback` 命令。它只接受本次安装旧值或新值，不覆盖第三种内容。
- 如果回退也失败，错误中会给出收据位置与原因。保留目录，解决文件占用、磁盘空间或权限问题后再回退。只有 `rolled_back` 才代表恢复完成。
- 若只留下备份目录却没有收据，表示备份准备尚未完成，源码写入尚未开始；安装器不会自行覆盖或删除这些备份。保留并检查该目录后再处理。
- 强制终止可能留下 `.poolcore-write-*` 临时文件。它们不是运行资源，也不会被本脚本递归清理；确认安装/回退状态后可人工检查处理。

务必不要在更新过程中同时编辑文件或改目录链接。安装器会检查路径、进程锁和替换前的文件值，但不能锁住 Godot、编辑器、杀毒软件或另一个账户的所有操作。SHA256用于完整性和版本匹配，不是数字签名；只运行来源可信的安装脚本与清单。

## 制包人员：最终冻结后才生成清单

仓库内的 `tools/reference_wing_delivery/prepare_source_update.py` 是准备器，不会自己选择文件。集成负责人提供逐行列出的明确文件清单；不接受通配符或递归目录。准备器从指定的原始 351f Git 对象读取旧哈希，从当前最终源码读取新哈希，生成一个未压缩的 `manifest.json + payload` 目录。不会提交、推送、导出 Godot 包或上传。

```text
python tools/reference_wing_delivery/prepare_source_update.py --project . --allowlist 最终清单.txt --output 新建暂存目录 --update-id 本次更新标识
```

不要现在凭工作目录的全部改动生成清单。最终范围由集成负责人确认，应覆盖五个房间的最终文件和必要集成点；排除 `.godot`、`output`、缓存、候选方案、原参考照片、密钥、过时包和无关 Android 修改。不要以测试中用的模拟资产清单替代最终清单。

展开 stage 校验通过、且最终清单冻结后，再创建紧凑外层包与唯一 ZIP。准备器不会删除展开 stage，压缩器也不会修改它：

```text
python tools/reference_wing_delivery/build_compact_source_update.py --stage 已验证展开目录 --output 新建紧凑包目录 --zip 新建交付文件.zip --baseline 干净351f项目目录 --closure-report tests/reference_wing/portability_report.json --baseline-inventory tests/reference_wing/delivery_review/exact_351f.baseline_inventory.json
```

依赖清单使用最终 portability report 的字面量/动态引用种子，再补全全局 class_name、相对 GLB 图片路径、声明的 native 扩展资源和已经查询过的二进制 Godot 资源依赖。二进制查询证据只针对绑定 SHA256 的原文件，不是渲染验收；若换成其他二进制资源会要求重新核实。`--baseline-inventory` 必须来自真实 351f archive 的完整验证，不要用当前工作副本自行猜旧哈希。源码验收工具会在报告旁生成同样的 `.baseline_inventory.json`。

压缩器逐项保留 manifest 的所有 payload 字节，按精确大小生成无扩展 USTAR，再用单流 XZ 无损压缩。它会重新流式检查解压后的每个 SHA256 与完整集合，再检查外层 ZIP 成员/CRC 并给出 ZIP 的 SHA256。路径若超出 USTAR 的可编码范围会明确失败，不静默改名。不得把测试复制项目、暂存目录或失败产物作为最终交付。只有内部展开 stage 的测试才可显式使用入口的 `--expanded`；普通紧凑包不使用这个选项，缺少 descriptor 会拒绝而不会静默绕过依赖检查。

安装器回归测试：

```text
python -m unittest discover -s tests/reference_wing -p "install_test*.py" -v
python -m unittest discover -s tests/reference_wing/delivery_review -p "test_*.py" -v
```

这些测试只验证模拟项目的安装/回退和防覆盖行为，不等于 Windows 执行验证、真实最终包验证或 Godot 图形验证。
