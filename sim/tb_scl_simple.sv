`timescale 1ns/1ps
module tb_scl_simple;
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

    polar_scl_decoder dut (
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
    integer err_cnt;
    initial begin
        rst_n = 0;
        start = 0;
        s_tvalid = 0;
        s_tlast = 0;
        m_tready = 1;
        err_cnt = 0;
        #20 rst_n = 1;
        #10;

        // All-zero codeword, all LLR=+8
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);

        for (i = 0; i < 64; i = i + 1) begin
            s_tvalid = 1;
            s_tlast = (i == 63);
            s_tdata = 8;
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
            if (m_tdata != 0) begin
                err_cnt = err_cnt + 1;
                $display("  ERR: output bit=%0d (expected 0)", m_tdata);
            end
        end
    end
endmodule
