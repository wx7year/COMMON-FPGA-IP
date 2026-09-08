`timescale 1ns/1ps
module tb_fft_detail;
    localparam N=8, LOG2_N=3, DIN_WIDTH=16, DOUT_WIDTH=19, TWIDDLE_WIDTH=16, INTERN_WIDTH=19;
    reg clk,rst_n,fwd_inv; reg [31:0] s_tdata; reg s_tvalid,s_tlast; wire s_tready;
    wire [37:0] m_tdata; wire m_tvalid,m_tlast; reg m_tready; wire busy,done;
    fft_top #(.N(N),.LOG2_N(LOG2_N),.DIN_WIDTH(DIN_WIDTH),.DOUT_WIDTH(DOUT_WIDTH),.TWIDDLE_WIDTH(TWIDDLE_WIDTH)) dut
      (.clk(clk),.rst_n(rst_n),.fwd_inv(fwd_inv),.s_axis_tdata(s_tdata),.s_axis_tvalid(s_tvalid),
       .s_axis_tready(s_tready),.s_axis_tlast(s_tlast),.m_axis_tdata(m_tdata),.m_axis_tvalid(m_tvalid),
       .m_axis_tready(m_tready),.m_axis_tlast(m_tlast),.busy(busy),.done(done));
    initial clk=0; always #5 clk=~clk;
    integer cyc;
    initial begin
        rst_n=0;s_tvalid=0;s_tlast=0;m_tready=1;fwd_inv=1;cyc=0;
        #50;rst_n=1;#20;
        @(posedge clk);
        for(cyc=0;cyc<N;cyc=cyc+1) begin
            s_tdata={16'd0,16'(cyc+1)}; s_tvalid=1; s_tlast=(cyc==N-1);
            @(posedge clk);
            while(!s_tready) @(posedge clk);
        end
        s_tvalid=0;s_tlast=0;
        #800; $finish;
    end
    always @(posedge clk) begin
        if (dut.u_core.state==2 && dut.u_core.stage_cnt==1) begin
            $display("S1 t=%0t bfly=%0d tw_addr=%0d twr=%0d twi=%0d twi_s1=%0d bs1=%0d bis1=%0d mult_im=%0d bw_im=%0d",
                $time, dut.u_core.butterfly_cnt, dut.u_core.tw_addr,
                dut.u_core.tw_re, dut.u_core.tw_im, dut.u_core.tw_im_s1,
                dut.u_core.b_re_s1, dut.u_core.b_im_s1,
                dut.u_core.mult_p_im, dut.u_core.bw_im);
        end
    end
endmodule
