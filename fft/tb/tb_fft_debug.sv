`timescale 1ns / 1ps
module tb_fft_debug;
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

    integer cnt;
    integer out_cnt;
    initial begin
        rst_n=0; s_axis_tvalid=0; s_axis_tlast=0; m_axis_tready=1; fwd_inv=1;
        #(CLK_PERIOD*5); rst_n=1; #(CLK_PERIOD*2);

        // 驱动 N 个输入（冲激：x[0]=1, 其余=0）
        $display("Start driving input");
        for (cnt = 0; cnt < N; cnt = cnt+1) begin
            s_axis_tdata = (cnt==0) ? {16'd0, 16'd1} : {16'd0, 16'd0};
            s_axis_tvalid = 1;
            s_axis_tlast = (cnt==N-1);
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
        end
        s_axis_tvalid = 0; s_axis_tlast = 0;
        $display("Input done, waiting for output");

        // 等输出
        out_cnt = 0;
        while (out_cnt < N) begin
            @(posedge clk);
            if (m_axis_tvalid) begin
                $display("  out[%0d] = %d", out_cnt, m_axis_tdata[DOUT_WIDTH-1:0]);
                out_cnt = out_cnt + 1;
            end
        end
        $display("All output received");
        #(CLK_PERIOD*10);
        $finish;
    end

    initial begin
        #(CLK_PERIOD*10000);
        $display("Timeout! busy=%b done=%b sready=%b mvalid=%b state=%0d stage=%0d bfly=%0d drain=%0d",
                 busy, done, s_axis_tready, m_axis_tvalid,
                 dut.u_core.state, dut.u_core.stage_cnt, dut.u_core.butterfly_cnt, dut.u_core.drain_cnt);
        $finish;
    end

    // 每 20 周期打印状态
    integer mon_cnt;
    initial begin
        mon_cnt = 0;
        forever begin
            @(posedge clk);
            mon_cnt = mon_cnt + 1;
            if (mon_cnt % 20 == 0)
                $display("t=%0d state=%0d stage=%0d bfly=%0d drain=%0d busy=%b mvalid=%b",
                         mon_cnt, dut.u_core.state, dut.u_core.stage_cnt, dut.u_core.butterfly_cnt,
                         dut.u_core.drain_cnt, busy, m_axis_tvalid);
        end
    end
endmodule
