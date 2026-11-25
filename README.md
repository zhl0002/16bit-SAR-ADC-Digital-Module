# 16 位 SAR ADC 数字模块 - 电容失配数字校准模块

这个仓库按数字集成电路的设计流程组织。九个子项目各有自己的入口、输入和产物。从完整的 Verilog 设计基线出发，选取校准模块 `cali_logic` 做 RTL 功能验证，再综合成标准单元电路，检查 RTL 与门级网表的逻辑等价性，随后加入扫描链并验证测试向量，接着将扫描版实现为可交接的标准单元版图，用 Calibre 验证实物版图，提取布线寄生参数，最后用 PrimeTime 检查已约束路径的布线后时序。

| 顺序 | 子项目 | 完成的工作 | 主要产物 |
| --- | --- | --- | --- |
| 01 | [Verilog](01-Verilog/) | 整理完整数字设计与模块接口，建立源码基线 | 八个 Verilog 模块、编译清单和三份阅读指南 |
| 02 | [RTL 设计与验证](02-RTL-Design/) | 对 `cali_logic` 建立自检用例，检查控制、校准和权重读出 | 已验证 RTL、七份 testbench、VCS 回归脚本、用例结果与 Lint 报告 |
| 03 | [DC逻辑综合](03-Logic-Synthesis/) | 把第 02 阶段的模块映射成标准单元，并检查试综合面积和内部时序 | 综合 Tcl、门级网表、SDC、DDC、SVF 和原始结果报告 |
| 04 | [形式等价验证(LEX)](04-Formal-Verification/) | 用 Formality 对比第 02 阶段的 RTL 与第 03 阶段的网表，706 个比较点全部通过 | 复跑 Tcl、输入校验清单和原始等价报告 |
| 05 | [可测性设计（DFT）](05-Design-for-Test/) | 插入 584 单元扫描链，验证功能模式，生成并回放 349 个固定型故障向量 | 扫描网表、SPF、SCANDEF、插入指导 SVF、串行 STIL、故障表和验证报告 |
| 06 | [布局布线（P&R）](06-Place-and-Route/) | 用 ICC2 完成布局布线、布线后等价，并将块级版图占地压缩 36.08% | 试实现 SDC、复查与面积优化脚本、候选结果与交接说明 |
| 07 | [物理验证（DRC & LVS）](07-DRC-and-LVS/) | 用 Calibre 检查 SMIC18 版图规则和电路连接，块级 LVS 通过，边界和密度待顶层复核 | Calibre 配置示例、CDL 修正脚本、规则计数与验证摘要 |
| 08 | [寄生参数提取（PEX）](08-Parasitic-Extraction/) | 配置 Calibre xRC，验证工程规则下的 PHDB 和 PDB，核对 ICC2 工程版 SPEF | Calibre 配置示例、提取与 SPEF 校验报告、文件校验值 |
| 09 | [静态时序分析（STA）](09-Static-Timing-Analysis/) | 用 PrimeTime 验证紧凑版 cali_logic 的寄生标注和 10 ns 功能模式内部时序 | 复跑 Tcl、试分析 SDC、时钟、约束覆盖和建立／保持时间报告 |

第 01 阶段覆盖完整数字模块。第 02 至 09 阶段以独立的 `cali_logic` 为对象。
