// ============================================================================
// 直接型 FIR 滤波器 (全并行)
//
// 结构:
//   - 输入移位寄存器链 (N_TAPS 级)
//   - 每个抽头 x[n-k] * h[k]
//   - 加法树求和
//
// 系数通过扁平化 parameter COEFFS 传入:
//   COEFFS = {h[N_TAPS-1], h[N_TAPS-2], ..., h[1], h[0]}
//   每个系数 COEFF_WIDTH bit, 有符号
//
// 输出: y[n] = sum_{k=0}^{N_TAPS-1} h[k] * x[n-k]
//
// 参数:
//   N_TAPS      - 抽头数
//   DATA_WIDTH  - 输入数据位宽 (有符号)
//   COEFF_WIDTH - 系数位宽 (有符号)
//   OUT_WIDTH   - 输出位宽 (有符号, 截断/饱和)
//   COEFFS      - 系数数组 (扁平化)
//   SYMMETRIC   - 1=对称系数优化 (h[k]=h[N-1-k], 减少一半乘法器)
// ============================================================================
module fir_direct #(
    parameter integer N_TAPS      = 31,
    parameter integer DATA_WIDTH  = 16,
    parameter integer COEFF_WIDTH = 16,
    parameter integer OUT_WIDTH   = 16,
    parameter [N_TAPS*COEFF_WIDTH-1:0] COEFFS = {N_TAPS*COEFF_WIDTH{1'b0}},
    parameter integer SYMMETRIC   = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // 输入
    input  wire signed [DATA_WIDTH-1:0]  din,
    input  wire                          din_valid,

    // 输出
    output wire signed [OUT_WIDTH-1:0]   dout,
    output wire                          dout_valid
);

    // ------------------------------------------------------------------
    // 输入移位寄存器链
    // ------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] delay_line [0:N_TAPS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_TAPS; i = i + 1)
                delay_line[i] <= 'd0;
        end else if (din_valid) begin
            delay_line[0] <= din;
            for (i = 1; i < N_TAPS; i = i + 1)
                delay_line[i] <= delay_line[i-1];
        end
    end

    // ------------------------------------------------------------------
    // 系数提取
    // ------------------------------------------------------------------
    wire signed [COEFF_WIDTH-1:0] coeff [0:N_TAPS-1];
    genvar g;
    generate
        for (g = 0; g < N_TAPS; g = g + 1) begin : gen_coeff
            assign coeff[g] = COEFFS[g*COEFF_WIDTH +: COEFF_WIDTH];
        end
    endgenerate

    // ------------------------------------------------------------------
    // 乘法 + 加法
    // ------------------------------------------------------------------
    localparam MUL_WIDTH = DATA_WIDTH + COEFF_WIDTH;
    localparam SUM_WIDTH = MUL_WIDTH + $clog2(N_TAPS);  // 加法树完整位宽

    reg signed [SUM_WIDTH-1:0] accum;

    generate
        if (SYMMETRIC) begin : gen_symmetric
            // 对称系数优化: 先加 x[n-k] + x[n-(N-1-k)], 再乘 h[k]
            localparam PAIR_WIDTH = DATA_WIDTH + 1;
            localparam integer HALF_TAPS = (N_TAPS + 1) / 2;

            wire signed [PAIR_WIDTH-1:0] pair_sum [0:HALF_TAPS-1];
            wire signed [MUL_WIDTH:0] product [0:HALF_TAPS-1];

            for (g = 0; g < HALF_TAPS; g = g + 1) begin : gen_pairs
                if (g == N_TAPS - 1 - g) begin
                    // 中间抽头 (奇数抽头时)
                    assign pair_sum[g] = delay_line[g];
                end else begin
                    assign pair_sum[g] = delay_line[g] + delay_line[N_TAPS-1-g];
                end
                assign product[g] = pair_sum[g] * coeff[g];
            end

            // 加法树
            integer j;
            always @(*) begin
                accum = 'd0;
                for (j = 0; j < HALF_TAPS; j = j + 1)
                    accum = accum + product[j];
            end
        end else begin : gen_non_symmetric
            // 非对称: 直接乘加
            wire signed [MUL_WIDTH-1:0] product [0:N_TAPS-1];
            for (g = 0; g < N_TAPS; g = g + 1) begin : gen_mul
                assign product[g] = delay_line[g] * coeff[g];
            end

            integer j;
            always @(*) begin
                accum = 'd0;
                for (j = 0; j < N_TAPS; j = j + 1)
                    accum = accum + product[j];
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // 输出截断 + 饱和
    // 乘法结果是 Q(DATA_WIDTH-1 + COEFF_WIDTH-1)
    // 右移 (COEFF_WIDTH-1) 位回到 Q(DATA_WIDTH-1)
    // ------------------------------------------------------------------
    localparam SHIFT_BITS = COEFF_WIDTH - 1;
    wire signed [SUM_WIDTH-1:0] accum_shifted = accum >>> SHIFT_BITS;

    function signed [OUT_WIDTH-1:0] saturate;
        input signed [SUM_WIDTH-1:0] val;
        begin
            if (val > $signed({{(SUM_WIDTH-OUT_WIDTH+1){1'b0}}, {(OUT_WIDTH-1){1'b1}}}))
                saturate = {1'b0, {(OUT_WIDTH-1){1'b1}}};
            else if (val < $signed({{(SUM_WIDTH-OUT_WIDTH+1){1'b1}}, {(OUT_WIDTH-1){1'b0}}}))
                saturate = {1'b1, {(OUT_WIDTH-1){1'b0}}};
            else
                saturate = val[OUT_WIDTH-1:0];
        end
    endfunction

    // 输出寄存器 (延迟 1 拍, 因为移位寄存器是时序的, 乘加是组合的)
    reg signed [OUT_WIDTH-1:0] dout_r;
    reg                        dout_valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_r       <= 'd0;
            dout_valid_r <= 1'b0;
        end else begin
            dout_r       <= saturate(accum_shifted);
            dout_valid_r <= din_valid;
        end
    end

    assign dout       = dout_r;
    assign dout_valid = dout_valid_r;

endmodule
