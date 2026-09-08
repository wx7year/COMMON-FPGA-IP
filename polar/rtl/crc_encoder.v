/*
 * CRC Encoder - Parameterizable
 * 参数化 CRC 编码器
 *
 * 支持 CRC16 (CRC-CCITT: x^16+x^12+x^5+1) 和 CRC24A (5G NR)
 *   CRC16  polynomial = 16'h1021
 *   CRC24A polynomial = 24'h800063
 *
 * 5G NR Polar CRC:
 *   - 初始值全 1
 *   - 输出直接为寄存器值（不取反）
 *   - CRC 位附加在信息位之后，一起进行 Polar 编码
 *
 * 用法：start 拉高1拍复位，然后逐拍输入 data_in（data_valid=1），
 *       最后一位时 data_last=1，下一拍 crc_valid=1，crc_out 有效。
 */
module crc_encoder #(
    parameter integer CRC_WIDTH  = 16,
    parameter [CRC_WIDTH-1:0] POLYNOMIAL = 16'h1021,
    parameter integer INIT_VALUE = {CRC_WIDTH{1'b1}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,       // 开始新 CRC（复位寄存器）
    input  wire             data_in,     // 串行数据输入
    input  wire             data_valid,  // 输入有效
    input  wire             data_last,   // 最后一位输入
    output wire [CRC_WIDTH-1:0] crc_out, // CRC 结果
    output reg              crc_valid    // CRC 结果有效脉冲
);

    reg [CRC_WIDTH-1:0] crc_reg;

    // LFSR 迭代
    wire feedback = crc_reg[CRC_WIDTH-1] ^ data_in;
    wire [CRC_WIDTH-1:0] crc_next;

    genvar i;
    generate
        for (i = 0; i < CRC_WIDTH; i = i + 1) begin : gen_lfsr
            if (i == 0) begin : gen_bit0
                assign crc_next[i] = feedback;
            end else begin : gen_bitn
                assign crc_next[i] = POLYNOMIAL[i] ?
                    (crc_reg[i-1] ^ feedback) : crc_reg[i-1];
            end
        end
    endgenerate

    assign crc_out = crc_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= INIT_VALUE[CRC_WIDTH-1:0];
            crc_valid <= 1'b0;
        end else begin
            crc_valid <= 1'b0;
            if (start) begin
                crc_reg <= INIT_VALUE[CRC_WIDTH-1:0];
            end else if (data_valid) begin
                crc_reg <= crc_next;
                if (data_last)
                    crc_valid <= 1'b1;  // 下一拍结果有效
            end
        end
    end

endmodule
