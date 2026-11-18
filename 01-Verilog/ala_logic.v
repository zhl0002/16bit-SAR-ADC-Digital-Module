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
