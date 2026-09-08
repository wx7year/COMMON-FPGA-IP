/*
 * FFT Top - AXI4-Stream Interface, Forward/Inverse Configurable
 * FFT 顶层：AXI4-Stream 接口，正向/反向可配置
 *
 * 接口约定（与项目现有 nr_pdcch_fft_1024 等一致）：
 *   - 输入 s_axis_tdata = {Q[DIN_WIDTH-1:0], I[DIN_WIDTH-1:0]}
 *   - 输出 m_axis_tdata = {Q[DOUT_WIDTH-1:0], I[DOUT_WIDTH-1:0]}
 *   - s_axis_tlast 标记一帧最后一个样点，同时锁存 fwd_inv 配置
 *   - m_axis_tlast 标记输出帧最后一个样点
 *
 * IFFT 实现：IFFT(x) = conj(FFT(conj(x))) / N
 *   - 输入虚部取反 → FFT → 输出虚部取反 → 右移 LOG2_N 位
 *
 * 参数：
 *   N              - FFT 点数（必须是 2 的幂）
 *   DIN_WIDTH      - 输入实部/虚部位宽
 *   DOUT_WIDTH     - 输出实部/虚部位宽（默认 DIN_WIDTH+LOG2_N）
 *   TWIDDLE_WIDTH  - 旋转因子位宽
 */
module fft_top #(
    parameter integer N              = 1024,
    parameter integer LOG2_N         = $clog2(N),
    parameter integer DIN_WIDTH      = 16,
    parameter integer DOUT_WIDTH     = DIN_WIDTH + LOG2_N,
    parameter integer TWIDDLE_WIDTH  = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // 方向配置：1=正向FFT，0=反向IFFT（在 s_axis_tlast 时锁存）
    input  wire                         fwd_inv,

    // AXI4-Stream 从接口（输入）
    input  wire [2*DIN_WIDTH-1:0]       s_axis_tdata,    // {Q, I}
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire                         s_axis_tlast,

    // AXI4-Stream 主接口（输出，自然序）
    output wire [2*DOUT_WIDTH-1:0]      m_axis_tdata,    // {Q, I}
    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire                         m_axis_tlast,

    // 状态
    output wire                         busy,
    output wire                         done
);

    //==========================================================================
    // 方向配置（帧期间保持稳定，与 Xilinx FFT config 通道行为一致）
    //==========================================================================

    //==========================================================================
    // 输入共轭（IFFT 时虚部取反）
    //==========================================================================
    wire [DIN_WIDTH-1:0] din_i = s_axis_tdata[DIN_WIDTH-1:0];
    wire [DIN_WIDTH-1:0] din_q = s_axis_tdata[2*DIN_WIDTH-1:DIN_WIDTH];

    wire [DIN_WIDTH-1:0] core_din_i = din_i;
    wire [DIN_WIDTH-1:0] core_din_q = fwd_inv ? din_q : (~din_q + 1'b1);  // IFFT: Q取反

    //==========================================================================
    // 帧启动逻辑：组合逻辑生成 start，保证第一个数据和 start 同周期到达 core
    //==========================================================================
    wire core_start;
    reg [LOG2_N-1:0] in_cnt;

    assign core_start = (in_cnt == 0) && s_axis_tvalid && s_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_cnt <= 'd0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                if (s_axis_tlast || in_cnt == N-1)
                    in_cnt <= 'd0;
                else
                    in_cnt <= in_cnt + 1'b1;
            end
        end
    end

    //==========================================================================
    // FFT 核心
    //==========================================================================
    wire [DOUT_WIDTH-1:0] core_dout_i;
    wire [DOUT_WIDTH-1:0] core_dout_q;
    wire core_dout_valid;
    wire core_dout_ready;
    wire [LOG2_N-1:0] core_dout_index;

    fft_core #(
        .N(N),
        .LOG2_N(LOG2_N),
        .DIN_WIDTH(DIN_WIDTH),
        .TWIDDLE_WIDTH(TWIDDLE_WIDTH),
        .DOUT_WIDTH(DOUT_WIDTH)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(core_start),
        .busy(busy),
        .done(done),
        .din_re(core_din_i),
        .din_im(core_din_q),
        .din_valid(s_axis_tvalid & s_axis_tready),
        .din_ready(s_axis_tready),
        .dout_re(core_dout_i),
        .dout_im(core_dout_q),
        .dout_valid(core_dout_valid),
        .dout_ready(core_dout_ready),
        .dout_index(core_dout_index)
    );

    assign core_dout_ready = m_axis_tready;

    //==========================================================================
    // 输出共轭 + 除以 N（IFFT 时）
    //==========================================================================
    // IFFT: 输出虚部取反，右移 LOG2_N 位（除以 N）
    wire [DOUT_WIDTH-1:0] out_i;
    wire [DOUT_WIDTH-1:0] out_q;
    wire [DOUT_WIDTH+LOG2_N-1:0] out_i_ext;
    wire [DOUT_WIDTH+LOG2_N-1:0] out_q_ext;

    assign out_i_ext = $signed(core_dout_i);
    assign out_q_ext = fwd_inv ? $signed(core_dout_q) : -$signed(core_dout_q);

    // 除以 N = 右移 LOG2_N
    assign out_i = fwd_inv ? core_dout_i : out_i_ext >>> LOG2_N;
    assign out_q = fwd_inv ? core_dout_q : out_q_ext >>> LOG2_N;

    assign m_axis_tdata  = {out_q, out_i};
    assign m_axis_tvalid = core_dout_valid;
    assign m_axis_tlast  = core_dout_valid && (core_dout_index == N-1);

endmodule
