/*
 * Cyclic Shifter for QC-LDPC
 * 准循环 LDPC 循环移位器：对 ZC bit 向量做循环右移
 *
 * 5G NR LDPC 基矩阵中每个非零元素表示 ZC×ZC 循环移位矩阵，
 * 移位量为该元素的值（0..ZC-1），-1 表示零矩阵。
 *
 * 循环右移 shift 位：din = [b_{ZC-1}, b_{ZC-2}, ..., b_0]
 *   dout = [b_{shift-1}, ..., b_0, b_{ZC-1}, ..., b_shift]
 *
 * 资源：纯组合逻辑（MUX 树），无寄存器
 */
module ldpc_cyclic_shift #(
    parameter integer ZC        = 4,
    parameter integer SHIFT_W   = $clog2(ZC)
)(
    input  wire [ZC-1:0]      din,
    input  wire [SHIFT_W-1:0]  shift,
    output wire [ZC-1:0]      dout
);
    // 循环右移：{din, din} >> (ZC - shift)，取低 ZC 位
    wire [2*ZC-1:0] doubled = {din, din};
    assign dout = doubled >> (ZC - shift);

endmodule
