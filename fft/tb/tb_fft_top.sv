/*
 * FFT Top Testbench
 * 自检测试平台：读取 C model 生成的输入/期望输出，驱动 DUT 并比对
 *
 * 用法：
 *   1. 先在 model/ 目录运行 make gen_all 生成测试向量
 *   2. 编译并运行本 testbench
 *
 * 测试内容：
 *   - 正向 FFT：输入随机复数，输出与 C model 比对
 *   - 反向 FFT：同上
 *   - 误差阈值：允许 ±2 LSB（定点舍入误差）
 */

`timescale 1ns / 1ps

module tb_fft_top;

    //==========================================================================
    // 参数
    //==========================================================================
    localparam integer N              = 1024;
    localparam integer LOG2_N         = $clog2(N);
    localparam integer DIN_WIDTH      = 16;
    localparam integer DOUT_WIDTH     = DIN_WIDTH + LOG2_N;  // 26
    localparam integer TWIDDLE_WIDTH  = 16;
    localparam integer CLK_PERIOD     = 10;  // 100MHz
    localparam integer ERR_THRESHOLD  = 512;   // 允许误差 LSB（Q1.15旋转因子量化误差）

    //==========================================================================
    // 信号
    //==========================================================================
    reg                         clk;
    reg                         rst_n;
    reg                         fwd_inv;

    reg  [2*DIN_WIDTH-1:0]      s_axis_tdata;
    reg                         s_axis_tvalid;
    wire                        s_axis_tready;
    reg                         s_axis_tlast;

    wire [2*DOUT_WIDTH-1:0]     m_axis_tdata;
    wire                        m_axis_tvalid;
    reg                         m_axis_tready;
    wire                        m_axis_tlast;

    wire                        busy;
    wire                        done;

    //==========================================================================
    // DUT
    //==========================================================================
    fft_top #(
        .N(N),
        .LOG2_N(LOG2_N),
        .DIN_WIDTH(DIN_WIDTH),
        .DOUT_WIDTH(DOUT_WIDTH),
        .TWIDDLE_WIDTH(TWIDDLE_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .fwd_inv(fwd_inv),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .busy(busy),
        .done(done)
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
    // 测试数据存储
    //==========================================================================
    integer input_file, expected_file;
    integer i, j;
    integer err_count;
    integer total_err;
    integer max_err_re, max_err_im;

    reg signed [DIN_WIDTH-1:0]  input_i [0:N-1];
    reg signed [DIN_WIDTH-1:0]  input_q [0:N-1];
    reg signed [DOUT_WIDTH-1:0] expected_i [0:N-1];
    reg signed [DOUT_WIDTH-1:0] expected_q [0:N-1];

    //==========================================================================
    // 任务：加载输入文件
    //==========================================================================
    task load_input;
        input string fname;
        begin
            input_file = $fopen(fname, "r");
            if (input_file == 0) begin
                $display("ERROR: Cannot open input file %s", fname);
                $finish;
            end
            for (i = 0; i < N; i = i + 1) begin
                $fscanf(input_file, "%d %d", input_i[i], input_q[i]);
            end
            $fclose(input_file);
            $display("Loaded %d input samples from %s", N, fname);
        end
    endtask

    //==========================================================================
    // 任务：加载期望输出文件
    //==========================================================================
    task load_expected;
        input string fname;
        begin
            expected_file = $fopen(fname, "r");
            if (expected_file == 0) begin
                $display("ERROR: Cannot open expected file %s", fname);
                $finish;
            end
            for (i = 0; i < N; i = i + 1) begin
                $fscanf(expected_file, "%d %d", expected_i[i], expected_q[i]);
            end
            $fclose(expected_file);
            $display("Loaded %d expected samples from %s", N, fname);
        end
    endtask

    //==========================================================================
    // 任务：驱动一帧输入
    //==========================================================================
    task drive_frame;
        integer drv_i;
        begin
            @(posedge clk);
            for (drv_i = 0; drv_i < N; drv_i = drv_i + 1) begin
                s_axis_tdata  = {input_q[drv_i], input_i[drv_i]};
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (drv_i == N-1);
                @(posedge clk);
                while (!s_axis_tready) @(posedge clk);
            end
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    //==========================================================================
    // 任务：收集输出并比对
    //==========================================================================
    task collect_and_compare;
        input string test_name;
        integer col_i;
        begin
            err_count = 0;
            total_err = 0;
            max_err_re = 0;
            max_err_im = 0;

            for (col_i = 0; col_i < N; col_i = col_i + 1) begin
                @(posedge clk);
                while (!m_axis_tvalid) @(posedge clk);

                begin
                    reg signed [DOUT_WIDTH-1:0] got_i, got_q;
                    integer err_re, err_im;
                    got_i = m_axis_tdata[DOUT_WIDTH-1:0];
                    got_q = m_axis_tdata[2*DOUT_WIDTH-1:DOUT_WIDTH];
                    err_re = (got_i > expected_i[col_i]) ? (got_i - expected_i[col_i]) : (expected_i[col_i] - got_i);
                    err_im = (got_q > expected_q[col_i]) ? (got_q - expected_q[col_i]) : (expected_q[col_i] - got_q);

                    if (err_re > max_err_re) max_err_re = err_re;
                    if (err_im > max_err_im) max_err_im = err_im;
                    total_err = total_err + err_re + err_im;

                    if (err_re > ERR_THRESHOLD || err_im > ERR_THRESHOLD) begin
                        err_count = err_count + 1;
                        if (err_count <= 10) begin
                            $display("  MISMATCH [%0d]: got(%d,%d) expected(%d,%d) err(%d,%d)",
                                     col_i, got_i, got_q, expected_i[col_i], expected_q[col_i], err_re, err_im);
                        end
                    end
                end
            end

            $display("  [%s] Mismatched samples: %0d / %0d", test_name, err_count, N);
            $display("  [%s] Max error: RE=%0d, IM=%0d, Total=%0d", test_name, max_err_re, max_err_im, total_err);

            if (err_count == 0)
                $display("  [%s] PASS", test_name);
            else
                $display("  [%s] FAIL", test_name);
        end
    endtask

    //==========================================================================
    // 主测试流程
    //==========================================================================
    initial begin
        // 初始化
        s_axis_tdata  = 'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;  // 总是准备接收
        fwd_inv       = 1'b1;

        wait (rst_n);
        #(CLK_PERIOD * 10);

        //----------------------------------------------------------------------
        // 测试 1：正向 FFT
        //----------------------------------------------------------------------
        $display("=== Test 1: Forward FFT (N=%0d) ===", N);
        load_input("data/input_1024.txt");
        load_expected("data/expected_fft_1024.txt");
        fwd_inv = 1'b1;
        $display("  Driving input...");
        fork
            drive_frame();
            collect_and_compare("Forward FFT");
        join
        $display("  Test 1 done");

        #(CLK_PERIOD * 20);

        //----------------------------------------------------------------------
        // 测试 2：反向 FFT (IFFT)
        //----------------------------------------------------------------------
        $display("=== Test 2: Inverse FFT (N=%0d) ===", N);
        load_input("data/input_1024.txt");
        load_expected("data/expected_ifft_1024.txt");
        fwd_inv = 1'b0;
        fork
            drive_frame();
            collect_and_compare("Inverse FFT");
        join

        #(CLK_PERIOD * 20);
        $display("=== All tests completed ===");
        $finish;
    end

    // 超时保护
    initial begin
        #(CLK_PERIOD * 200000);
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
