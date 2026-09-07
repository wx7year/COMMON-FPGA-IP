/*
 * LDPC CNU (Check Node Update) Testbench
 * 测试串行 Min-Sum 校验节点更新单元
 */
`timescale 1ns / 1ps

module tb_ldpc_cnu;
    localparam integer LLR_WIDTH = 6;
    localparam integer NUM_INPUTS = 4;
    localparam integer CLK_PERIOD = 10;

    reg clk, rst_n, start;
    wire busy, done;
    reg signed [LLR_WIDTH-1:0] llr_in;
    reg llr_valid;
    wire signed [LLR_WIDTH-1:0] msg_out;
    wire msg_valid;

    ldpc_cnu #(.LLR_WIDTH(LLR_WIDTH), .NUM_INPUTS(NUM_INPUTS), .ALPHA(1)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
        .llr_in(llr_in), .llr_valid(llr_valid),
        .msg_out(msg_out), .msg_valid(msg_valid)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer errors;
    integer out_idx;
    reg signed [LLR_WIDTH-1:0] out_buf [0:NUM_INPUTS-1];

    always @(posedge clk) begin
        if (msg_valid) begin
            out_buf[out_idx] <= msg_out;
            out_idx <= out_idx + 1;
        end
    end

    task run_cnu;
        input signed [LLR_WIDTH-1:0] v0, v1, v2, v3;
        begin
            out_idx = 0;
            start = 1;
            @(posedge clk); start = 0;
            llr_in = v0; llr_valid = 1;
            @(posedge clk);
            llr_in = v1;
            @(posedge clk);
            llr_in = v2;
            @(posedge clk);
            llr_in = v3;
            @(posedge clk);
            llr_valid = 0;
            @(posedge done);
            @(posedge clk);
        end
    endtask

    function signed [LLR_WIDTH-1:0] min_sum_ref;
        input integer idx;
        input signed [LLR_WIDTH-1:0] l0, l1, l2, l3;
        integer vals[0:3];
        integer abs_vals[0:3];
        integer min1, min2, min1_idx, sign_total;
        integer i, min_excl, out_sign, result;
        begin
            vals[0]=l0; vals[1]=l1; vals[2]=l2; vals[3]=l3;
            min1 = 1000; min2 = 1000; min1_idx = 0; sign_total = 0;
            for (i=0; i<4; i=i+1) begin
                abs_vals[i] = vals[i] < 0 ? -vals[i] : vals[i];
                sign_total = sign_total ^ (vals[i] < 0 ? 1 : 0);
                if (abs_vals[i] < min1) begin
                    min2 = min1; min1 = abs_vals[i]; min1_idx = i;
                end else if (abs_vals[i] < min2) begin
                    min2 = abs_vals[i];
                end
            end
            min_excl = (idx == min1_idx) ? min2 : min1;
            out_sign = sign_total ^ (vals[idx] < 0 ? 1 : 0);
            result = out_sign ? -min_excl : min_excl;
            // alpha=0.75: result - (result>>>2)
            result = result - (result >>> 2);
            min_sum_ref = result;
        end
    endfunction

    initial begin
        rst_n = 0; errors = 0;
        start = 0; llr_valid = 0; out_idx = 0;
        #(CLK_PERIOD*5); rst_n = 1;

        // Test 1: LLR = [3, -1, 2, -4]
        $display("Test 1: LLR = [3, -1, 2, -4]");
        run_cnu(6'sd3, -6'sd1, 6'sd2, -6'sd4);
        $display("  output = [%0d, %0d, %0d, %0d]", out_buf[0], out_buf[1], out_buf[2], out_buf[3]);
        if (out_buf[0] !== min_sum_ref(0, 3,-1,2,-4)) begin $display("  FAIL [0]"); errors++; end
        if (out_buf[1] !== min_sum_ref(1, 3,-1,2,-4)) begin $display("  FAIL [1]"); errors++; end
        if (out_buf[2] !== min_sum_ref(2, 3,-1,2,-4)) begin $display("  FAIL [2]"); errors++; end
        if (out_buf[3] !== min_sum_ref(3, 3,-1,2,-4)) begin $display("  FAIL [3]"); errors++; end
        if (errors == 0) $display("  PASS");

        // Test 2: 全正 LLR = [5, 2, 8, 1]
        $display("Test 2: LLR = [5, 2, 8, 1]");
        run_cnu(6'sd5, 6'sd2, 6'sd8, 6'sd1);
        $display("  output = [%0d, %0d, %0d, %0d]", out_buf[0], out_buf[1], out_buf[2], out_buf[3]);
        if (out_buf[0] !== min_sum_ref(0, 5,2,8,1)) begin $display("  FAIL [0]"); errors++; end
        if (out_buf[1] !== min_sum_ref(1, 5,2,8,1)) begin $display("  FAIL [1]"); errors++; end
        if (out_buf[2] !== min_sum_ref(2, 5,2,8,1)) begin $display("  FAIL [2]"); errors++; end
        if (out_buf[3] !== min_sum_ref(3, 5,2,8,1)) begin $display("  FAIL [3]"); errors++; end
        if (errors == 0) $display("  PASS");

        // Test 3: 含零 LLR = [0, -3, 0, 2]
        $display("Test 3: LLR = [0, -3, 0, 2]");
        run_cnu(6'sd0, -6'sd3, 6'sd0, 6'sd2);
        $display("  output = [%0d, %0d, %0d, %0d]", out_buf[0], out_buf[1], out_buf[2], out_buf[3]);
        if (out_buf[0] !== min_sum_ref(0, 0,-3,0,2)) begin $display("  FAIL [0]"); errors++; end
        if (out_buf[1] !== min_sum_ref(1, 0,-3,0,2)) begin $display("  FAIL [1]"); errors++; end
        if (out_buf[2] !== min_sum_ref(2, 0,-3,0,2)) begin $display("  FAIL [2]"); errors++; end
        if (out_buf[3] !== min_sum_ref(3, 0,-3,0,2)) begin $display("  FAIL [3]"); errors++; end
        if (errors == 0) $display("  PASS");

        $display("\n=== CNU Test Complete, errors=%0d ===", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 10000);
        $display("Timeout!"); $finish;
    end
endmodule
