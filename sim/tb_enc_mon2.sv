`timescale 1ns/1ps
module tb_enc_mon2;
    localparam N=64, K=32, CRC_LEN=16;
    reg clk,rst_n,start; wire busy,done;
    reg s_data,s_valid,s_last; wire s_ready;
    wire m_data,m_valid,m_last; reg m_ready;
    polar_encoder #(.N(N),.K(K),.CRC_LEN(CRC_LEN)) u_enc(
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),
        .s_axis_tdata(s_data),.s_axis_tvalid(s_valid),.s_axis_tready(s_ready),.s_axis_tlast(s_last),
        .m_axis_tdata(m_data),.m_axis_tvalid(m_valid),.m_axis_tready(m_ready),.m_axis_tlast(m_last));
    initial clk=0; always #5 clk=~clk;
    integer i,out_cnt;
    reg [7:0] mon_cnt;
    always @(posedge clk) begin
        if (m_valid) mon_cnt <= mon_cnt + 1;
        if (m_valid) $display("out[%0d]=%0b state=%0d cnt=%0d t=%0t", mon_cnt, m_data, u_enc.state, u_enc.cnt, $time);
    end
    initial begin
        mon_cnt=0;
        rst_n=0;start=0;s_valid=0;s_last=0;m_ready=1;
        #20;rst_n=1;#20;
        @(posedge clk);start<=1;@(posedge clk);start<=0;
        for(i=0;i<K;i=i+1) begin
            @(posedge clk);
            s_data<=i[0];s_valid<=1;s_last<=(i==K-1);
        end
        @(posedge clk);s_valid<=0;s_last<=0;
        #5000;
        $display("Total m_valid pulses: %0d", mon_cnt);
        $finish;
    end
endmodule
