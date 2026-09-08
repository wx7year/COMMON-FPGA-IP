`timescale 1ns/1ps
module tb_fir_debug2;
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
    integer cyc;
    initial begin
        rst_n=0;s_tvalid=0;s_tlast=0;m_tready=1;
        #60;rst_n=1;#20;
        $display("coeff[0]=%0d coeff[1]=%0d coeff[15]=%0d", dut.coeff_rom[0], dut.coeff_rom[1], dut.coeff_rom[15]);
        // 送冲激
        @(posedge clk); s_tdata=16'd32767; s_tvalid=1;
        @(posedge clk); s_tvalid=0;
        $display("After input: x_shift[0]=%0d x_shift[1]=%0d", dut.x_shift[0], dut.x_shift[1]);
        // 等输出
        for(cyc=0;cyc<20;cyc=cyc+1) begin
            @(posedge clk);
            if (cyc < 15)
                $display("cyc=%0d state=%0d mac=%0d tap_idx=%0d pre_add=%0d coeff=%0d prod=%0d acc0=%0d acc1=%0d sum=%0d mvalid=%b mdata=%0d",
                    cyc, dut.state, dut.mac_cnt, dut.gen_mac[0].tap_idx, dut.gen_mac[0].pre_add,
                    dut.gen_mac[0].coeff, dut.gen_mac[0].prod_r, dut.gen_mac[0].acc_r, dut.gen_mac[1].acc_r,
                    dut.sum_r, m_tvalid, m_tdata);
        end
        $finish;
    end
endmodule
