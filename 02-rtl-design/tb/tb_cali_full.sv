`timescale 1ns/1ps

module tb_cali_full;

    // 测试程序驱动的输入
    reg clk        = 1'b0;
    reg rst_n      = 1'b0;
    reg go         = 1'b0;
    reg cmp_result = 1'b0;
    reg cmp_done   = 1'b0;
    reg [4:0] rd_addr = 5'd0;

    // 接收校准模块的输出
    wire req;
    wire released;
    wire weights_valid;
    wire rd_valid;

    wire [2:0] error_code;
    wire [2:0] phase;
    wire [39:0] sel_a;
    wire [39:0] sel_b;
    wire [31:0] rd_data;

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

    // 仿真时钟周期为 10 ns
    always #5 clk = ~clk;

    initial begin
        $dumpfile("cali_full.vcd");
        $dumpvars(0, tb_cali_full);
    end

    // 复位后启动一次完整校准
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        go = 1'b1;

        @(negedge clk);
        go = 1'b0;
    end

        // 根据四段电容网络得到的等效位权
    // 所有权重统一乘以 12，避免使用小数
    integer model_w [0:19];

    initial begin
        model_w[0]  = 12;
        model_w[1]  = 24;
        model_w[2]  = 48;
        model_w[3]  = 96;
        model_w[4]  = 192;
        model_w[5]  = 384;

        model_w[6]  = 402;
        model_w[7]  = 804;
        model_w[8]  = 1608;
        model_w[9]  = 3216;

        model_w[10] = 3795;
        model_w[11] = 3795;
        model_w[12] = 7590;
        model_w[13] = 15180;
        model_w[14] = 30360;

        model_w[15] = 60184;
        model_w[16] = 60184;
        model_w[17] = 120368;
        model_w[18] = 240736;
        model_w[19] = 481472;
    end

    // 将开关编码转换为参考电平
    function automatic integer switch_level(
        input [1:0] selection
    );
        begin
            case (selection)
                2'b00: switch_level = 0;
                2'b01: switch_level = 1;
                2'b10: switch_level = -1;

                default: begin
                    switch_level = 0;
                    $fatal(1,
                        "Invalid or unknown CDAC selection");
                end
            endcase
        end
    endfunction

    // 保存采样连接，记录当前比较残差和请求次数
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
            cmp_done <= 1'b0;

            // 采样阶段跟踪电容的初始连接
            if (phase == 3'b001)
                sampled_sel = sel_a;

            if (req == 1'b1) begin
                residual_model = 0;

                // 全部 20 个电容共同贡献比较残差
                for (cap_idx = 0; cap_idx < 20;
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

        // 当前电容模型对应的独立算法参考结果
    // 单位与 DUT 一致：8 位小数的定点数
    integer reference_q8 [0:19];

    initial begin
        reference_q8[0]  = 256;
        reference_q8[1]  = 512;
        reference_q8[2]  = 1024;
        reference_q8[3]  = 2048;
        reference_q8[4]  = 4096;
        reference_q8[5]  = 8192;

        reference_q8[6]  = 8448;
        reference_q8[7]  = 16896;
        reference_q8[8]  = 33792;
        reference_q8[9]  = 67584;

        reference_q8[10] = 79872;
        reference_q8[11] = 79872;
        reference_q8[12] = 159744;
        reference_q8[13] = 319488;
        reference_q8[14] = 638976;

        reference_q8[15] = 1266688;
        reference_q8[16] = 1266688;
        reference_q8[17] = 2533376;
        reference_q8[18] = 5066752;
        reference_q8[19] = 10133504;
    end

    integer rd_index;
    real measured_weight;
    real true_weight;
    real error_weight;

    initial begin
        // 等待完整校准退出
        wait (released === 1'b1);

        // 等待同一时钟沿的寄存器更新完成
        #1;

        if (error_code !== 3'b000)
            $fatal(1,
                "Calibration failed: error_o=%b",
                error_code);

        if (weights_valid !== 1'b1)
            $fatal(1,
                "Calibration exited without valid weights");

        if (request_count != 11008)
            $fatal(1,
                "Wrong request count: actual=%0d expected=11008",
                request_count);

        if ((sel_a !== 40'd0) || (sel_b !== 40'd0))
            $fatal(1,
                "CDAC commands were not parked");

        // 退出标志应为一个时钟周期的脉冲
        @(posedge clk);
        #1;

        if (released !== 1'b0)
            $fatal(1,
                "Release pulse did not clear");

        $display(
            "addr,dut_q8,reference_q8,true_weight,error_W0");

        // 通过正式读取接口检查全部 20 个权重
        for (rd_index = 0; rd_index < 20;
             rd_index = rd_index + 1) begin

            @(negedge clk);
            rd_addr = rd_index[4:0];

            // 等待组合读取逻辑稳定
            #1;

            if (rd_valid !== 1'b1)
                $fatal(1,
                    "Invalid weight read: address=%0d",
                    rd_index);

            if (rd_data !== reference_q8[rd_index])
                $fatal(1,
                    "Weight mismatch: addr=%0d actual=%0d expected=%0d",
                    rd_index,
                    rd_data,
                    reference_q8[rd_index]);

            measured_weight = $itor(rd_data) / 256.0;
            true_weight = $itor(model_w[rd_index]) / 12.0;
            error_weight = measured_weight - true_weight;

            $display("%0d,%0d,%0d,%0.6f,%0.6f",
                rd_index,
                rd_data,
                reference_q8[rd_index],
                true_weight,
                error_weight);
        end

        // 检查范围以外的读取地址
        @(negedge clk);
        rd_addr = 5'd20;
        #1;

        if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
            $fatal(1,
                "Out-of-range address 20 was not rejected");

        @(negedge clk);
        rd_addr = 5'd31;
        #1;

        if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
            $fatal(1,
                "Out-of-range address 31 was not rejected");

        if ((weights_valid !== 1'b1) ||
            (error_code !== 3'b000))
            $fatal(1,
                "Status changed during weight reading");

        $display("PASS: full-flow reference consistency");
        $display("All 20 weight reads matched the reference");
        $display("comparison requests = %0d",
                 request_count);
        $display(
            "Accuracy signoff requires analysis of the error report");

        $finish;
    end

    // 整个测试的保护性时间上限
    initial begin
        #2000000;
        $fatal(1, "Full calibration test timed out");
    end

endmodule
