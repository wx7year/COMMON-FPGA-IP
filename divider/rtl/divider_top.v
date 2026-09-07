/*
 * Integer Divider - Restoring Division, Signed
 * 整数除法器：恢复余数法，有符号
 *
 * 算法：恢复余数除法
 *   1. 取绝对值
 *   2. 对每一位（从高位到低位）：余数左移1位 → 减除数 → 非负则商位=1，否则恢复
 *   3. WIDTH 周期完成
 *   4. 调整商和余数的符号
 *
 * 延迟：WIDTH + 2 周期
 * 资源：1 个加法器/减法器 + 寄存器，无乘法器
 *
 * 注意：除数为 0 时输出未定义（可扩展除零检测）
 */
module divider_top #(
    parameter integer WIDTH = 16,
    parameter integer CNT_W = $clog2(WIDTH)
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    start,
    output reg                     busy,
    output reg                     done,

    input  wire signed [WIDTH-1:0] dividend,   // 被除数 a
    input  wire signed [WIDTH-1:0] divisor,    // 除数 b

    output reg signed [WIDTH-1:0]  quotient,   // 商 q = a / b
    output reg signed [WIDTH-1:0]  remainder   // 余数 r = a % b（符号与被除数相同）
);

    //==========================================================================
    // 状态机
    //==========================================================================
    localparam S_IDLE = 2'd0;
    localparam S_CALC = 2'd1;
    localparam S_SIGN = 2'd2;

    reg [1:0] state;
    reg [CNT_W-1:0] bit_cnt;

    // 绝对值
    reg [WIDTH-1:0] a_abs;
    reg [WIDTH-1:0] b_abs;
    reg             q_sign;   // 商符号：1=负
    reg             r_sign;   // 余数符号：1=负（与被除数相同）

    // 除法寄存器
    reg [WIDTH-1:0] rem_reg;  // 余数
    reg [WIDTH-1:0] quo_reg;  // 商

    // 中间运算
    wire [WIDTH:0]   rem_shifted = {rem_reg, quo_reg[WIDTH-1]};  // 左移1位
    wire [WIDTH:0]   rem_sub     = rem_shifted - {1'b0, b_abs};
    wire             rem_neg     = rem_sub[WIDTH];  // 1=负数

    //==========================================================================
    // 主控制
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            bit_cnt   <= 'd0;
            a_abs     <= 'd0;
            b_abs     <= 'd0;
            q_sign    <= 1'b0;
            r_sign    <= 1'b0;
            rem_reg   <= 'd0;
            quo_reg   <= 'd0;
            quotient  <= 'd0;
            remainder <= 'd0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        state   <= S_CALC;
                        busy    <= 1'b1;
                        bit_cnt <= WIDTH[CNT_W-1:0] - 1'b1;

                        // 取绝对值
                        a_abs <= dividend[WIDTH-1] ? -dividend : dividend;
                        b_abs <= divisor[WIDTH-1]  ? -divisor  : divisor;

                        // 符号：商 = 异或，余数 = 被除数符号
                        q_sign <= dividend[WIDTH-1] ^ divisor[WIDTH-1];
                        r_sign <= dividend[WIDTH-1];

                        rem_reg <= 'd0;
                        quo_reg <= dividend[WIDTH-1] ? -dividend : dividend;
                    end
                end

                S_CALC: begin
                    if (rem_neg) begin
                        // 余数为负，恢复，商位=0
                        rem_reg <= rem_sub[WIDTH-1:0] + b_abs;
                        quo_reg <= {quo_reg[WIDTH-2:0], 1'b0};
                    end else begin
                        // 余数非负，商位=1
                        rem_reg <= rem_sub[WIDTH-1:0];
                        quo_reg <= {quo_reg[WIDTH-2:0], 1'b1};
                    end

                    if (bit_cnt == 0) begin
                        state <= S_SIGN;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                S_SIGN: begin
                    // 调整商的符号
                    quotient  <= q_sign ? -quo_reg : quo_reg;
                    // 调整余数的符号（与被除数相同）
                    remainder <= r_sign ? -rem_reg : rem_reg;
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
