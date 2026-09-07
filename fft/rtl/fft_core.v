/*
 * FFT Core - Radix-2 DIT, Ping-pong RAM, Single Butterfly Pipelined
 * FFT 核心：基2 按时间抽取，乒乓RAM，单蝶形流水线
 *
 * 架构（资源最小化，对齐 Xilinx FFT Radix-2 Lite）：
 *   - 1 个蝶形单元 + 1 个复数乘法器（3乘法结构，省1个DSP）
 *   - 2 块双口 RAM（乒乓，深度 N，原位运算交替读写）
 *   - 1 块旋转因子 ROM（深度 N/2）
 *   - 6 级流水线，每周期发起 1 个蝶形
 *
 * 吞吐：
 *   - 每帧处理周期 = N*log2(N)/2 + PIPE_DEPTH + N(load) + N(unload)
 *   - N=1024: ≈5120+6+1024+1024 = 7174 周期
 *   - 80MHz 时钟下 ≈90us，支持最高约 11MHz 连续帧输入（1024点/帧）
 *   - 若需更高吞吐，可扩展多蝶形并行版本
 *
 * 定点格式：
 *   - 旋转因子 Q1.(TWIDDLE_WIDTH-1)
 *   - 每级乘法后右移 (TWIDDLE_WIDTH-1)，蝶形后位宽增长 1bit
 *   - 内部全精度位宽 = DIN_WIDTH + LOG2_N
 *
 * 乒乓机制：
 *   - 偶数级(stage 0,2,4..)：读 bank0，写 bank1
 *   - 奇数级(stage 1,3,5..)：读 bank1，写 bank0
 *   - 源 bank 和目标 bank 不同，读和写完全并行无冲突
 */
