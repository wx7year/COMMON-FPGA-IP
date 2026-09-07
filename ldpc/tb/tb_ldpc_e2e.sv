/*
 * LDPC End-to-End Testbench
 * 编码 → BPSK调制 → AWGN → 译码 → 误码率统计
 *
 * 使用测试基矩阵 4×8, ZC=4, 码率 4/8=0.5
 */
`timescale 1ns / 1ps

module tb_ldpc_e2e;
    localparam integer ZC        = 4;
    localparam integer ROWS      = 4;
    localparam integer N_B       = 8;
    localparam integer K_B       = 4;
    localparam integer M_B       = 4;
    localparam integer LLR_WIDTH = 6;
    localparam integer MAX_ITER  = 4;
    localparam integer BLOCK_W   = ZC * LLR_WIDTH;
    localparam integer CLK_PERIOD = 10;
    localparam integer NUM_BLOCKS = 20;  // 测试帧数

    reg clk, rst_n;

    // 编码器
    reg enc_start;
    wire enc_busy, enc_done;
    reg [ZC-1:0] enc_s_tdata;
    reg enc_s_tvalid, enc_s_tlast;
    wire enc_s_tready;
    wire [ZC-1:0] enc_m_tdata;
    wire enc_m_tvalid, enc_m_tlast;
    reg enc_m_tready;

    ldpc_encoder #(
        .BG(0), .ZC(ZC), .ROWS(ROWS), .N_B(N_B), .K_B(K_B), .M_B(M_B),
        .BG_MEM_FILE("ldpc_bg_test.mem")
    ) u_enc (
        .clk(clk), .rst_n(rst_n), .start(enc_start), .busy(enc_busy), .done(enc_done),
        .s_axis_tdata(enc_s_tdata), .s_axis_tvalid(enc_s_tvalid),
        .s_axis_tready(enc_s_tready), .s_axis_tlast(enc_s_tlast),
        .m_axis_tdata(enc_m_tdata), .m_axis_tvalid(enc_m_tvalid),
        .m_axis_tready(enc_m_tready), .m_axis_tlast(enc_m_tlast)
    );

    // 译码器
    reg dec_start;
    wire dec_busy, dec_done;
    wire [2:0] dec_iter;
    reg [BLOCK_W-1:0] dec_s_tdata;
    reg dec_s_tvalid, dec_s_tlast;
    wire dec_s_tready;
    wire [ZC-1:0] dec_m_tdata;
    wire dec_m_tvalid, dec_m_tlast;
    reg dec_m_tready;

    ldpc_decoder #(
        .BG(0), .ZC(ZC), .ROWS(ROWS), .N_B(N_B), .K_B(K_B), .M_B(M_B),
        .LLR_WIDTH(LLR_WIDTH), .MAX_ITER(MAX_ITER),
        .BG_MEM_FILE("ldpc_bg_test.mem")
    ) u_dec (
        .clk(clk), .rst_n(rst_n), .start(dec_start), .busy(dec_busy), .done(dec_done),
        .iter_count(dec_iter),
        .s_axis_tdata(dec_s_tdata), .s_axis_tvalid(dec_s_tvalid),
        .s_axis_tready(dec_s_tready), .s_axis_tlast(dec_s_tlast),
        .m_axis_tdata(dec_m_tdata), .m_axis_tvalid(dec_m_tvalid),
        .m_axis_tready(dec_m_tready), .m_axis_tlast(dec_m_tlast)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // 存储
    reg [ZC-1:0] tx_info [0:K_B-1];
    reg [ZC-1:0] tx_code [0:N_B-1];
    reg [ZC-1:0] rx_code [0:N_B-1];
    integer enc_idx, dec_idx;
    integer total_bits, error_bits;
    integer frame;
    real snr_db, noise_std;

    // 编码器输出收集
    always @(posedge clk) begin
        if (enc_m_tvalid && enc_m_tready) begin
            tx_code[enc_idx] <= enc_m_tdata;
            enc_idx <= enc_idx + 1;
        end
    end

    // 译码器输出收集
    always @(posedge clk) begin
        if (dec_m_tvalid && dec_m_tready) begin
            rx_code[dec_idx] <= dec_m_tdata;
            dec_idx <= dec_idx + 1;
        end
    end

    task bpsk_awgn_llr;
        input [ZC-1:0] bits;
        input real noise_sigma;
        output [BLOCK_W-1:0] llr_block;
        integer k;
        real bpsk_sym, noise, llr_val;
        reg signed [LLR_WIDTH-1:0] llr_q;
        begin
            for (k = 0; k < ZC; k = k + 1) begin
                bpsk_sym = bits[k] ? -1.0 : 1.0;
                // 高斯噪声近似（用 $random 生成均匀噪声再 Box-Muller，简化为均匀缩放）
                noise = ($random % 1000) / 1000.0 - 0.5;
                noise = noise * 2.0 * noise_sigma * 1.732;  // 均匀→近似高斯（3sigma范围）
                llr_val = (bpsk_sym + noise) * 4.0;  // LLR 缩放
                if (llr_val > 31.0) llr_val = 31.0;
                if (llr_val < -32.0) llr_val = -32.0;
                llr_q = $rtoi(llr_val);
                llr_block[(k+1)*LLR_WIDTH-1 -: LLR_WIDTH] = llr_q;
            end
        end
    endtask

    task run_frame;
        input integer seed;
        input real sigma;
        integer k, i;
        reg [ZC-1:0] info_block;
        begin
            // 生成随机信息位
            for (k = 0; k < K_B; k = k + 1) begin
                info_block = $random(seed);
                tx_info[k] = info_block;
            end

            // 编码
            enc_idx = 0;
            enc_start = 1;
            @(posedge clk); enc_start = 0;
            for (k = 0; k < K_B; k = k + 1) begin
                enc_s_tdata = tx_info[k];
                enc_s_tvalid = 1;
                enc_s_tlast = (k == K_B-1);
                @(posedge clk);
            end
            enc_s_tvalid = 0;
            @(posedge enc_done);
            @(posedge clk);

            // BPSK + AWGN → LLR，送入译码器
            dec_idx = 0;
            dec_start = 1;
            @(posedge clk); dec_start = 0;
            for (k = 0; k < N_B; k = k + 1) begin
                bpsk_awgn_llr(tx_code[k], sigma, dec_s_tdata);
                dec_s_tvalid = 1;
                dec_s_tlast = (k == N_B-1);
                @(posedge clk);
            end
            dec_s_tvalid = 0;
            @(posedge dec_done);
            @(posedge clk);

            // 统计误码（只统计信息位部分）
            for (k = 0; k < K_B; k = k + 1) begin
                for (i = 0; i < ZC; i = i + 1) begin
                    total_bits = total_bits + 1;
                    if (rx_code[k][i] !== tx_info[k][i])
                        error_bits = error_bits + 1;
                end
            end
        end
    endtask

    initial begin
        rst_n = 0;
        enc_start = 0; enc_s_tvalid = 0; enc_s_tlast = 0; enc_m_tready = 1;
        dec_start = 0; dec_s_tvalid = 0; dec_s_tlast = 0; dec_m_tready = 1;
        total_bits = 0; error_bits = 0;
        #(CLK_PERIOD*5); rst_n = 1;
        #(CLK_PERIOD*2);

        $display("=== LDPC End-to-End Test ===");
        $display("Config: N_B=%0d, K_B=%0d, ZC=%0d, rate=%0.2f, max_iter=%0d",
                 N_B, K_B, ZC, 1.0*K_B/N_B, MAX_ITER);

        // 无噪声测试（SNR=inf），应零误码
        $display("\n--- Test: No noise (should be BER=0) ---");
        run_frame(42, 0.001);
        $display("  Frame 0: total=%0d, errors=%0d, BER=%0.4f",
                 total_bits, error_bits, 1.0*error_bits/total_bits);
        $display("  tx_info: %b %b %b %b", tx_info[0], tx_info[1], tx_info[2], tx_info[3]);
        $display("  rx_code: %b %b %b %b", rx_code[0], rx_code[1], rx_code[2], rx_code[3]);
        $display("  tx_code: %b %b %b %b %b %b %b %b",
                 tx_code[0], tx_code[1], tx_code[2], tx_code[3],
                 tx_code[4], tx_code[5], tx_code[6], tx_code[7]);

        // 低噪声
        $display("\n--- Test: Low noise (sigma=0.3) ---");
        total_bits = 0; error_bits = 0;
        for (frame = 0; frame < 5; frame = frame + 1)
            run_frame(100+frame, 0.3);
        $display("  5 frames: total=%0d, errors=%0d, BER=%0.6f",
                 total_bits, error_bits, 1.0*error_bits/total_bits);

        // 中噪声
        $display("\n--- Test: Medium noise (sigma=0.7) ---");
        total_bits = 0; error_bits = 0;
        for (frame = 0; frame < 5; frame = frame + 1)
            run_frame(200+frame, 0.7);
        $display("  5 frames: total=%0d, errors=%0d, BER=%0.6f",
                 total_bits, error_bits, 1.0*error_bits/total_bits);

        $display("\n=== E2E Test Complete ===");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 200000);
        $display("Timeout!"); $finish;
    end
endmodule
