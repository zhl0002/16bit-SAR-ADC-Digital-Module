# 02 RTL 设计与功能验证

本项目从 [01 Verilog](../01-Verilog/) 选取校准模块 `cali_logic`，用独立的比较器和 CDAC 数字模型验证控制、权重计算及读出。综合阶段采用这里的 [已验证 RTL](rtl/cali_logic.v)。

## 步骤与目的

| 步骤 | 具体做法 | 目的与完成标志 |
| --- | --- | --- |
| 1. 核对 RTL 边界 | 查看 `cali_logic` 的启动、复位、阶段码、CDAC 选择、比较请求与响应、权重读口 | 先明确何时采纳判决、何时可以读取结果，以及如何判断退出和成功 |
| 2. 先验证控制 | 运行 `tb_cali_logic`，检查复位、读地址、比较请求、超时、超时边界响应与运行中复位。用波形对照 `state_q`、`cmp_req_o`、`cmp_done_i`、`error_o` | 在扩展到整轮校准前，确认状态机各关键边界行为。自检通过 90,233 次判断，其中包含逐周期重复检查 |
| 3. 用已知权重检查算法 | 先在 `tb_cali_b6` 设 b6 理想等效权重 32，再在 `tb_cali_b6_mismatch` 改为 33。观察残差与一位判决 | 核对结果随模型变化。两组的 Q8 权重分别为 8,192 和 8,448，各发出 384 次比较请求 |
| 4. 验证完整校准和读出 | 用 `tb_cali_full` 校准 b6 到 b19，逐地址读出 20 个权重并与独立算法参考比较 | 确认正反向测量、位权递推和读口协同工作。一轮 11,008 次比较请求，20 项读取均匹配 |
| 5. 改变比较条件 | 用 `tb_cali_b6_offset` 跑 `0`、`+8`、`−8` 三种固定失调。用 `tb_cali_full_latency` 轮换 1、2、4、8 周期延迟 | 检查固定失调下的双向测量结果，以及等待期间不提前使用判决。三组失调的 b6 权重均为 8,448，四种延迟均通过 |
| 6. 检查再次启动和复位 | 用 `tb_cali_full_repeat` 连续启动两轮，然后拉低复位并读取权重 | 检查前一次结果不会影响下一轮。两轮共 22,016 次请求，复位后的高位权重清零且失效 |
| 7. 审查并回归 | 运行 VCS Lint 检查赋值和比较位宽，整理常量后重新编译七份 testbench。以各组 `PASS` 与正常 `$finish` 作为运行检查点 | 确认源码整理后的行为。在本次快照中，九组配置全部通过。保留的比较位宽和空语句提示已按默认参数审查 |

## 软件操作速查

1. **准备单个测试**。在 Verdi 中用 **File → Import Design → From File** 加入 [RTL](rtl/cali_logic.v) 和一份 [testbench](tb/)，语言选 SystemVerilog。测试顶层是该 `.sv` 文件里的模块，`dut` 是它下面的校准实例。
2. **启动仿真**。首次生成 `simv` 由 VCS 执行。从本目录进入一个独立运行目录，例如下面的 `runs/control`，编译时保留 KDB 和调试信号访问。已有匹配的 `simv` 时，可直接使用下一步的界面。

   ```bash
   mkdir -p runs/control
   cd runs/control
   vcs -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
       -top tb_cali_logic ../../rtl/cali_logic.v ../../tb/tb_cali_logic.sv \
       -o simv -l compile.log
   ```

3. **在 Verdi 中运行和复查**。打开 **Tools → Preferences → Simulation**，选 VCS，在 **Executable Path** 填本用例 `simv` 的完整路径。用 **Tools → Run Simulation** 启动。需要完整自检时选 **No Specific Time**。失调用例在 **Options** 中每次填一个 `+CMP_OFFSET=0`、`+CMP_OFFSET=8` 或 `+CMP_OFFSET=-8`。从源码右键 **Add to Waveform** 添加信号，在 nWave 看波形，在 **Console** 看 `PASS`。改源码后可用 **Simulation → Rebuild and Restart** 调用原编译配置。

## 验证基线与范围

工具版本为 VCS 和 Verdi W-2024.09-SP1，验证快照的 RTL SHA-256 为 `7f3492564ac433dda73dbc2f64162cc9ba2b3d39f3a7a14ed55bf00a13be1edf`。七份 testbench 的九组配置均通过。默认 `CMP_TIMEOUT=1024`，仿真激励时钟为 10 ns。完整校准的 11,008 次请求包含逐位比较，每个位权仍按 32 对正反向测量执行。

结论适用于独立模块和所用数字模型。实际比较器接口、CDC、顶层参数、整机 ADC 精度与部分保护路径需要继续验证。覆盖率汇总工具曾异常退出，本阶段保留功能观测和自检结果。
