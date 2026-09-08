`timescale 1ns/1ps
module tb_enc_mon;
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
    initial begin
        $display("N=%0d K=%0d",N,K);
        rst_n=0;start=0;s_valid=0;s_last=0;m_ready=1;
        #20;rst_n=1;#20;
        @(posedge clk);start<=1;@(posedge clk);start<=0;
        // 用非阻塞赋值，每周期发一个
        for(i=0;i<K;i=i+1) begin
            @(posedge clk);
            s_data<=i[0];s_valid<=1;s_last<=(i==K-1);
        end
        @(posedge clk);s_valid<=0;s_last<=0;
        // 监控输出
        out_cnt=0;
        for(i=0;i<100;i=i+1) begin
            @(posedge clk);
            if (m_valid) out_cnt=out_cnt+1;
            if (i<70 || m_valid)
                $display("t=%0t state=%0d cnt=%0d s_ready=%0b m_valid=%0b m_data=%0b out_cnt=%0d done=%0b",
                    $time,u_enc.state,u_enc.cnt,s_ready,m_valid,m_data,out_cnt,done);
        end
        $display("Total outputs: %0d",out_cnt);
        $finish;
    end
endmodule
