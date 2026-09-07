/*
 * CORDIC - COordinate Rotation DIgital Computer
 * 迭代式 CORDIC，旋转/向量双模式
 *
 * 功能：
 *   旋转模式 (mode=0):  (x,y,z) → (x*cos(z)-y*sin(z), x*sin(z)+y*cos(z), 0)
 *                        用于 sin/cos 计算（输入 x=1.0, y=0, z=angle，开启增益预补偿）
 *   向量模式 (mode=1):  (x,y,z) → (sqrt(x²+y²)/K, 0, z+atan2(y,x))
 *                        用于 atan2 和 magnitude 计算（不做增益预补偿）
 *
 * 架构：迭代式（时分复用），1 个运算单元，ITERATIONS 周期完成
 * 资源：~2 个加法器 + 1 个角度 ROM，无乘法器
 *
 * 角度格式：Q2.(ANGLE_WIDTH-2)，范围 [-2, 2) rad
 * 数据格式：有符号整数，内部位宽 = DATA_WIDTH + 4（防止迭代溢出）
 *
 * 增益预补偿：
 *   CORDIC 固有增益 K = Π 1/cos(atan(2^-i)) ≈ 1.6468
 *   旋转模式下，输入 x 预乘 1/K≈0.60725（移位加法），输出即真实值
 *   向量模式下不预补偿，输出 magnitude = √(x²+y²) / K
 */
module cordic_top #(
    parameter integer DATA_WIDTH   = 16,
    parameter integer ANGLE_WIDTH  = 16,   // Q2.14
    parameter integer ITERATIONS   = 16,
    parameter integer INTERNAL_WIDTH = DATA_WIDTH + 4,  // 内部加宽防溢出
    parameter integer CNT_WIDTH    = $clog2(ITERATIONS)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // 控制
    input  wire                         start,
    output reg                          busy,
    output reg                          done,

    // 模式：0=旋转, 1=向量
    input  wire                         mode,

    // 输入
    input  wire signed [DATA_WIDTH-1:0]  x_in,
    input  wire signed [DATA_WIDTH-1:0]  y_in,
    input  wire signed [ANGLE_WIDTH-1:0] z_in,

    // 输出
    output reg signed [DATA_WIDTH-1:0]   x_out,
    output reg signed [DATA_WIDTH-1:0]   y_out,
    output reg signed [ANGLE_WIDTH-1:0]  z_out
);

    //==========================================================================
    // 角度查找表 atan(2^-i)，Q2.14 格式
    //==========================================================================
    reg signed [ANGLE_WIDTH-1:0] atan_table [0:ITERATIONS-1];
    real angle_real;
    integer i;

    initial begin
        for (i = 0; i < ITERATIONS; i = i + 1) begin
            angle_real = $atan(1.0 / (1 << i));
            atan_table[i] = $rtoi(angle_real * (2.0 ** (ANGLE_WIDTH - 2)) + 0.5);
        end
    end

    //==========================================================================
    // 状态机
    //==========================================================================
    localparam S_IDLE = 2'd0;
    localparam S_ITER = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state;
    reg [CNT_WIDTH-1:0] iter_cnt;

    // 迭代寄存器（内部加宽）
    reg signed [INTERNAL_WIDTH-1:0]  x_reg, y_reg;
    reg signed [ANGLE_WIDTH-1:0]     z_reg;

    //==========================================================================
    // 增益预补偿 1/K ≈ 0.60725（仅旋转模式）
    // 1/K = 2^-1 + 2^-4 + 2^-5 + 2^-7 + 2^-8 + 2^-10 + 2^-11 + 2^-12
    //==========================================================================
    wire signed [INTERNAL_WIDTH-1:0] x_ext = $signed(x_in);
    wire signed [INTERNAL_WIDTH-1:0] y_ext = $signed(y_in);
    wire signed [INTERNAL_WIDTH-1:0] x_compensated;

    assign x_compensated =
        (x_ext >>> 1) + (x_ext >>> 4) + (x_ext >>> 5) +
        (x_ext >>> 7) + (x_ext >>> 8) + (x_ext >>> 10) +
        (x_ext >>> 11) + (x_ext >>> 12);

    // 旋转模式用预补偿 x，向量模式用原始 x
    wire signed [INTERNAL_WIDTH-1:0] x_start = mode ? x_ext : x_compensated;

    //==========================================================================
    // 迭代运算（组合逻辑）
    //==========================================================================
    wire signed [INTERNAL_WIDTH-1:0] x_shifted = x_reg >>> iter_cnt;
    wire signed [INTERNAL_WIDTH-1:0] y_shifted = y_reg >>> iter_cnt;
    wire signed [ANGLE_WIDTH-1:0]    atan_val  = atan_table[iter_cnt];

    // d = mode ? -sign(y) : sign(z)
    // sign(y)=y[MSB], -sign(y) = ~y[MSB]
    // sign(z)=z[MSB]
    wire d = mode ? ~y_reg[INTERNAL_WIDTH-1] : z_reg[ANGLE_WIDTH-1];

    wire signed [INTERNAL_WIDTH-1:0] x_next = d ? (x_reg + y_shifted) : (x_reg - y_shifted);
    wire signed [INTERNAL_WIDTH-1:0] y_next = d ? (y_reg - x_shifted) : (y_reg + x_shifted);
    wire signed [ANGLE_WIDTH-1:0]    z_next = d ? (z_reg + atan_val)  : (z_reg - atan_val);

    //==========================================================================
    // 输出饱和/截断
    //==========================================================================
    wire signed [DATA_WIDTH-1:0] x_out_sat, y_out_sat;
    assign x_out_sat = (x_reg > $signed({{(INTERNAL_WIDTH-DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}})) ?
                       {1'b0, {(DATA_WIDTH-1){1'b1}}} :
                       (x_reg < -$signed({{(INTERNAL_WIDTH-DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}})) ?
                       {1'b1, {(DATA_WIDTH-1){1'b0}}} :
                       x_reg[DATA_WIDTH-1:0];
    assign y_out_sat = (y_reg > $signed({{(INTERNAL_WIDTH-DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}})) ?
                       {1'b0, {(DATA_WIDTH-1){1'b1}}} :
                       (y_reg < -$signed({{(INTERNAL_WIDTH-DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}})) ?
                       {1'b1, {(DATA_WIDTH-1){1'b0}}} :
                       y_reg[DATA_WIDTH-1:0];

    //==========================================================================
    // 主控制
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            iter_cnt <= 'd0;
            x_reg    <= 'd0;
            y_reg    <= 'd0;
            z_reg    <= 'd0;
            x_out    <= 'd0;
            y_out    <= 'd0;
            z_out    <= 'd0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        state    <= S_ITER;
                        busy     <= 1'b1;
                        iter_cnt <= 'd0;
                        x_reg    <= x_start;
                        y_reg    <= y_ext;
                        z_reg    <= z_in;
                    end
                end

                S_ITER: begin
                    x_reg <= x_next;
                    y_reg <= y_next;
                    z_reg <= z_next;

                    if (iter_cnt == ITERATIONS - 1) begin
                        state <= S_DONE;
                    end else begin
                        iter_cnt <= iter_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    x_out <= x_out_sat;
                    y_out <= y_out_sat;
                    z_out <= z_reg;
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
