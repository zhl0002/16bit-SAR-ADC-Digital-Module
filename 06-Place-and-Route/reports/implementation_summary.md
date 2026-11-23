# cali_logic 布局布线结果

- 实现工具为 ICC2 V-2023.12-SP5。等价验证使用 Formality W-2024.09-SP3。
- 版图检查点为 `cali_logic/final_routed_10ns`。时序来自功能场景 `func_typ_trial`，使用典型角、10 ns 周期和试用 RC。

## 收敛记录

1. 试布线报告 1,311 条布线规则违例，其中 680 条为短路。重新建立时钟后，初版信号布线依然有 773 条短路，主要在 METAL1/METAL2。
2. 调整核心电源网到 METAL4/METAL5 并重布后，布线 DRC 和开路归零。启用 CCD 优化后，填充前最差 setup 裕量为 +0.0140 ns。
3. 插入 4,199 个物理填充单元后，setup 裕量短暂降至 −0.0135 ns。再次优化并恢复 10 ns 试实现约束后重新验收。

## 最终检查

| 检查项 | 结果 | 本地证据 |
| --- | --- | --- |
| 版图边界 | 423.92 µm × 423.20 µm | `cali_logic_routed.def` 的 `DIEAREA` |
| 组件、端口和扫描链 | 7,525 个 DEF 组件、137 个 DEF 端口（含 PG）、一条扫描链 | `cali_logic_routed.def` |
| 布局合法性 | 通过 | `legality.rpt` |
| 布线 | 0 开路，0 布线 DRC | `routes.rpt` |
| 电源连接 | VDD、VSS 各自连通，标准单元和电源端口无悬空 | `pg_connectivity.rpt`、`pg_drc.rpt` |
| ICC2 内部 LVS | 0 短路、0 开路、0 悬空走线 | `internal_lvs.rpt` |
| 时钟树 | 584 个负载、16 个中继单元，最大延迟约 1.01 ns，偏斜约 0.77 ns | `clock_qor.rpt` |
| Setup / Hold | +0.1087 ns / +0.5845 ns，两类违例均为 0 | `setup.rpt`、`hold.rpt`、`qor.rpt` |
| GDS 结构 | 263 个从顶层可达的结构，校验了 250 个用到的工艺单元结构 | `gds_validation.rpt`、`gds_cell_sources.rpt` |
| 布线后等价 | 707 个比较点通过，失败 0 | `equivalence.rpt` |

## 本地交接产物

| 产物 | 用途 |
| --- | --- |
| `cali_logic_trial.ndm` | 重开检查点以查看版图、继续调优或导出报告 |
| `cali_logic_routed.gds` / `cali_logic_routed.def` | 分别用于版图集成与物理验证，以及检查组件、端口、布线和扫描链 |
| `cali_logic_routed.v` / `cali_logic_routed_pg.v` | 分别用于逻辑等价，以及核对供电网和物理单元 |
| `cali_logic_routed.sdc` | 保存试实现约束，供下游时序分析读取 |
| `cali_logic_trial.smic18_mesh_par_25.spef` | 记录布线后提取的寄生，供支持 SPEF 的时序工具读入 |
| `cali_logic_trial.sdf` | 记录本轮估算的门级延迟，供之后的延迟回标仿真 |
| `cali_logic_trial.spef_scenario` / `SHA256SUMS` | 识别 SPEF 对应场景和核对发布文件一致性 |

当前版图约 0.1794 mm²，超过 0.0100 mm² 的面积目标。后续签核仍需补齐正式提取模型、顶层 I/O 和多场景约束、工艺 DRC/LVS/ERC 及天线规则，并复核 tap 覆盖和供电可靠性。SDF 已导出，本轮验收没有使用其做回标仿真。
