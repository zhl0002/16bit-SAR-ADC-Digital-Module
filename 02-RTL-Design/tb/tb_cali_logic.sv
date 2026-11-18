`timescale 1ns/1ps

// Control-interface tests only. No analog/CDAC accuracy model.
// 10 ns is a simulation stimulus choice, not the implementation constraint.
module tb_cali_logic;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 1;
    reg go = 0;
    reg cmp_result = 0;
    reg cmp_done = 0;
    reg [4:0] rd_addr = 0;
    wire req, released, weights_valid, rd_valid;
    wire [2:0] error_code, phase;
    wire [39:0] sel_a, sel_b;
    wire [31:0] rd_data;
    localparam integer TIMEOUT = 1024;
    integer checks = 0;
    integer addr;
    integer elapsed;
    integer cap;
    reg previous_req = 0;
    reg previous_release = 0;

    cali_logic dut (
        .clk_i(clk), .rst_ni(rst_n), .cal_go_i(go),
        .cmp_result_i(cmp_result), .cmp_done_i(cmp_done),
        .cmp_req_o(req), .cal_release_ready_o(released),
        .weights_valid_o(weights_valid), .error_o(error_code),
        .phase_o(phase), .cal_bp_sel_a_o(sel_a),
        .cal_bp_sel_b_o(sel_b), .weight_rd_addr_i(rd_addr),
        .weight_rd_data_o(rd_data), .weight_rd_valid_o(rd_valid)
    );

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1)
                $fatal(1, "FAIL at %0t: %s", $time, message);
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n = 0;
            go = 0;
            cmp_done = 0;
            cmp_result = 0;
            #1;
            check(req === 0 && released === 0, "reset clears request/release");
            check(weights_valid === 0 && error_code === 0, "reset clears status");
            check(sel_a === 0 && sel_b === 0, "reset parks CDAC commands");
            repeat (2) @(negedge clk);
            rst_n = 1;
            #1;
        end
    endtask

    task automatic start_and_wait_request;
        integer cycles;
        begin
            @(negedge clk);
            go = 1;
            @(negedge clk);
            go = 0;
            #1;
            check(rd_valid === 0 && rd_data === 0, "busy read is invalid and zero");
            cycles = 0;
            while (req !== 1'b1 && cycles < 100) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            check(req === 1'b1, "first comparison requested within bound");
        end
    endtask

    // Sample after nonblocking assignments have settled.
    always @(posedge clk) begin
        #1;
        if (rst_n === 1'b1) begin
            check(!(req && previous_req), "request is a one-cycle pulse");
            check(!(released && previous_release), "release is a one-cycle pulse");
            for (cap = 0; cap < 20; cap = cap + 1) begin
                check(sel_b[2*cap +: 2] === {sel_a[2*cap],sel_a[2*cap+1]},
                      "B-side field is the bit swap of A-side field");
                check(sel_a[2*cap +: 2] !== 2'b11, "no reserved CDAC command");
            end
            previous_req = req;
            previous_release = released;
        end else begin
            previous_req = 0;
            previous_release = 0;
        end
    end

    initial begin
        $dumpfile("cali_logic.vcd");
        $dumpvars(0, tb_cali_logic);
        reset_dut();
        $display("CASE 1: reset and read-address behavior");
        for (addr = 0; addr < 32; addr = addr + 1) begin
            @(negedge clk);
            rd_addr = addr;
            #1;
            if (addr < 6) begin
                check(rd_valid === 1, "nominal weight is valid after reset");
                check(rd_data === (32'd256 << addr), "nominal fixed-point weight");
            end else begin
                check(rd_valid === 0, "uncalibrated/out-of-range weight invalid");
                check(rd_data === 0, "uncalibrated/out-of-range weight zero after reset");
            end
        end

        $display("CASE 2: no response, timeout, park, release");
        start_and_wait_request();
        elapsed = 0;
        while (released !== 1'b1 && elapsed < TIMEOUT + 16) begin
            @(posedge clk);
            #1;
            elapsed = elapsed + 1;
        end
        check(released === 1'b1, "timeout exits within bounded time");
        check(error_code === 3'b001, "timeout sets only error bit zero");
        check(weights_valid === 0, "failed calibration does not validate weights");
        check(sel_a === 0 && sel_b === 0, "CDAC parked before release");
        @(posedge clk);
        #1;
        check(released === 0, "release deasserts on following cycle");
        check(error_code === 3'b001, "error retained until reset or new calibration");

        $display("CASE 3: completion wins at the timeout boundary");
        reset_dut();
        start_and_wait_request();
        // At the observed request, wait_q is zero. Assert done before the
        // rising edge that would otherwise trigger timeout.
        repeat (TIMEOUT-1) begin
            @(posedge clk);
            #1;
            check(error_code === 0, "no early timeout");
        end
        @(negedge clk);
        cmp_done = 1;
        cmp_result = 1;
        @(posedge clk);
        #1;
        check(error_code === 0, "valid completion has priority over timeout");
        // White-box observation confirms capture; no analog accuracy claim.
        check(dut.state_q === 4'd7 && dut.decision_q === 1'b1,
              "boundary response was captured into DECIDE state");
        @(negedge clk);
        cmp_done = 0;

        $display("CASE 4: asynchronous reset aborts active calibration");
        reset_dut();
        check(phase === 0, "reset returns to idle phase");
        $display("PASS: control interface tests, %0d checks", checks);
        $display("NOT TESTED: full calibration accuracy, CDC, timing, synthesis or layout");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Global watchdog: test did not finish");
    end
endmodule
