/*
 * CORDIC Testbench
 * 测试 sin/cos（旋转模式）和 atan2/magnitude（向量模式）
 */
`timescale 1ns / 1ps

module tb_cordic;
    localparam integer DATA_WIDTH  = 16;
    localparam integer ANGLE_WIDTH = 16;
    localparam integer ITERATIONS  = 16;
    localparam integer CLK_PERIOD  = 10;

    reg clk, rst_n;
    reg start, mode;
    reg signed [DATA_WIDTH-1:0] x_in, y_in;
    reg signed [ANGLE_WIDTH-1:0] z_in;
    wire busy, done;
    wire signed [DATA_WIDTH-1:0] x_out, y_out;
    wire signed [ANGLE_WIDTH-1:0] z_out;

    cordic_top #(
        .DATA_WIDTH(DATA_WIDTH), .ANGLE_WIDTH(ANGLE_WIDTH),
        .ITERATIONS(ITERATIONS)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .mode(mode), .x_in(x_in), .y_in(y_in), .z_in(z_in),
        .x_out(x_out), .y_out(y_out), .z_out(z_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer errors;
    real expected, actual, err;

    task run_test;
        input [15:0] test_id;
        input mode_in;
        input signed [DATA_WIDTH-1:0] xi, yi;
        input signed [ANGLE_WIDTH-1:0] zi;
        begin
            @(posedge clk);
            mode = mode_in;
            x_in = xi; y_in = yi; z_in = zi;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            @(posedge done);
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; errors = 0;
        #(CLK_PERIOD*5); rst_n = 1;
        #(CLK_PERIOD*2);

        // 测试1：旋转模式，sin/cos(45°)
        // x=1.0(Q1.15=32767), y=0, z=45°(Q2.14 = 45/180*pi*16384 ≈ 12868)
        $display("Test 1: Rotation, sin/cos(45deg)");
        run_test(0, 0, 16'sd32767, 0, 16'sd12868);
        expected = 0.7071 * 32767;
        actual = x_out;
        err = (actual - expected) / expected;
        $display("  x_out(cos) = %0d, expected ~%.0f, err=%.4f", x_out, expected, err);
        if (err > 0.02) errors = errors + 1;

        // 测试2：向量模式，atan2(1,1)=45°, magnitude=sqrt(2)
        $display("Test 2: Vector, atan2(1,1)");
        run_test(1, 1, 16'sd23170, 16'sd23170, 0);  // x=y=23170 (0.707*32767)
        expected = 45.0 / 180.0 * 3.14159 * 16384;  // Q2.14
        actual = z_out;
        err = (actual - expected) / expected;
        $display("  z_out(atan) = %0d, expected ~%.0f, err=%.4f", z_out, expected, err);
        if (err > 0.02) errors = errors + 1;

        $display("\n=== CORDIC Test Complete, errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 10000);
        $display("Timeout!"); $finish;
    end
endmodule
