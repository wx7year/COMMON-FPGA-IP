/*
 * Multiplier Testbench
 * 测试一般乘法器和复数乘法器
 */
`timescale 1ns / 1ps

module tb_multiplier;
    localparam integer A_W = 16, B_W = 16, CLK_PERIOD = 10;

    reg clk, rst_n, en;
    reg signed [A_W-1:0] a, b;
    wire signed [A_W+B_W-1:0] p;

    multiplier_top #(.A_WIDTH(A_W), .B_WIDTH(B_W), .PIPE_STAGES(2)) u_mul (
        .clk(clk), .rst_n(rst_n), .en(en), .a(a), .b(b), .p(p)
    );

    // 复数乘法器
    reg signed [A_W-1:0] a_re, a_im, c_re, c_im;
    wire signed [A_W+B_W:0] p_re, p_im;

    complex_mult_top #(.A_WIDTH(A_W), .C_WIDTH(B_W), .USE_3_MULT(1)) u_cmul (
        .clk(clk), .rst_n(rst_n), .en(en),
        .a_re(a_re), .a_im(a_im), .c_re(c_re), .c_im(c_im),
        .p_re(p_re), .p_im(p_im)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer errors;
    longint exp_val;

    initial begin
        rst_n = 0; en = 0; errors = 0;
        #(CLK_PERIOD*5); rst_n = 1; en = 1;

        // 一般乘法器测试
        a = 100; b = 200;
        #(CLK_PERIOD*3);
        exp_val = 100 * 200;
        if (p !== exp_val) begin $display("MUL FAIL: %0d != %0d", p, exp_val); errors++; end
        else $display("MUL PASS: 100*200=%0d", p);

        a = -50; b = 30;
        #(CLK_PERIOD*3);
        exp_val = -50 * 30;
        if (p !== exp_val) begin $display("MUL FAIL: %0d != %0d", p, exp_val); errors++; end
        else $display("MUL PASS: -50*30=%0d", p);

        // 复数乘法器测试：(3+4i)*(1+2i) = -5+10i
        a_re = 3; a_im = 4; c_re = 1; c_im = 2;
        #(CLK_PERIOD*4);
        exp_val = -5;
        if (p_re !== exp_val) begin $display("CMUL RE FAIL: %0d != %0d", p_re, exp_val); errors++; end
        else $display("CMUL PASS: (3+4i)(1+2i) re=%0d", p_re);
        exp_val = 10;
        if (p_im !== exp_val) begin $display("CMUL IM FAIL: %0d != %0d", p_im, exp_val); errors++; end
        else $display("CMUL PASS: (3+4i)(1+2i) im=%0d", p_im);

        $display("\n=== Multiplier Test Complete, errors=%0d ===", errors);
        $finish;
    end
endmodule
