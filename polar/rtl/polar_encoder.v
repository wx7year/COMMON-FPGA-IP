/*
 * Polar Encoder - 5G NR with Q_N reliability sequence + CRC
 * 5G NR Polar 编码器：真实可靠性序列 Q_N + CRC 校验
 *
 * 编码流程：
 *   1. 加载 K 个信息位，同时计算 CRC
 *   2. 附加 CRC_LEN 位校验位，共 K_total = K + CRC_LEN 个信息位
 *   3. 按 Q_N 可靠性序列放置：信息位放在最可靠的 K_total 个子信道
 *   4. 极化变换（全组合逻辑）
 *   5. 串行输出 N 个编码位
 *
 * 参数：
 *   N          母码长度
 *   K          信息位数（不含 CRC）
 *   CRC_LEN    CRC 校验位数（0=无CRC）
 *   CRC_POLY   CRC 多项式
 */
module polar_encoder #(
    parameter integer N          = 64,
    parameter integer K          = 32,
    parameter integer CRC_LEN    = 16,
    parameter [CRC_LEN-1:0] CRC_POLY = 16'h1021,
    parameter integer LOG2N      = $clog2(N),
    parameter integer N_W        = $clog2(N+1),
    parameter integer K_TOTAL    = K + CRC_LEN
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               start,
    output reg                busy,
    output reg                done,

    // 信息位输入（串行，K 拍）
    input  wire               s_axis_tdata,
    input  wire               s_axis_tvalid,
    output wire               s_axis_tready,
    input  wire               s_axis_tlast,

    // 编码输出（串行，N 拍）
    output reg                m_axis_tdata,
    output reg                m_axis_tvalid,
    input  wire               m_axis_tready,
    output reg                m_axis_tlast
);

    //==========================================================================
    // Q_N 可靠性序列（从 q_n_{N}.vh 加载）
    // Q_N[0] = 最不可靠, Q_N[N-1] = 最可靠
    //==========================================================================
    `include "q_n_64.vh"  // 定义 localparam [LOG2N-1:0] Q_N [0:N-1]

    //==========================================================================
    // CRC 编码器
    //==========================================================================
    wire [CRC_LEN-1:0] crc_result;
    wire               crc_valid;
    reg                crc_start;
    reg                crc_data_in;
    reg                crc_data_valid;
    reg                crc_data_last;

    generate
        if (CRC_LEN > 0) begin : gen_crc
            crc_encoder #(
                .CRC_WIDTH(CRC_LEN),
                .POLYNOMIAL(CRC_POLY)
            ) u_crc (
                .clk(clk), .rst_n(rst_n),
                .start(crc_start),
                .data_in(crc_data_in),
                .data_valid(crc_data_valid),
                .data_last(crc_data_last),
                .crc_out(crc_result),
                .crc_valid(crc_valid)
            );
        end else begin : gen_no_crc
            assign crc_result = 'd0;
            assign crc_valid = 1'b1;
        end
    endgenerate

    //==========================================================================
    // 状态机
    //==========================================================================
    localparam S_IDLE      = 3'd0;
    localparam S_LOAD_INFO = 3'd1;
    localparam S_LOAD_CRC  = 3'd2;
    localparam S_PLACE     = 3'd3;
    localparam S_ENC       = 3'd4;
    localparam S_OUT       = 3'd5;

    reg [2:0] state;
    reg [N_W-1:0] cnt;
    reg [N_W-1:0] crc_bit_cnt;

    // 输入寄存器（信息位 + 冻结位）
    reg [0:N-1] u_reg;

    // 信息位暂存（用于放置到 Q_N 位置）
    reg [0:K_TOTAL-1] info_bits;

    //==========================================================================
    // 极化变换：全组合逻辑
    //==========================================================================
    wire [0:N-1] stage_wires [0:LOG2N];
    assign stage_wires[0] = u_reg;

    genvar stage, i, j;
    generate
        for (stage = 0; stage < LOG2N; stage = stage + 1) begin : gen_stage
            localparam integer HALF = 1 << stage;
            localparam integer BLOCK = 1 << (stage + 1);
            for (i = 0; i < N; i = i + BLOCK) begin : gen_block
                for (j = 0; j < HALF; j = j + 1) begin : gen_butterfly
                    // 标准 F=[[1,1],[0,1]]: left=left^right, right unchanged
                    assign stage_wires[stage+1][i+j]       = stage_wires[stage][i+j] ^ stage_wires[stage][i+j+HALF];
                    assign stage_wires[stage+1][i+j+HALF]  = stage_wires[stage][i+j+HALF];
                end
            end
        end
    endgenerate

    wire [0:N-1] codeword = stage_wires[LOG2N];

    assign s_axis_tready = (state == S_LOAD_INFO);

    //==========================================================================
    // 主状态机
    //==========================================================================
    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cnt <= 'd0;
            crc_bit_cnt <= 'd0;
            u_reg <= 'd0;
            info_bits <= 'd0;
            m_axis_tdata <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            crc_start <= 1'b0;
            crc_data_in <= 1'b0;
            crc_data_valid <= 1'b0;
            crc_data_last <= 1'b0;
        end else begin
            done <= 1'b0;
            crc_start <= 1'b0;
            crc_data_valid <= 1'b0;
            crc_data_last <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    if (start) begin
                        state <= S_LOAD_INFO;
                        busy <= 1'b1;
                        cnt <= 'd0;
                        u_reg <= 'd0;
                        info_bits <= 'd0;
                        crc_start <= 1'b1;
                    end
                end

                S_LOAD_INFO: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        info_bits[cnt[N_W-1:0]] <= s_axis_tdata;
                        crc_data_in <= s_axis_tdata;
                        crc_data_valid <= 1'b1;
                        if (s_axis_tlast || cnt == K - 1) begin
                            crc_data_last <= 1'b1;
                            if (CRC_LEN > 0)
                                state <= S_LOAD_CRC;
                            else
                                state <= S_PLACE;
                            cnt <= 'd0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                S_LOAD_CRC: begin
                    // 等待 CRC 计算完成，然后将 CRC 位加入 info_bits
                    if (crc_valid) begin
                        // CRC 位放在信息位之后
                        for (pi = 0; pi < CRC_LEN; pi = pi + 1)
                            info_bits[K + pi] <= crc_result[CRC_LEN-1-pi];
                        state <= S_PLACE;
                    end
                end

                S_PLACE: begin
                    // 按 Q_N 可靠性序列放置信息位
                    // 信息位放在 Q_N[N-K_total + i] 位置
                    u_reg[Q_N[N-K_TOTAL+cnt[N_W-1:0]]] <= info_bits[cnt[N_W-1:0]];
                    if (cnt == K_TOTAL - 1) begin
                        state <= S_ENC;
                        cnt <= 'd0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_ENC: begin
                    // 极化变换是组合逻辑，一拍缓冲，提前设置 valid
                    state <= S_OUT;
                    cnt <= 'd0;
                    m_axis_tvalid <= 1'b1;
                end

                S_OUT: begin
                    m_axis_tdata <= codeword[cnt[N_W-1:0]];
                    m_axis_tlast <= (cnt == N - 1);
                    if (m_axis_tready) begin
                        if (cnt == N - 1) begin
                            state <= S_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                            m_axis_tvalid <= 1'b0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
