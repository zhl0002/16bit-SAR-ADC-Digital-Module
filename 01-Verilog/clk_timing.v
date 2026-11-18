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
