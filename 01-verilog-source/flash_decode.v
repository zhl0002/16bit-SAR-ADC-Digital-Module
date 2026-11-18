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
