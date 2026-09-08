/*
 * FIR Filter - Auto Resource Optimized, Multi-MAC Parallel
 * FIR 滤波器：自动资源优化，多 MAC 并行架构
 *
 * 自动资源优化原理：
 *   根据 CLK_FREQ / SAMPLE_RATE 计算过采样比 OVERSAMPLE，
 *   自动决定需要的乘法器数量 NUM_MULT = ceil(EFF_TAPS / OVERSAMPLE)。
 *   每个乘法器时分复用 TAPS_PER_MULT 个抽头，在输入间隔内完成运算。
 *
 *   例：80MHz 时钟、10MHz 数据率、32抽头对称FIR：
 *     OVERSAMPLE = 8, EFF_TAPS = 16, NUM_MULT = ceil(16/8) = 2
 *     仅需 2 个 DSP48，而非 32 个全展开结构
 *
 * 对称系数优化：
 *   SYMMETRIC=1 时，利用 h[k]=h[N-1-k]，先做 x[n-k]+x[n-(N-1-k)] 预加，
 *   乘法次数减半（EFF_TAPS = ceil(N/2)）。
 *
 * 资源（与 Xilinx FIR Compiler 低吞吐配置对齐）：
 *   - DSP48：NUM_MULT 个（自动计算）
 *   - LUT/FF：控制逻辑 + 移位寄存器
 *   - 无 BRAM（系数用分布式 ROM，抽头数大时可改 BRAM）
 *
 * 延迟：TAPS_PER_MULT + 3（乘法+累加+输出寄存）周期
 */
