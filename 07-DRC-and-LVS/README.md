# 物理验证（DRC & LVS）

本阶段将 [ICC2 紧凑版](../06-Place-and-Route/) `cali_logic/packed_final` 的版图交给 Siemens Calibre Interactive 和 RVE。DRC 检查 SMIC18 版图规则，LVS 比较从 GDS 提取的电路和参考 CDL，ERC 补查电源路径。

| 步骤 | 软件和主要操作 | 目的与结果 |
| --- | --- | --- |
| 准备版图 | 在 ICC2 从同一紧凑版检查点导出 1 nm 数据库单位的 GDS，在 Calibre Inputs 指定 GDSII 和顶层 | 核对导出前后的版图层次和图形，使用同一输入运行 DRC、LVS |
| 跑 DRC 并读报告 | 在 Calibre Interactive 选择 SMIC18 DRC 规则，设定输出，在 RVE 按规则查看标记 | 执行 421 个规则检查。报告记录芯片边界和整体金属密度项，移交顶层复核 |
| 准备 LVS 参考网表 | 用 v2lvs 转换布线后带电源网表，再核对工艺单元 CDL 的全局供电、器件子类型和尺寸单位 | 让参考器件与版图提取使用一致的比较表示 |
| 追踪剩余连接差异 | 用 Calibre 报告及层次对照定位失配，修正参考 CDL 中 26 对仅大小写不同的内部网名 | 保留 Verilog 中原本独立的网络。确认标准单元内部结构及器件参数 |
| 复跑 LVS 和核查 ERC | 在 Calibre Interactive 载入 v5 CDL，复跑并检查 `lvs.report`。对照 ERC 标记与 TIELO 提取网表 | 块级 LVS 为 `CORRECT`，96 个端口、12,671 条网、17,798 个比较实例匹配。定位一条标准单元内部偏置路径 |

## 工程文件

| 文件 | 功能与用途 |
| --- | --- |
| [`scripts/repair_cdl_net_names.py`](scripts/repair_cdl_net_names.py) | 对本项目的 v4 CDL 顶层修复网名大小写冲突，生成 v5 副本。供保有原始 CDL 的成员复现最后一次修正 |
| [`calibre/drc_wrapper.tvf.example`](calibre/drc_wrapper.tvf.example) | DRC 控制文件示例。记录 GDS 顶层、ASCII 标记库、汇总报告、规则入口和每条规则的结果上限 |
| [`calibre/lvs_wrapper.svrf.example`](calibre/lvs_wrapper.svrf.example) | LVS 控制文件示例。记录两侧顶层、v5 参考输入、LVS 报告和供 RVE 读取的结果目录 |
| [`reports/drc_rule_counts.csv`](reports/drc_rule_counts.csv) | 汇总本轮七类有输出的 DRC 规则、标记计数和顶层复核项 |
| [`reports/verification_summary.md`](reports/verification_summary.md) | 保存比较结果、失配诊断及 ERC 处置依据，列出本地原始证据 |
| [`reports/input_fingerprints.txt`](reports/input_fingerprints.txt) | 记录本轮 GDS、参考网表和报告的 SHA-256，用于对照工程归档 |

Calibre 版本为 v2025.1_16.10。版图、完整 CDL、原始结果库和晶圆厂规则由本地工程保管。当前状态为**块级 LVS 通过，DRC 与 ERC 待顶层签核复核**。最终整片版图需在芯片边界和金属填充定稿后重跑物理验证。
