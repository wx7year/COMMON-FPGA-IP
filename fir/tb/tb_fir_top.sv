/*
 * FIR Top Testbench
 * 自检测试平台：读取 C model 生成的输入/期望输出，驱动 DUT 并比对
 *
 * 用法：
 *   1. 在 model/ 目录运行 make gen_all 生成测试向量
 *   2. 编译并运行本 testbench
 */

`timescale 1ns / 1ps

module tb_fir_top;

    //==========================================================================
    // 参数
    //==========================================================================
    localparam integer NUM_TAPS      = 32;
    localparam integer DATA_WIDTH    = 16;
    localparam integer COEFF_WIDTH   = 16;
    localparam integer CLK_FREQ      = 80_000_000;
    localparam integer SAMPLE_RATE   = 10_000_000;
    localparam integer SYMMETRIC     = 1;
    localparam integer OUT_WIDTH     = DATA_WIDTH + COEFF_WIDTH + $clog2(NUM_TAPS) + 1;
    localparam integer CLK_PERIOD    = 12;  // ~83MHz，接近 80MHz
    localparam integer ERR_THRESHOLD = 8;   // 允许误差 LSB
    localparam integer NUM_SAMPLES   = 2048;

    //==========================================================================
    // 信号
    //==========================================================================
    reg                          clk;
    reg                          rst_n;

    reg  [DATA_WIDTH-1:0]        s_axis_tdata;
    reg                          s_axis_tvalid;
    wire                         s_axis_tready;
    reg                          s_axis_tlast;

    wire [OUT_WIDTH-1:0]         m_axis_tdata;
    wire                         m_axis_tvalid;
    reg                          m_axis_tready;
    wire                         m_axis_tlast;

    wire                         busy;
    wire [31:0]                  num_mult_used;

    //==========================================================================
    // DUT
    //==========================================================================
    fir_top #(
        .NUM_TAPS(NUM_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .CLK_FREQ(CLK_FREQ),
        .SAMPLE_RATE(SAMPLE_RATE),
        .SYMMETRIC(SYMMETRIC),
        .COEFF_FILE("data/fir_coeff.mem")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .busy(busy),
        .num_mult_used(num_mult_used)
    );

    //==========================================================================
    // 时钟和复位
    //==========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
    end

    //==========================================================================
    // 测试数据
    //==========================================================================
    integer input_file, expected_file;
    integer i, err_count, total_err, max_err;
    integer sample_cnt;

    reg signed [DATA_WIDTH-1:0] input_data [0:NUM_SAMPLES-1];
    reg signed [OUT_WIDTH-1:0]  expected_data [0:NUM_SAMPLES-1];

    //==========================================================================
    // 主测试
    //==========================================================================
    initial begin
        $display("=== FIR Testbench ===");
        $display("  NUM_TAPS=%0d, SYMMETRIC=%0d", NUM_TAPS, SYMMETRIC);
        $display("  CLK_FREQ=%0d, SAMPLE_RATE=%0d", CLK_FREQ, SAMPLE_RATE);
        $display("  Expected NUM_MULT = %0d", (NUM_TAPS/2 + (CLK_FREQ/SAMPLE_RATE) - 1) / (CLK_FREQ/SAMPLE_RATE));

        // 加载输入
        input_file = $fopen("data/fir_input.txt", "r");
        if (input_file == 0) begin
            $display("ERROR: Cannot open data/fir_input.txt");
            $display("Run 'make gen_all' in model/ directory first.");
            $finish;
        end
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            $fscanf(input_file, "%d", input_data[i]);
        end
        $fclose(input_file);

        // 加载期望输出
        expected_file = $fopen("data/fir_expected.txt", "r");
        if (expected_file == 0) begin
            $display("ERROR: Cannot open data/fir_expected.txt");
            $finish;
        end
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            $fscanf(expected_file, "%d", expected_data[i]);
        end
        $fclose(expected_file);

        $display("Loaded %0d input samples and %0d expected outputs", NUM_SAMPLES, NUM_SAMPLES);

        wait (rst_n);
        #(CLK_PERIOD * 10);

        // 驱动输入 + 收集输出
        err_count = 0;
        total_err = 0;
        max_err = 0;
        sample_cnt = 0;

        fork
            // 驱动输入线程
            begin
                for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                    @(posedge clk);
                    s_axis_tdata  = input_data[i];
                    s_axis_tvalid = 1'b1;
                    s_axis_tlast  = (i == NUM_SAMPLES - 1);
                    @(posedge clk);
                    while (!s_axis_tready) @(posedge clk);
                end
                s_axis_tvalid = 1'b0;
                s_axis_tlast  = 1'b0;
            end

            // 收集输出线程
            begin
                for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                    @(posedge clk);
                    while (!m_axis_tvalid) @(posedge clk);

                    begin
                        reg signed [OUT_WIDTH-1:0] got;
                        integer err;
                        got = m_axis_tdata;
                        err = (got > expected_data[i]) ? (got - expected_data[i]) : (expected_data[i] - got);
                        if (err > max_err) max_err = err;
                        total_err = total_err + err;

                        if (err > ERR_THRESHOLD) begin
                            err_count = err_count + 1;
                            if (err_count <= 10)
                                $display("  MISMATCH [%0d]: got=%0d expected=%0d err=%0d",
                                         i, got, expected_data[i], err);
                        end
                    end
                    sample_cnt = sample_cnt + 1;
                end
            end
        join

        $display("");
        $display("=== Results ===");
        $display("  Samples processed: %0d", sample_cnt);
        $display("  NUM_MULT used: %0d", num_mult_used);
        $display("  Mismatched: %0d / %0d (threshold=%0d)", err_count, NUM_SAMPLES, ERR_THRESHOLD);
        $display("  Max error: %0d, Total error: %0d", max_err, total_err);

        if (err_count == 0)
            $display("  PASS");
        else
            $display("  FAIL");

        #(CLK_PERIOD * 20);
        $finish;
    end

    // 超时保护
    initial begin
        #(CLK_PERIOD * 500000);
        $display("ERROR: Timeout!");
        $finish;
    end

    // 初始 m_axis_tready
    initial m_axis_tready = 1'b1;

endmodule
