/*
 * DDS (Direct Digital Synthesis)
 * 直接数字频率合成器：生成正弦/余弦波
 *
 * 架构：
 *   1. 相位累加器：每时钟加 FTW（频率控制字）
 *   2. 相位偏移：累加 phase_offset
 *   3. 相位截断：取高 LUT_ADDR_W 位作为 LUT 地址
 *   4. LUT 查找：完整周期 sin/cos 表（1024 点，16bit）
 *   5. 输出寄存器
 *
 * 频率分辨率：f_out = f_clk * FTW / 2^PHASE_WIDTH
 *
 * 参数：
 *   PHASE_WIDTH  相位累加器位宽（默认 32）
 *   LUT_ADDR_W   LUT 地址位宽（默认 10，即 1024 点）
 *   OUTPUT_WIDTH 输出位宽（默认 16）
 */
module dds #(
    parameter integer PHASE_WIDTH = 32,
    parameter integer LUT_ADDR_W  = 10,
    parameter integer OUTPUT_WIDTH = 16,
    parameter integer LUT_DEPTH   = 1 << LUT_ADDR_W,
    parameter         LUT_FILE    = "dds_sin_cos_lut.mem"
)(
    input  wire                           clk,
    input  wire                           rst_n,

    // 频率控制字：f_out = f_clk * ftw / 2^PHASE_WIDTH
    input  wire [PHASE_WIDTH-1:0]         ftw,
    // 相位偏移（可选，设 0 即可）
    input  wire [PHASE_WIDTH-1:0]         phase_offset,

    // 输出：{cos, sin}，每个 OUTPUT_WIDTH 位
    output wire [2*OUTPUT_WIDTH-1:0]      m_axis_tdata,
    output wire                           m_axis_tvalid
);

    //==========================================================================
    // 相位累加器
    //==========================================================================
    reg [PHASE_WIDTH-1:0] phase_acc;
    reg [PHASE_WIDTH-1:0] phase_total;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 'd0;
        end else begin
            phase_acc <= phase_acc + ftw;
        end
    end

    always @(*) begin
        phase_total = phase_acc + phase_offset;
    end

    //==========================================================================
    // LUT（完整周期 sin/cos）
    //==========================================================================
    reg [2*OUTPUT_WIDTH-1:0] lut [0:LUT_DEPTH-1];

    initial begin
        $readmemh(LUT_FILE, lut);
    end

    // 相位截断：取高 LUT_ADDR_W 位
    wire [LUT_ADDR_W-1:0] lut_addr = phase_total[PHASE_WIDTH-1 -: LUT_ADDR_W];

    //==========================================================================
    // 输出寄存器
    //==========================================================================
    reg [2*OUTPUT_WIDTH-1:0] dout_reg;
    reg valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_reg <= 'd0;
            valid_reg <= 1'b0;
        end else begin
            dout_reg <= lut[lut_addr];
            valid_reg <= 1'b1;
        end
    end

    assign m_axis_tdata = dout_reg;
    assign m_axis_tvalid = valid_reg;

endmodule
