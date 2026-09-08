`timescale 1ns / 1ps
module tb_fft_debug2;
    localparam integer N = 8;
    localparam integer LOG2_N = 3;
    localparam integer DIN_WIDTH = 16;
    localparam integer DOUT_WIDTH = DIN_WIDTH + LOG2_N;
    localparam integer TWIDDLE_WIDTH = 16;
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

    integer cycle;
    initial begin
        $display("TB: starting");
        rst_n=0; s_axis_tvalid=0; s_axis_tlast=0; m_axis_tready=1; fwd_inv=1;
        cycle=0;
        #(CLK_PERIOD*5); rst_n=1;
        $display("TB: reset done");

        // 驱动输入 [1,2,3,4,5,6,7,8]
        for (cycle = 0; cycle < N; cycle = cycle+1) begin
            @(posedge clk);
            s_axis_tdata = {16'd0, 16'(cycle+1)};
            s_axis_tvalid = 1;
            s_axis_tlast = (cycle==N-1);
        end
        @(posedge clk);
        s_axis_tvalid = 0; s_axis_tlast = 0;
        $display("TB: input done, state=%0d", dut.u_core.state);

        // 等输出
        for (cycle = 0; cycle < 100; cycle = cycle+1) begin
            @(posedge clk);
            #1;
            if (m_axis_tvalid) begin
                $display("TB: got output re=%d im=%d", m_axis_tdata[DOUT_WIDTH-1:0], m_axis_tdata[2*DOUT_WIDTH-1:DOUT_WIDTH]);
            end
            if (done) begin
                $display("TB: done");
                break;
            end
        end
        #(CLK_PERIOD*5);
        $display("TB: finish");
        $finish;
    end
endmodule
