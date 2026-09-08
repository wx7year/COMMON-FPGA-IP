`timescale 1ns/1ps
module tb_ram_check;
    localparam N=8, LOG2_N=3, DIN_WIDTH=16, DOUT_WIDTH=19, TWIDDLE_WIDTH=16, INTERN_WIDTH=19;
    reg clk,rst_n,fwd_inv; reg [31:0] s_tdata; reg s_tvalid,s_tlast; wire s_tready;
    wire [37:0] m_tdata; wire m_tvalid,m_tlast; reg m_tready; wire busy,done;
    fft_top #(.N(N),.LOG2_N(LOG2_N),.DIN_WIDTH(DIN_WIDTH),.DOUT_WIDTH(DOUT_WIDTH),.TWIDDLE_WIDTH(TWIDDLE_WIDTH)) dut
      (.clk(clk),.rst_n(rst_n),.fwd_inv(fwd_inv),.s_axis_tdata(s_tdata),.s_axis_tvalid(s_tvalid),
       .s_axis_tready(s_tready),.s_axis_tlast(s_tlast),.m_axis_tdata(m_tdata),.m_axis_tvalid(m_tvalid),
       .m_axis_tready(m_tready),.m_axis_tlast(m_tlast),.busy(busy),.done(done));
    initial clk=0; always #5 clk=~clk;
    integer i;
    initial begin
        rst_n=0;s_tvalid=0;s_tlast=0;m_tready=1;fwd_inv=1;
        #50;rst_n=1;#20;
        for(i=0;i<N;i=i+1) begin @(posedge clk); s_tdata={16'd0,16'(i+1)}; s_tvalid=1; s_tlast=(i==N-1); end
        @(posedge clk); s_tvalid=0;
        @(posedge clk); while(dut.u_core.state!=2) @(posedge clk);
        $display("RAM contents after load:");
        for(i=0;i<N;i=i+1) $display("  ram0[%0d]=%d", i, dut.u_core.ram0[i][18:0]);
        #100; $finish;
    end
endmodule
