# 04 形式等价验证

本项目用 Synopsys Formality W-2024.09-SP3 核对独立校准模块 `cali_logic`。参考侧采用[第 02 阶段的 RTL](../02-RTL-Design/rtl/cali_logic.v)，实现侧采用[第 03 阶段的门级网表](../03-Logic-Synthesis/netlist/cali_logic_mapped.v)。两侧使用这次综合与验证对应的默认 RTL 参数。

## 步骤与目的

| 步骤 | Formality 操作 | 目的与完成标志 |
| --- | --- | --- |
| 1. 加载综合指导 | 在 **0. Guid.** 启用 Synopsys Auto Setup，然后加载第 03 阶段的 `cali_logic.svf` | 将 DC 的综合变换交给 Formality，辅助识别两侧的对应逻辑 |
| 2. 读入参考设计 | 在 **1. Ref. → Read Design Files** 加入 RTL，用 **Set Top Design** 设为 `r:/WORK/cali_logic` | 把综合前的逻辑设为比较基准 |
| 3. 读入实现设计 | 在 **2. Impl.** 读入综合时用的标准单元库和门级网表，设顶层为 `i:/WORK/cali_logic` | 让工具解析网表中的标准单元，建立综合后电路的逻辑表示 |
| 4. 检查比较条件 | 在 **3. Setup → Constants** 确认没有手动固定输入，并检查两侧设计中的黑盒 | 确认复位、启动和比较器输入仍参与验证。本次两个设计层次均无黑盒实例 |
| 5. 匹配比较点 | **4. Match → Run Matching** | 配对两侧的寄存器和端口。706 个比较点按名称匹配，两侧未匹配数均为 0 |
| 6. 证明等价并归档 | **5. Verify → Verify**，用 `report_status` 导出结果，用 **File → Save Session** 保存本地会话 | 检查对应逻辑是否等价，并保留可复查的结果 |

本版本界面把文件加载操作显示为 **Files** 与 **Currently Loaded** 之间的右箭头 **`>`**。文件进入右侧列表后，再指定设计顶层。

## 工程文件

| 文件 | 功能和用途 |
| --- | --- |
| [参考 RTL](../02-RTL-Design/rtl/cali_logic.v) | 形式验证的参考输入 |
| [门级网表](../03-Logic-Synthesis/netlist/cali_logic_mapped.v) | 形式验证的实现输入，包含标准单元实例和连线 |
| [综合指导 SVF](../03-Logic-Synthesis/formality/cali_logic.svf) | 记录综合变换，供 Formality 在匹配和验证阶段使用 |
| [`scripts/run_lec.tcl`](scripts/run_lec.tcl) | 批量复跑同一组输入的加载、匹配与证明，并输出状态报告和可重开的会话 |
| [`reports/verification.rpt`](reports/verification.rpt) | 图形界面运行后导出的原始状态报告，包含通过数量、Auto Setup 条件和 RTL 解释警告 |
| [`inputs.sha256`](inputs.sha256) | 固定本轮使用的 RTL、网表和 SVF 版本 |

工艺库由本地环境提供。运行生成的 `cali_logic.fss` 是本地 Formality 会话快照，可用于打开结果和查看比较点。

## 验证结果

| 项目 | 结果 |
| --- | --- |
| Formality 状态 | `Verification SUCCEEDED` |
| 通过比较点 | 706，其中 122 个端口点、584 个寄存器点 |
| 失败比较点 | 0 |
| 两侧未匹配比较点 | 参考侧 0，实现侧 0 |

结论适用于本次输入和报告列明的 Synopsys Auto Setup 条件。参考 RTL 展开时有 5 处 `FMR_ELAB-147` 提示，涉及变量索引可能越界。此次等价证明通过，越界索引在实际运行中的可达性仍待单独复查。修改 RTL 或重新综合后，应对相应的新输入重新运行等价检查。

## 复跑

在仓库根目录校验输入，并从独立运行目录启动 Formality。`SMIC18_DB` 指向与综合相同的本地库，`LEC_OUT` 指定尚未创建的结果目录。

```bash
sha256sum -c 04-Formal-Verification/inputs.sha256
script="$PWD/04-Formal-Verification/scripts/run_lec.tcl"
scratch=$(mktemp -d)
cd "$scratch"
SMIC18_DB=/path/to/typical.db LEC_OUT="$scratch/results" \
    fm_shell -f "$script"
```

已验证的综合门级网表作为[第 05 阶段可测性设计](../05-Design-for-Test/)的扫描插入输入。第 05 阶段另行检查扫描插入后的功能模式。
