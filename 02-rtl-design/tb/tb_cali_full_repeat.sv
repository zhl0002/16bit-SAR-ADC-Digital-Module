`timescale 1ns/1ps

module tb_cali_full_repeat;

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
        $dumpfile("cali_full_repeat.vcd");
        $dumpvars(0, tb_cali_full_repeat);
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

    // 校准期间，正式读取接口必须保持无效且输出零。
    always @(posedge clk) begin
        #1;
        if (rst_n === 1'b1) begin
            if (error_code !== 3'b000)
                $fatal(1, "Unexpected calibration error: %b", error_code);
            if (dut.state_q !== 4'd0) begin
                if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
                    $fatal(1, "Weight read was enabled while calibration was busy");
            end
        end
    end

    // go 在下降沿后改变，DUT 在下一个上升沿接收启动命令。
    task automatic start_calibration(input integer run_id);
        begin
            @(negedge clk);
            #1;
            rd_addr = 5'd19;
            go = 1'b1;
            @(posedge clk);
            #1;
            if (dut.state_q !== 4'd1)
                $fatal(1, "Run %0d: start command was not accepted", run_id);
            if ((weights_valid !== 1'b0) ||
                (dut.valid_q !== 20'h0003f))
                $fatal(1, "Run %0d: old valid flags were not cleared", run_id);
            if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
                $fatal(1, "Run %0d: busy read was not blocked", run_id);
            @(negedge clk);
            #1;
            go = 1'b0;
        end
    endtask

    // 每轮独立检查结束状态、请求次数和全部权重。
    task automatic check_calibration(
        input integer run_id,
        input integer count_before
    );
        integer rd_index;
        begin
            wait (released === 1'b1);
            #1;
            if ((error_code !== 3'b000) ||
                (weights_valid !== 1'b1) ||
                (dut.valid_q !== 20'hfffff))
                $fatal(1, "Run %0d: invalid completion status", run_id);
            if ((request_count - count_before) != 11008)
                $fatal(1, "Run %0d: requests=%0d, expected=11008",
                    run_id, request_count - count_before);
            if ((sel_a !== 40'd0) || (sel_b !== 40'd0))
                $fatal(1, "Run %0d: CDAC commands were not parked", run_id);

            @(posedge clk);
            #1;
            if (released !== 1'b0)
                $fatal(1, "Run %0d: release pulse did not clear", run_id);

            for (rd_index = 0; rd_index < 20; rd_index = rd_index + 1) begin
                @(negedge clk);
                rd_addr = rd_index[4:0];
                #1;
                if ((rd_valid !== 1'b1) ||
                    (rd_data !== reference_q8[rd_index]))
                    $fatal(1, "Run %0d: addr=%0d valid=%b data=%0d expected=%0d",
                        run_id, rd_index, rd_valid, rd_data, reference_q8[rd_index]);
            end

            @(negedge clk);
            rd_addr = 5'd20;
            #1;
            if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
                $fatal(1, "Run %0d: address 20 was not rejected", run_id);
            @(negedge clk);
            rd_addr = 5'd31;
            #1;
            if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
                $fatal(1, "Run %0d: address 31 was not rejected", run_id);
            if ((weights_valid !== 1'b1) || (error_code !== 3'b000))
                $fatal(1, "Run %0d: status changed during reads", run_id);

            $display("PASS: run %0d, all 20 weights matched, requests = %0d",
                run_id, request_count - count_before);
        end
    endtask

    integer count_before;
    integer reset_index;

    // 唯一的流程控制线程：首次校准、无复位重校准、最终复位检查。
    initial begin
        repeat (3) @(negedge clk);
        #1;
        rst_n = 1'b1;

        count_before = request_count;
        start_calibration(1);
        check_calibration(1, count_before);

        // 此处不拉低 rst_n，直接启动第二轮。
        count_before = request_count;
        start_calibration(2);
        check_calibration(2, count_before);
        if (request_count != 22016)
            $fatal(1, "Wrong total request count: %0d", request_count);
        $display("total comparison requests before reset = %0d", request_count);

        @(negedge clk);
        #1;
        rst_n = 1'b0;
        #1;
        if ((dut.state_q !== 4'd0) || (dut.sum_q !== 0) ||
            (dut.valid_q !== 20'h0003f) || (weights_valid !== 1'b0) ||
            (error_code !== 3'b000) || (released !== 1'b0) ||
            (req !== 1'b0) || (phase !== 3'b000) ||
            (sel_a !== 40'd0) || (sel_b !== 40'd0))
            $fatal(1, "Asynchronous reset did not restore initial status");

        repeat (3) @(negedge clk);
        #1;
        rst_n = 1'b1;
        for (reset_index = 0; reset_index < 20; reset_index = reset_index + 1) begin
            @(negedge clk);
            rd_addr = reset_index[4:0];
            #1;
            if (reset_index < 6) begin
                if ((rd_valid !== 1'b1) ||
                    (rd_data !== reference_q8[reset_index]))
                    $fatal(1, "Reset: low weight %0d was not restored", reset_index);
            end else begin
                if ((rd_valid !== 1'b0) || (rd_data !== 32'd0))
                    $fatal(1, "Reset: high weight %0d was not cleared", reset_index);
            end
        end
        if ((request_count != 0) || (weights_valid !== 1'b0) ||
            (error_code !== 3'b000) || (released !== 1'b0) ||
            (dut.state_q !== 4'd0))
            $fatal(1, "Unexpected activity after reset");

        $display("PASS: reset recovery, low 6 weights valid, high 14 weights zero and invalid");
        $display("PASS: repeated full calibration and reset recovery");
        $display("This test checks repeatability; ADC accuracy signoff remains separate");
        $finish;
    end

    // 整个测试的保护性时间上限
    initial begin
        #6000000;
        $fatal(1, "Repeated full calibration test timed out");
    end

endmodule
