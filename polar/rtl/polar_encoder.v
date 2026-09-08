/*
 * Polar Encoder - 5G NR
 * 5G NR Polar 编码器
 *
 * 编码流程：
 *   1. 加载 K 个信息位，放置到可靠子信道（当前用连续放置，可替换为 38.212 可靠性序列）
 *   2. 极化变换（N log2(N)/2 个蝶形，全组合逻辑）
 *   3. 串行输出 N 个编码位
 *
 * 极化变换蝶形（F^T=[[1,1],[0,1]]，与译码器 f/g 函数匹配）：
 *   stage s (0..log2N-1):
 *     u = a[i+j], v = a[i+j+2^s]
 *     a[i+j] = u ^ v
 *     a[i+j+2^s] = v
 *
 * 参数：
 *   N     母码长度（32/64/128/256/512/1024）
 *   K     信息位数
 *
 * 注意：真实 5G NR 还需子块交织和速率匹配，当前为核心极化变换版本。
 */
module polar_encoder #(
    parameter integer N        = 64,
    parameter integer K        = 32,
    parameter integer LOG2N    = $clog2(N),
    parameter integer N_W      = $clog2(N+1)
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

    localparam S_IDLE  = 2'd0;
    localparam S_LOAD  = 2'd1;
    localparam S_ENC   = 2'd2;
    localparam S_OUT   = 2'd3;

    reg [1:0] state;
    reg [N_W-1:0] cnt;

    // 输入寄存器（信息位 + 冻结位）
    reg [0:N-1] u_reg;   // 注意：[0:N-1]，索引 0 是第一个输入

    // 极化变换：全组合逻辑，用 generate 实现多级蝶形
    wire [0:N-1] stage_wires [0:LOG2N];
    assign stage_wires[0] = u_reg;

    genvar stage, i, j;
    generate
        for (stage = 0; stage < LOG2N; stage = stage + 1) begin : gen_stage
            localparam integer HALF = 1 << stage;
            localparam integer BLOCK = 1 << (stage + 1);
            for (i = 0; i < N; i = i + BLOCK) begin : gen_block
                for (j = 0; j < HALF; j = j + 1) begin : gen_butterfly
                    // 蝶形：左=a^b, 右=b（与译码器 f/g 函数匹配）
                    assign stage_wires[stage+1][i+j]       = stage_wires[stage][i+j] ^ stage_wires[stage][i+j+HALF];
                    assign stage_wires[stage+1][i+j+HALF]  = stage_wires[stage][i+j+HALF];
                end
            end
        end
    endgenerate

    wire [0:N-1] codeword = stage_wires[LOG2N];

    assign s_axis_tready = (state == S_LOAD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cnt <= 'd0;
            u_reg <= 'd0;
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
                        cnt <= 'd0;
                        u_reg <= 'd0;  // 冻结位初始化为 0
                    end
                end

                S_LOAD: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        // 信息位放在最后 K 个位置（高可靠性区域的简化近似）
                        u_reg[N-K+cnt[N_W-1:0]] <= s_axis_tdata;
                        if (s_axis_tlast || cnt == K - 1) begin
                            state <= S_ENC;
                            cnt <= 'd0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                S_ENC: begin
                    // 极化变换是组合逻辑，这里只需要一拍打拍
                    state <= S_OUT;
                    cnt <= 'd0;
                end

                S_OUT: begin
                    m_axis_tvalid <= 1'b1;
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
