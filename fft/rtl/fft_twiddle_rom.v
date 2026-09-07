/*
 * FFT Twiddle Factor ROM
 * 旋转因子只读存储器
 *
 * 存储 W_N^k = exp(-2πjk/N), k = 0 .. N/2-1
 * 量化为 TWIDDLE_WIDTH 位有符号定点数（Q1.TWIDDLE_WIDTH-1 格式）
 *
 * 资源：推断为分布式 ROM 或 BRAM（取决于深度和综合策略）
 * 深度：N/2，宽度：2*TWIDDLE_WIDTH
 *
 * 注意：使用 initial 块 + $cos/$sin 在综合时计算，Vivado 支持推断 ROM。
 *       若综合工具不支持，可改用 scripts/gen_twiddle.py 生成 .hex 文件
 *       并用 $readmemh 加载。
 */
module fft_twiddle_rom #(
    parameter integer N              = 1024,
    parameter integer TWIDDLE_WIDTH  = 16,
    parameter integer ADDR_WIDTH     = $clog2(N/2)
)(
    input  wire                         clk,
    input  wire [ADDR_WIDTH-1:0]        addr,
    output wire [TWIDDLE_WIDTH-1:0]     twiddle_re,
    output wire [TWIDDLE_WIDTH-1:0]     twiddle_im
);

    localparam DEPTH = N / 2;
    localparam real PI = 3.14159265358979323846;

    reg [2*TWIDDLE_WIDTH-1:0] rom [0:DEPTH-1];

    // 综合时计算旋转因子（Vivado/Quartus 均支持 initial 块推断 ROM）
    integer k;
    real angle;
    real scale;
    initial begin
        scale = (2.0 ** (TWIDDLE_WIDTH - 1)) - 1.0;  // 最大正值，留 1 LSB 余量防溢出
        for (k = 0; k < DEPTH; k = k + 1) begin
            angle = -2.0 * PI * k / N;
            rom[k][TWIDDLE_WIDTH-1:0]               = $rtoi(scale * $cos(angle) + 0.5);
            rom[k][2*TWIDDLE_WIDTH-1:TWIDDLE_WIDTH] = $rtoi(scale * $sin(angle) + 0.5);
        end
    end

    reg [2*TWIDDLE_WIDTH-1:0] dout;

    always @(posedge clk) begin
        dout <= rom[addr];
    end

    assign twiddle_re = dout[TWIDDLE_WIDTH-1:0];
    assign twiddle_im = dout[2*TWIDDLE_WIDTH-1:TWIDDLE_WIDTH];

endmodule
