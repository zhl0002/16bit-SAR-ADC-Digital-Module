# cali_logic 工程版 PEX 核查结果

## Calibre xRC

- 图形界面以 ICC2 最终紧凑版的 1 nm GDS 和 LVS v5 CDL 为输入，顶层均为 `cali_logic`。H-Cells 与 x-Cells 清单对应 117 种标准单元。
- 首次图形界面运行生成 `svdb/cali_logic.phdb`，LVS 比较为 `CORRECT`。保存的 `cali_logic_pex.runset` 用于接续配置。
- 本地已备有工程试算规则入口 `rules/9k_itf_trial/cali_logic_9k_trial.svrf`。独立验证以同套规则重建 PHDB 并执行 Gate Level RCC，LVS 为 `CORRECT`，PDB 报告 **0 个错误、4 个警告**。警告指向 `ntd`、`ptd`、`psd`、`nsd` 未映射到校准层。
- 图形界面下一次实际运行需要在工程规则下重建 PHDB，再复跑 PDB 并导出 `cali_logic.spef`。

## ICC2 工程版 SPEF

从 `cali_logic/packed_final` 副本以 `typ_trial` 导出显式耦合的 SPEF。已核对设计名、RC 记录、网络集合与文件校验值。其统计与 Calibre 的 PDB 日志分别归档。见 [SPEF 校验摘要](spef_validation.txt)。

| 本地文件 | 用途 |
| --- | --- |
| `calibre_gui_01/cali_logic_pex.runset` | 保存现有 Calibre 图形界面的项目输入、提取模式及输出配置 |
| `cali_logic_standard_cells.hcell`、`cali_logic_standard_cells.xcell` | 保存标准单元匹配和布线提取边界 |
| `cali_logic_9k_trial.svrf`、`rules.C`、`rules.R` | 工程提取规则入口及电容、电阻规则 |
| `svdb/cali_logic.phdb`、PDB、`cali_logic.spef` | Calibre 的版图连接数据库、寄生数据库和最终交换文件 |
| `icc2_engineering_01/output/cali_logic_pex_engineering_coupled.pack_seed_par_25.spef` | 供工程版 STA 试跑的已校验寄生参数 |

工程试算角用于块级分析。正式签核需按实际工艺角和最终版图复提。
