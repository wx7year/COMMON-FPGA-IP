`timescale 1ns/1ps
module tb_scl_random;
    localparam N=64, K=32, CRC_LEN=16, L=4, LLR_WIDTH=6, PM_WIDTH=16;
    reg clk,rst_n,start; wire busy,done;
    reg signed [LLR_WIDTH-1:0] s_data; reg s_valid,s_last; wire s_ready;
    wire m_data,m_valid,m_last; reg m_ready;
    wire [1:0] best_path; wire [PM_WIDTH-1:0] best_pm; wire crc_pass;
    polar_scl_decoder #(.N(N),.K(K),.CRC_LEN(CRC_LEN),.L(L),.LLR_WIDTH(LLR_WIDTH),.PM_WIDTH(PM_WIDTH)) u_dec(
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),
        .s_axis_tdata(s_data),.s_axis_tvalid(s_valid),.s_axis_tready(s_ready),.s_axis_tlast(s_last),
        .m_axis_tdata(m_data),.m_axis_tvalid(m_valid),.m_axis_tready(m_ready),.m_axis_tlast(m_last),
        .best_path(best_path),.best_pm(best_pm),.crc_pass(crc_pass));
    initial clk=0; always #5 clk=~clk;
    integer i,out_cnt,seed;
    initial begin
        seed=42;
        rst_n=0;start=0;s_valid=0;s_last=0;m_ready=1;
        #20;rst_n=1;#20;
        $display("Starting SCL decode (random LLR)");
        @(posedge clk);start<=1;@(posedge clk);start<=0;
        for(i=0;i<N;i=i+1) begin
            @(posedge clk);
            s_data <= $signed({$random(seed)} % 32);
            s_valid<=1; s_last<=(i==N-1);
        end
        @(posedge clk);s_valid<=0;s_last<=0;
        $display("Input done at t=%0t state=%0d",$time,u_dec.state);
        out_cnt=0;
        for(i=0;i<K;i=i+1) begin
            @(posedge clk);
            while(!m_valid) @(posedge clk);
            out_cnt=out_cnt+1;
        end
        $display("Done: %0d outputs at t=%0t, best_path=%0d best_pm=%0d crc_pass=%0b",out_cnt,$time,best_path,best_pm,crc_pass);
        #50;$finish;
    end
    initial #50000 begin $display("TIMEOUT state=%0d leaf=%0d stage=%0d",u_dec.state,u_dec.leaf_idx,u_dec.stage); $finish; end
endmodule
