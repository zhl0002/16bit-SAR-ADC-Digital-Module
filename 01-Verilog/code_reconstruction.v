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
