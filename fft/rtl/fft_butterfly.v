/*
 * FFT Radix-2 Butterfly Unit
 * 蝶形运算单元：A' = A + B*W,  B' = A - B*W
 *
 * 延迟：1 周期
 * 位宽：输入 DATA_WIDTH，输出 DATA_WIDTH+1（加法增长 1bit）
 *
 * 资源：2 个复数加/减法器（4 个实加/减），无乘法器
 */
module fft_butterfly #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,

    // 输入 A（上支路）
    input  wire [DATA_WIDTH-1:0]    a_re,
    input  wire [DATA_WIDTH-1:0]    a_im,

    // 输入 B*W（下支路，已乘完旋转因子）
    input  wire [DATA_WIDTH-1:0]    bw_re,
    input  wire [DATA_WIDTH-1:0]    bw_im,

    // 输出 A' = A + B*W
    output reg  [DATA_WIDTH:0]      y1_re,
    output reg  [DATA_WIDTH:0]      y1_im,

    // 输出 B' = A - B*W
    output reg  [DATA_WIDTH:0]      y2_re,
    output reg  [DATA_WIDTH:0]      y2_im
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y1_re <= 'd0;
            y1_im <= 'd0;
            y2_re <= 'd0;
            y2_im <= 'd0;
        end else if (en) begin
            // A' = A + B*W
            y1_re <= $signed(a_re) + $signed(bw_re);
            y1_im <= $signed(a_im) + $signed(bw_im);
            // B' = A - B*W
            y2_re <= $signed(a_re) - $signed(bw_re);
            y2_im <= $signed(a_im) - $signed(bw_im);
        end
    end

endmodule