module fft_core #(
    parameter integer N              = 1024,
    parameter integer LOG2_N         = $clog2(N),
    parameter integer DIN_WIDTH      = 16,
    parameter integer TWIDDLE_WIDTH  = 16,
    parameter integer DOUT_WIDTH     = DIN_WIDTH + LOG2_N,
    parameter integer INTERN_WIDTH   = DIN_WIDTH + LOG2_N,
    parameter integer ADDR_WIDTH     = LOG2_N,
    parameter integer TW_ADDR_WIDTH  = LOG2_N - 1,
    parameter integer PIPE_DEPTH     = 5   // 发起蝶形到写回的周期数
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // 控制
    input  wire                         start,
    output reg                          busy,
    output reg                          done,

    // 输入
    input  wire [DIN_WIDTH-1:0]         din_re,
    input  wire [DIN_WIDTH-1:0]         din_im,
    input  wire                         din_valid,
    output wire                         din_ready,

    // 输出（自然序）
    output wire [DOUT_WIDTH-1:0]        dout_re,
    output wire [DOUT_WIDTH-1:0]        dout_im,
    output reg                          dout_valid,
    input  wire                         dout_ready,
    output wire [ADDR_WIDTH-1:0]        dout_index
);

    //==========================================================================
    // 状态机
    //==========================================================================
    localparam S_IDLE    = 2'd0;
    localparam S_LOAD    = 2'd1;
    localparam S_PROC    = 2'd2;
    localparam S_UNLOAD  = 2'd3;

    reg [1:0] state;

    //==========================================================================
    // 乒乓双口 RAM：bank0 和 bank1
    // 每个 bank 是双口 RAM，口A对应 addr_a，口B对应 addr_b
    //==========================================================================
    reg [2*INTERN_WIDTH-1:0] ram0 [0:N-1];
    reg [2*INTERN_WIDTH-1:0] ram1 [0:N-1];

    // bank0 口A
    reg [ADDR_WIDTH-1:0]      addr_a0;
    reg                       we_a0;
    reg [2*INTERN_WIDTH-1:0]  wdata_a0;
    reg [2*INTERN_WIDTH-1:0]  rdata_a0;

    // bank0 口B
    reg [ADDR_WIDTH-1:0]      addr_b0;
    reg                       we_b0;
    reg [2*INTERN_WIDTH-1:0]  wdata_b0;
    reg [2*INTERN_WIDTH-1:0]  rdata_b0;

    // bank1 口A
    reg [ADDR_WIDTH-1:0]      addr_a1;
    reg                       we_a1;
    reg [2*INTERN_WIDTH-1:0]  wdata_a1;
    reg [2*INTERN_WIDTH-1:0]  rdata_a1;

    // bank1 口B
    reg [ADDR_WIDTH-1:0]      addr_b1;
    reg                       we_b1;
    reg [2*INTERN_WIDTH-1:0]  wdata_b1;
    reg [2*INTERN_WIDTH-1:0]  rdata_b1;

    always @(posedge clk) begin
        if (we_a0) ram0[addr_a0] <= wdata_a0;
        rdata_a0 <= ram0[addr_a0];
        if (we_b0) ram0[addr_b0] <= wdata_b0;
        rdata_b0 <= ram0[addr_b0];
        if (we_a1) ram1[addr_a1] <= wdata_a1;
        rdata_a1 <= ram1[addr_a1];
        if (we_b1) ram1[addr_b1] <= wdata_b1;
        rdata_b1 <= ram1[addr_b1];
    end

    //==========================================================================
    // 旋转因子 ROM
    //==========================================================================
    reg [TW_ADDR_WIDTH-1:0] tw_addr;
    wire [TWIDDLE_WIDTH-1:0] tw_re, tw_im;

    fft_twiddle_rom #(
        .N(N), .TWIDDLE_WIDTH(TWIDDLE_WIDTH), .ADDR_WIDTH(TW_ADDR_WIDTH)
    ) u_tw_rom (
        .clk(clk), .addr(tw_addr), .twiddle_re(tw_re), .twiddle_im(tw_im)
    );

    //==========================================================================
    // 复数乘法器 B * W（3 周期延迟）
    //==========================================================================
    reg [INTERN_WIDTH-1:0] b_re_s1, b_im_s1;
    wire [INTERN_WIDTH+TWIDDLE_WIDTH:0] mult_p_re, mult_p_im;

    fft_complex_mult #(
        .A_WIDTH(INTERN_WIDTH), .C_WIDTH(TWIDDLE_WIDTH)
    ) u_cmult (
        .clk(clk), .rst_n(rst_n), .en(1'b1),
        .a_re(b_re_s1), .a_im(b_im_s1),
        .c_re(tw_re), .c_im(tw_im),
        .p_re(mult_p_re), .p_im(mult_p_im)
    );

    //==========================================================================
    // 右移去旋转因子增益 + 蝶形（1 周期延迟）
    //==========================================================================
    localparam SHIFTED_W = INTERN_WIDTH + 2;
    wire [SHIFTED_W-1:0] bw_re = mult_p_re >>> (TWIDDLE_WIDTH - 1);
    wire [SHIFTED_W-1:0] bw_im = mult_p_im >>> (TWIDDLE_WIDTH - 1);

    // A 延迟到蝶形输入（S1→乘法3周期→蝶形，共延迟4周期）
    reg [INTERN_WIDTH-1:0] a_re_d [0:3];
    reg [INTERN_WIDTH-1:0] a_im_d [0:3];
    wire [INTERN_WIDTH-1:0] a_re_butter = a_re_d[3];
    wire [INTERN_WIDTH-1:0] a_im_butter = a_im_d[3];

    wire [INTERN_WIDTH:0] y1_re, y1_im, y2_re, y2_im;

    fft_butterfly #(
        .DATA_WIDTH(SHIFTED_W)
    ) u_butterfly (
        .clk(clk), .rst_n(rst_n), .en(1'b1),
        .a_re({{(SHIFTED_W-INTERN_WIDTH){a_re_butter[INTERN_WIDTH-1]}}, a_re_butter}),
        .a_im({{(SHIFTED_W-INTERN_WIDTH){a_im_butter[INTERN_WIDTH-1]}}, a_im_butter}),
        .bw_re(bw_re), .bw_im(bw_im),
        .y1_re(y1_re), .y1_im(y1_im),
        .y2_re(y2_re), .y2_im(y2_im)
    );

    // 蝶形输出截断到 INTERN_WIDTH
    wire [INTERN_WIDTH-1:0] y1_re_t = y1_re[INTERN_WIDTH-1:0];
    wire [INTERN_WIDTH-1:0] y1_im_t = y1_im[INTERN_WIDTH-1:0];
    wire [INTERN_WIDTH-1:0] y2_re_t = y2_re[INTERN_WIDTH-1:0];
    wire [INTERN_WIDTH-1:0] y2_im_t = y2_im[INTERN_WIDTH-1:0];

    //==========================================================================
    // 流水线：地址 + stage奇偶（决定写回哪个bank）
    //==========================================================================
    reg [ADDR_WIDTH-1:0] addr_a_pipe [0:PIPE_DEPTH-1];
    reg [ADDR_WIDTH-1:0] addr_b_pipe [0:PIPE_DEPTH-1];
    reg                  wb_bank_pipe [0:PIPE_DEPTH-1];  // 写回目标bank
    reg                  pipe_v [0:PIPE_DEPTH-1];

    //==========================================================================
    // PROC 计数器和地址生成
    //==========================================================================
    reg [LOG2_N-1:0]   stage_cnt;
    reg [LOG2_N-1:0]   butterfly_cnt;
    reg [3:0]          drain_cnt;

    wire [LOG2_N-1:0]  span       = 1 << stage_cnt;
    wire [LOG2_N-1:0]  pos        = butterfly_cnt & (span - 1);
    wire [LOG2_N-1:0]  group      = butterfly_cnt >> stage_cnt;
    wire [ADDR_WIDTH-1:0] calc_addr_a = (group << (stage_cnt + 1)) | pos;
    wire [ADDR_WIDTH-1:0] calc_addr_b = calc_addr_a | span;
    wire [TW_ADDR_WIDTH-1:0] calc_tw_addr = pos << (LOG2_N - 1 - stage_cnt);

    // 源 bank（读）= stage_cnt[0]，目标 bank（写）= ~stage_cnt[0]
    wire src_bank = stage_cnt[0];

    //==========================================================================
    // LOAD / UNLOAD 计数器
    //==========================================================================
    reg [ADDR_WIDTH-1:0] load_cnt;
    reg [ADDR_WIDTH-1:0] unload_cnt;

    // 最后一级的目标 bank = UNLOAD 时读的 bank
    // stage = LOG2_N-1，目标 bank = ~(LOG2_N-1)[0]
    localparam LAST_STAGE = LOG2_N - 1;
    localparam UNLOAD_BANK = ~LAST_STAGE[0];  // 0=bank0, 1=bank1

    function [ADDR_WIDTH-1:0] bit_reverse;
        input [ADDR_WIDTH-1:0] x;
        integer j;
        begin
            for (j = 0; j < ADDR_WIDTH; j = j + 1)
                bit_reverse[j] = x[ADDR_WIDTH-1-j];
        end
    endfunction

    assign din_ready  = (state == S_LOAD);
    assign dout_index = unload_cnt;

    // UNLOAD 读数据选择
    wire [2*INTERN_WIDTH-1:0] unload_data = UNLOAD_BANK ? rdata_a1 : rdata_a0;
    assign dout_re = unload_data[INTERN_WIDTH-1 -: DOUT_WIDTH];
    assign dout_im = unload_data[2*INTERN_WIDTH-1 -: DOUT_WIDTH];

    //==========================================================================
    // 主控制 + RAM 地址 + 写使能（全部时序逻辑，避免多驱动）
    //==========================================================================
    integer p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            load_cnt      <= 'd0;
            unload_cnt    <= 'd0;
            stage_cnt     <= 'd0;
            butterfly_cnt <= 'd0;
            drain_cnt     <= 'd0;
            dout_valid    <= 1'b0;

            we_a0 <= 1'b0; we_b0 <= 1'b0;
            we_a1 <= 1'b0; we_b1 <= 1'b0;
            addr_a0 <= 'd0; addr_b0 <= 'd0;
            addr_a1 <= 'd0; addr_b1 <= 'd0;

            b_re_s1 <= 'd0; b_im_s1 <= 'd0;
            for (p = 0; p < 4; p = p + 1) begin
                a_re_d[p] <= 'd0; a_im_d[p] <= 'd0;
            end
            for (p = 0; p < PIPE_DEPTH; p = p + 1) begin
                addr_a_pipe[p] <= 'd0;
                addr_b_pipe[p] <= 'd0;
                wb_bank_pipe[p] <= 1'b0;
                pipe_v[p] <= 1'b0;
            end
        end else begin
            done <= 1'b0;

            //---- 默认关闭写使能 ----
            we_a0 <= 1'b0; we_b0 <= 1'b0;
            we_a1 <= 1'b0; we_b1 <= 1'b0;

            //---- 流水线推进（每周期） ----
            // A 延迟链
            a_re_d[0] <= (state == S_PROC && butterfly_cnt < N/2) ?
                            (src_bank ? rdata_a1[INTERN_WIDTH-1:0] : rdata_a0[INTERN_WIDTH-1:0]) : 'd0;
            a_im_d[0] <= (state == S_PROC && butterfly_cnt < N/2) ?
                            (src_bank ? rdata_a1[2*INTERN_WIDTH-1:INTERN_WIDTH] : rdata_a0[2*INTERN_WIDTH-1:INTERN_WIDTH]) : 'd0;
            for (p = 1; p < 4; p = p + 1) begin
                a_re_d[p] <= a_re_d[p-1];
                a_im_d[p] <= a_im_d[p-1];
            end

            // B 寄存到乘法器输入
            b_re_s1 <= (state == S_PROC && butterfly_cnt < N/2) ?
                         (src_bank ? rdata_b1[INTERN_WIDTH-1:0] : rdata_b0[INTERN_WIDTH-1:0]) : 'd0;
            b_im_s1 <= (state == S_PROC && butterfly_cnt < N/2) ?
                         (src_bank ? rdata_b1[2*INTERN_WIDTH-1:INTERN_WIDTH] : rdata_b0[2*INTERN_WIDTH-1:INTERN_WIDTH]) : 'd0;

            // 地址流水线
            addr_a_pipe[0] <= calc_addr_a;
            addr_b_pipe[0] <= calc_addr_b;
            wb_bank_pipe[0] <= ~src_bank;  // 目标 bank
            pipe_v[0] <= (state == S_PROC && butterfly_cnt < N/2);
            for (p = 1; p < PIPE_DEPTH; p = p + 1) begin
                addr_a_pipe[p] <= addr_a_pipe[p-1];
                addr_b_pipe[p] <= addr_b_pipe[p-1];
                wb_bank_pipe[p] <= wb_bank_pipe[p-1];
                pipe_v[p] <= pipe_v[p-1];
            end

            //---- 写回（流水线末端） ----
            if (pipe_v[PIPE_DEPTH-1]) begin
                if (wb_bank_pipe[PIPE_DEPTH-1] == 1'b0) begin
                    we_a0 <= 1'b1;
                    addr_a0 <= addr_a_pipe[PIPE_DEPTH-1];
                    wdata_a0 <= {y1_im_t, y1_re_t};
                    we_b0 <= 1'b1;
                    addr_b0 <= addr_b_pipe[PIPE_DEPTH-1];
                    wdata_b0 <= {y2_im_t, y2_re_t};
                end else begin
                    we_a1 <= 1'b1;
                    addr_a1 <= addr_a_pipe[PIPE_DEPTH-1];
                    wdata_a1 <= {y1_im_t, y1_re_t};
                    we_b1 <= 1'b1;
                    addr_b1 <= addr_b_pipe[PIPE_DEPTH-1];
                    wdata_b1 <= {y2_im_t, y2_re_t};
                end
            end

            //---- 状态机 ----
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        state <= S_LOAD;
                        busy <= 1'b1;
                        load_cnt <= 'd0;
                    end
                end

                S_LOAD: begin
                    // 加载到 bank0（初始源 bank）
                    if (din_valid) begin
                        we_a0 <= 1'b1;
                        addr_a0 <= load_cnt;
                        wdata_a0 <= {
                            {(INTERN_WIDTH-DIN_WIDTH){din_im[DIN_WIDTH-1]}}, din_im,
                            {(INTERN_WIDTH-DIN_WIDTH){din_re[DIN_WIDTH-1]}}, din_re
                        };
                        if (load_cnt == N-1) begin
                            state <= S_PROC;
                            stage_cnt <= 'd0;
                            butterfly_cnt <= 'd0;
                            drain_cnt <= 'd0;
                        end else begin
                            load_cnt <= load_cnt + 1'b1;
                        end
                    end
                end

                S_PROC: begin
                    if (butterfly_cnt < N/2) begin
                        // 发起一个蝶形：设置源 bank 读地址 + 旋转因子
                        if (src_bank == 1'b0) begin
                            addr_a0 <= calc_addr_a;
                            addr_b0 <= calc_addr_b;
                        end else begin
                            addr_a1 <= calc_addr_a;
                            addr_b1 <= calc_addr_b;
                        end
                        tw_addr <= calc_tw_addr;

                        // 推进计数
                        if (butterfly_cnt == N/2 - 1) begin
                            butterfly_cnt <= 'd0;
                            if (stage_cnt == LOG2_N - 1) begin
                                drain_cnt <= PIPE_DEPTH + 1;  // 等流水线排空
                            end else begin
                                stage_cnt <= stage_cnt + 1'b1;
                            end
                        end else begin
                            butterfly_cnt <= butterfly_cnt + 1'b1;
                        end
                    end else if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1'b1;
                        if (drain_cnt == 1) begin
                            state <= S_UNLOAD;
                            unload_cnt <= 'd0;
                        end
                    end
                end

                S_UNLOAD: begin
                    // 按位反序地址读 UNLOAD_BANK 的口A
                    if (UNLOAD_BANK == 1'b0)
                        addr_a0 <= bit_reverse(unload_cnt);
                    else
                        addr_a1 <= bit_reverse(unload_cnt);

                    dout_valid <= 1'b1;
                    if (dout_ready) begin
                        if (unload_cnt == N-1) begin
                            state <= S_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                            dout_valid <= 1'b0;
                        end else begin
                            unload_cnt <= unload_cnt + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
