# cali_logic 块级物理验证结果

## 输入与版本

- 版图为 ICC2 紧凑版 `cali_logic/packed_final`，GDS 顶层是 `cali_logic`。本轮 DRC 和 LVS 共用 1 nm 数据库单位的验证 GDS。
- DRC 使用 `SMIC_CalDRC_018LGMS_1833_V1.19_REV1_0.drc`。LVS 使用 `SMIC_CalLVS_018MSE_1833_V1.11_1.lvs`，参考是 `cali_logic_compact_10ns_lvs_v5.cdl`。
- 两项均在 Calibre Interactive v2025.1_16.10 运行。

## DRC

执行 421 个规则检查。汇总报告有 1,034 个结果记录和 1,041 个展开后的出现次数。剩余记录来自 `BD_1`、`BD_2a` 和五个整体金属密度项，详见[规则计数](drc_rule_counts.csv)。`BD_2a` 达到每条规则 1,000 条的报告上限，实际数量可能更高。边界和金属填充在 ADC 顶层确定后复查。

## LVS

| 比较对象 | 版图 | 参考 | 未匹配 |
| --- | ---: | ---: | ---: |
| 端口 | 96 | 96 | 0 |
| 网络 | 12,671 | 12,671 | 0 |
| 比较实例 | 17,798 | 17,798 | 0 |

最终 GUI 报告状态为 **CORRECT**。比较计数来自 Calibre 的转换后统计。版图实现端口与 LVS 比较端口按各自的定义计数，Calibre 将别名所代表的同一物理节点合并。

参考网表先核对全局供电、1.8 V 器件子类型和 L/W 单位。v4 消除器件属性差异后，层次比较确认 MXI2X1 单元内部匹配，剩余网络失配与 26 对仅大小写不同的内部网名对应。Calibre 当前的 `SOURCE CASE NO` 会折叠这些名字。v5 只重命名冲突的内部网络，例如把 `N1800` 改为 `CAL_NET_UPPER_1800`，保留原 `n1800`。沿用同一 GDS 和 SMIC 规则复跑通过。

## ERC

常规 ERC 规则产生 0 条结果。独立运行的 `PATHCHK POWER && ! GROUND NOFLOAT` 记录 1 个网络及 11 个标记图形。标记落在 `U_TIELO_PHASE2` 边界内，提取网表确认该单元的 VDD/VSS 与顶层同名电源相连，Y 驱动 `phase_o[2]`。标记与库 CDL 的内部偏置结构一致，处置依据随最终签核资料归档。

## 本地报告

| 工程文件 | 用途 |
| --- | --- |
| `cali_logic_compact_10ns.drc.summary`、`cali_logic_compact_10ns.drc.results` | 汇总规则计数，供 RVE 定位几何标记 |
| `lvs.report`、`lvs.report.ext`、`lay.net` | 比较结果、版图提取报告、抽取网表 |
| `erc.rep`、`svdb/cali_logic.pathchk.rep`、`svdb/cali_logic.pathchk.erc` | ERC 计数、路径实例定位及标记数据 |
