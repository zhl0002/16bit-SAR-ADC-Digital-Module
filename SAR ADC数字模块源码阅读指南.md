# SAR ADC数字模块源码阅读指南

这份指南按整机流程介绍八个模块，再给出各模块的完整源码。所有时序块使用 clk_i，rst_ni 为低有效异步复位。

## 阅读导航

| 名字 | 功能 | 代码行数 |
| --- | --- | --- |
| [adc_digital_top.v](<adc_digital_top.v#L1>) | 接收启动命令，调度校准、转换和重构，记录整机错误 | 345 |
| [cali_logic.v](<cali_logic.v#L1>) | 控制校准SAR、测量正反向权重、平均并保存权重 | 297 |
| [ala_logic.v](<ala_logic.v#L1>) | 控制LSB重复搜索，检测翻转，统计搜索和平均结果 | 111 |
| [flash_decode.v](<flash_decode.v#L1>) | 将合法温度计码译成两位粗码，并保持结果 | 23 |
| [code_reconstruction.v](<code_reconstruction.v#L1>) | 按权重重构，计算ALA修正，舍入并输出16位码 | 169 |
| [clk_timing.v](<clk_timing.v#L1>) | 按可配置周期产生采样请求脉冲 | 25 |
| [digital_regs.v](<digital_regs.v#L1>) | 保存配置、记录输出，通过地址映射提供寄存器访问 | 124 |
| [spi_4wire.v](<spi_4wire.v#L1>) | 接收48位SPI帧，提交写入或移出读快照 | 78 |

行数包含注释和空行。点击模块名可打开对应文件，下文源码与这些文件逐字对应。

## 整机的数据流

```text
SPI → digital_regs → 配置与启动命令
校准命令 → cali_logic内部SAR → CDAC命令和比较请求 → 权重表
采样命令 → Flash → 正常SAR事务 → ALA比较事务
符号码 + 校准权重 + ALA统计 → code_reconstruction → 16位输出
clk_timing → 周期采样请求
```

正常SAR通过顶层请求和响应端口接入。校准SAR在 cali_logic 内。开关驱动、电平转换及比较器的实际触发和结果同步由接入层负责。

Flash、正常SAR和ALA在 valid、ready 同时为1的上升沿完成交接。一条通道一次只有一个未完成请求，响应最早在请求接受后的下一周期返回。cancel 要求接入层撤销本次工作并清理迟到响应。

校准比较使用单拍 cmp_req_o，请求后等待 cmp_done_i 与对应的 cmp_result_i。正常完成和错误结束都会先恢复共模，再给释放脉冲。

## 参数和数据尺度

顶层默认 WEIGHT_W=32、FRAC_BITS=8、TIMEOUT_CYCLES=65536。权重的整数编码256表示1个归一化单位。ALA_STEP使用相同尺度；GAIN_Q16和OFFSET决定怎样换算成最终输出码。

重构使用下列计算顺序。

```text
normal = Σ((2×sign_bit−1)×Wi)
corrected = normal − S×ALA_STEP − trunc_toward_zero(A×ALA_STEP/M)
signed_code = round_nearest_away(corrected×GAIN_Q16 / 2^(FRAC_BITS+16)) + OFFSET
code = saturate(signed_code, −32768, 32767) + 32768
```

关闭ALA时跳过两项ALA修正，M=0时跳过平均项。顶层用 errors_o[7] 记录没有平均样本的情况。

## 当前硬件清单

| 模块 | 端口名 | 内部信号及索引 | 参数 | 常量 | RTL存储位 |
| --- | --- | --- | --- | --- | --- |
| adc_digital_top | 46 | 38 | 3 | 12 | 69 |
| cali_logic | 15 | 18 | 7 | 18 | 610 |
| ala_logic | 18 | 5 | 1 | 1 | 45 |
| flash_decode | 6 | 0 | 0 | 0 | 3 |
| code_reconstruction | 17 | 11 | 2 | 10 | 184 |
| clk_timing | 5 | 1 | 0 | 0 | 33 |
| digital_regs | 26 | 3 | 1 | 0 | 193 |
| spi_4wire | 10 | 7 | 0 | 0 | 89 |

内部名字按声明计数，数组按一个名字计数。RTL存储位数使用当前顶层默认配置，包含输出寄存器和权重数组，合计1226位。最终单元数量还取决于综合优化与状态机编码。

## 1. adc_digital_top.v

[打开源码](<adc_digital_top.v#L1>)

顶层把整机工作分成校准和正常转换两条流程。空闲时，校准请求优先于采样请求；两者同时到来会记录启动冲突。采样只有在使能、数值配置有效、整表权重有效时才会进入转换流程。

正常转换依次经过 Flash 请求、Flash 响应、粗码检查、SAR 请求和 SAR 响应。SAR 的低十八位符号码与两位 Flash 粗码组成 sign_code_q。按配置完成 ALA 后，顶层启动重构，收到成功完成信号时更新 code_o 并给一拍 code_valid_o。

timeout_q 为 Flash 和 SAR 的请求等待、响应等待计时。transaction_fault 根据当前状态检查超时、fault 和非法粗码，错误时发取消与 frame_done_o。响应和请求接受的优先级高于超时。校准和 ALA 的比较超时由各自模块处理。

sign_code_q 从 SAR 响应接受后保持到本帧重构完成。数字寄存器在整机忙时拒绝数值配置写入，因此重构期间的符号码、ALA 统计、步长、增益和偏移都有稳定来源。

### 源码

```verilog
module adc_digital_top #(
    parameter [31:0] WEIGHT_W = 32,
    parameter [31:0] FRAC_BITS = 8,
    parameter [31:0] TIMEOUT_CYCLES = 65536
) (
    input wire clk_i,
    input wire rst_ni,
    input wire sample_start_i,
    input wire cal_start_i,
    output wire busy_o,
    output wire sample_ready_o,
    output reg frame_done_o,
    output reg cal_done_o,
    output wire weights_valid_o,
    output reg [7:0] errors_o,
    output reg [15:0] code_o,
    output reg code_valid_o,
    input wire spi_cs_ni,
    input wire spi_sclk_i,
    input wire spi_mosi_i,
    output wire spi_miso_o,
    output wire flash_req_valid_o,
    input wire flash_req_ready_i,
    input wire flash_rsp_valid_i,
    output wire flash_rsp_ready_o,
    input wire [2:0] flash_thermometer_i,
    input wire flash_fault_i,
    output reg flash_cancel_o,
    output wire sar_req_valid_o,
    input wire sar_req_ready_i,
    output wire [1:0] sar_flash_code_o,
    input wire sar_rsp_valid_i,
    output wire sar_rsp_ready_o,
    input wire [17:0] sar_sign_code_i,
    input wire sar_fault_i,
    output reg sar_cancel_o,
    output wire cal_cmp_req_o,
    input wire cal_cmp_done_i,
    input wire cal_cmp_result_i,
    output wire [2:0] cal_phase_cmd_o,
    output wire [39:0] cal_bp_cmd_p_o,
    output wire [39:0] cal_bp_cmd_n_o,
    output wire ala_req_valid_o,
    input wire ala_req_ready_i,
    output wire ala_repeat_o,
    output wire [3:0] ala_index_o,
    input wire ala_rsp_valid_i,
    output wire ala_rsp_ready_o,
    input wire ala_decision_i,
    input wire ala_fault_i,
    output wire ala_cancel_o
);
    localparam [3:0] IDLE=0, CAL_START=1, CAL_WAIT=2, FLASH_REQUEST=3;
    localparam [3:0] FLASH_WAIT=4, FLASH_CHECK=5, SAR_REQUEST=6, SAR_WAIT=7;
    localparam [3:0] ALA_START=8, ALA_WAIT=9, RECON_START=10, RECON_WAIT=11;
    reg [3:0] state_q;
    reg [((TIMEOUT_CYCLES>1) ? $clog2(TIMEOUT_CYCLES) : 1)-1:0] timeout_q;
    reg [19:0] sign_code_q;
    reg [1:0] transaction_fault;
    wire [7:0] reg_addr;
    wire [31:0] reg_wr_data, reg_rd_data;
    wire reg_wr_en;
    wire cfg_enable, cfg_ala_enable, cfg_continuous;
    wire [3:0] cfg_comparisons;
    wire [WEIGHT_W-1:0] cfg_ala_step;
    wire [31:0] cfg_gain, cfg_period;
    wire signed [31:0] cfg_offset;
    wire cfg_valid, cfg_cal_start, cfg_sample_start, cfg_clear_errors, cfg_rejected;
    wire [4:0] debug_weight_addr, recon_weight_addr;
    wire [WEIGHT_W-1:0] weight_data;
    wire weight_valid, sample_tick, cal_done;
    wire [2:0] cal_error;
    wire [1:0] flash_code, ala_error;
    wire flash_valid, ala_done, recon_done, recon_error;
    wire signed [4:0] search_sum, avg_sum;
    wire [3:0] avg_count;
    wire [15:0] reconstructed_code;
    assign busy_o = state_q!=IDLE;
    assign cfg_valid = cfg_gain!=0 && (!cfg_ala_enable || cfg_ala_step!=0);
    assign sample_ready_o = !busy_o && cfg_enable && cfg_valid && weights_valid_o;
    assign flash_req_valid_o = state_q==FLASH_REQUEST;
    assign flash_rsp_ready_o = state_q==FLASH_WAIT;
    assign sar_req_valid_o = state_q==SAR_REQUEST;
    assign sar_rsp_ready_o = state_q==SAR_WAIT;
    assign sar_flash_code_o = flash_code;
    spi_4wire u_spi (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cs_ni(spi_cs_ni),
        .sclk_i(spi_sclk_i),
        .mosi_i(spi_mosi_i),
        .miso_o(spi_miso_o),
        .rd_data_i(reg_rd_data),
        .addr_o(reg_addr),
        .wr_data_o(reg_wr_data),
        .wr_en_o(reg_wr_en)
    );
    digital_regs #(
        .WEIGHT_W(WEIGHT_W)
    ) u_regs (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .addr_i(reg_addr),
        .wr_en_i(reg_wr_en),
        .wr_data_i(reg_wr_data),
        .rd_data_o(reg_rd_data),
        .busy_i(busy_o),
        .weights_valid_i(weights_valid_o),
        .errors_i(errors_o),
        .code_valid_i(code_valid_o),
        .code_i(code_o),
        .weight_data_i(weight_data),
        .weight_valid_i(weight_valid),
        .weight_addr_o(debug_weight_addr),
        .enable_o(cfg_enable),
        .ala_enable_o(cfg_ala_enable),
        .continuous_o(cfg_continuous),
        .comparisons_o(cfg_comparisons),
        .ala_step_o(cfg_ala_step),
        .gain_q16_o(cfg_gain),
        .offset_o(cfg_offset),
        .period_cycles_o(cfg_period),
        .cal_start_o(cfg_cal_start),
        .sample_start_o(cfg_sample_start),
        .clear_errors_o(cfg_clear_errors),
        .rejected_o(cfg_rejected)
    );
    clk_timing u_clk_timing (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .enable_i(cfg_continuous && cfg_enable && cfg_valid && weights_valid_o && state_q!=CAL_START && state_q!=CAL_WAIT),
        .period_cycles_i(cfg_period),
        .sample_tick_o(sample_tick)
    );
    // ====================================================================
    // 校准、ALA、Flash译码及统一重构
    // ====================================================================
    cali_logic #(
        .WEIGHT_W(WEIGHT_W),
        .FRAC_BITS(FRAC_BITS),
        .PAIR_LOG2(5),
        .SAMPLE_CYCLES(8),
        .SETTLE_CYCLES(4),
        .PARK_CYCLES(4),
        .CMP_TIMEOUT(TIMEOUT_CYCLES)
    ) u_cali_logic (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cal_go_i(state_q == CAL_START),
        .cmp_result_i(cal_cmp_result_i),
        .cmp_done_i(cal_cmp_done_i),
        .cmp_req_o(cal_cmp_req_o),
        .cal_release_ready_o(cal_done),
        .weights_valid_o(weights_valid_o),
        .error_o(cal_error),
        .phase_o(cal_phase_cmd_o),
        .cal_bp_sel_a_o(cal_bp_cmd_p_o),
        .cal_bp_sel_b_o(cal_bp_cmd_n_o),
        .weight_rd_addr_i((state_q==RECON_START || state_q==RECON_WAIT) ? recon_weight_addr : debug_weight_addr),
        .weight_rd_data_o(weight_data),
        .weight_rd_valid_o(weight_valid)
    );
    ala_logic #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) u_ala_logic (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(state_q == ALA_START),
        .comparisons_i(cfg_comparisons),
        .done_o(ala_done),
        .error_o(ala_error),
        .req_valid_o(ala_req_valid_o),
        .req_ready_i(ala_req_ready_i),
        .repeat_o(ala_repeat_o),
        .index_o(ala_index_o),
        .rsp_valid_i(ala_rsp_valid_i),
        .rsp_ready_o(ala_rsp_ready_o),
        .decision_i(ala_decision_i),
        .fault_i(ala_fault_i),
        .cancel_o(ala_cancel_o),
        .search_sum_o(search_sum),
        .avg_sum_o(avg_sum),
        .avg_count_o(avg_count)
    );
    flash_decode u_flash_decode (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .capture_i(flash_rsp_valid_i && flash_rsp_ready_o && !flash_fault_i),
        .thermometer_i(flash_thermometer_i),
        .code_o(flash_code),
        .valid_o(flash_valid)
    );
    code_reconstruction #(
        .WEIGHT_W(WEIGHT_W),
        .FRAC_BITS(FRAC_BITS)
    ) u_reconstruction (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(state_q == RECON_START),
        .sign_code_i(sign_code_q),
        .ala_enable_i(cfg_ala_enable),
        .search_sum_i(search_sum),
        .avg_sum_i(avg_sum),
        .avg_count_i(avg_count),
        .ala_step_i(cfg_ala_step),
        .gain_q16_i(cfg_gain),
        .offset_i(cfg_offset),
        .weight_addr_o(recon_weight_addr),
        .weight_data_i(weight_data),
        .weight_valid_i(weight_valid),
        .done_o(recon_done),
        .error_o(recon_error),
        .code_o(reconstructed_code)
    );
    // ================= 事务错误共用退出路径，响应优先于超时 =================
    always @* begin
        transaction_fault = 0;
        case (state_q)
            FLASH_REQUEST:
                if (!flash_req_ready_i && (TIMEOUT_CYCLES<=1 || timeout_q==TIMEOUT_CYCLES-1))
                    transaction_fault = 2'b01;
            FLASH_WAIT:
                if (flash_rsp_valid_i ? flash_fault_i : (TIMEOUT_CYCLES<=1 || timeout_q==TIMEOUT_CYCLES-1))
                    transaction_fault = 2'b01;
            FLASH_CHECK:
                if (!flash_valid)
                    transaction_fault = 2'b01;
            SAR_REQUEST:
                if (!sar_req_ready_i && (TIMEOUT_CYCLES<=1 || timeout_q==TIMEOUT_CYCLES-1))
                    transaction_fault = 2'b10;
            SAR_WAIT:
                if (sar_rsp_valid_i ? sar_fault_i : (TIMEOUT_CYCLES<=1 || timeout_q==TIMEOUT_CYCLES-1))
                    transaction_fault = 2'b10;
            default: transaction_fault = 0;
        endcase
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            timeout_q <= 0;
            sign_code_q <= 0;
            frame_done_o <= 0;
            cal_done_o <= 0;
            code_o <= 16'h8000;
            code_valid_o <= 0;
            errors_o <= 0;
            flash_cancel_o <= 0;
            sar_cancel_o <= 0;
        end else begin
            frame_done_o <= 0;
            cal_done_o <= 0;
            code_valid_o <= 0;
            flash_cancel_o <= 0;
            sar_cancel_o <= 0;
            if (cfg_clear_errors)
                errors_o <= 0;
            if (cfg_rejected || (busy_o && (cal_start_i || cfg_cal_start || sample_start_i || cfg_sample_start || sample_tick)))
                errors_o[0] <= 1;
            if (transaction_fault!=0) begin
                if (transaction_fault[0])
                    errors_o[2] <= 1;
                if (transaction_fault[1])
                    errors_o[3] <= 1;
                flash_cancel_o <= transaction_fault[0];
                sar_cancel_o <= transaction_fault[1];
                frame_done_o <= 1;
                timeout_q <= 0;
                state_q <= IDLE;
            end else case (state_q)
                IDLE: begin
                    timeout_q <= 0;
                    if (cal_start_i || cfg_cal_start) begin
                        state_q <= CAL_START;
                        if (sample_start_i || cfg_sample_start || sample_tick)
                            errors_o[0] <= 1;
                    end else if (sample_start_i || cfg_sample_start || sample_tick) begin
                        if (sample_ready_o)
                            state_q <= FLASH_REQUEST;
                        else begin
                            errors_o[1] <= 1;
                            frame_done_o <= 1;
                        end
                    end
                end
                CAL_START: state_q <= CAL_WAIT;
                CAL_WAIT:
                    if (cal_done) begin
                        cal_done_o <= 1;
                        if (cal_error!=0 || !weights_valid_o)
                            errors_o[6] <= 1;
                        state_q <= IDLE;
                    end
                FLASH_REQUEST, SAR_REQUEST:
                    if ((state_q==FLASH_REQUEST) ? flash_req_ready_i : sar_req_ready_i) begin
                        timeout_q <= 0;
                        state_q <= (state_q==FLASH_REQUEST) ? FLASH_WAIT : SAR_WAIT;
                    end else
                        timeout_q <= timeout_q+1'b1;
                FLASH_WAIT, SAR_WAIT:
                    if ((state_q==FLASH_WAIT) ? flash_rsp_valid_i : sar_rsp_valid_i) begin
                        timeout_q <= 0;
                        if (state_q==FLASH_WAIT)
                            state_q <= FLASH_CHECK;
                        else begin
                            sign_code_q <= {flash_code,sar_sign_code_i};
                            state_q <= cfg_ala_enable ? ALA_START : RECON_START;
                        end
                    end else
                        timeout_q <= timeout_q+1'b1;
                FLASH_CHECK: state_q <= SAR_REQUEST;
                ALA_START: state_q <= ALA_WAIT;
                ALA_WAIT:
                    if (ala_done) begin
                        if (ala_error!=0) begin
                            errors_o[4] <= 1;
                            frame_done_o <= 1;
                            state_q <= IDLE;
                        end else begin
                            if (avg_count==0)
                                errors_o[7] <= 1;
                            state_q <= RECON_START;
                        end
                    end
                RECON_START: state_q <= RECON_WAIT;
                RECON_WAIT:
                    if (recon_done) begin
                        frame_done_o <= 1;
                        if (!recon_error) begin
                            code_o <= reconstructed_code;
                            code_valid_o <= 1;
                        end else
                            errors_o[5] <= 1;
                        state_q <= IDLE;
                    end
                default: begin
                    errors_o[0] <= 1;
                    frame_done_o <= 1;
                    flash_cancel_o <= 1;
                    sar_cancel_o <= 1;
                    state_q <= IDLE;
                end
            endcase
        end
    end
endmodule
```

## 2. cali_logic.v

[打开源码](<cali_logic.v#L1>)

校准模块按 b6 到 b19 的顺序工作。target_q 表示目标，bit_q 在比较、扫描和高位还原三个阶段分别指示当前电容、当前权重或还原地址。

正侧底板选择码保存在 cal_bp_sel_a_o，负侧由对应两位字段交换位序产生。01 表示接 P，10 表示接 N，00 表示接 M。每次动作同时控制两侧对应电容。

默认每个目标执行32组正反向测量。扫描时把各项带符号贡献累计到 sum_q，平均时加32并右移6位。b18、b19 还需在数字域加回激励时的抵消项。权重存入 weight_q[6:19]，由 valid_q 逐项记录有效性。

cal_release_ready_o 表示共模恢复已经完成。weights_valid_o 和 error_o 表示整轮结果，weight_rd_valid_o 表示读口当前这一项是否有效。

[cali_logic接口、信号、常量与参数阅读指南](<cali_logic接口、信号、常量与参数阅读指南.md>) · [cali_logic源码阅读指南](<cali_logic源码阅读指南.md>)

### 源码

```verilog
module cali_logic #(
    parameter [31:0] WEIGHT_W = 32,
    parameter [31:0] FRAC_BITS = 8,
    parameter [31:0] PAIR_LOG2 = 5,
    parameter [31:0] SAMPLE_CYCLES = 8,
    parameter [31:0] SETTLE_CYCLES = 4,
    parameter [31:0] PARK_CYCLES = 4,
    parameter [31:0] CMP_TIMEOUT = 1024
) (
    input wire clk_i,
    input wire rst_ni,
    input wire cal_go_i,
    input wire cmp_result_i,
    input wire cmp_done_i,
    output reg cmp_req_o,
    output reg cal_release_ready_o,
    output reg weights_valid_o,
    output reg [2:0] error_o,
    output reg [2:0] phase_o,
    output reg [39:0] cal_bp_sel_a_o,
    output wire [39:0] cal_bp_sel_b_o,
    input wire [4:0] weight_rd_addr_i,
    output reg [WEIGHT_W-1:0] weight_rd_data_o,
    output reg weight_rd_valid_o
);
    localparam ACC_W = WEIGHT_W + (((PAIR_LOG2+2)>6) ? PAIR_LOG2+2 : 6) + 2;
    localparam WAIT_W = $clog2({2'b0,SAMPLE_CYCLES} + SETTLE_CYCLES + PARK_CYCLES + CMP_TIMEOUT);
    reg signed [ACC_W-1:0] sum_q;
    reg [19:0] valid_q;
    reg [WEIGHT_W-1:0] selected_w;
    reg signed [ACC_W:0] operand;
    wire signed [ACC_W:0] result = $signed({sum_q[ACC_W-1],sum_q}) + operand;
    reg [2:0] fault_bits;
    // ================= cal_ctrl.v：流程、校准SAR和两侧CDAC =================
    localparam [3:0] ST_IDLE=0, ST_PRESET=1, ST_SAMPLE=2, ST_EXCITE=3;
    localparam [3:0] ST_SETTLE=4, ST_REQ=5, ST_WAIT_CMP=6, ST_DECIDE=7;
    localparam [3:0] ST_TRIAL=8, ST_SCAN=9, ST_ADVANCE=10, ST_AVERAGE=11;
    localparam [3:0] ST_RESTORE=12, ST_WRITE=13, ST_PARK=14, ST_FINISH=15;
    reg [3:0] state_q;
    reg [4:0] target_q;
    reg [4:0] bit_q;
    reg polarity_q;
    reg decision_q;
    reg [((PAIR_LOG2<1) ? 1 : PAIR_LOG2)-1:0] pair_count_q;
    reg [WAIT_W-1:0] wait_q;
    reg [16:0] code_q;
    genvar cap;
    // 每两位字段交换位序：01对应P，10对应N，00对应共模M。
    generate
        for (cap=0; cap<20; cap=cap+1) begin : negative_array
            assign cal_bp_sel_b_o[2*cap+:2] = {cal_bp_sel_a_o[2*cap],cal_bp_sel_a_o[2*cap+1]};
        end
    endgenerate
    always @* begin
        case (state_q)
            ST_PRESET, ST_SAMPLE: phase_o = 3'b001;
            ST_EXCITE, ST_SETTLE, ST_REQ, ST_WAIT_CMP, ST_DECIDE,
            ST_TRIAL, ST_SCAN: phase_o = 3'b011;
            default: phase_o = 3'b000;
        endcase
        fault_bits = 0;
        case (state_q)
            ST_WAIT_CMP:
                if (!cmp_done_i && CMP_TIMEOUT!=0 && wait_q==CMP_TIMEOUT-1)
                    fault_bits = 3'b001;
            ST_SCAN:
                if (bit_q>=6 || code_q[bit_q])
                    fault_bits = !valid_q[bit_q] ? 3'b100 : ((result[ACC_W]!=result[ACC_W-1]) ? 3'b010 : 3'b000);
            ST_AVERAGE:
                if (sum_q<0 || result[ACC_W]!=result[ACC_W-1])
                    fault_bits = 3'b100;
            ST_RESTORE:
                if (result[ACC_W]!=result[ACC_W-1])
                    fault_bits = 3'b010;
            ST_WRITE:
                if (sum_q<=0 || sum_q>$signed({1'b0,{(WEIGHT_W-1){1'b1}}}))
                    fault_bits = 3'b100;
            default: fault_bits = 0;
        endcase
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE;
            target_q <= 6;
            bit_q <= 5;
            polarity_q <= 0;
            decision_q <= 0;
            pair_count_q <= 0;
            wait_q <= 0;
            code_q <= 0;
            cal_bp_sel_a_o <= 0;
            cmp_req_o <= 0;
            cal_release_ready_o <= 0;
            error_o <= 0;
        end else begin
            cmp_req_o <= 0;
            cal_release_ready_o <= 0;
            if (fault_bits!=0) begin
                error_o <= error_o | fault_bits;
                wait_q <= 0;
                state_q <= ST_PARK;
            end else case (state_q)
                ST_IDLE:
                    if (cal_go_i) begin
                        target_q <= 6;
                        pair_count_q <= 0;
                        polarity_q <= 0;
                        error_o <= 0;
                        state_q <= ST_PRESET;
                    end
                ST_PRESET: begin
                    cal_bp_sel_a_o <= {28'b0,2'b10,{5{2'b01}}}; // b19～b6、b5、b4～b0
                    code_q <= 0;
                    bit_q <= (target_q<18) ? target_q-1'b1 : 5'd16;
                    wait_q <= 0;
                    state_q <= ST_SAMPLE;
                end
                ST_SAMPLE, ST_SETTLE: begin
                    if (wait_q==((state_q==ST_SAMPLE) ? SAMPLE_CYCLES-1 : SETTLE_CYCLES-1)) begin
                        wait_q <= 0;
                        state_q <= (state_q==ST_SAMPLE) ? ST_EXCITE : ST_REQ;
                    end else
                        wait_q <= wait_q+1'b1;
                end
                ST_EXCITE: begin
                    cal_bp_sel_a_o[2*target_q+:2] <= polarity_q ? 2'b10 : 2'b01;
                    if (target_q>=18)
                        cal_bp_sel_a_o[35:34] <= polarity_q ? 2'b01 : 2'b10;
                    if (target_q==19)
                        cal_bp_sel_a_o[37:36] <= polarity_q ? 2'b01 : 2'b10;
                    wait_q <= 0;
                    state_q <= ST_SETTLE;
                end
                ST_REQ: begin
                    cmp_req_o <= 1;
                    wait_q <= 0;
                    state_q <= ST_WAIT_CMP;
                end
                ST_WAIT_CMP:
                    if (cmp_done_i) begin
                        decision_q <= cmp_result_i;
                        state_q <= ST_DECIDE;
                    end else if (CMP_TIMEOUT!=0)
                        wait_q <= wait_q+1'b1;
                ST_DECIDE: begin
                    if (bit_q>=6 || !decision_q)
                        cal_bp_sel_a_o[2*bit_q+:2] <= decision_q ? 2'b10 : 2'b01;
                    code_q[bit_q] <= (bit_q==5) ? !decision_q : decision_q;
                    if (bit_q>=6) begin
                        bit_q <= bit_q-1'b1;
                        wait_q <= 0;
                        state_q <= ST_SETTLE;
                    end else if (bit_q!=0) begin
                        bit_q <= bit_q-1'b1;
                        state_q <= ST_TRIAL;
                    end else begin
                        bit_q <= 0;
                        state_q <= ST_SCAN;
                    end
                end
                ST_TRIAL: begin
                    cal_bp_sel_a_o[2*bit_q+:2] <= 2'b10;
                    wait_q <= 0;
                    state_q <= ST_SETTLE;
                end
                ST_SCAN:
                    if (bit_q==((target_q<18) ? target_q-1'b1 : 5'd16))
                        state_q <= ST_ADVANCE;
                    else
                        bit_q <= bit_q+1'b1;
                ST_ADVANCE:
                    if (!polarity_q) begin
                        polarity_q <= 1;
                        state_q <= ST_PRESET;
                    end else if (pair_count_q==((1 << PAIR_LOG2)-1))
                        state_q <= ST_AVERAGE;
                    else begin
                        pair_count_q <= pair_count_q+1'b1;
                        polarity_q <= 0;
                        state_q <= ST_PRESET;
                    end
                ST_AVERAGE: begin
                    bit_q <= 17;
                    state_q <= (target_q>=18) ? ST_RESTORE : ST_WRITE;
                end
                ST_RESTORE:
                    if (target_q==19 && bit_q==17)
                        bit_q <= 18;
                    else
                        state_q <= ST_WRITE;
                ST_WRITE:
                    if (target_q==19) begin
                        wait_q <= 0;
                        state_q <= ST_PARK;
                    end else begin
                        target_q <= target_q+1'b1;
                        polarity_q <= 0;
                        pair_count_q <= 0;
                        state_q <= ST_PRESET;
                    end
                ST_PARK: begin
                    cal_bp_sel_a_o <= 0;
                    if (wait_q==PARK_CYCLES-1)
                        state_q <= ST_FINISH;
                    else
                        wait_q <= wait_q+1'b1;
                end
                ST_FINISH: begin
                    cal_release_ready_o <= 1;
                    state_q <= ST_IDLE;
                end
                default: begin
                    error_o[2] <= 1;
                    wait_q <= 0;
                    state_q <= ST_PARK;
                end
            endcase
        end
    end
    // ================= cal_calculation.v：直接形成带符号贡献并累加 =================
    always @* begin
        operand = 0;
        case (state_q)
            ST_SCAN: begin
                operand = $signed({{(ACC_W+1-WEIGHT_W){1'b0}},selected_w});
                if (bit_q<6)
                    operand = operand <<< 1;
                if (((bit_q>=6) ? !code_q[bit_q] : (bit_q==5)) ^ polarity_q)
                    operand = -operand;
            end
            ST_AVERAGE: operand = {{ACC_W{1'b0}},1'b1} << PAIR_LOG2;
            ST_RESTORE: operand = $signed({{(ACC_W+1-WEIGHT_W){1'b0}},selected_w});
            default: operand = 0;
        endcase
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            sum_q <= 0;
        else if (state_q==ST_IDLE && cal_go_i)
            sum_q <= 0;
        else if (state_q==ST_WRITE && fault_bits==0 && target_q!=19)
            sum_q <= 0;
        else if (fault_bits==0) begin
            case (state_q)
                ST_SCAN:
                    if (bit_q>=6 || code_q[bit_q])
                        sum_q <= $signed(result[ACC_W-1:0]);
                ST_AVERAGE: sum_q <= $signed(result[ACC_W-1:0]) >>> (PAIR_LOG2+1);
                ST_RESTORE: sum_q <= $signed(result[ACC_W-1:0]);
                default: ; // 其他状态保持累计值。
            endcase
        end
    end
    // ================= weight_regs.v：低六位标称权重、高十四位校准权重 =================
    reg [WEIGHT_W-1:0] weight_q [6:19];
    reg [4:0] weight_addr;
    reg [4:0] weight_index;
    always @* begin
        weight_addr = (state_q==ST_IDLE) ? weight_rd_addr_i : 5'd0;
        if (state_q==ST_SCAN || state_q==ST_RESTORE)
            weight_addr = bit_q;
        case (weight_addr)
            0: selected_w = (1 << FRAC_BITS);
            1: selected_w = (2 << FRAC_BITS);
            2: selected_w = (4 << FRAC_BITS);
            3: selected_w = (8 << FRAC_BITS);
            4: selected_w = (16 << FRAC_BITS);
            5: selected_w = (32 << FRAC_BITS);
            default: selected_w = (weight_addr>=6 && weight_addr<=19) ? weight_q[weight_addr] : 0;
        endcase
        weight_rd_data_o = 0;
        weight_rd_valid_o = 0;
        if (state_q==ST_IDLE && weight_rd_addr_i<20) begin
            weight_rd_data_o = selected_w;
            weight_rd_valid_o = valid_q[weight_rd_addr_i];
        end
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= 20'h0003f;
            weights_valid_o <= 0;
            for (weight_index=6; weight_index<20; weight_index=weight_index+1)
                weight_q[weight_index] <= 0;
        end else begin
            if (state_q==ST_IDLE && cal_go_i) begin
                valid_q <= 20'h0003f;
                weights_valid_o <= 0;
            end
            if (state_q==ST_WRITE && fault_bits==0) begin
                weight_q[target_q] <= sum_q[WEIGHT_W-1:0];
                valid_q[target_q] <= 1;
            end
            if (state_q==ST_FINISH)
                weights_valid_o <= (error_o==0);
        end
    end
endmodule
```

## 3. ala_logic.v

[打开源码](<ala_logic.v#L1>)

running_q 表示正在执行，averaging_q 表示已进入平均，outstanding_q 表示请求已经接受、正在等待响应。index_o 保存比较序号，limit_q 保存本次预算，timeout_q 对请求和响应等待分别计时。

进入平均之前，搜索判决一直同号，所以 search_sum_o 的符号可以表示上一搜索判决。第一次判决以后，decision_i 等于 search_sum_o 的符号位时说明出现翻转，后续请求的 repeat_o 变为0。

翻转那次判决仍计入搜索和。控制块和计算块在同一时钟沿读取的是沿前的 averaging_q，因此这次搜索步与后续只比较的平均阶段能够分开统计。

search_sum_o、avg_sum_o、avg_count_o 分别保存 S、A、M。总次数允许1～10。M=0时，顶层记录缺少平均样本，重构只使用搜索修正。done_o 配合 error_o 表示本次工作是否成功。

### 源码

```verilog
module ala_logic #(
    parameter [31:0] TIMEOUT_CYCLES = 65536
) (
    input wire clk_i,
    input wire rst_ni,
    input wire start_i,
    input wire [3:0] comparisons_i,
    output reg done_o,
    output reg [1:0] error_o,
    output wire req_valid_o,
    input wire req_ready_i,
    output wire repeat_o,
    output reg [3:0] index_o,
    input wire rsp_valid_i,
    output wire rsp_ready_o,
    input wire decision_i,
    input wire fault_i,
    output reg cancel_o,
    output reg signed [4:0] search_sum_o,
    output reg signed [4:0] avg_sum_o,
    output reg [3:0] avg_count_o
);
    // ================= ala_LSB_repeat：请求、翻转检测与平均阶段控制 =================
    localparam WAIT_W = (TIMEOUT_CYCLES>1) ? $clog2(TIMEOUT_CYCLES) : 1;
    reg running_q;
    reg averaging_q;
    reg outstanding_q;
    reg [3:0] limit_q;
    reg [WAIT_W-1:0] timeout_q;
    assign req_valid_o = running_q && !outstanding_q;
    assign rsp_ready_o = running_q && outstanding_q;
    assign repeat_o = running_q && !averaging_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            running_q <= 0;
            averaging_q <= 0;
            outstanding_q <= 0;
            index_o <= 0;
            limit_q <= 0;
            timeout_q <= 0;
            done_o <= 0;
            error_o <= 0;
            cancel_o <= 0;
        end else begin
            done_o <= 0;
            cancel_o <= 0;
            if (!running_q) begin
                if (start_i) begin
                    index_o <= 0;
                    limit_q <= comparisons_i;
                    averaging_q <= 0;
                    outstanding_q <= 0;
                    timeout_q <= 0;
                    error_o <= 0;
                    if (comparisons_i==0 || comparisons_i>10) begin
                        error_o[1] <= 1;
                        done_o <= 1;
                    end else
                        running_q <= 1;
                end
            end else if (req_valid_o && req_ready_i) begin
                outstanding_q <= 1;
                timeout_q <= 0;
            end else if (rsp_valid_i && rsp_ready_o) begin
                timeout_q <= 0;
                outstanding_q <= 0;
                if (fault_i) begin
                    error_o[1] <= 1;
                    running_q <= 0;
                    done_o <= 1;
                    cancel_o <= 1;
                end else begin
                    // 翻转之前搜索判决同号，搜索和的符号可代表上一次判决。
                    if (!averaging_q && index_o!=0 && decision_i==search_sum_o[4])
                        averaging_q <= 1;
                    if (index_o+1>=limit_q) begin
                        running_q <= 0;
                        done_o <= 1;
                    end else
                        index_o <= index_o+1'b1;
                end
            end else if (TIMEOUT_CYCLES<=1 || timeout_q==TIMEOUT_CYCLES-1) begin
                running_q <= 0;
                outstanding_q <= 0;
                done_o <= 1;
                error_o[0] <= 1;
                cancel_o <= 1;
            end else
                timeout_q <= timeout_q+1'b1;
        end
    end
    // ================= ala_calculation：翻转判决仍计入搜索项 =================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            search_sum_o <= 0;
            avg_sum_o <= 0;
            avg_count_o <= 0;
        end else if (!running_q && start_i) begin
            search_sum_o <= 0;
            avg_sum_o <= 0;
            avg_count_o <= 0;
        end else if (rsp_valid_i && rsp_ready_o && !fault_i) begin
            if (!averaging_q)
                search_sum_o <= search_sum_o+(decision_i ? 5'sd1 : -5'sd1);
            else begin
                avg_sum_o <= avg_sum_o+(decision_i ? 5'sd1 : -5'sd1);
                avg_count_o <= avg_count_o+1'b1;
            end
        end
    end
endmodule
```

## 4. flash_decode.v

[打开源码](<flash_decode.v#L1>)

capture_i 有效的时钟沿，模块检查 thermometer_i 并保存结果。000、001、011、111 分别产生00、01、10、11；其他模式产生无效结果。

源码右侧三位常量的最高位是 valid_o，低两位是 code_o。例如3'b110表示有效且粗码为10。capture_i 为0时保持结果，供后续 SAR 使用。

### 源码

```verilog
module flash_decode (
    input wire clk_i,
    input wire rst_ni,
    input wire capture_i,
    input wire [2:0] thermometer_i,
    output reg [1:0] code_o,
    output reg valid_o
);
    // 右侧三位依次为有效标志、两位粗码，非法温度计码清零。
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            {valid_o,code_o} <= 3'b000;
        else if (capture_i) begin
            case (thermometer_i)
                3'b000: {valid_o,code_o} <= 3'b100;
                3'b001: {valid_o,code_o} <= 3'b101;
                3'b011: {valid_o,code_o} <= 3'b110;
                3'b111: {valid_o,code_o} <= 3'b111;
                default: {valid_o,code_o} <= 3'b000;
            endcase
        end
    end
endmodule
```

## 5. code_reconstruction.v

[打开源码](<code_reconstruction.v#L1>)

重构先读取二十项权重，符号码为1时加权重，为0时减权重。随后计算搜索修正 S×ALA_STEP 和平均修正 A×ALA_STEP/M，再进行增益缩放、舍入、偏移与饱和。

remaining_q 在搜索修正阶段保存 |S|，在平均分子阶段保存 |A|。divide_q 先累加平均分子，除法时将尚未处理的分子放在高位，将逐次产生的商移入低位。bit_q 先扫描0～19，再在除法入口清零，计数 NUM_W 次。

remainder_q 保存余数。M 为1～10时，trial 的最高位能表示试探减法是否为负，进而决定保存减法结果还是恢复试探余数。整个除法按位执行。

operand 形成扫描、搜索和平均三个阶段的带符号贡献。scale_operand 在 SCALE 之外为0，product_q 保存乘积，output_value 根据乘积符号完成最近舍入与半值远离零处理，再加偏移。输出饱和到有符号16位范围后，转为偏移二进制。

从接受 start_i 到 done_o 有效，调用方需要保持符号码、ALA 统计、ALA 使能、步长、增益与偏移稳定。整机顶层提供这项保证。weight_data_i 和 weight_valid_i 则按 weight_addr_o 对应当前扫描项。

### 源码

```verilog
module code_reconstruction #(
    parameter [31:0] WEIGHT_W = 32,
    parameter [31:0] FRAC_BITS = 8
) (
    input wire clk_i,
    input wire rst_ni,
    input wire start_i,
    input wire [19:0] sign_code_i,
    input wire ala_enable_i,
    input wire signed [4:0] search_sum_i,
    input wire signed [4:0] avg_sum_i,
    input wire [3:0] avg_count_i,
    input wire [WEIGHT_W-1:0] ala_step_i,
    input wire [31:0] gain_q16_i,
    input wire signed [31:0] offset_i,
    output wire [4:0] weight_addr_o,
    input wire [WEIGHT_W-1:0] weight_data_i,
    input wire weight_valid_i,
    output reg done_o,
    output reg error_o,
    output reg [15:0] code_o
);
    // 顶层在本次重构结束前保持符号码、ALA统计和数值配置稳定。
    localparam ACC_W = WEIGHT_W+8;
    localparam NUM_W = WEIGHT_W+4;
    localparam [2:0] IDLE=0, SCAN=1, SEARCH_CORRECTION=2, BUILD_NUMERATOR=3;
    localparam [2:0] DIVIDE=4, APPLY_AVERAGE=5, SCALE=6, OUTPUT_CODE=7;
    reg [2:0] state_q;
    reg [5:0] bit_q;
    reg signed [ACC_W-1:0] sum_q;
    reg [3:0] remaining_q;
    reg [NUM_W-1:0] divide_q;
    reg [3:0] remainder_q;
    reg signed [ACC_W+32:0] product_q;
    reg signed [ACC_W-1:0] operand;
    reg signed [ACC_W+32:0] output_value;
    wire signed [ACC_W-1:0] scale_operand = (state_q==SCALE) ? sum_q : 0;
    wire [4:0] trial = {remainder_q,divide_q[NUM_W-1]}-{1'b0,avg_count_i};
    assign weight_addr_o = bit_q[4:0];
    // ================= 计算选择：共用加法贡献、输出舍入与饱和前的值 =================
    always @* begin
        operand = 0;
        case (state_q)
            SCAN: begin
                operand = $signed({{(ACC_W-WEIGHT_W){1'b0}},weight_data_i});
                if (!sign_code_i[bit_q])
                    operand = -operand;
            end
            SEARCH_CORRECTION: begin
                operand = $signed({{(ACC_W-WEIGHT_W){1'b0}},ala_step_i});
                if (!search_sum_i[4])
                    operand = -operand;
            end
            APPLY_AVERAGE: begin
                operand = $signed({{(ACC_W-NUM_W){1'b0}},divide_q});
                if (!avg_sum_i[4])
                    operand = -operand;
            end
            default: operand = 0;
        endcase
        output_value = product_q[ACC_W+32] ? -product_q : product_q;
        output_value = (output_value+($signed({{(ACC_W+32){1'b0}},1'b1}) << (FRAC_BITS+15))) >>> (FRAC_BITS+16);
        if (product_q[ACC_W+32])
            output_value = -output_value;
        output_value = output_value+$signed({{(ACC_W+1){offset_i[31]}},offset_i});
    end
    // ================= 串行计算：位扫描、修正、移位除法和输出 =================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            bit_q <= 0;
            sum_q <= 0;
            remaining_q <= 0;
            divide_q <= 0;
            remainder_q <= 0;
            product_q <= 0;
            done_o <= 0;
            error_o <= 0;
            code_o <= 16'h8000;
        end else begin
            done_o <= 0;
            case (state_q)
                IDLE:
                    if (start_i) begin
                        error_o <= 0;
                        if (gain_q16_i==0 || (ala_enable_i && (ala_step_i==0 || avg_count_i>10 ||
                            search_sum_i>5'sd10 || search_sum_i < -5'sd10 ||
                            avg_sum_i>$signed({1'b0,avg_count_i}) || avg_sum_i < -$signed({1'b0,avg_count_i})))) begin
                            error_o <= 1;
                            done_o <= 1;
                        end else begin
                            bit_q <= 0;
                            sum_q <= 0;
                            // 范围检查已保证绝对值不超过10，计数只需4位。
                            remaining_q <= !ala_enable_i ? 4'd0 : (search_sum_i[4] ? -search_sum_i[3:0] : search_sum_i[3:0]);
                            divide_q <= 0;
                            remainder_q <= 0;
                            state_q <= SCAN;
                        end
                    end
                SCAN:
                    if (!weight_valid_i || weight_data_i[WEIGHT_W-1]) begin
                        error_o <= 1;
                        done_o <= 1;
                        state_q <= IDLE;
                    end else begin
                        sum_q <= sum_q+operand;
                        if (bit_q==19)
                            state_q <= SEARCH_CORRECTION;
                        else
                            bit_q <= bit_q+1'b1;
                    end
                SEARCH_CORRECTION:
                    if (remaining_q==0) begin
                        remaining_q <= !ala_enable_i ? 4'd0 : (avg_sum_i[4] ? -avg_sum_i[3:0] : avg_sum_i[3:0]);
                        state_q <= BUILD_NUMERATOR;
                    end else begin
                        remaining_q <= remaining_q-1'b1;
                        sum_q <= sum_q+operand;
                    end
                BUILD_NUMERATOR:
                    if (remaining_q==0) begin
                        if (!ala_enable_i || avg_count_i==0)
                            state_q <= SCALE;
                        else begin
                            bit_q <= 0;
                            state_q <= DIVIDE;
                        end
                    end else begin
                        divide_q <= divide_q+{{(NUM_W-WEIGHT_W){1'b0}},ala_step_i};
                        remaining_q <= remaining_q-1'b1;
                    end
                DIVIDE: begin
                    // 未处理的分子在高位，已产生的商从低位依次移入。
                    divide_q <= {divide_q[NUM_W-2:0],!trial[4]};
                    remainder_q <= trial[4] ? {remainder_q[2:0],divide_q[NUM_W-1]} : trial[3:0];
                    if (bit_q==NUM_W-1)
                        state_q <= APPLY_AVERAGE;
                    else
                        bit_q <= bit_q+1'b1;
                end
                APPLY_AVERAGE: begin
                    sum_q <= sum_q+operand;
                    state_q <= SCALE;
                end
                SCALE: begin
                    product_q <= $signed({{33{scale_operand[ACC_W-1]}},scale_operand}) *
                        $signed({{(ACC_W+1){1'b0}},gain_q16_i});
                    state_q <= OUTPUT_CODE;
                end
                OUTPUT_CODE: begin
                    if (output_value>32767)
                        code_o <= 16'hffff;
                    else if (output_value < -32768)
                        code_o <= 16'h0000;
                    else
                        code_o <= output_value[15:0]^16'h8000;
                    done_o <= 1;
                    state_q <= IDLE;
                end
                default: begin
                    error_o <= 1;
                    done_o <= 1;
                    state_q <= IDLE;
                end
            endcase
        end
    end
endmodule
```

## 6. clk_timing.v

[打开源码](<clk_timing.v#L1>)

count_q 是内部周期计数。使能且周期非零时逐拍增加，达到当前 period_cycles_i 后清零，并发一拍 sample_tick_o。

周期输入为可运行时修改的32位数。每拍使用当前周期判断，所以调小周期后，已经累计的计数也会与新周期比较。停用或周期为0时计数清零。

### 源码

```verilog
module clk_timing (
    input wire clk_i,
    input wire rst_ni,
    input wire enable_i,
    input wire [31:0] period_cycles_i,
    output reg sample_tick_o
);
    // 32位周期可运行时调整，计数按当前周期值判断。
    reg [31:0] count_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= 0;
            sample_tick_o <= 0;
        end else begin
            sample_tick_o <= 0;
            if (!enable_i || period_cycles_i==0)
                count_q <= 0;
            else if (count_q+1>=period_cycles_i) begin
                count_q <= 0;
                sample_tick_o <= 1;
            end else
                count_q <= count_q+1'b1;
        end
    end
endmodule
```

## 7. digital_regs.v

[打开源码](<digital_regs.v#L1>)

读组合块按地址选择配置、状态、最近输出和权重。写时序块保存配置，同时产生校准启动、采样启动、清错和写入拒绝脉冲。

last_code_q 保存读口接收到的最近有效输出。data_seen_q 表示是否已经接收过输出，frame_count_q 对成功输出计数并按32位自然回绕。读口的数据记录时机由 code_valid_i 决定。

CONTROL 的 bit4 发清错脉冲。忙时只有专用0x10清错命令能够接受；空闲时配置按地址更新。ALA_N允许1～10，WEIGHT_ADDR允许0～19，PERIOD要求非零，非法写入产生 rejected_o。

STATUS 的配置有效位由增益非零、ALA使能及步长非零的条件直接计算。权重调试读取还要求整机空闲和单项权重有效。

### 源码

```verilog
module digital_regs #(
    parameter [31:0] WEIGHT_W = 32
) (
    input wire clk_i,
    input wire rst_ni,
    input wire [7:0] addr_i,
    input wire wr_en_i,
    input wire [31:0] wr_data_i,
    output reg [31:0] rd_data_o,
    input wire busy_i,
    input wire weights_valid_i,
    input wire [7:0] errors_i,
    input wire code_valid_i,
    input wire [15:0] code_i,
    input wire [WEIGHT_W-1:0] weight_data_i,
    input wire weight_valid_i,
    output reg [4:0] weight_addr_o,
    output reg enable_o,
    output reg ala_enable_o,
    output reg continuous_o,
    output reg [3:0] comparisons_o,
    output reg [WEIGHT_W-1:0] ala_step_o,
    output reg [31:0] gain_q16_o,
    output reg signed [31:0] offset_o,
    output reg [31:0] period_cycles_o,
    output reg cal_start_o,
    output reg sample_start_o,
    output reg clear_errors_o,
    output reg rejected_o
);
    // ================= 读映射：配置、状态、结果和逐项权重 =================
    reg [15:0] last_code_q;
    reg data_seen_q;
    reg [31:0] frame_count_q;
    always @* begin
        rd_data_o = 0;
        case (addr_i)
            8'h00: rd_data_o = 32'hadc01601;
            8'h04: rd_data_o = {26'd0,continuous_o,3'b000,ala_enable_o,enable_o};
            8'h08: rd_data_o = {16'd0,errors_i,4'd0,data_seen_q,
                (gain_q16_o!=0 && (!ala_enable_o || ala_step_o!=0)),weights_valid_i,busy_i};
            8'h0c: rd_data_o = {28'd0,comparisons_o};
            8'h10: rd_data_o = {{(32-WEIGHT_W){1'b0}},ala_step_o};
            8'h14: rd_data_o = gain_q16_o;
            8'h18: rd_data_o = $unsigned(offset_o);
            8'h1c: rd_data_o = {16'd0,last_code_q};
            8'h20: rd_data_o = frame_count_q;
            8'h24: rd_data_o = {27'd0,weight_addr_o};
            8'h28:
                if (!busy_i && weight_valid_i)
                    rd_data_o = {{(32-WEIGHT_W){1'b0}},weight_data_i};
            8'h2c: rd_data_o = {31'd0,(!busy_i && weight_valid_i)};
            8'h30: rd_data_o = period_cycles_o;
            default: rd_data_o = 0;
        endcase
    end
    // ================= 写映射：忙时只接受专用清错命令 =================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            weight_addr_o <= 0;
            enable_o <= 1;
            ala_enable_o <= 1;
            continuous_o <= 0;
            comparisons_o <= 10;
            ala_step_o <= 0;
            gain_q16_o <= 0;
            offset_o <= 0;
            period_cycles_o <= 1000;
            cal_start_o <= 0;
            sample_start_o <= 0;
            clear_errors_o <= 0;
            rejected_o <= 0;
            last_code_q <= 16'h8000;
            data_seen_q <= 0;
            frame_count_q <= 0;
        end else begin
            cal_start_o <= 0;
            sample_start_o <= 0;
            clear_errors_o <= 0;
            rejected_o <= 0;
            if (code_valid_i) begin
                last_code_q <= code_i;
                data_seen_q <= 1;
                frame_count_q <= frame_count_q+1'b1;
            end
            if (wr_en_i) begin
                if (addr_i==8'h04 && wr_data_i[4])
                    clear_errors_o <= 1;
                if (busy_i) begin
                    if (addr_i!=8'h04 || wr_data_i!=32'h00000010)
                        rejected_o <= 1;
                end else case (addr_i)
                    8'h04:
                        if (wr_data_i!=32'h00000010) begin
                            enable_o <= wr_data_i[0];
                            ala_enable_o <= wr_data_i[1];
                            cal_start_o <= wr_data_i[2];
                            sample_start_o <= wr_data_i[3];
                            continuous_o <= wr_data_i[5];
                        end
                    8'h0c:
                        if (wr_data_i>=1 && wr_data_i<=10)
                            comparisons_o <= wr_data_i[3:0];
                        else
                            rejected_o <= 1;
                    8'h10: ala_step_o <= wr_data_i[WEIGHT_W-1:0];
                    8'h14: gain_q16_o <= wr_data_i;
                    8'h18: offset_o <= $signed(wr_data_i);
                    8'h24:
                        if (wr_data_i<20)
                            weight_addr_o <= wr_data_i[4:0];
                        else
                            rejected_o <= 1;
                    8'h30:
                        if (wr_data_i!=0)
                            period_cycles_o <= wr_data_i;
                        else
                            rejected_o <= 1;
                    default: rejected_o <= 1;
                endcase
            end
        end
    end
endmodule
```

## 8. spi_4wire.v

[打开源码](<spi_4wire.v#L1>)

SPI使用模式0，每帧按MSB先行传输8位命令、8位地址、32位数据。command_q 保存读、写或非法三类，addr_o 在地址字节结束时保存地址。

wr_data_o 逐位移入接收数据，始终保留最近32位。收到完整写帧后，这32位就是数据字，wr_en_o 随之拉高一拍。只有写使能有效时，地址和写数据才构成一次提交。

收到地址后，read_pending_q 留出一个 clk_i 周期让寄存器读口更新，再将 rd_data_i 快照装入 tx_q。数据段在SCLK下降沿移出，CS拉高时清除帧状态。

CS和MOSI通过两级采样进入 clk_i 域，SCLK使用三级采样检测边沿。使用时要求 clk_i 至少为SCLK的8倍，CS建立、保持和帧间高电平各至少4个 clk_i 周期。

### 源码

```verilog
module spi_4wire (
    input wire clk_i,
    input wire rst_ni,
    input wire cs_ni,
    input wire sclk_i,
    input wire mosi_i,
    output wire miso_o,
    input wire [31:0] rd_data_i,
    output reg [7:0] addr_o,
    output reg [31:0] wr_data_o,
    output reg wr_en_o
);
    // 模式0，每帧48位。wr_data_o兼作接收移位寄存器，仅wr_en_o为1时提交。
    reg [1:0] cs_q;
    reg [2:0] sclk_q;
    reg [1:0] mosi_q;
    reg [5:0] count_q;
    reg [31:0] tx_q;
    reg [1:0] command_q;
    reg read_pending_q;
    assign miso_o = !cs_ni && !cs_q[1] ? tx_q[31] : 1'b0;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cs_q <= 2'b11;
            sclk_q <= 0;
            mosi_q <= 0;
        end else begin
            cs_q <= {cs_q[0],cs_ni};
            sclk_q <= {sclk_q[1:0],sclk_i};
            mosi_q <= {mosi_q[0],mosi_i};
        end
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= 0;
            tx_q <= 0;
            command_q <= 0;
            read_pending_q <= 0;
            addr_o <= 0;
            wr_data_o <= 0;
            wr_en_o <= 0;
        end else begin
            wr_en_o <= 0;
            if (cs_q[1]) begin
                count_q <= 0;
                tx_q <= 0;
                command_q <= 0;
                read_pending_q <= 0;
                wr_data_o <= 0;
            end else begin
                if (read_pending_q) begin
                    read_pending_q <= 0;
                    tx_q <= (command_q==0) ? rd_data_i : 32'd0;
                end
                if (sclk_q[1] && !sclk_q[2] && count_q<48) begin
                    wr_data_o <= {wr_data_o[30:0],mosi_q[1]};
                    count_q <= count_q+1'b1;
                    if (count_q==7) begin
                        // 保存命令类别：0读、1写、2非法。
                        case ({wr_data_o[6:0],mosi_q[1]})
                            8'h00: command_q <= 0;
                            8'h80: command_q <= 1;
                            default: command_q <= 2;
                        endcase
                    end
                    if (count_q==15) begin
                        addr_o <= {wr_data_o[6:0],mosi_q[1]};
                        read_pending_q <= 1;
                    end
                    if (count_q==47 && command_q==1)
                        wr_en_o <= 1;
                end
                if (!sclk_q[1] && sclk_q[2] && count_q>16 && count_q<=48)
                    tx_q <= {tx_q[30:0],1'b0};
            end
        end
    end
endmodule
```

