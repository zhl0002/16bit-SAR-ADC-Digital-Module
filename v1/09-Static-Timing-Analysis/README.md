# 静态时序分析（STA）

本阶段在 Synopsys PrimeTime W-2024.09-SP3 中检查 `cali_logic` 紧凑版布线后的时序。输入为 [P&R 阶段](../06-Place-and-Route/)交付的门级网表和 SDC、SMIC18 `typical` 时序库，以及 [PEX 阶段](../08-Parasitic-Extraction/)交付的 ICC2 工程版 SPEF。本轮为功能模式，`scan_en = 0`，试分析时钟 `cal_clk = 10 ns`。

| 步骤 | 软件与主要操作 | 目的与结果 |
| --- | --- | --- |
| 建立时序设计 | 在 PrimeTime 图形会话读入时序库和布线后门级网表，链接顶层 | 将实例关联到标准单元时序模型，确认顶层为 `cali_logic` |
| 应用功能模式约束 | 读入 P&R SDC，检查时钟报告 | 确认 `cal_clk` 由 `clk_i` 驱动，周期为 10 ns，分析功能模式 |
| 标注互连寄生 | 读入 ICC2 SPEF，检查寄生覆盖率 | 3,367 条有驱动的内部及边界 pin-to-pin 网络全部标注为 RC 网络，另有 61 条无驱动内部网络 |
| 检查时序覆盖 | 运行 `check_timing` | 记录缺少输入延时的 9 个输入、缺少外部驱动的 12 个端口和缺少最大延时约束的 121 个输出端点 |
| 检查实际路径和汇总 | 在 PrimeTime 查看最差 max/min 路径及 Endpoints Summary | `cal_clk` 的 Setup、Hold 各统计 584 个端点，违例数均为 0 |
| 归档会话和报告 | 保存本地 PrimeTime 会话和归档报告 | 记录环境、实际路径和完整时钟树增量延时，供复核和顶层集成 |

| 检查 | 最差寄存器间路径 | 裕量 |
| --- | --- | ---: |
| Setup | `bit_q_reg[2]` → `weight_q_reg[6][4]` | +0.0136 ns |
| Hold | `target_q_reg[1]` → `weight_q_reg[10][2]` | +0.3094 ns |

## 工程文件

| 文件 | 功能与用途 |
| --- | --- |
| [`run_engineering_sta.tcl`](run_engineering_sta.tcl) | 在新 PrimeTime 会话中复跑。通过 `STA_LIB`、`STA_NETLIST`、`STA_SPEF` 指定本地库、门级网表和 SPEF，再用 `pt_shell -f` 执行脚本 |
| [`constraints/cali_logic_compact_10ns.sdc`](constraints/cali_logic_compact_10ns.sdc) | 本轮 P&R 导出的约束，保留时钟、传播设置和扫描使能的功能模式取值 |
| [`reports/clocks.rpt`](reports/clocks.rpt) | 核对时钟名、波形、周期和源端口 |
| [`reports/timing_summary.rpt`](reports/timing_summary.rpt) | 归档 `cal_clk` 路径组的 Setup／Hold 违例汇总 |
| [`reports/setup_reg_to_reg.rpt`](reports/setup_reg_to_reg.rpt)、[`reports/hold_reg_to_reg.rpt`](reports/hold_reg_to_reg.rpt) | 复核最差寄存器间路径及展开的时钟树。报告显示从 `clk_i` 经 CTS 缓冲到寄存器时钟引脚的逐级延时 |
| [`reports/check_timing.rpt`](reports/check_timing.rpt) | 定位缺失时序约束和驱动模型的对象 |
| [`reports/parasitics_annotation.rpt`](reports/parasitics_annotation.rpt) | 保存实际 SPEF 读入和标注统计。本机路径替换为文件名 |
| [`reports/input_fingerprints.txt`](reports/input_fingerprints.txt) | 核对复跑所需网表、原始 SDC、工程 SPEF 和发布版 SDC 的对应关系 |

本轮工程版 STA 已完成。10 ns `typical` 条件下的结果可作为 ADC 顶层集成的基线。模块级正式 STA 需要签核级寄生、正式时钟、I/O 时序预算及规定的 PVT 场景。整颗 ADC 的最终时序签核以顶层集成版为对象。时序库、布线后网表、完整 SPEF 和 PrimeTime 会话数据库保存在本地工程。
