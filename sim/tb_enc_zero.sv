`timescale 1ns/1ps
module tb_enc_zero;
    localparam N=64, K=32, CRC_LEN=16;
    reg clk,rst_n,start; wire busy,done;
    reg s_data,s_valid,s_last; wire s_ready;
    wire m_data,m_valid,m_last; reg m_ready;
    polar_encoder #(.N(N),.K(K),.CRC_LEN(CRC_LEN)) u_enc(
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),
        .s_axis_tdata(s_data),.s_axis_tvalid(s_valid),.s_axis_tready(s_ready),.s_axis_tlast(s_last),
        .m_axis_tdata(m_data),.m_axis_tvalid(m_valid),.m_axis_tready(m_ready),.m_axis_tlast(m_last));
    initial clk=0; always #5 clk=~clk;
    integer i,out_cnt,ones;
    initial begin
        rst_n=0;start=0;s_valid=0;s_last=0;m_ready=1;
        #20;rst_n=1;#20;
        @(posedge clk);start<=1;@(posedge clk);start<=0;
        for(i=0;i<K;i=i+1) begin
            @(posedge clk);
            s_data<=0;s_valid<=1;s_last<=(i==K-1);
        end
        @(posedge clk);s_valid<=0;s_last<=0;
        out_cnt=0;ones=0;
        for(i=0;i<N;i=i+1) begin
            @(posedge clk);
            while(!m_valid) @(posedge clk);
            out_cnt=out_cnt+1;
            if(m_data) ones=ones+1;
        end
        $display("Zero input: %0d outputs, %0d ones (should be 0)",out_cnt,ones);
        #50;$finish;
    end
endmodule
