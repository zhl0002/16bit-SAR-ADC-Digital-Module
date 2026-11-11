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
