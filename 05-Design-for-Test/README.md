# 可测性设计（DFT）

本阶段以[第 03 阶段的 `cali_logic` 门级网表](../03-Logic-Synthesis/netlist/cali_logic_mapped.v)为输入。使用 Design Vision / Design Compiler 完成扫描插入，用 Formality 检查功能模式，再用 TestMAX ATPG 生成固定型故障向量，用 VCS 核对实际串行回放结果。

## 步骤与目的

| 步骤 | 软件与主要操作 | 目的与验收结果 |
| --- | --- | --- |
| 1. 读入综合结果 | 在 Design Vision 用 **File → Read** 读入 Verilog，指定本地 SMIC18 `typical.db`，链接 `cali_logic` | 从已经通过第 04 阶段等价验证的综合基线开始，解析标准单元实例 |
| 2. 定义扫描接口及协议 | 在 Console 配置 `clk_i` 测试周期 100 ns、时钟沿 45/55 ns、`rst_ni` 低有效。用 **File → Execute Script…** 加入 `scan_in`、`scan_out` 和高有效 `scan_en`，建立协议 | 用原有时钟和复位实施单条多路选择触发器扫描链。移位时复位保持无效 |
| 3. 预览、插入并导出 | 在 **Test → Run DFT DRC** 检查设计，用 Tcl 执行预览、插入和导出 | 插入后一条 `scan_chain_0` 串接 584 个扫描单元，插入后 DFT DRC 无违规 |
| 4. 验证插入后的功能模式 | 在 Formality 比较综合网表与扫描网表，加载插入指导 SVF；在 **Setup → Constants** 将实现侧的 `scan_en` 设为 0，然后匹配并验证 | 功能模式下 706 个比较点通过，失败为 0；匹配报告列出的新增实现端口为 `scan_en` 和 `scan_out` |
| 5. 建测试模型并执行 ATPG | 本轮在 TestMAX Shell (`tmax -shell`) 读入网表和单元功能模型，用 SPF 做 DRC，再运行固定型故障 ATPG 并导出串行 STIL | 协议解析零错误，实际追踪到 584 个扫描单元。报告覆盖率 99.88%，生成 349 个扫描向量 |
| 6. 在 VCS 回放向量 | 用 Python 脚本根据 STIL 生成测试平台，编译扫描网表和标准单元功能模型 | 349 个向量、205,101 个周期、246,743 次指定输出位检查全部通过 |

`scan_en=0` 时运行功能逻辑，`scan_en=1` 时移位。100 ns 是本轮测试协议周期。

## 关键工程文件

| 文件 | 功能与用途 |
| --- | --- |
| [`netlist/cali_logic_scan.v`](netlist/cali_logic_scan.v) | 扫描插入后的门级 Verilog，供等价验证、ATPG、门级仿真和物理设计读取 |
| [`test/cali_logic_scan.spf`](test/cali_logic_scan.spf) | 测试协议，定义扫描移位、捕获和时钟，供 TestMAX `run_drc` 使用 |
| [`physical/cali_logic_scan.def`](physical/cali_logic_scan.def) | SCANDEF，记录扫描链端点和单元顺序，供布局布线管理与重排扫描链 |
| [`formality/cali_logic_scan.svf`](formality/cali_logic_scan.svf) | 记录扫描插入指导，供插入后功能等价验证使用 |
| [`patterns/cali_logic_stuck_serial.stil`](patterns/cali_logic_stuck_serial.stil) | TestMAX 导出的原始串行向量，包含波形、激励和预期响应 |
| [`reports/cali_logic_stuck_faults.rpt`](reports/cali_logic_stuck_faults.rpt) | 24,862 条逐故障记录，供检查故障分类和定位未检测项 |
| [`reports/scan_preview.rpt`](reports/scan_preview.rpt)、[`scan_chains.rpt`](reports/scan_chains.rpt)、[`post_scan_drc.rpt`](reports/post_scan_drc.rpt) | 分别确认计划扫描链、实际扫描链及插入后规则检查 |
| [`reports/post_scan_lec.rpt`](reports/post_scan_lec.rpt)、[`functional_mode_constants.rpt`](reports/functional_mode_constants.rpt)、[`post_scan_unmatched.rpt`](reports/post_scan_unmatched.rpt) | 记录 Formality 结果、功能模式约束和新增扫描端口 |
| [`reports/atpg_summary.rpt`](reports/atpg_summary.rpt)、[`vcs_serial.rpt`](reports/vcs_serial.rpt) | ATPG 日志摘录与实际门级回放日志，供复核覆盖率及回放结果 |
| [`artifacts.sha256`](artifacts.sha256) | 校验本轮网表、协议、扫描链文件、插入指导及两份 ATPG 原始产物的文件内容 |
| [`scripts/`](scripts/) | 四份 Design Vision Tcl 用于建立协议、预览、插入和导出；Python 和 Bash 脚本用于 VCS 串行回放 |

四份扫描 Tcl 以脚本所在目录作为报告或产物的输出位置。将它们复制到独立的 DFT 运行目录，从已链接的 `cali_logic` 会话配置测试时钟、复位和单链模式后，按 `prepare_scan_protocol.tcl`、`preview_scan.tcl`、`insert_scan.tcl`、`export_scan_results.tcl` 的顺序执行，在预览前和插入后检查 DRC。本地保留可重新打开的 `cali_logic_scan.ddc` 和 `cali_logic_post_scan.fss`，标准单元库由本地 PDK 提供。

## 结果与回放

TestMAX 的未折叠固定型故障结果为 24,771 已检测、60 不可检测、31 未检测，可能检测及 ATPG 判定不可测试各为 0。99.88% 是工具报告的 **Test Coverage**。ATPG 日志保留 `N23` 单元模型警告；本轮通过独立 VCS 功能仿真验证了已导出的串行向量行为。

需要重新生成本地向量时，在独立的 ATPG 运行目录启动 `tmax -shell`。按顺序执行 `read_netlist <本地 smic18.v> -library`、`read_netlist <扫描网表>`、`run_build_model cali_logic`，然后用 `run_drc <测试协议 SPF>` 检查扫描链。在 `TEST-T>` 执行 `set_faults -model stuck`、`add_faults -all`、`run_atpg -auto`。用以下命令保存本地测试向量和故障明细。

```tcl
write_patterns cali_logic_stuck_serial.stil -format stil -serial
write_faults cali_logic_stuck_faults.rpt -all
```

在 `05-Design-for-Test` 目录复跑 VCS。需要 Python 3、VCS 和与本轮相同的 SMIC18 单元 Verilog 功能模型。示例使用仓库的原始 STIL，也可传入本地重新导出的路径。

```bash
sha256sum -c artifacts.sha256
SMIC18_VERILOG=/path/to/smic18.v \
    bash scripts/run_serial_vcs.sh patterns/cali_logic_stuck_serial.stil
```

脚本打印仿真目录并保留编译、仿真日志。检查 `ATPG_SERIAL_PASS patterns=349 cycles=205101 output_bit_checks=246743`。本轮门级回放未加载 SDF。扫描网表和 SCANDEF 可交给后续布局布线，物理实现需同时配套 SDC 与物理工艺库。
