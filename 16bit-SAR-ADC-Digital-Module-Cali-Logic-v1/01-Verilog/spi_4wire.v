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
