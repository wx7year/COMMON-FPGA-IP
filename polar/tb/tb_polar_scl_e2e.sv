/*
 * Polar SCL End-to-End Testbench
 * Polar SCL 端到端测试：编码→BPSK→AWGN→SCL译码→CRC校验
 *
 * 流程：
 *   1. 生成 K 个随机信息位
 *   2. Polar 编码（含 CRC16）
 *   3. BPSK 调制 + AWGN 加噪，生成 LLR
 *   4. SCL 译码（L=4）
 *   5. 比对输入/输出，统计 BER，检查 CRC
 */

`timescale 1ns / 1ps

module tb_polar_scl_e2e;

    //==========================================================================
    // 参数
    //==========================================================================
    localparam integer N         = 64;
    localparam integer K         = 32;
    localparam integer CRC_LEN   = 16;
    localparam integer L         = 4;
    localparam integer LLR_WIDTH = 6;
    localparam integer PM_WIDTH  = 16;
    localparam integer NUM_FRAMES = 100;  // 测试帧数
    localparam real    NOISE_SIGMA = 0.5; // AWGN 标准差

    //==========================================================================
    // 信号
    //==========================================================================
    reg clk, rst_n;

    // 编码器接口
    reg enc_start;
    wire enc_busy, enc_done;
    reg enc_s_data, enc_s_valid, enc_s_last;
    wire enc_s_ready;
    wire enc_m_data, enc_m_valid, enc_m_last;
    reg enc_m_ready;

    // 译码器接口
    reg dec_start;
    wire dec_busy, dec_done;
    reg signed [LLR_WIDTH-1:0] dec_s_data;
    reg dec_s_valid, dec_s_last;
    wire dec_s_ready;
    wire dec_m_data, dec_m_valid, dec_m_last;
    reg dec_m_ready;
    wire [1:0] best_path;
    wire [PM_WIDTH-1:0] best_pm;
    wire crc_pass;

    //==========================================================================
    // DUT
    //==========================================================================
    polar_encoder #(
        .N(N), .K(K), .CRC_LEN(CRC_LEN), .CRC_POLY(16'h1021)
    ) u_enc (
        .clk(clk), .rst_n(rst_n),
        .start(enc_start), .busy(enc_busy), .done(enc_done),
        .s_axis_tdata(enc_s_data), .s_axis_tvalid(enc_s_valid),
        .s_axis_tready(enc_s_ready), .s_axis_tlast(enc_s_last),
        .m_axis_tdata(enc_m_data), .m_axis_tvalid(enc_m_valid),
        .m_axis_tready(enc_m_ready), .m_axis_tlast(enc_m_last)
    );

    polar_scl_decoder #(
        .N(N), .K(K), .CRC_LEN(CRC_LEN), .L(L),
        .LLR_WIDTH(LLR_WIDTH), .PM_WIDTH(PM_WIDTH)
    ) u_dec (
        .clk(clk), .rst_n(rst_n),
        .start(dec_start), .busy(dec_busy), .done(dec_done),
        .s_axis_tdata(dec_s_data), .s_axis_tvalid(dec_s_valid),
        .s_axis_tready(dec_s_ready), .s_axis_tlast(dec_s_last),
        .m_axis_tdata(dec_m_data), .m_axis_tvalid(dec_m_valid),
        .m_axis_tready(dec_m_ready), .m_axis_tlast(dec_m_last),
        .best_path(best_path), .best_pm(best_pm), .crc_pass(crc_pass)
    );

    //==========================================================================
    // 时钟
    //==========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    //==========================================================================
    // 存储
    //==========================================================================
    reg [0:K-1] info_bits;
    reg [0:N-1] codeword;
    reg signed [LLR_WIDTH-1:0] llr_arr [0:N-1];
    reg [0:K-1] dec_bits;

    integer frame, bit_i, err_count, total_err, crc_ok_count;
    integer seed;

    //==========================================================================
    // AWGN 噪声生成（Box-Muller 简化版：4 个均匀分布相加近似高斯）
    //==========================================================================
    function real awgn;
        input integer seed_in;
        output integer seed_out;
        real sum;
        integer i;
        integer s;
        integer r;
        begin
            s = seed_in;
            sum = 0.0;
            for (i = 0; i < 12; i = i + 1) begin
                r = $random(s);
                sum = sum + ((r / 2147483647.0) + 1.0) * 0.5;
            end
            seed_out = s;
            awgn = (sum - 6.0) * NOISE_SIGMA;
        end
    endfunction

    //==========================================================================
    // 主测试
    //==========================================================================
    initial begin
        $display("=== Polar SCL End-to-End Test ===");
        $display("  N=%0d, K=%0d, CRC=%0d, L=%0d, sigma=%.2f", N, K, CRC_LEN, L, NOISE_SIGMA);
        $display("  Frames=%0d", NUM_FRAMES);

        rst_n = 0;
        enc_start = 0; enc_s_valid = 0; enc_s_last = 0; enc_m_ready = 1;
        dec_start = 0; dec_s_valid = 0; dec_s_last = 0; dec_m_ready = 1;
        #20; rst_n = 1; #20;

        total_err = 0;
        crc_ok_count = 0;
        seed = 42;

        for (frame = 0; frame < NUM_FRAMES; frame = frame + 1) begin
            $display("Frame %0d: generating info bits", frame);
            // 1. 生成随机信息位
            for (bit_i = 0; bit_i < K; bit_i = bit_i + 1)
                info_bits[bit_i] = {$random(seed)} & 1'b1;

            $display("Frame %0d: encoding...", frame);
            // 2. 编码
            fork
                begin : enc_drv
                    integer ei;
                    @(posedge clk); enc_start <= 1; @(posedge clk); enc_start <= 0;
                    for (ei = 0; ei < K; ei = ei + 1) begin
                        @(posedge clk);
                        enc_s_data <= info_bits[ei];
                        enc_s_valid <= 1;
                        enc_s_last <= (ei == K-1);
                    end
                    @(posedge clk);
                    enc_s_valid <= 0; enc_s_last <= 0;
                end
                begin : enc_col
                    integer ci;
                    for (ci = 0; ci < N; ci = ci + 1) begin
                        @(posedge clk);
                        while (!enc_m_valid) @(posedge clk);
                        #1 codeword[ci] = enc_m_data;
                    end
                end
            join
            $display("Frame %0d: encoding done, generating LLR", frame);

            // 3. BPSK + AWGN -> LLR
            for (bit_i = 0; bit_i < N; bit_i = bit_i + 1) begin
                // BPSK + AWGN -> LLR
                begin
                    real x, y, llr_real;
                    integer llr_int;
                    x = codeword[bit_i] ? -1.0 : 1.0;
                    y = x + awgn(seed, seed);
                    llr_real = y * (2.0 / (NOISE_SIGMA * NOISE_SIGMA));
                    llr_int = $rtoi(llr_real);
                    if (llr_int > 31) llr_int = 31;
                    if (llr_int < -32) llr_int = -32;
                    llr_arr[bit_i] = llr_int[LLR_WIDTH-1:0];
                end
            end

            $display("Frame %0d: LLR done, decoding...", frame);
            // 4. SCL 译码
            fork
                begin : dec_drv
                    integer di;
                    @(posedge clk); dec_start <= 1; @(posedge clk); dec_start <= 0;
                    for (di = 0; di < N; di = di + 1) begin
                        @(posedge clk);
                        dec_s_data <= llr_arr[di];
                        dec_s_valid <= 1;
                        dec_s_last <= (di == N-1);
                    end
                    @(posedge clk);
                    dec_s_valid <= 0; dec_s_last <= 0;
                end
                begin : dec_col
                    integer ci;
                    for (ci = 0; ci < K; ci = ci + 1) begin
                        @(posedge clk);
                        while (!dec_m_valid) @(posedge clk);
                        #1 dec_bits[ci] = dec_m_data;
                    end
                end
            join
            $display("Frame %0d: decoding done, comparing", frame);

            // 5. 比对
            err_count = 0;
            for (bit_i = 0; bit_i < K; bit_i = bit_i + 1) begin
                if (dec_bits[bit_i] != info_bits[bit_i])
                    err_count = err_count + 1;
            end
            total_err = total_err + err_count;
            if (crc_pass) crc_ok_count = crc_ok_count + 1;

            $display("  Frame %0d: errors=%0d/%0d, best_path=%0d, best_pm=%0d, crc_pass=%0b",
                     frame, err_count, K, best_path, best_pm, crc_pass);
        end

        $display("");
        $display("=== Summary ===");
        $display("  Total bits: %0d", NUM_FRAMES * K);
        $display("  Total errors: %0d", total_err);
        $display("  BER: %.6f", total_err / (NUM_FRAMES * K * 1.0));
        $display("  CRC pass: %0d/%0d", crc_ok_count, NUM_FRAMES);
        if (total_err == 0)
            $display("  PASS (zero errors)");
        else
            $display("  FAIL");

        #50; $finish;
    end

    // 超时保护
    initial begin
        #1000000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
