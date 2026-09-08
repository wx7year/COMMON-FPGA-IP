/*
 * Polar End-to-End Testbench
 * 编码 → BPSK调制 → AWGN → SC译码 → 误码率统计
 */
`timescale 1ns / 1ps

module tb_polar_e2e;
    localparam integer N         = 64;
    localparam integer K         = 32;
    localparam integer LLR_WIDTH = 6;
    localparam integer CLK_PERIOD = 10;
    localparam integer NUM_FRAMES = 10;

    reg clk, rst_n;

    // 编码器
    reg enc_start;
    wire enc_busy, enc_done;
    reg enc_s_tdata, enc_s_tvalid, enc_s_tlast;
    wire enc_s_tready;
    wire enc_m_tdata, enc_m_tvalid, enc_m_tlast;
    reg enc_m_tready;

    polar_encoder #(.N(N), .K(K)) u_enc (
        .clk(clk), .rst_n(rst_n), .start(enc_start), .busy(enc_busy), .done(enc_done),
        .s_axis_tdata(enc_s_tdata), .s_axis_tvalid(enc_s_tvalid),
        .s_axis_tready(enc_s_tready), .s_axis_tlast(enc_s_tlast),
        .m_axis_tdata(enc_m_tdata), .m_axis_tvalid(enc_m_tvalid),
        .m_axis_tready(enc_m_tready), .m_axis_tlast(enc_m_tlast)
    );

    // 译码器
    reg dec_start;
    wire dec_busy, dec_done;
    reg signed [LLR_WIDTH-1:0] dec_s_tdata;
    reg dec_s_tvalid, dec_s_tlast;
    wire dec_s_tready;
    wire dec_m_tdata, dec_m_tvalid, dec_m_tlast;
    reg dec_m_tready;

    polar_sc_decoder #(.N(N), .K(K), .LLR_WIDTH(LLR_WIDTH)) u_dec (
        .clk(clk), .rst_n(rst_n), .start(dec_start), .busy(dec_busy), .done(dec_done),
        .s_axis_tdata(dec_s_tdata), .s_axis_tvalid(dec_s_tvalid),
        .s_axis_tready(dec_s_tready), .s_axis_tlast(dec_s_tlast),
        .m_axis_tdata(dec_m_tdata), .m_axis_tvalid(dec_m_tvalid),
        .m_axis_tready(dec_m_tready), .m_axis_tlast(dec_m_tlast)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg [0:K-1] tx_info;
    reg [0:N-1] tx_code;
    reg [0:K-1] rx_info;
    integer enc_idx, dec_idx;
    integer total_bits, error_bits;
    integer frame;

    always @(posedge clk) begin
        if (enc_m_tvalid && enc_m_tready) begin
            tx_code[enc_idx] <= enc_m_tdata;
            enc_idx <= enc_idx + 1;
        end
    end

    always @(posedge clk) begin
        if (dec_m_tvalid && dec_m_tready) begin
            rx_info[dec_idx] <= dec_m_tdata;
            dec_idx <= dec_idx + 1;
        end
    end

    task bpsk_awgn_llr;
        input bit_val;
        input real noise_sigma;
        output signed [LLR_WIDTH-1:0] llr;
        real bpsk_sym, noise, llr_val;
        begin
            bpsk_sym = bit_val ? -1.0 : 1.0;
            noise = ($random % 1000) / 1000.0 - 0.5;
            noise = noise * 2.0 * noise_sigma * 1.732;
            llr_val = (bpsk_sym + noise) * 4.0;
            if (llr_val > 31.0) llr_val = 31.0;
            if (llr_val < -32.0) llr_val = -32.0;
            llr = $rtoi(llr_val);
        end
    endtask

    task run_frame;
        input integer seed;
        input real sigma;
        integer k, i;
        reg signed [LLR_WIDTH-1:0] llr_val;
        begin
            // 生成随机信息位
            for (k = 0; k < K; k = k + 1)
                tx_info[k] = $random(seed);

            // 编码
            enc_idx = 0;
            enc_start = 1;
            @(posedge clk); enc_start = 0;
            for (k = 0; k < K; k = k + 1) begin
                enc_s_tdata = tx_info[k];
                enc_s_tvalid = 1;
                enc_s_tlast = (k == K-1);
                @(posedge clk);
            end
            enc_s_tvalid = 0;
            @(posedge enc_done);
            @(posedge clk);

            // BPSK + AWGN → LLR，送入译码器
            dec_idx = 0;
            dec_start = 1;
            @(posedge clk); dec_start = 0;
            for (k = 0; k < N; k = k + 1) begin
                bpsk_awgn_llr(tx_code[k], sigma, llr_val);
                dec_s_tdata = llr_val;
                dec_s_tvalid = 1;
                dec_s_tlast = (k == N-1);
                @(posedge clk);
            end
            dec_s_tvalid = 0;
            @(posedge dec_done);
            @(posedge clk);

            // 统计误码
            for (k = 0; k < K; k = k + 1) begin
                total_bits = total_bits + 1;
                if (rx_info[k] !== tx_info[k])
                    error_bits = error_bits + 1;
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

        $display("=== Polar E2E Test (N=%0d, K=%0d, rate=%0.2f) ===", N, K, 1.0*K/N);

        // 无噪声
        $display("\n--- No noise (should be BER=0) ---");
        run_frame(42, 0.001);
        $display("  Frame 0: total=%0d, errors=%0d, BER=%0.4f",
                 total_bits, error_bits, 1.0*error_bits/total_bits);
        $display("  tx_info: %b", tx_info);
        $display("  rx_info: %b", rx_info);

        // 低噪声
        $display("\n--- Low noise (sigma=0.3) ---");
        total_bits = 0; error_bits = 0;
        for (frame = 0; frame < 5; frame = frame + 1)
            run_frame(100+frame, 0.3);
        $display("  5 frames: total=%0d, errors=%0d, BER=%0.6f",
                 total_bits, error_bits, 1.0*error_bits/total_bits);

        // 中噪声
        $display("\n--- Medium noise (sigma=0.7) ---");
        total_bits = 0; error_bits = 0;
        for (frame = 0; frame < 5; frame = frame + 1)
            run_frame(200+frame, 0.7);
        $display("  5 frames: total=%0d, errors=%0d, BER=%0.6f",
                 total_bits, error_bits, 1.0*error_bits/total_bits);

        $display("\n=== Polar E2E Test Complete ===");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 500000);
        $display("Timeout!"); $finish;
    end
endmodule
