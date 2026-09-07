/*
 * LDPC Testbench
 * 测试 LDPC 编码器（QC-LDPC）
 */
`timescale 1ns / 1ps

module tb_ldpc;
    localparam integer ZC   = 4;
    localparam integer ROWS = 4;
    localparam integer N_B  = 8;
    localparam integer K_B  = 4;
    localparam integer M_B  = 4;
    localparam integer CLK_PERIOD = 10;

    reg clk, rst_n, start;
    wire busy, done;

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
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .s_axis_tdata(enc_s_tdata), .s_axis_tvalid(enc_s_tvalid),
        .s_axis_tready(enc_s_tready), .s_axis_tlast(enc_s_tlast),
        .m_axis_tdata(enc_m_tdata), .m_axis_tvalid(enc_m_tvalid),
        .m_axis_tready(enc_m_tready), .m_axis_tlast(enc_m_tlast)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer i, errors;
    reg [ZC-1:0] out_buf [0:N_B-1];
    integer out_idx;

    // 输出收集：每周期采样 m_tvalid
    always @(posedge clk) begin
        if (enc_m_tvalid && enc_m_tready) begin
            out_buf[out_idx] <= enc_m_tdata;
            out_idx <= out_idx + 1;
        end
    end

    task run_encode;
        input [ZC-1:0] data0, data1, data2, data3;
        begin
            out_idx = 0;
            start = 1;
            @(posedge clk); start = 0;
            enc_s_tdata = data0; enc_s_tvalid = 1; enc_s_tlast = 0;
            @(posedge clk);
            enc_s_tdata = data1;
            @(posedge clk);
            enc_s_tdata = data2;
            @(posedge clk);
            enc_s_tdata = data3; enc_s_tlast = 1;
            @(posedge clk);
            enc_s_tvalid = 0; enc_s_tlast = 0;
            // 等待编码完成
            @(posedge done);
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; start = 0; errors = 0;
        enc_s_tvalid = 0; enc_s_tlast = 0; enc_m_tready = 1;
        out_idx = 0;
        #(CLK_PERIOD*5); rst_n = 1;
        #(CLK_PERIOD*2);

        // Test 1: 全零输入 → 全零输出
        $display("Test 1: All-zero input");
        run_encode(4'b0000, 4'b0000, 4'b0000, 4'b0000);
        for (i = 0; i < N_B; i++) begin
            if (out_buf[i] !== 4'b0000) begin
                $display("  FAIL: out[%0d]=%b, expected 0000", i, out_buf[i]);
                errors++;
            end
        end
        if (errors == 0) $display("  PASS: all outputs zero");

        // Test 2: 单比特输入
        $display("Test 2: Single-bit input (info[0][0]=1)");
        run_encode(4'b0001, 4'b0000, 4'b0000, 4'b0000);
        for (i = 0; i < N_B; i++)
            $display("  out[%0d] = %b", i, out_buf[i]);
        // 验证：信息位部分应等于输入
        if (out_buf[0] !== 4'b0001) begin $display("  FAIL: info[0] mismatch"); errors++; end
        if (out_buf[1] !== 4'b0000) begin $display("  FAIL: info[1] mismatch"); errors++; end
        if (out_buf[2] !== 4'b0000) begin $display("  FAIL: info[2] mismatch"); errors++; end
        if (out_buf[3] !== 4'b0000) begin $display("  FAIL: info[3] mismatch"); errors++; end
        $display("  info part check done");

        $display("\n=== LDPC Encoder Test Complete, errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 100000);
        $display("Timeout!"); $finish;
    end
endmodule
