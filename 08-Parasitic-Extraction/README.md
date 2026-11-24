# 寄生参数提取（PEX）

本阶段从 [物理验证](../07-DRC-and-LVS/) 交接的 `cali_logic` 紧凑版 GDS 和 v5 CDL 开始，使用现有 SMIC18 六层工程规则，在 Calibre Interactive 的 xRC 模式下设置门级 RCC 提取。目标是把标准单元之间的布线电阻、对地电容和耦合电容交给静态时序分析。

| 步骤 | 软件与主要操作 | 目的与结果 |
| --- | --- | --- |
| 设置输入和提取边界 | 在 Calibre Interactive PEX 设置已通过 LVS 的 GDS、参考 CDL、H-Cells 和 x-Cells | 核对两侧顶层及标准单元边界，保存工程 Runset |
| 建立 PHDB | 在 Calibre Run Control 运行版图数据库阶段 | 图形界面已生成 PHDB，源网表比较报告为 `CORRECT` |
| 加载工程规则并计算 RCC | 使用本地 `cali_logic_9k_trial.svrf`，按同一套规则建立 PHDB，再生成 PDB | 独立 Calibre 验证的 LVS 为 `CORRECT`，PDB 报告 0 个错误和 4 个底层映射警告 |
| 配置 SPEF 导出 | 在 Calibre Outputs 选择 SPEF、Source Names 和 PrimeTime compatible，使用同次运行的 PDB 进行格式化 | 保存了目标输出设置。Calibre 图形界面的 PDB 复跑与 SPEF 导出待完成 |
| 工程版 STA 交接 | 在 ICC2 紧凑版副本以 `typ_trial` 导出带显式耦合的 SPEF，并核对文件结构 | 已得到可供工程版 STA 使用的 SPEF，包含 3,367 条网络 |

## 工程文件

| 文件 | 功能与用途 |
| --- | --- |
| [`calibre/pex_wrapper.svrf.example`](calibre/pex_wrapper.svrf.example) | 保存 GDS、参考 CDL、PHDB 输出、SPEF 格式和现有提取规则的配置骨架。使用本地工程路径填写 |
| [`reports/extraction_summary.md`](reports/extraction_summary.md) | 记录 Calibre 图形界面和独立检查的完成状态、警告与工程交接 |
| [`reports/spef_validation.txt`](reports/spef_validation.txt) | 记录实际 ICC2 SPEF 的网络、接地电容、耦合电容和电阻计数 |
| [`reports/input_fingerprints.txt`](reports/input_fingerprints.txt) | 保存本地 Runset、单元边界清单和工程版 SPEF 的校验值 |

完整工艺规则、版图、参考网表、数据库和 SPEF 保存在本地工程。现有结果用于块级工程分析。流片签核需使用晶圆厂认可的 9K 提取规则对最终版图复提。
