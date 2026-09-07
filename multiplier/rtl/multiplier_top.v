/*
 * General Multiplier - Pipelined Signed Multiplier
 * 通用有符号乘法器，可配置流水线级数
 *
 * 参数：
 *   A_WIDTH      - 被乘数位宽
 *   B_WIDTH      - 乘数位宽
 *   PIPE_STAGES  - 流水线级数 (0=组合逻辑, 1=输入寄存, 2=输入+输出寄存)
 *
 * 资源：1 个 DSP48（当位宽适合时），或 LUT 乘法
 * 延迟：PIPE_STAGES 周期
 */
module multiplier_top #(
    parameter integer A_WIDTH     = 16,
    parameter integer B_WIDTH     = 16,
    parameter integer PIPE_STAGES = 2,
    parameter integer P_WIDTH     = A_WIDTH + B_WIDTH
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      en,

    input  wire signed [A_WIDTH-1:0] a,
    input  wire signed [B_WIDTH-1:0] b,

    output wire signed [P_WIDTH-1:0] p
);

    generate
        if (PIPE_STAGES == 0) begin : gen_comb
            assign p = a * b;
        end else if (PIPE_STAGES == 1) begin : gen_input_reg
            reg signed [A_WIDTH-1:0] a_r;
            reg signed [B_WIDTH-1:0] b_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_r <= 'd0;
                    b_r <= 'd0;
                end else if (en) begin
                    a_r <= a;
                    b_r <= b;
                end
            end
            assign p = a_r * b_r;
        end else begin : gen_full_pipe  // PIPE_STAGES >= 2
            reg signed [A_WIDTH-1:0] a_r;
            reg signed [B_WIDTH-1:0] b_r;
            reg signed [P_WIDTH-1:0] p_r;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_r <= 'd0;
                    b_r <= 'd0;
                    p_r <= 'd0;
                end else if (en) begin
                    a_r <= a;
                    b_r <= b;
                    p_r <= a_r * b_r;
                end
            end
            assign p = p_r;
        end
    endgenerate

endmodule
