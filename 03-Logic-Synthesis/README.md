# 03 逻辑综合

本项目把 [02 阶段已验证的 `cali_logic` RTL](../02-RTL-Design/rtl/cali_logic.v) 综合成标准单元门级网表。记录使用 Synopsys Design Compiler W-2024.09-SP3，图形界面为 Design Vision。映射使用 SMIC18 典型库，试综合时钟为 10 ns。

## 步骤与目的

| 步骤 | 具体做法和软件入口 | 目的与完成标志 |
| --- | --- | --- |
| 1. 分析 RTL | 在独立运行目录打开 Design Vision，使用 **File → Analyze**，选择 `cali_logic.v` 和 Verilog 格式 | 确认 DC 可以解析目标源码。以 Console 的 `Presto compilation completed successfully` 为检查点 |
| 2. 展开并检查结构 | 用 **File → Elaborate** 选择 `WORK` 中的 `cali_logic`，保持默认参数。然后 **File → Link Design**、**Design → Check Design** | 确定参数化位宽和逻辑层次，解析设计引用，人工核对结构警告。A/B 底板码间的直接连线来自 RTL 的两位互换 |
| 3. 建立试用时钟约束 | 选中顶层 `clk_i`，用 **Attributes → Specify Clock** 建立 `cal_clk`。周期 10 ns，上升和下降沿为 0 ns、5 ns。查看时钟报告核对名称、端口和周期 | 让 DC 以明确的时序目标优化寄存器间路径，避免在无时钟的条件下得到误导性的报告 |
| 4. 映射标准单元 | 运行 **Design → Compile Design**，保持默认优化选项 | 把寄存器、控制和算术逻辑映射到标准单元。Console 出现 `Optimization Complete` 表示本轮综合结束 |
| 5. 复查连接、时序和面积 | 再做 **Design → Check Design** 和 **Timing → Check Timing**。用 **Timing → Report Timing Paths** 查 `max` 建立时间，用 **Design → Report Area** 查单元数和面积 | 把优化后的结构、约束覆盖和内部最紧张路径分开核对。记录未指定输入到达时间的 `TIM-216` 警告 |
| 6. 保存复核用文件 | 用 **File → Save As** 选 Verilog 并保存设计层次，在 Design Vision 底部 Console 用 `write_sdc cali_logic_trial_10ns.sdc` 导出约束。在报告区使用 **Save Report to File** 保存结果 | 固定门级电路、约束与面积时序证据，作为形式等价和后续分析的输入 |

## 工程文件

| 文件 | 功能和用途 |
| --- | --- |
| [`scripts/run_synthesis.tcl`](scripts/run_synthesis.tcl) | 在 DC 中复跑独立模块综合，按顺序分析、展开、链接、加载约束、映射并导出。使用与图形流程相同的 `compile -exact_map` |
| [`constraints/cali_logic_trial_10ns.sdc`](constraints/cali_logic_trial_10ns.sdc) | 在 `clk_i` 上定义 10 ns 的 `cal_clk`。供综合和后续时序复查使用 |
| [`netlist/cali_logic_mapped.v`](netlist/cali_logic_mapped.v) | 原试综合的门级 Verilog 网表，记录标准单元和连线。它可作为形式等价验证的实现侧输入 |
| [`dc_db/`](dc_db/) | 原 Design Vision 保存的 DDC 项目快照。包括顶层 `cali_logic.ddc` 与三个层次子设计的 DDC 文件，重新打开后可配合匹配的时序库检查电路和报告 |
| [`formality/cali_logic.svf`](formality/cali_logic.svf) | 用综合脚本重新生成的变换指导文件。重跑网表的 Verilog 模块内容与仓库网表逐字节一致，SVF 已通过 Formality 读入检查。以后和对应 RTL、网表一起用于等价验证 |
| [`reports/area.rpt`](reports/area.rpt) | 原面积报告，保留单元数、缓冲器数量及面积数据 |
| [`reports/timing_setup_10ns.rpt`](reports/timing_setup_10ns.rpt) | 原建立时间报告，保留起点、终点、逐级延迟和余量 |

有匹配的 SMIC18 `typical.db` 和 DC 环境时，可从本目录用以下命令复跑。脚本另外生成一套可重新打开的 DDC、与该次网表配套的 SVF，以及结构、约束、面积和时序报告。`SYNTH_OUT` 指定一个尚未存在的输出目录。

```bash
script="$PWD/scripts/run_synthesis.tcl"
scratch=$(mktemp -d)
cd "$scratch"
SMIC18_DB=/path/to/typical.db SYNTH_OUT="$scratch/results" \
    dc_shell -no_home_init -no_local_init -f "$script"
```

## 本次试综合结果

| 项目 | 结果 |
| --- | --- |
| 顶层与运行配置 | `cali_logic`，默认 RTL 参数，典型库，10 ns 临时周期 |
| 标准单元总数 | 3,162 |
| 标准单元总面积 | 82,192.018520（库面积单位） |
| 报告中的最紧张建立路径 | `state_q_reg[3]` → `sum_q_reg[19]`，路径组 `cal_clk` |
| 建立时间余量 | `+0.03 ns`（`MET`），适用于本次试综合条件 |

- [门级 Verilog 网表](netlist/cali_logic_mapped.v)记录综合后的标准单元实例及连接。
- [试综合 SDC](constraints/cali_logic_trial_10ns.sdc)记录 `clk_i` 上的时钟定义和单位。

10 ns 是探索用约束，外部端口时序预算还需结合系统接口确定。面积是单元库面积之和，实际布局占地还包含实现开销。下一步做形式等价验证，比较本目录网表与第 02 阶段 RTL。正式目标确定后，再用相应约束和工艺角重新综合和检查时序。
