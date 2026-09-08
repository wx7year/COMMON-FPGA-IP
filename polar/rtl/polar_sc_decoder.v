/*
 * Polar SC Decoder - 5G NR
 * 5G NR Polar 连续消除（SC）译码器
 *
 * 蝶形结构（与 FFT 不同）：
 *   stage s: 成对 (i, i + N/2^(s+1))，i 的低 s 位为 0
 *   左输出：f(a,b) = sign(a)*sign(b)*min(|a|,|b|)
 *   右输出：g(a,b,u) = b + (1-2u)*a
 *
 * 遍历：叶子 0..N-1 顺序，forward 计算左路径 f，backward 计算右路径 g
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
    reg beta [0:LOG2N][0:N-1];

    reg [0:N-1] u_hat;

    assign s_axis_tready = (state == S_LOAD);

    // 当前 stage 的半块大小
    wire [N_W-1:0] half = N >> (stage[0 +: STAGE_W] + 1);
    // 当前叶子在 stage 级的块内偏移
    wire [N_W-1:0] offset = leaf_idx % (N >> stage[0 +: STAGE_W]);
    // 是否右半部分
    wire is_right = (offset >= half);
    // 成对元素索引
    wire [N_W-1:0] pair_idx = is_right ? (leaf_idx - half) : (leaf_idx + half);

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

    integer si, ni;
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
                            for (si = 0; si <= LOG2N; si = si + 1)
                                for (ni = 0; ni < N; ni = ni + 1)
                                    beta[si][ni] <= 1'b0;
                        end else begin
                            load_cnt <= load_cnt + 1'b1;
                        end
                    end
                end

                S_FORWARD: begin
                    if (stage < LOG2N) begin
                        if (!is_right) begin
                            // 左子节点：f(alpha[stage][leaf_idx], alpha[stage][pair_idx])
                            alpha[stage+1][leaf_idx] <= f_func(
                                alpha[stage][leaf_idx],
                                alpha[stage][pair_idx]
                            );
                        end
                        // 右子节点的 g 在 backward 计算
                        stage <= stage + 1'b1;
                    end else begin
                        state <= S_DECISION;
                    end
                end

                S_DECISION: begin
                    u_hat[leaf_idx] <= alpha[LOG2N][leaf_idx[0 +: N_W]][LLR_WIDTH-1];
                    beta[LOG2N][leaf_idx] <= alpha[LOG2N][leaf_idx[0 +: N_W]][LLR_WIDTH-1];
                    stage <= LOG2N - 1;
                    state <= S_BACKWARD;
                end

                S_BACKWARD: begin
                    if (stage < LOG2N) begin
                        if (is_right) begin
                            // 右子节点：g(alpha[stage][pair_idx], alpha[stage][leaf_idx], beta)
                            // beta 用左子节点的判决异或
                            alpha[stage+1][leaf_idx] <= g_func(
                                alpha[stage][pair_idx],
                                alpha[stage][leaf_idx],
                                beta[stage+1][pair_idx[0 +: N_W]]
                            );
                        end
                        // 更新 beta[stage][父节点] = 左子树 ^ 右子树
                        beta[stage][pair_idx] <= beta[stage+1][pair_idx] ^ beta[stage+1][leaf_idx];

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
