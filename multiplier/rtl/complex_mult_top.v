/*
 * Complex Multiplier - 3-multiply / 4-multiply Configurable
 * 复数乘法器：(a+bi) * (c+di) = (ac-bd) + (ad+bc)i
 *
 * 两种架构：
 *   USE_3_MULT=1: 3 乘法公式（省 1 个 DSP48，延迟 3 周期）
 *     k1 = c*(a+b), k2 = a*(d-c), k3 = b*(c+d)
 *     real = k1-k3, imag = k1+k2
 *   USE_3_MULT=0: 4 乘法公式（延迟 2 周期，多用 1 个 DSP）
 *     real = ac-bd, imag = ad+bc
 *
 * 参数：
 *   A_WIDTH - 被乘数位宽 (a+bi)
 *   C_WIDTH - 乘数位宽 (c+di)
 *   USE_3_MULT - 1=3乘法(省资源), 0=4乘法(低延迟)
 */
module complex_mult_top #(
    parameter integer A_WIDTH    = 16,
    parameter integer C_WIDTH    = 16,
    parameter integer USE_3_MULT = 1,
    parameter integer OUT_WIDTH  = A_WIDTH + C_WIDTH + 1
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        en,

    input  wire signed [A_WIDTH-1:0]   a_re,
    input  wire signed [A_WIDTH-1:0]   a_im,
    input  wire signed [C_WIDTH-1:0]   c_re,
    input  wire signed [C_WIDTH-1:0]   c_im,

    output wire signed [OUT_WIDTH-1:0] p_re,
    output wire signed [OUT_WIDTH-1:0] p_im
);

    generate
        if (USE_3_MULT) begin : gen_3mult
            //---- 第1级：预计算 ----
            localparam SUM_A_W = A_WIDTH + 1;
            localparam SUM_C_W = C_WIDTH + 1;
            reg signed [A_WIDTH-1:0] a_re_r, a_im_r;
            reg signed [C_WIDTH-1:0] c_re_r, c_im_r;
            reg signed [SUM_A_W-1:0] a_plus_b;
            reg signed [SUM_C_W-1:0] d_minus_c;
            reg signed [SUM_C_W-1:0] c_plus_d;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_re_r <= 'd0; a_im_r <= 'd0;
                    c_re_r <= 'd0; c_im_r <= 'd0;
                    a_plus_b <= 'd0; d_minus_c <= 'd0; c_plus_d <= 'd0;
                end else if (en) begin
                    a_re_r <= a_re; a_im_r <= a_im;
                    c_re_r <= c_re; c_im_r <= c_im;
                    a_plus_b  <= a_re + a_im;
                    d_minus_c <= c_im - c_re;
                    c_plus_d  <= c_re + c_im;
                end
            end

            //---- 第2级：3个乘法 ----
            localparam PROD_W = A_WIDTH + C_WIDTH + 1;
            reg signed [PROD_W-1:0] k1, k2, k3;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    k1 <= 'd0; k2 <= 'd0; k3 <= 'd0;
                end else if (en) begin
                    k1 <= c_re_r * a_plus_b;
                    k2 <= a_re_r * d_minus_c;
                    k3 <= a_im_r * c_plus_d;
                end
            end

            //---- 第3级：输出组合 ----
            reg signed [OUT_WIDTH-1:0] p_re_r, p_im_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    p_re_r <= 'd0; p_im_r <= 'd0;
                end else if (en) begin
                    p_re_r <= k1 - k3;
                    p_im_r <= k1 + k2;
                end
            end
            assign p_re = p_re_r;
            assign p_im = p_im_r;

        end else begin : gen_4mult
            //---- 第1级：输入寄存 ----
            reg signed [A_WIDTH-1:0] a_re_r, a_im_r;
            reg signed [C_WIDTH-1:0] c_re_r, c_im_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_re_r <= 'd0; a_im_r <= 'd0;
                    c_re_r <= 'd0; c_im_r <= 'd0;
                end else if (en) begin
                    a_re_r <= a_re; a_im_r <= a_im;
                    c_re_r <= c_re; c_im_r <= c_im;
                end
            end

            //---- 第2级：4个乘法 + 加减 ----
            localparam PROD_W = A_WIDTH + C_WIDTH;
            reg signed [OUT_WIDTH-1:0] p_re_r, p_im_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    p_re_r <= 'd0; p_im_r <= 'd0;
                end else if (en) begin
                    p_re_r <= (a_re_r * c_re_r) - (a_im_r * c_im_r);
                    p_im_r <= (a_re_r * c_im_r) + (a_im_r * c_re_r);
                end
            end
            assign p_re = p_re_r;
            assign p_im = p_im_r;
        end
    endgenerate

endmodule
