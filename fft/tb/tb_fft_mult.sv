`timescale 1ns / 1ps
module tb_fft_mult;
    localparam integer N = 8;
    localparam integer LOG2_N = 3;
    localparam integer DIN_WIDTH = 16;
    localparam integer DOUT_WIDTH = DIN_WIDTH + LOG2_N;
    localparam integer TWIDDLE_WIDTH = 16;
    localparam integer INTERN_WIDTH = DIN_WIDTH + LOG2_N;
    localparam integer CLK_PERIOD = 10;

    reg clk, rst_n, fwd_inv;
    reg [2*DIN_WIDTH-1:0] s_axis_tdata;
    reg s_axis_tvalid, s_axis_tlast;
    wire s_axis_tready;
    wire [2*DOUT_WIDTH-1:0] m_axis_tdata;
    wire m_axis_tvalid, m_axis_tlast;
    reg m_axis_tready;
    wire busy, done;

    fft_top #(.N(N),.LOG2_N(LOG2_N),.DIN_WIDTH(DIN_WIDTH),.DOUT_WIDTH(DOUT_WIDTH),.TWIDDLE_WIDTH(TWIDDLE_WIDTH)) dut (
        .clk(clk),.rst_n(rst_n),.fwd_inv(fwd_inv),
        .s_axis_tdata(s_axis_tdata),.s_axis_tvalid(s_axis_tvalid),.s_axis_tready(s_axis_tready),.s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),.m_axis_tvalid(m_axis_tvalid),.m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast),
        .busy(busy),.done(done)
    );

    initial clk=0; always #(CLK_PERIOD/2) clk=~clk;

    integer i, cycle;
    initial begin
        rst_n=0; s_axis_tvalid=0; s_axis_tlast=0; m_axis_tready=1; fwd_inv=1;
        #(CLK_PERIOD*5); rst_n=1; #(CLK_PERIOD*2);

        for (i = 0; i < N; i = i+1) begin
            @(posedge clk);
            s_axis_tdata = {16'd0, 16'(i+1)};
            s_axis_tvalid = 1;
            s_axis_tlast = (i==N-1);
        end
        @(posedge clk);
        s_axis_tvalid = 0; s_axis_tlast = 0;

        for (cycle = 0; cycle < 30; cycle = cycle+1) begin
            @(posedge clk);
            $display("t=%0d state=%0d bfly=%0d a_re=%0d b_re=%0d tw_re=%0d mult_re=%0d bw_re=%0d y1=%0d y2=%0d",
                     cycle, dut.u_core.state, dut.u_core.butterfly_cnt,
                     dut.u_core.a_re_d[3], dut.u_core.b_re_s1,
                     dut.u_core.tw_re, dut.u_core.mult_p_re,
                     dut.u_core.bw_re, dut.u_core.y1_re_t, dut.u_core.y2_re_t);
            if (done) break;
        end
        #(CLK_PERIOD*5);
        $finish;
    end
endmodule
