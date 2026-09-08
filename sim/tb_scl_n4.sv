`timescale 1ns/1ps
module tb_scl_n4;
    reg clk, rst_n;
    reg start;
    wire busy, done;
    reg signed [5:0] s_tdata;
    reg s_tvalid, s_tlast;
    wire s_tready;
    wire m_tdata, m_tvalid, m_tlast;
    reg m_tready;
    wire [1:0] best_path;
    wire [15:0] best_pm;
    wire crc_pass;

    // N=4, K=1 (no CRC for simple test)
    polar_scl_decoder #(
        .N(4), .K(1), .CRC_LEN(0), .L(4),
        .LLR_WIDTH(6), .PM_WIDTH(16), .LOG2N(2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .best_path(best_path), .best_pm(best_pm), .crc_pass(crc_pass)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer i;
    reg [3:0] dec_bits;
    initial begin
        rst_n = 0;
        start = 0;
        s_tvalid = 0;
        s_tlast = 0;
        m_tready = 1;
        #20 rst_n = 1;
        #10;

        // Test: info=1 at Q_N[3]=3, u=[0,0,0,1], codeword=[0,1,0,1]
        // llr = [8, -8, 8, -8]
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);

        for (i = 0; i < 4; i = i + 1) begin
            s_tvalid = 1;
            s_tlast = (i == 3);
            case (i)
                0: s_tdata = 8;
                1: s_tdata = -8;
                2: s_tdata = 8;
                3: s_tdata = -8;
            endcase
            @(posedge clk);
        end
        s_tvalid = 0;

        wait(done);
        @(posedge clk);
        $display("Done. best_path=%0d best_pm=%0d crc_pass=%0d", best_path, best_pm, crc_pass);
        #100 $finish;
    end

    always @(posedge clk) begin
        if (m_tvalid) begin
            $display("  Output bit: %0d", m_tdata);
        end
    end
endmodule
