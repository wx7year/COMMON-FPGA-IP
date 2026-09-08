`timescale 1ns/1ps
module tb_fir_impulse;
    localparam NUM_TAPS=31, DATA_WIDTH=16, COEFF_WIDTH=16;
    localparam CLK_FREQ=80_000_000, SAMPLE_RATE=10_000_000, SYMMETRIC=1;
    localparam OUT_WIDTH=DATA_WIDTH+COEFF_WIDTH+$clog2(NUM_TAPS)+1;
    reg clk,rst_n; reg [15:0] s_tdata; reg s_tvalid,s_tlast; wire s_tready;
    wire [OUT_WIDTH-1:0] m_tdata; wire m_tvalid; reg m_tready; wire m_tlast; wire busy;
    fir_top #(.NUM_TAPS(NUM_TAPS),.DATA_WIDTH(DATA_WIDTH),.COEFF_WIDTH(COEFF_WIDTH),
        .CLK_FREQ(CLK_FREQ),.SAMPLE_RATE(SAMPLE_RATE),.SYMMETRIC(SYMMETRIC),
        .COEFF_FILE("data/fir_coeff.mem")) dut
      (.clk(clk),.rst_n(rst_n),.s_axis_tdata(s_tdata),.s_axis_tvalid(s_tvalid),
       .s_axis_tready(s_tready),.s_axis_tlast(s_tlast),.m_axis_tdata(m_tdata),
       .m_axis_tvalid(m_tvalid),.m_axis_tready(m_tready),.m_axis_tlast(m_tlast),.busy(busy));
    initial clk=0; always #6 clk=~clk;
    initial begin
        rst_n=0;s_tvalid=0;s_tlast=0;m_tready=1;
        #60;rst_n=1;#20;
        fork
            begin: drv
                integer d;
                for(d=0;d<35;d=d+1) begin
                    @(posedge clk);
                    s_tdata = (d==0) ? 16'd32767 : 16'd0;
                    s_tvalid = 1;
                    s_tlast = (d==34);
                    @(posedge clk);
                    while(!s_tready) @(posedge clk);
                end
                s_tvalid=0;s_tlast=0;
            end
            begin: col
                integer c;
                for(c=0;c<35;c=c+1) begin
                    @(posedge clk);
                    while(!m_tvalid) @(posedge clk);
                    $display("y[%0d] = %0d", c, $signed(m_tdata));
                end
            end
        join
        $finish;
    end
    initial #200000 $finish;
endmodule
