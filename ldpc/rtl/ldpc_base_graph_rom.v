/*
 * LDPC Base Graph ROM (combinational output)
 * 5G NR LDPC 基矩阵只读存储器，组合输出（无寄存器延迟）
 *
 * 每个元素 9 bit：0..383 表示移位量，511 (-1) 表示零矩阵。
 */
module ldpc_base_graph_rom #(
    parameter integer BG          = 1,
    parameter integer ROWS        = 4,
    parameter integer N_B         = (BG == 1) ? 26 : 14,
    parameter integer K_B         = (BG == 1) ? 22 : 10,
    parameter integer M_B         = 4,
    parameter integer SHIFT_W     = 9,
    parameter         MEM_FILE    = "ldpc_bg1.mem"
)(
    input  wire [$clog2(ROWS)-1:0]  row,
    input  wire [$clog2(N_B)-1:0]   col,
    output wire [SHIFT_W-1:0]       shift_out  // 511 = -1 (零矩阵)
);

    localparam DEPTH = ROWS * N_B;
    reg [SHIFT_W-1:0] rom [0:DEPTH-1];

    initial begin
        $readmemh(MEM_FILE, rom);
    end

    assign shift_out = rom[row * N_B + col];

endmodule
