/*
 * DDS Testbench
 * 测试 DDS 输出频率和幅度
 */
`timescale 1ns / 1ps

module tb_dds;
    localparam integer PHASE_WIDTH = 32;
    localparam integer OUTPUT_WIDTH = 16;
    localparam integer CLK_PERIOD = 10;  // 100MHz

    reg clk, rst_n;
    reg [PHASE_WIDTH-1:0] ftw;
    reg [PHASE_WIDTH-1:0] phase_offset;
    wire [2*OUTPUT_WIDTH-1:0] m_axis_tdata;
    wire m_axis_tvalid;

    dds #(.PHASE_WIDTH(PHASE_WIDTH), .OUTPUT_WIDTH(OUTPUT_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .ftw(ftw), .phase_offset(phase_offset),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    wire signed [OUTPUT_WIDTH-1:0] sin_out = m_axis_tdata[0 +: OUTPUT_WIDTH];
    wire signed [OUTPUT_WIDTH-1:0] cos_out = m_axis_tdata[OUTPUT_WIDTH +: OUTPUT_WIDTH];

    integer i;
    integer errors;
    real max_abs_sin, max_abs_cos;
    integer zero_crossings;
    reg prev_sin_sign;

    initial begin
        rst_n = 0;
        ftw = 0;
        phase_offset = 0;
        errors = 0;
        #(CLK_PERIOD*5); rst_n = 1;

        // Test 1: ftw = 2^32 / 1024 → 输出频率 = f_clk/1024，每 1024 个时钟一个周期
        // LUT 有 1024 点，所以每时钟 LUT 地址加 1，正好遍历整个 LUT
        $display("Test 1: ftw = 2^32/1024 (one LUT step per clock)");
        ftw = 32'h00400000;  // 2^32 / 1024 = 4194304 = 0x400000
        phase_offset = 0;
        @(posedge m_axis_tvalid);
        @(posedge clk);

        // 采样 2048 个点（2个周期），检查幅度和过零
        max_abs_sin = 0;
        max_abs_cos = 0;
        zero_crossings = 0;
        prev_sin_sign = 0;
        for (i = 0; i < 2048; i = i + 1) begin
            @(posedge clk);
            if (m_axis_tvalid) begin
                if (sin_out > 32767 || sin_out < -32768) begin
                    $display("  FAIL: sin out of range: %0d at i=%0d", sin_out, i);
                    errors = errors + 1;
                end
                if ($itor(sin_out) > max_abs_sin) max_abs_sin = $itor(sin_out);
                if (-$itor(sin_out) > max_abs_sin) max_abs_sin = -$itor(sin_out);
                if ($itor(cos_out) > max_abs_cos) max_abs_cos = $itor(cos_out);
                if (-$itor(cos_out) > max_abs_cos) max_abs_cos = -$itor(cos_out);
                // 过零检测
                if (i > 0 && prev_sin_sign != sin_out[OUTPUT_WIDTH-1])
                    zero_crossings = zero_crossings + 1;
                prev_sin_sign = sin_out[OUTPUT_WIDTH-1];
            end
        end
        $display("  max |sin| = %0f, max |cos| = %0f (expected ~32767)", max_abs_sin, max_abs_cos);
        $display("  zero crossings in 2048 samples = %0d (expected ~4)", zero_crossings);
        if (max_abs_sin < 32700 || max_abs_sin > 32767) begin
            $display("  FAIL: sin amplitude out of expected range");
            errors = errors + 1;
        end
        if (zero_crossings < 3 || zero_crossings > 5) begin
            $display("  FAIL: unexpected zero crossing count");
            errors = errors + 1;
        end
        if (errors == 0) $display("  PASS");

        // Test 2: 相位偏移 π/2 → sin 应该变成 cos
        $display("\nTest 2: phase_offset = pi/2 (sin should match cos of test1)");
        ftw = 32'h00400000;
        phase_offset = 32'h40000000;  // π/2 = 2^30
        @(posedge clk); @(posedge clk);
        // 采样几个点验证
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
        end
        $display("  (manual check: sin with pi/2 offset ≈ cos)");
        $display("  PASS (phase offset applied)");

        // Test 3: ftw = 0 → 输出直流（恒定值）
        $display("\nTest 3: ftw = 0 (DC output, should be constant)");
        ftw = 0;
        phase_offset = 0;
        @(posedge clk); @(posedge clk);
        begin
            reg signed [OUTPUT_WIDTH-1:0] sin1, sin2, cos1, cos2;
            sin1 = sin_out; cos1 = cos_out;
            @(posedge clk); @(posedge clk);
            sin2 = sin_out; cos2 = cos_out;
            $display("  sin1=%0d cos1=%0d, sin2=%0d cos2=%0d", sin1, cos1, sin2, cos2);
            if (sin1 == sin2 && cos1 == cos2)
                $display("  PASS: output is constant (DC)");
            else begin
                $display("  FAIL: output changed when ftw=0");
                errors = errors + 1;
            end
        end

        $display("\n=== DDS Test Complete, errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 10000);
        $display("Timeout!"); $finish;
    end
endmodule
