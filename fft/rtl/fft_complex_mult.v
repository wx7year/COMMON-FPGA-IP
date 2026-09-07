/*
 * Complex Multiplier (3-multiply architecture)
 * 复数乘法器：(a+bi) * (c+di) = (ac-bd) + (ad+bc)i
 *
 * 3 乘法公式（节省 1 个 DSP48）：
 *   k1 = c * (a + b)
 *   k2 = a * (d - c)
 *   k3 = b * (c + d)
 *   real = k1 - k3 = ac - bd
 *   imag = k1 + k2 = ad + bc
 *
 * 延迟：3 周期（输入寄存 → 乘法 → 输出寄存）
 * 输出位宽：A_WIDTH + C_WIDTH + 1（全精度，含符号扩展）
 *
 * 资源：3 个实数乘法器（DSP48），比 4 乘法结构省 25% DSP
 */
module fft_complex_mult #(
    parameter integer A_WIDTH = 16,
    parameter integer C_WIDTH = 16
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       en,

    // 输入 A = a + bi
    input  wire [A_WIDTH-1:0]         a_re,
    input  wire [A_WIDTH-1:0]         a_im,

    // 输入 C = c + di（旋转因子）
    input  wire [C_WIDTH-1:0]         c_re,
    input  wire [C_WIDTH-1:0]         c_im,

    // 输出 P = A * C，位宽 A_WIDTH+C_WIDTH+1
    output wire [A_WIDTH+C_WIDTH:0]   p_re,
    output wire [A_WIDTH+C_WIDTH:0]   p_im
);

    localparam SUM_A_W = A_WIDTH + 1;  // a+b 的位宽
    localparam SUM_C_W = C_WIDTH + 1;  // d-c, c+d 的位宽
    localparam PROD_W  = A_WIDTH + C_WIDTH + 1;  // 乘积位宽
    localparam OUT_W   = A_WIDTH + C_WIDTH + 1;  // 输出位宽

    //---- 第 1 级：输入寄存 + 预计算和差 ----
    reg signed [A_WIDTH-1:0]   a_re_r, a_im_r;
    reg signed [C_WIDTH-1:0]   c_re_r, c_im_r;
    reg signed [SUM_A_W-1:0]   a_plus_b;
    reg signed [SUM_C_W-1:0]   d_minus_c;
    reg signed [SUM_C_W-1:0]   c_plus_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_re_r    <= 'd0;
            a_im_r    <= 'd0;
            c_re_r    <= 'd0;
            c_im_r    <= 'd0;
            a_plus_b  <= 'd0;
            d_minus_c <= 'd0;
            c_plus_d  <= 'd0;
        end else if (en) begin
            a_re_r    <= $signed(a_re);
            a_im_r    <= $signed(a_im);
            c_re_r    <= $signed(c_re);
            c_im_r    <= $signed(c_im);
            a_plus_b  <= $signed(a_re) + $signed(a_im);
            d_minus_c <= $signed(c_im) - $signed(c_re);
            c_plus_d  <= $signed(c_re) + $signed(c_im);
        end
    end

    //---- 第 2 级：3 个乘法 ----
    reg signed [PROD_W-1:0] k1;  // c * (a+b)
    reg signed [PROD_W-1:0] k2;  // a * (d-c)
    reg signed [PROD_W-1:0] k3;  // b * (c+d)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k1 <= 'd0;
            k2 <= 'd0;
            k3 <= 'd0;
        end else if (en) begin
            k1 <= c_re_r * a_plus_b;
            k2 <= a_re_r * d_minus_c;
            k3 <= a_im_r * c_plus_d;
        end
    end

    //---- 第 3 级：输出组合 ----
    reg signed [OUT_W-1:0] p_re_r;
    reg signed [OUT_W-1:0] p_im_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_re_r <= 'd0;
            p_im_r <= 'd0;
        end else if (en) begin
            p_re_r <= k1 - k3;
            p_im_r <= k1 + k2;
        end
    end

    assign p_re = p_re_r;
    assign p_im = p_im_r;

endmodule
