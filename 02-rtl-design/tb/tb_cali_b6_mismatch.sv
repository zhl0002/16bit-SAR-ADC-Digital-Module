`timescale 1ns/1ps

module tb_cali_b6_mismatch;

    // 测试程序驱动的输入
    reg clk        = 1'b0;
    reg rst_n      = 1'b0;
    reg go         = 1'b0;
    reg cmp_result = 1'b0;
    reg cmp_done   = 1'b0;
    reg [4:0] rd_addr = 5'd0;

    // 接收设计模块的输出
    wire req;
    wire released;
    wire weights_valid;
    wire rd_valid;

    wire [2:0] error_code;
    wire [2:0] phase;
    wire [39:0] sel_a;
    wire [39:0] sel_b;
    wire [31:0] rd_data;

    // 实例化被测试的校准模块
    cali_logic dut (
        .clk_i(clk),
        .rst_ni(rst_n),
        .cal_go_i(go),
        .cmp_result_i(cmp_result),
        .cmp_done_i(cmp_done),

        .cmp_req_o(req),
        .cal_release_ready_o(released),
        .weights_valid_o(weights_valid),
        .error_o(error_code),
        .phase_o(phase),
        .cal_bp_sel_a_o(sel_a),
        .cal_bp_sel_b_o(sel_b),

        .weight_rd_addr_i(rd_addr),
        .weight_rd_data_o(rd_data),
        .weight_rd_valid_o(rd_valid)
    );

    // 时钟每 5 ns 翻转一次，周期为 10 ns
    always #5 clk = ~clk;

    // 记录波形
    initial begin
        $dumpfile("cali_b6_mismatch.vcd");
        $dumpvars(0, tb_cali_b6_mismatch);
    end

    // 先复位，再发出一个周期的启动信号
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        go = 1'b1;

        @(negedge clk);
        go = 1'b0;
    end

        // 等效权重：C0 至 C5 为标称值，C6 设为 33 以测试权重偏差
    integer model_w [0:6];

    initial begin
        model_w[0] = 1;
        model_w[1] = 2;
        model_w[2] = 4;
        model_w[3] = 8;
        model_w[4] = 16;
        model_w[5] = 32;
        model_w[6] = 33;
    end

    // 将开关编码转换为归一化电平
    function automatic integer switch_level(
        input [1:0] selection
    );
        begin
            case (selection)
                2'b00: switch_level = 0;   // 共模
                2'b01: switch_level = 1;   // 正参考
                2'b10: switch_level = -1;  // 负参考

                default: begin
                    switch_level = 0;
                    $fatal(1, "Invalid or unknown CDAC selection");
                end
            endcase
        end
    endfunction

    // 保存采样连接，并记录残差和请求次数
    reg [39:0] sampled_sel = 40'd0;
    integer residual_model = 0;
    integer request_count = 0;
    integer cap_idx;

    always @(negedge clk) begin
        if (!rst_n) begin
            sampled_sel = 40'd0;
            residual_model = 0;
            request_count = 0;

            cmp_result <= 1'b0;
            cmp_done   <= 1'b0;
        end else begin
            // 完成信号默认拉低，响应时保持一个周期
            cmp_done <= 1'b0;

            // phase=001 对应预置和采样阶段
            if (phase == 3'b001)
                sampled_sel = sel_a;

            if (req == 1'b1) begin
                // 本模型只用于 b6，避免误用于其他目标
                if (dut.target_q !== 5'd6)
                    $fatal(1, "This model only supports target b6");

                residual_model = 0;

                for (cap_idx = 0; cap_idx <= 6;
                     cap_idx = cap_idx + 1) begin

                    residual_model = residual_model
                        + model_w[cap_idx]
                        * (
                            switch_level(
                                sel_a[2*cap_idx +: 2]
                            )
                            - switch_level(
                                sampled_sel[2*cap_idx +: 2]
                            )
                          );
                end

                request_count = request_count + 1;

                cmp_result <= (residual_model >= 0);
                cmp_done   <= 1'b1;
            end
        end
    end

        // 检查 b6 的校准结果
    always @(posedge clk) begin
        // 等待设计中的非阻塞赋值更新完成
        #1;

        if (rst_n) begin
            if (error_code !== 3'b000)
                $fatal(1,
                    "Calibration error: error_o=%b",
                    error_code);

            // b6 权重已经写入
            if (dut.valid_q[6] === 1'b1) begin

                if (dut.weight_q[6] !== 32'd8448)
                    $fatal(1,
                        "Wrong b6 weight: actual=%0d expected=8448",
                        dut.weight_q[6]);

                if (request_count != 384)
                    $fatal(1,
                        "Wrong request count: actual=%0d expected=384",
                        request_count);

                // 本测试只完成 b6，整组权重尚未全部有效
                if (weights_valid !== 1'b0)
                    $fatal(1,
                        "All weights unexpectedly marked valid");

                $display("PASS: b6 mismatch calibration");
                $display("b6 weight = %0d",
                         dut.weight_q[6]);
                $display("comparison requests = %0d",
                         request_count);

                $finish;
            end
        end
    end

    // 限制整个测试的最长时间，避免无限运行
    initial begin
        #200000;
        $fatal(1,
            "Test timeout: b6 calibration did not complete");
    end

endmodule
