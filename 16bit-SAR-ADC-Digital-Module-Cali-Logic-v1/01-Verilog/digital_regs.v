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
