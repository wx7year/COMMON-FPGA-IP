/*
 * Divider Testbench
 * 测试有符号整数除法
 */
`timescale 1ns / 1ps

module tb_divider;
    localparam integer W = 16, CLK_PERIOD = 10;

    reg clk, rst_n, start;
    reg signed [W-1:0] dividend, divisor;
    wire busy, done;
    wire signed [W-1:0] quotient, remainder;

    divider_top #(.WIDTH(W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .dividend(dividend), .divisor(divisor),
        .quotient(quotient), .remainder(remainder)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer errors;
    reg signed [W-1:0] exp_q, exp_r;

    task run_div;
        input signed [W-1:0] a, b;
        begin
            dividend = a; divisor = b;
            @(posedge clk); start = 1;
            @(posedge clk); start = 0;
            @(posedge done);
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; start = 0; errors = 0;
        #(CLK_PERIOD*5); rst_n = 1;

        // 100 / 10 = 10, r=0
        run_div(100, 10);
        exp_q = 10; exp_r = 0;
        if (quotient !== exp_q || remainder !== exp_r) begin
            $display("FAIL: 100/10 = %0d r%0d, expected %0d r%0d", quotient, remainder, exp_q, exp_r);
            errors++;
        end else $display("PASS: 100/10 = %0d r%0d", quotient, remainder);

        // -100 / 10 = -10, r=0
        run_div(-100, 10);
        exp_q = -10; exp_r = 0;
        if (quotient !== exp_q || remainder !== exp_r) begin
            $display("FAIL: -100/10 = %0d r%0d, expected %0d r%0d", quotient, remainder, exp_q, exp_r);
            errors++;
        end else $display("PASS: -100/10 = %0d r%0d", quotient, remainder);

        // 100 / -10 = -10, r=0
        run_div(100, -10);
        exp_q = -10; exp_r = 0;
        if (quotient !== exp_q || remainder !== exp_r) begin
            $display("FAIL: 100/-10 = %0d r%0d, expected %0d r%0d", quotient, remainder, exp_q, exp_r);
            errors++;
        end else $display("PASS: 100/-10 = %0d r%0d", quotient, remainder);

        // 7 / 3 = 2, r=1
        run_div(7, 3);
        exp_q = 2; exp_r = 1;
        if (quotient !== exp_q || remainder !== exp_r) begin
            $display("FAIL: 7/3 = %0d r%0d, expected %0d r%0d", quotient, remainder, exp_q, exp_r);
            errors++;
        end else $display("PASS: 7/3 = %0d r%0d", quotient, remainder);

        // -7 / 3 = -2, r=-1 (余数与被除数同号)
        run_div(-7, 3);
        exp_q = -2; exp_r = -1;
        if (quotient !== exp_q || remainder !== exp_r) begin
            $display("FAIL: -7/3 = %0d r%0d, expected %0d r%0d", quotient, remainder, exp_q, exp_r);
            errors++;
        end else $display("PASS: -7/3 = %0d r%0d", quotient, remainder);

        $display("\n=== Divider Test Complete, errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 10000);
        $display("Timeout!"); $finish;
    end
endmodule
