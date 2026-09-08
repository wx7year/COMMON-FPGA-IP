/*
 * Polar SCL Decoder - Successive Cancellation List (L=4)
 * 5G NR Polar SCL 译码器：列表大小 L=4，路径度量 PM，CRC 辅助选路
 *
 * 算法：
 *   - 维护 L=4 条候选路径，每条有 alpha(LLR)、u_hat(判决位)、PM(路径度量)
 *   - 冻结位：所有路径强制判决 0，PM 更新
 *   - 信息位：每条路径分裂为 0/1，共 2L=8 候选，按 PM 排序保留 L=4 条
 *   - 译码结束：CRC 校验，选通过 CRC 且 PM 最小的路径输出
 *
 * PM 计算（越小越好）：
 *   PM += max(0, (2u-1)*LLR)  即判决与 LLR 符号不一致时惩罚 |LLR|
 *
 * 极化变换：跨步合并（stride），与编码器一致
 *   alpha[stage][j] 对应叶子 {j + k*(N>>stage) | k=0..2^stage-1}
 *   f: alpha[stage+1][j] = f(alpha[stage][j], alpha[stage][j+half]), half=N>>(stage+1)
 *   g: alpha[stage+1][j+half] = g(alpha[stage][j], alpha[stage][j+half], u_L)
 */
