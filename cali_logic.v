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
