/*
 * Polar SC Decoder - 5G NR
 * 5G NR Polar 连续消除（SC）译码器
 *
 * 深度优先遍历：
 *   Forward：根→叶子，对路径上每个 stage 计算当前节点的所有左子元素（f函数）
 *   Decision：叶子硬判决（冻结位强制 0）
 *   Backward：叶子→根，计算右子元素（g函数，用左子叶子判决）
 *
 * f(a,b) = sign(a)*sign(b)*min(|a|,|b|)
 * g(a,b,u) = b + (1-2u)*a
 *
 * 蝶形：stage s, half=N/2^(s+1), 节点起始 node_start=leaf-(leaf%(N>>s))
 *   左子元素：alpha[s+1][node_start+j] = f(alpha[s][node_start+j], alpha[s][node_start+half+j])
 *   右子元素：alpha[s+1][node_start+half+j] = g(alpha[s][node_start+j], alpha[s][node_start+half+j], u_hat[node_start+j])
 */
module polar_sc_decoder #(
    parameter integer N         = 64,
    parameter integer K         = 32,
    parameter integer LLR_WIDTH = 6,
    parameter integer LOG2N     = $clog2(N),
    parameter integer N_W       = $clog2(N+1),
    parameter integer STAGE_W   = $clog2(LOG2N+1)
)(
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        start,
    output reg                         busy,
    output reg                         done,

    input  wire signed [LLR_WIDTH-1:0] s_axis_tdata,
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire                        s_axis_tlast,

    output reg                         m_axis_tdata,
    output reg                         m_axis_tvalid,
    input  wire                        m_axis_tready,
    output reg                         m_axis_tlast
);

    localparam S_IDLE     = 3'd0;
    localparam S_LOAD     = 3'd1;
    localparam S_FORWARD  = 3'd2;
    localparam S_DECISION = 3'd3;
    localparam S_BACKWARD = 3'd4;
    localparam S_OUTPUT   = 3'd5;

    reg [2:0] state;
    reg [N_W-1:0] leaf_idx;
    reg [STAGE_W-1:0] stage;
    reg [N_W-1:0] load_cnt;
    reg [N_W-1:0] out_cnt;

    reg signed [LLR_WIDTH-1:0] alpha [0:LOG2N][0:N-1];
    reg [0:N-1] u_hat;

    assign s_axis_tready = (state == S_LOAD);

    // 冻结位：前 N-K 个位置为冻结位（简化，非真实可靠性序列）
    wire is_frozen = (leaf_idx < (N - K));

    // f 函数
    function signed [LLR_WIDTH-1:0] f_func;
        input signed [LLR_WIDTH-1:0] a, b;
        reg sign_a, sign_b, sign_out;
        reg [LLR_WIDTH-2:0] abs_a, abs_b, abs_min;
        begin
            sign_a = a[LLR_WIDTH-1];
            sign_b = b[LLR_WIDTH-1];
            abs_a = sign_a ? -a : a[LLR_WIDTH-2:0];
            abs_b = sign_b ? -b : b[LLR_WIDTH-2:0];
            abs_min = (abs_a < abs_b) ? abs_a : abs_b;
            sign_out = sign_a ^ sign_b;
            f_func = sign_out ? -$signed({1'b0, abs_min}) : $signed({1'b0, abs_min});
        end
    endfunction

    // g 函数
    function signed [LLR_WIDTH-1:0] g_func;
        input signed [LLR_WIDTH-1:0] a, b;
        input u;
        reg signed [LLR_WIDTH:0] sum;
        begin
            sum = u ? (b - a) : (b + a);
            if (sum > $signed({1'b0, {LLR_WIDTH-1{1'b1}}}))
                g_func = {1'b0, {LLR_WIDTH-1{1'b1}}};
            else if (sum < -$signed({1'b0, {LLR_WIDTH-1{1'b1}}}))
                g_func = {1'b1, {LLR_WIDTH-1{1'b0}}};
            else
                g_func = sum[LLR_WIDTH-1:0];
        end
    endfunction

    integer si, ni, ji;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            leaf_idx <= 'd0;
            stage <= 'd0;
            load_cnt <= 'd0;
            out_cnt <= 'd0;
            m_axis_tdata <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    if (start) begin
                        state <= S_LOAD;
                        busy <= 1'b1;
                        load_cnt <= 'd0;
                    end
                end

                S_LOAD: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        alpha[0][load_cnt] <= s_axis_tdata;
                        if (s_axis_tlast || load_cnt == N - 1) begin
                            state <= S_FORWARD;
                            leaf_idx <= 'd0;
                            stage <= 'd0;
                        end else begin
                            load_cnt <= load_cnt + 1'b1;
                        end
                    end
                end

                S_FORWARD: begin
                    // 对当前 stage，若 leaf 在左子树，计算当前节点所有 half 个左子元素
                    if (stage < LOG2N) begin
                        if ((leaf_idx % (N >> stage)) < (N >> (stage+1))) begin
                            for (ji = 0; ji < (N >> (stage+1)); ji = ji + 1) begin
                                alpha[stage+1][(leaf_idx - (leaf_idx % (N >> stage))) + ji] <= f_func(
                                    alpha[stage][(leaf_idx - (leaf_idx % (N >> stage))) + ji],
                                    alpha[stage][(leaf_idx - (leaf_idx % (N >> stage))) + ji + (N >> (stage+1))]
                                );
                            end
                        end
                        stage <= stage + 1'b1;
                    end else begin
                        state <= S_DECISION;
                    end
                end

                S_DECISION: begin
                    // 冻结位强制 0，信息位硬判决
                    if (is_frozen) begin
                        u_hat[leaf_idx] <= 1'b0;
                    end else begin
                        u_hat[leaf_idx] <= alpha[LOG2N][leaf_idx[0 +: N_W]][LLR_WIDTH-1];
                    end
                    stage <= LOG2N - 1;
                    state <= S_BACKWARD;
                end

                S_BACKWARD: begin
                    if (stage < LOG2N) begin
                        // 计算右子节点中与当前 leaf 对应的元素
                        // right_idx = node_start + half + (offset % half)
                        // left_idx  = node_start + (offset % half)
                        alpha[stage+1][(leaf_idx - (leaf_idx % (N >> stage))) + (N >> (stage+1)) + ((leaf_idx % (N >> stage)) % (N >> (stage+1)))] <= g_func(
                            alpha[stage][(leaf_idx - (leaf_idx % (N >> stage))) + ((leaf_idx % (N >> stage)) % (N >> (stage+1)))],
                            alpha[stage][(leaf_idx - (leaf_idx % (N >> stage))) + (N >> (stage+1)) + ((leaf_idx % (N >> stage)) % (N >> (stage+1)))],
                            u_hat[(leaf_idx - (leaf_idx % (N >> stage))) + ((leaf_idx % (N >> stage)) % (N >> (stage+1)))]
                        );

                        if (stage == 0) begin
                            if (leaf_idx == N - 1) begin
                                state <= S_OUTPUT;
                                out_cnt <= 'd0;
                            end else begin
                                leaf_idx <= leaf_idx + 1'b1;
                                stage <= 'd0;
                                state <= S_FORWARD;
                            end
                        end else begin
                            stage <= stage - 1'b1;
                        end
                    end
                end

                S_OUTPUT: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata <= u_hat[N-K+out_cnt[N_W-1:0]];
                    m_axis_tlast <= (out_cnt == K - 1);
                    if (m_axis_tready) begin
                        if (out_cnt == K - 1) begin
                            state <= S_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                            m_axis_tvalid <= 1'b0;
                        end else begin
                            out_cnt <= out_cnt + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
