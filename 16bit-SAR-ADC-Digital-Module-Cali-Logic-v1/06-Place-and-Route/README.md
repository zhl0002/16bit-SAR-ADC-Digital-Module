# 布局布线（P&R）

本阶段把 `cali_logic` 的[扫描门级网表](../05-Design-for-Test/netlist/cali_logic_scan.v)和 [SCANDEF](../05-Design-for-Test/physical/cali_logic_scan.def)实现为 SMIC18 六层金属版图。使用 IC Compiler II（ICC2）及其 Library Manager 准备物理库、完成实现并检查可交付数据。最后用 Formality 核对布线是否改变了扫描网表的逻辑。

## 步骤与目的

| 阶段 | 软件与主要操作 | 目的与结果 |
| --- | --- | --- |
| 工艺与设计导入 | 在 ICC2 Library Manager 建立参考 NDM；在 ICC2 读入扫描网表、SCANDEF 和 SDC | 解析标准单元的物理与时序视图，建立功能模式、典型角和 10 ns 试实现时钟 |
| Floorplan 与电源规划 | 在 ICC2 设定 55% 初始核心利用率、放置接口端口，建 VDD/VSS 环、供电条带及行电源轨 | 面向比较器、CDAC 电平转换器和数字顶层组织引脚，给标准单元提供电源通路 |
| 标准单元布局 | 运行拥塞驱动布局和合法化，在图形界面查看拥塞图 | 让标准单元落在合法行上，识别 M1/M2 的局部拥塞 |
| RC 与时钟树 | 加载六层 `TLUPlus` 与映射，绑定典型角，再建立并布线时钟树 | 用试用 RC 估算互连延迟，向 584 个时钟负载分配 `cal_clk` |
| 试布线和电源网改版 | 用 `check_routes` 和 Error Browser 定位短路。将核心供电条带从 METAL2 移至 METAL4/METAL5，保留 METAL1 行电源轨 | 释放低层信号通道。重布时钟和信号后，ICC2 报告连线开路及布线 DRC 均为 0 |
| 布线优化和填充 | 运行 `route_opt` 并启用 CCD，补入物理填充单元，填充后再检查和优化 | 填充后典型角 setup/hold 裕量分别为 +0.1087/+0.5845 ns，两项违例均为 0 |
| 验收与导出 | 检查合法性、布线、PG 和 ICC2 内部 LVS，写出 GDS、DEF、网表、SDC、SPEF 和 SDF | 保存最终版图检查点和下游输入，校验 GDS 层次及标准单元结构 |
| 布线后等价 | Formality 对比 DFT 扫描网表和布线后逻辑网表，保持 `scan_en` 自由 | 707 个比较点通过，覆盖该对网表中的功能和扫描逻辑 |

## 面积优化

在复制的原版 NDM 上压缩核心区和原有单元坐标，重建电源、端口和走线，并关闭扫描链重排与重新分组。比较多个核心利用率，按面积、布线、PG、时序和全模式等价选版。最终 `u89_seed` 的版图尺寸为 **339.72 µm × 337.56 µm**，边界面积 **114,675.88 µm²**，比原版缩小 **36.08%**。10 ns 试条件下的最差 setup / hold 裕量为 +0.0151 ns / +0.3134 ns，ICC2 布线违规与开路均为 0，Formality 707 点通过。

## 工程文件

| 文件 | 功能与用途 |
| --- | --- |
| [`constraints/cali_logic_trial_10ns.sdc`](constraints/cali_logic_trial_10ns.sdc) | 复现本轮 10 ns 时钟和 `scan_en=0` 核心模式约束。读取前应已建立 ICC2 场景 |
| [`scripts/check_routed_block.tcl`](scripts/check_routed_block.tcl) | 在本地最终 NDM 上复查合法性、布线、PG、LVS、时钟和时序，分别保存报告 |
| [`scripts/verify_postroute_equivalence.tcl`](scripts/verify_postroute_equivalence.tcl) | 读取本地单元时序库、DFT 网表和布线后逻辑网表，复查布线后等价 |
| [`reports/implementation_summary.md`](reports/implementation_summary.md) | 汇总原版的收敛过程、指标和交接文件 |
| [`reports/area_optimization.md`](reports/area_optimization.md) | 记录紧凑版的压缩流程、选版依据和交接文件 |
| [`reports/area_sweep.csv`](reports/area_sweep.csv) | 汇总面积试验各候选的尺寸、裕量和验收状态 |
| [`scripts/compact_routed_block.tcl`](scripts/compact_routed_block.tcl)、[`scripts/measure_area_trials.py`](scripts/measure_area_trials.py) | 用原版 NDM 复现紧凑候选，并从 DEF 与 ICC2 报告提取面积和检查状态 |

原始检查点为 `cali_logic/final_routed_10ns`，紧凑版为 `cali_logic/packed_final`。本轮完成独立模块的版图实现与工程检查。正式流片还需确认签核 RC、顶层 I/O 预算、PVT 场景、晶圆厂规则验证和 100 µm × 100 µm 面积目标。库、版图和提取文件由本地项目保管，其名称和用途见结果摘要。

紧凑版 `cali_logic/packed_final` 已交给[第 07 阶段物理验证](../07-DRC-and-LVS/)。该阶段记录 Calibre 块级 DRC、LVS 和 ERC 的输入与结果。