module polar_scl_decoder #(
    parameter integer N          = 64,
    parameter integer K          = 32,
    parameter integer CRC_LEN    = 16,
    parameter [CRC_LEN-1:0] CRC_POLY = 16'h1021,
    parameter integer L          = 4,
    parameter integer LLR_WIDTH  = 6,
    parameter integer PM_WIDTH   = 16,
    parameter integer LOG2N      = $clog2(N),
    parameter integer N_W        = $clog2(N+1),
    parameter integer STAGE_W    = $clog2(LOG2N+1),
    parameter integer K_TOTAL    = K + CRC_LEN,
    parameter integer L_W        = $clog2(L)
)(
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        start,
    output reg                         busy,
    output reg                         done,

    // LLR 输入（串行，N 拍，有符号）
    input  wire signed [LLR_WIDTH-1:0] s_axis_tdata,
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire                        s_axis_tlast,

    // 信息位输出（串行，K 拍，不含 CRC）
    output reg                         m_axis_tdata,
    output reg                         m_axis_tvalid,
    input  wire                        m_axis_tready,
    output reg                         m_axis_tlast,

    // 调试输出
    output reg  [L_W-1:0]              best_path,
    output reg  [PM_WIDTH-1:0]         best_pm,
    output reg                         crc_pass
);

    //==========================================================================
    // 可靠性序列 Q_N（从 .vh 文件加载）
    //==========================================================================
    `include "q_n_64.vh"

    //==========================================================================
    // 状态定义
    //==========================================================================
    localparam S_IDLE     = 3'd0;
    localparam S_LOAD     = 3'd1;
    localparam S_FORWARD  = 3'd2;
    localparam S_DECISION = 3'd3;
    localparam S_SPLIT    = 3'd4;
    localparam S_BACKWARD = 3'd5;
    localparam S_CRC      = 3'd6;
    localparam S_OUTPUT   = 3'd7;

    reg [2:0] state;

    //==========================================================================
    // 路径存储：L 条路径
    //==========================================================================
    reg signed [LLR_WIDTH-1:0] alpha [0:L-1][0:LOG2N][0:N-1];
    reg                        u_hat [0:L-1][0:N-1];
    reg signed [PM_WIDTH-1:0]  pm [0:L-1];

    //==========================================================================
    // f/g 函数
    //==========================================================================
    function signed [LLR_WIDTH-1:0] f_func;
        input signed [LLR_WIDTH-1:0] a, b;
        reg sign_a, sign_b, sign_out;
        reg signed [LLR_WIDTH:0] abs_a, abs_b, abs_min;
        reg signed [LLR_WIDTH-1:0] result;
        begin
            sign_a = a[LLR_WIDTH-1];
            sign_b = b[LLR_WIDTH-1];
            abs_a = sign_a ? -$signed(a) : $signed(a);
            abs_b = sign_b ? -$signed(b) : $signed(b);
            abs_min = (abs_a < abs_b) ? abs_a : abs_b;
            sign_out = sign_a ^ sign_b;
            if (abs_min > {1'b0, {LLR_WIDTH-1{1'b1}}})
                abs_min = {1'b0, {LLR_WIDTH-1{1'b1}}};
            result = abs_min[LLR_WIDTH-1:0];
            f_func = sign_out ? -result : result;
        end
    endfunction

    function signed [LLR_WIDTH-1:0] g_func;
        input signed [LLR_WIDTH-1:0] a, b;
        input u;
        reg signed [LLR_WIDTH:0] sum;
        begin
            // F=[[1,1],[0,1]]: x0=u0^u1, x1=u1
            // g(a,b,u0): u0=0 -> b+a, u0=1 -> b-a
            sum = u ? (b - a) : (b + a);
            if (sum > $signed({1'b0, {LLR_WIDTH-1{1'b1}}}))
                g_func = {1'b0, {LLR_WIDTH-1{1'b1}}};
            else if (sum < -$signed({1'b0, {LLR_WIDTH-1{1'b1}}}))
                g_func = {1'b1, {LLR_WIDTH-1{1'b0}}};
            else
                g_func = sum[LLR_WIDTH-1:0];
        end
    endfunction

    // PM 增量：max(0, (2u-1)*LLR)
    function signed [PM_WIDTH-1:0] pm_inc;
        input signed [LLR_WIDTH-1:0] llr;
        input u;
        reg signed [PM_WIDTH-1:0] val;
        begin
            val = u ? $signed(llr) : -$signed(llr);
            pm_inc = (val > 0) ? val : 'd0;
        end
    endfunction

    //==========================================================================
    // 内部寄存器
    //==========================================================================
    reg [N_W-1:0]     leaf_idx;
    reg [STAGE_W-1:0] stage;
    reg [N_W-1:0]     load_cnt;
    reg [N_W-1:0]     out_cnt;
    reg [N_W-1:0]     half;
    reg [N_W-1:0]     block_start;
    reg [N_W-1:0]     offset;
    reg [N_W-1:0]     uhat_idx;
    reg               u_partial [0:L-1];  // 部分判决临时变量

    assign s_axis_tready = (state == S_LOAD);

    //==========================================================================
    // 冻结位判断：leaf_idx 在 Q_N[0:N-K_TOTAL-1] 中
    //==========================================================================
    reg is_frozen;
    integer fi;
    always @(*) begin
        is_frozen = 1'b0;
        for (fi = 0; fi < N - K_TOTAL; fi = fi + 1) begin
            if (leaf_idx == Q_N[fi])
                is_frozen = 1'b1;
        end
    end

    //==========================================================================
    // 信息位路径分裂与排序
    //==========================================================================
    // 8 个候选：{path_idx, u_val}，计算 PM
    reg signed [PM_WIDTH-1:0] cand_pm   [0:2*L-1];
    reg [L_W-1:0]             cand_path [0:2*L-1];
    reg                       cand_u    [0:2*L-1];
    reg [2:0]                 sorted_idx [0:L-1];  // 选中的 4 个候选索引

    integer ci, si, ti;
    reg [7:0] selected_mask;  // 位掩码：标记已选中的候选
    always @(*) begin
        selected_mask = 8'd0;
        for (si = 0; si < L; si = si + 1) begin
            // 找第一个未选中的作为初始值
            for (ci = 0; ci < 2*L; ci = ci + 1) begin
                if (!selected_mask[ci]) begin
                    sorted_idx[si] = ci[2:0];
                end
            end
            // 找 PM 最小的未选中的（PM 相等时按索引小的优先，保留 u=0/u=1 多样性）
            for (ci = 0; ci < 2*L; ci = ci + 1) begin
                if (!selected_mask[ci]) begin
                    if (cand_pm[ci] < cand_pm[sorted_idx[si]] ||
                        (cand_pm[ci] == cand_pm[sorted_idx[si]] && ci[2:0] < sorted_idx[si])) begin
                        sorted_idx[si] = ci[2:0];
                    end
                end
            end
            selected_mask[sorted_idx[si]] = 1'b1;
        end
    end

    //==========================================================================
    // CRC 校验
    //==========================================================================
    reg [CRC_LEN-1:0] crc_check [0:L-1];
    integer cpi, cbi, cci;
    reg bit_val, feedback;
    always @(*) begin
        for (cpi = 0; cpi < L; cpi = cpi + 1) begin
            crc_check[cpi] = {CRC_LEN{1'b1}};
            for (cci = 0; cci < K_TOTAL; cci = cci + 1) begin
                bit_val = u_hat[cpi][Q_N[N-K_TOTAL+cci]];
                feedback = crc_check[cpi][CRC_LEN-1] ^ bit_val;
                crc_check[cpi] = {crc_check[cpi][CRC_LEN-2:0], 1'b0};
                if (feedback) begin
                    for (cbi = 0; cbi < CRC_LEN; cbi = cbi + 1) begin
                        if (CRC_POLY[cbi]) crc_check[cpi][cbi] = crc_check[cpi][cbi] ^ 1'b1;
                    end
                end
            end
        end
    end

    //==========================================================================
    // 主状态机
    //==========================================================================
    integer pi, ji;
    reg signed [LLR_WIDTH-1:0] root_llr;

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
            best_path <= 'd0;
            best_pm <= 'd0;
            crc_pass <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= S_LOAD;
                        busy <= 1'b1;
                        load_cnt <= 'd0;
                        for (pi = 0; pi < L; pi = pi + 1)
                            pm[pi] <= 'd0;
                    end
                end

                S_LOAD: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        for (pi = 0; pi < L; pi = pi + 1) begin
                            alpha[pi][0][load_cnt] <= s_axis_tdata;
                            for (ji = 1; ji <= LOG2N; ji = ji + 1)
                                alpha[pi][ji][load_cnt] <= 'd0;
                        end
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
                    if (stage < LOG2N) begin
                        half = N >> (stage + 1);
                        block_start = leaf_idx - (leaf_idx % (N >> stage));
                        // 只在左子树时计算当前块的 f
                        if ((leaf_idx % (N >> stage)) < half) begin
                            for (pi = 0; pi < L; pi = pi + 1) begin
                                for (ji = 0; ji < half; ji = ji + 1) begin
                                    alpha[pi][stage+1][block_start+ji] <= f_func(
                                        alpha[pi][stage][block_start+ji],
                                        alpha[pi][stage][block_start+ji+half]
                                    );
                                end
                            end
                        end
                        stage <= stage + 1'b1;
                    end else begin
                        state <= S_DECISION;
                    end
                end

                S_DECISION: begin
                    if (is_frozen) begin
                        // 冻结位：所有路径强制 0，PM 更新
                        for (pi = 0; pi < L; pi = pi + 1) begin
                            u_hat[pi][leaf_idx] <= 1'b0;
                            pm[pi] <= pm[pi] + pm_inc(alpha[pi][LOG2N][leaf_idx], 1'b0);
                        end
                        stage <= LOG2N - 1;
                        state <= S_BACKWARD;
                    end else begin
                        // 信息位：准备分裂
                        for (pi = 0; pi < L; pi = pi + 1) begin
                            cand_pm[2*pi]   = pm[pi] + pm_inc(alpha[pi][LOG2N][leaf_idx], 1'b0);
                            cand_path[2*pi] = pi[L_W-1:0];
                            cand_u[2*pi]    = 1'b0;
                            cand_pm[2*pi+1]   = pm[pi] + pm_inc(alpha[pi][LOG2N][leaf_idx], 1'b1);
                            cand_path[2*pi+1] = pi[L_W-1:0];
                            cand_u[2*pi+1]    = 1'b1;
                        end
                        state <= S_SPLIT;
                    end
                end

                S_SPLIT: begin
                    // 路径复制：选中的 4 个候选替换原 4 条路径
                    for (pi = 0; pi < L; pi = pi + 1) begin
                        for (ji = 0; ji <= LOG2N; ji = ji + 1) begin
                            for (integer ni = 0; ni < N; ni = ni + 1) begin
                                alpha[pi][ji][ni] <= alpha[cand_path[sorted_idx[pi]]][ji][ni];
                            end
                        end
                        for (ji = 0; ji < N; ji = ji + 1) begin
                            u_hat[pi][ji] <= u_hat[cand_path[sorted_idx[pi]]][ji];
                        end
                        u_hat[pi][leaf_idx] <= cand_u[sorted_idx[pi]];
                        pm[pi] <= cand_pm[sorted_idx[pi]];
                    end
                    stage <= LOG2N - 1;
                    state <= S_BACKWARD;
                end

                S_BACKWARD: begin
                    if (stage < LOG2N) begin
                        half = N >> (stage + 1);
                        block_start = leaf_idx - (leaf_idx % (N >> stage));
                        // 只在左子树最后一个叶子时计算 g（此时左子树判决完整）
                        if (leaf_idx == block_start + half - 1) begin
                            for (offset = 0; offset < half; offset = offset + 1) begin
                                for (pi = 0; pi < L; pi = pi + 1) begin
                                    // 部分判决：u_partial[offset] = XOR of u_hat[block_start+j] where (j & offset)==offset
                                    u_partial[pi] = 1'b0;
                                    for (ji = 0; ji < half; ji = ji + 1) begin
                                        if ((ji & offset) == offset)
                                            u_partial[pi] = u_partial[pi] ^ u_hat[pi][block_start+ji];
                                    end
                                    alpha[pi][stage+1][block_start+half+offset] <= g_func(
                                        alpha[pi][stage][block_start+offset],
                                        alpha[pi][stage][block_start+half+offset],
                                        u_partial[pi]
                                    );
                                end
                            end
                        end

                        if (stage == 0) begin
                            if (leaf_idx == N - 1) begin
                                state <= S_CRC;
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

                S_CRC: begin
                    best_path <= 'd0;
                    best_pm <= pm[0];
                    crc_pass <= (crc_check[0] == 'd0);
                    for (pi = 1; pi < L; pi = pi + 1) begin
                        if (crc_check[pi] == 'd0 && (!crc_pass || pm[pi] < best_pm)) begin
                            best_path <= pi[L_W-1:0];
                            best_pm <= pm[pi];
                            crc_pass <= 1'b1;
                        end
                    end
                    if (!crc_pass) begin
                        for (pi = 1; pi < L; pi = pi + 1) begin
                            if (pm[pi] < best_pm) begin
                                best_path <= pi[L_W-1:0];
                                best_pm <= pm[pi];
                            end
                        end
                    end
                    out_cnt <= 'd0;
                    m_axis_tvalid <= 1'b1;
                    state <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    m_axis_tdata <= u_hat[best_path][Q_N[N-K_TOTAL+out_cnt]];
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
