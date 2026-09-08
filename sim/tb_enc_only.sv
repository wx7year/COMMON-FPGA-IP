`timescale 1ns/1ps
module tb_enc_only;
    localparam N=64, K=32, CRC_LEN=16;
    reg clk,rst_n,start; wire busy,done;
    reg s_data,s_valid,s_last; wire s_ready;
    wire m_data,m_valid,m_last; reg m_ready;
    polar_encoder #(.N(N),.K(K),.CRC_LEN(CRC_LEN)) u_enc(
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),
        .s_axis_tdata(s_data),.s_axis_tvalid(s_valid),.s_axis_tready(s_ready),.s_axis_tlast(s_last),
        .m_axis_tdata(m_data),.m_axis_tvalid(m_valid),.m_axis_tready(m_ready),.m_axis_tlast(m_last));
    initial clk=0; always #5 clk=~clk;
    reg [0:K-1] info;
    integer i,out_cnt;
    initial begin
        rst_n=0;start=0;s_valid=0;s_last=0;m_ready=1;
        #20;rst_n=1;#20;
        info=32'hA5A5A5A5;
        $display("Start encoding, state=%0d",u_enc.state);
        fork
            begin
                @(posedge clk);start=1;@(posedge clk);start=0;
                for(i=0;i<K;i=i+1) begin
                    @(posedge clk);
                    s_data=info[i];s_valid=1;s_last=(i==K-1);
                    @(posedge clk);
                    while(!s_ready) @(posedge clk);
                end
                s_valid=0;s_last=0;
                $display("Input done at t=%0t state=%0d",$time,u_enc.state);
            end
            begin
                out_cnt=0;
                for(i=0;i<N;i=i+1) begin
                    @(posedge clk);
                    while(!m_valid) @(posedge clk);
                    out_cnt=out_cnt+1;
                    if (out_cnt<=5 || out_cnt>60)
                        $display("out[%0d]=%0d state=%0d cnt=%0d t=%0t",out_cnt-1,m_data,u_enc.state,u_enc.cnt,$time);
                end
                $display("Output done: %0d bits at t=%0t",out_cnt,$time);
            end
        join
        #50;$finish;
    end
    initial #20000 begin $display("TIMEOUT at t=%0t state=%0d cnt=%0d",$time,u_enc.state,u_enc.cnt); $finish; end
endmodule