module fir_top #(
    parameter integer NUM_TAPS      = 32,
    parameter integer DATA_WIDTH    = 16,
    parameter integer COEFF_WIDTH   = 16,
    parameter integer CLK_FREQ      = 80_000_000,
    parameter integer SAMPLE_RATE   = 10_000_000,
    parameter integer SYMMETRIC     = 1,        // 1=对称系数, 0=非对称
    parameter         COEFF_FILE    = "fir_coeff.mem",  // 系数文件（$readmemh）

    // ---- 自动计算参数（不要手动修改） ----
    parameter integer OVERSAMPLE    = (CLK_FREQ / SAMPLE_RATE > 0) ? (CLK_FREQ / SAMPLE_RATE) : 1,
    parameter integer EFF_TAPS      = SYMMETRIC ? ((NUM_TAPS + 1) / 2) : NUM_TAPS,
    parameter integer NUM_MULT      = (EFF_TAPS + OVERSAMPLE - 1) / OVERSAMPLE,  // 至少1
    parameter integer TAPS_PER_MULT = (EFF_TAPS + NUM_MULT - 1) / NUM_MULT,
    parameter integer ACC_WIDTH     = DATA_WIDTH + COEFF_WIDTH + $clog2(TAPS_PER_MULT) + 2,
    parameter integer SUM_WIDTH     = ACC_WIDTH + $clog2(NUM_MULT),
    parameter integer OUT_WIDTH     = DATA_WIDTH + COEFF_WIDTH + $clog2(NUM_TAPS) + 1
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // AXI4-Stream 输入
    input  wire [DATA_WIDTH-1:0]        s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire                         s_axis_tlast,

    // AXI4-Stream 输出
    output wire [OUT_WIDTH-1:0]         m_axis_tdata,
    output reg                          m_axis_tvalid,
    input  wire                         m_axis_tready,
    output reg                          m_axis_tlast,

    // 状态
    output wire                         busy,
    output wire [31:0]                  num_mult_used    // 实际使用的乘法器数量（调试用）
);

    assign num_mult_used = NUM_MULT;
    assign s_axis_tready = ~busy;  // 不忙时可接收

    //==========================================================================
    // 系数 ROM（EFF_TAPS 个系数，对称时只存一半）
    //==========================================================================
    reg signed [COEFF_WIDTH-1:0] coeff_rom [0:EFF_TAPS-1];

    initial begin
        $readmemh(COEFF_FILE, coeff_rom);
    end

    //==========================================================================
    // 输入移位寄存器
    //==========================================================================
    reg signed [DATA_WIDTH-1:0] x_shift [0:NUM_TAPS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1)
                x_shift[i] <= 'd0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            x_shift[0] <= s_axis_tdata;
            for (i = 1; i < NUM_TAPS; i = i + 1)
                x_shift[i] <= x_shift[i-1];
        end
    end

    //==========================================================================
    // 控制状态机
    //==========================================================================
    localparam S_IDLE = 2'd0;
    localparam S_MAC  = 2'd1;
    localparam S_OUT  = 2'd2;

    reg [1:0] state;
    reg [$clog2(TAPS_PER_MULT):0] mac_cnt;  // MAC 周期计数
    reg                       in_tlast_r;   // 锁存输入 tlast

    wire mac_done = (mac_cnt >= TAPS_PER_MULT + 2);  // +2 补偿乘法和累加延迟
    assign busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mac_cnt <= 'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            in_tlast_r <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    if (s_axis_tvalid && s_axis_tready) begin
                        state <= S_MAC;
                        mac_cnt <= 'd0;
                        in_tlast_r <= s_axis_tlast;
                    end
                end

                S_MAC: begin
                    if (mac_done) begin
                        state <= S_OUT;
                    end else begin
                        mac_cnt <= mac_cnt + 1'b1;
                    end
                end

                S_OUT: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= in_tlast_r;
                    if (m_axis_tready && m_axis_tvalid) begin
                        state <= S_IDLE;
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;
                    end
                end
            endcase
        end
    end

    //==========================================================================
    // 多 MAC 通道（generate 自动生成 NUM_MULT 个）
    // 每个通道处理 TAPS_PER_MULT 个连续抽头
    //==========================================================================
    wire signed [ACC_WIDTH-1:0] mac_out [0:NUM_MULT-1];
    wire mac_channel_active = (state == S_MAC) && (mac_cnt < TAPS_PER_MULT);

    genvar m;
    generate
        for (m = 0; m < NUM_MULT; m = m + 1) begin : gen_mac

            // 该通道处理的抽头范围 [m*TAPS_PER_MULT, min((m+1)*TAPS_PER_MULT, EFF_TAPS)-1]
            wire [$clog2(EFF_TAPS)-1:0] tap_idx = m * TAPS_PER_MULT + mac_cnt[$clog2(TAPS_PER_MULT)-1:0];
            wire tap_valid = (tap_idx < EFF_TAPS);

            // 对称预加：x[n-k] + x[n-(N-1-k)]
            // 注意：中间抽头（N奇数，k == N-1-k）不加倍，只取 x[k]
            wire is_middle_tap = (tap_idx == NUM_TAPS - 1 - tap_idx);
            wire [DATA_WIDTH:0] pre_add;
            if (SYMMETRIC) begin : gen_sym
                assign pre_add = is_middle_tap ?
                    $signed(x_shift[tap_idx]) :
                    ($signed(x_shift[tap_idx]) + $signed(x_shift[NUM_TAPS-1-tap_idx]));
            end else begin : gen_nosym
                assign pre_add = $signed(x_shift[tap_idx]);
            end

            // 系数
            wire signed [COEFF_WIDTH-1:0] coeff = coeff_rom[tap_idx];

            // 乘法（1 周期延迟）
            reg signed [DATA_WIDTH+COEFF_WIDTH:0] prod_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    prod_r <= 'd0;
                else if (mac_channel_active && tap_valid)
                    prod_r <= $signed(pre_add) * coeff;
                else
                    prod_r <= 'd0;  // 非活跃时清零，防止残留被多累加
            end

            // 累加（S_MAC 全程累加，补偿 prod_r 1 拍延迟）
            reg signed [ACC_WIDTH-1:0] acc_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    acc_r <= 'd0;
                end else if (state == S_IDLE) begin
                    acc_r <= 'd0;
                end else if (state == S_MAC) begin
                    acc_r <= acc_r + prod_r;
                end
            end

            assign mac_out[m] = acc_r;
        end
    endgenerate

    //==========================================================================
    // 多通道求和（组合逻辑，输出寄存）
    //==========================================================================
    reg signed [SUM_WIDTH-1:0] sum_r;
    integer s;

    always @(*) begin
        sum_r = 'd0;
        for (s = 0; s < NUM_MULT; s = s + 1)
            sum_r = sum_r + mac_out[s];
    end

    // 输出直接取 SUM_WIDTH 位（与 OUT_WIDTH 相同）
    assign m_axis_tdata = sum_r;

endmodule
