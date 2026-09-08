/*
 * FFT Core - Radix-2 DIT, Ping-pong RAM, Single Butterfly Pipelined
 * 清晰版：地址生成 → RAM读(异步) → 输入寄存(1拍) → 复数乘法(3拍) → 蝶形(1拍) → 写回
 * 总流水线延迟 = 1(输入寄存) + 3(乘法) + 1(蝶形) = 5 拍
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
    parameter integer PIPE_DEPTH     = 6   // 流水线级数，写回在 pipe_v[5]
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    output reg                          busy,
    output reg                          done,
    input  wire [DIN_WIDTH-1:0]         din_re,
    input  wire [DIN_WIDTH-1:0]         din_im,
    input  wire                         din_valid,
    output wire                         din_ready,
    output wire [DOUT_WIDTH-1:0]        dout_re,
    output wire [DOUT_WIDTH-1:0]        dout_im,
    output reg                          dout_valid,
    input  wire                         dout_ready,
    output wire [ADDR_WIDTH-1:0]        dout_index
);

    localparam S_IDLE   = 2'd0;
    localparam S_LOAD   = 2'd1;
    localparam S_PROC   = 2'd2;
    localparam S_UNLOAD = 2'd3;

    reg [1:0] state;

    //==========================================================================
    // 乒乓 RAM（同步写，异步读）
    //==========================================================================
    reg [2*INTERN_WIDTH-1:0] ram0 [0:N-1];
    reg [2*INTERN_WIDTH-1:0] ram1 [0:N-1];

    reg [ADDR_WIDTH-1:0]      addr_a0, addr_b0, addr_a1, addr_b1;
    reg                       we_a0, we_b0, we_a1, we_b1;
    reg [2*INTERN_WIDTH-1:0]  wdata_a0, wdata_b0, wdata_a1, wdata_b1;
    wire [2*INTERN_WIDTH-1:0] rdata_a0 = ram0[addr_a0];
    wire [2*INTERN_WIDTH-1:0] rdata_b0 = ram0[addr_b0];
    wire [2*INTERN_WIDTH-1:0] rdata_a1 = ram1[addr_a1];
    wire [2*INTERN_WIDTH-1:0] rdata_b1 = ram1[addr_b1];

    always @(posedge clk) begin
        if (we_a0) ram0[addr_a0] <= wdata_a0;
        if (we_b0) ram0[addr_b0] <= wdata_b0;
        if (we_a1) ram1[addr_a1] <= wdata_a1;
        if (we_b1) ram1[addr_b1] <= wdata_b1;
    end

    //==========================================================================
    // 旋转因子 ROM（异步读）
    //==========================================================================
    reg [TW_ADDR_WIDTH-1:0] tw_addr;
    wire [TWIDDLE_WIDTH-1:0] tw_re, tw_im;

    fft_twiddle_rom #(.N(N), .TWIDDLE_WIDTH(TWIDDLE_WIDTH), .ADDR_WIDTH(TW_ADDR_WIDTH)) u_tw_rom (
        .clk(clk), .addr(tw_addr), .twiddle_re(tw_re), .twiddle_im(tw_im)
    );

    //==========================================================================
    // 流水线第1级：输入寄存（RAM 读数据打一拍）
    //==========================================================================
    reg signed [INTERN_WIDTH-1:0] a_re_s1, a_im_s1, b_re_s1, b_im_s1;
    reg signed [TWIDDLE_WIDTH-1:0] tw_re_s1, tw_im_s1;  // 和 b_re_s1 同周期采样
    reg [ADDR_WIDTH-1:0] addr_a_pipe [0:PIPE_DEPTH-1];
    reg [ADDR_WIDTH-1:0] addr_b_pipe [0:PIPE_DEPTH-1];
    reg                  wb_bank_pipe [0:PIPE_DEPTH-1];
    reg                  pipe_v [0:PIPE_DEPTH-1];

    //==========================================================================
    // 流水线第2-4级：复数乘法器（3拍）
    //==========================================================================
    wire [INTERN_WIDTH+TWIDDLE_WIDTH:0] mult_p_re, mult_p_im;

    fft_complex_mult #(.A_WIDTH(INTERN_WIDTH), .C_WIDTH(TWIDDLE_WIDTH)) u_cmult (
        .clk(clk), .rst_n(rst_n), .en(1'b1),
        .a_re(b_re_s1), .a_im(b_im_s1),
        .c_re(tw_re_s1), .c_im(tw_im_s1),
        .p_re(mult_p_re), .p_im(mult_p_im)
    );

    //==========================================================================
    // 流水线第5级：右移去增益 + 蝶形（1拍）
    //==========================================================================
    localparam SHIFTED_W = INTERN_WIDTH + 2;
    wire [SHIFTED_W-1:0] bw_re = ($signed(mult_p_re) + (1 << (TWIDDLE_WIDTH-2))) >>> (TWIDDLE_WIDTH - 1);
    wire [SHIFTED_W-1:0] bw_im = ($signed(mult_p_im) + (1 << (TWIDDLE_WIDTH-2))) >>> (TWIDDLE_WIDTH - 1);

    // a 路径：RAM异步读晚1拍 + s1(1) + a_re_d 3级 = 5拍到a_butter
    // b 路径：RAM异步读晚1拍 + s1(1) + 乘法3 = 5拍输出bw
    // 两者在第5拍对齐，蝶形第5拍采样，第6拍输出写回
    reg signed [INTERN_WIDTH-1:0] a_re_d [0:2];
    reg signed [INTERN_WIDTH-1:0] a_im_d [0:2];
    wire signed [INTERN_WIDTH-1:0] a_re_butter = a_re_d[2];
    wire signed [INTERN_WIDTH-1:0] a_im_butter = a_im_d[2];

    wire [INTERN_WIDTH:0] y1_re, y1_im, y2_re, y2_im;

    fft_butterfly #(.DATA_WIDTH(SHIFTED_W)) u_butterfly (
        .clk(clk), .rst_n(rst_n), .en(1'b1),
        .a_re({{(SHIFTED_W-INTERN_WIDTH){a_re_butter[INTERN_WIDTH-1]}}, a_re_butter}),
        .a_im({{(SHIFTED_W-INTERN_WIDTH){a_im_butter[INTERN_WIDTH-1]}}, a_im_butter}),
        .bw_re(bw_re), .bw_im(bw_im),
        .y1_re(y1_re), .y1_im(y1_im),
        .y2_re(y2_re), .y2_im(y2_im)
    );

    wire [INTERN_WIDTH-1:0] y1_re_t = y1_re[INTERN_WIDTH-1:0];
    wire [INTERN_WIDTH-1:0] y1_im_t = y1_im[INTERN_WIDTH-1:0];
    wire [INTERN_WIDTH-1:0] y2_re_t = y2_re[INTERN_WIDTH-1:0];
    wire [INTERN_WIDTH-1:0] y2_im_t = y2_im[INTERN_WIDTH-1:0];

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
    wire src_bank = stage_cnt[0];

    //==========================================================================
    // LOAD / UNLOAD 计数器
    //==========================================================================
    reg [ADDR_WIDTH-1:0] load_cnt;
    reg [ADDR_WIDTH-1:0] unload_cnt;

    localparam LAST_STAGE = LOG2_N - 1;
    localparam UNLOAD_BANK = ~LAST_STAGE[0];

    function [ADDR_WIDTH-1:0] bit_reverse;
        input [ADDR_WIDTH-1:0] x;
        integer j;
        begin
            for (j = 0; j < ADDR_WIDTH; j = j + 1)
                bit_reverse[j] = x[ADDR_WIDTH-1-j];
        end
    endfunction

    assign din_ready  = (state == S_LOAD) || (state == S_IDLE);
    assign dout_index = unload_cnt;
    wire [2*INTERN_WIDTH-1:0] unload_data = UNLOAD_BANK ? rdata_a1 : rdata_a0;
    assign dout_re = unload_data[INTERN_WIDTH-1 -: DOUT_WIDTH];
    assign dout_im = unload_data[2*INTERN_WIDTH-1 -: DOUT_WIDTH];

    //==========================================================================
    // 主控制
    //==========================================================================
    integer p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 0; done <= 0;
            load_cnt <= 0; unload_cnt <= 0;
            stage_cnt <= 0; butterfly_cnt <= 0; drain_cnt <= 0;
            dout_valid <= 0;
            we_a0 <= 0; we_b0 <= 0; we_a1 <= 0; we_b1 <= 0;
            addr_a0 <= 0; addr_b0 <= 0; addr_a1 <= 0; addr_b1 <= 0;
            a_re_s1 <= 0; a_im_s1 <= 0; b_re_s1 <= 0; b_im_s1 <= 0; tw_re_s1 <= 0; tw_im_s1 <= 0;
            for (p = 0; p < 3; p = p + 1) begin a_re_d[p] <= 0; a_im_d[p] <= 0; end
            for (p = 0; p < PIPE_DEPTH; p = p + 1) begin
                addr_a_pipe[p] <= 0; addr_b_pipe[p] <= 0;
                wb_bank_pipe[p] <= 0; pipe_v[p] <= 0;
            end
        end else begin
            done <= 0;
            we_a0 <= 0; we_b0 <= 0; we_a1 <= 0; we_b1 <= 0;

            //---- 流水线推进 ----
            // 第1级：输入寄存（用 pipe_v[0] 使能，地址已设置一个周期，数据有效）
            if (pipe_v[0]) begin
                a_re_s1 <= src_bank ? rdata_a1[INTERN_WIDTH-1:0] : rdata_a0[INTERN_WIDTH-1:0];
                a_im_s1 <= src_bank ? rdata_a1[2*INTERN_WIDTH-1:INTERN_WIDTH] : rdata_a0[2*INTERN_WIDTH-1:INTERN_WIDTH];
                b_re_s1 <= src_bank ? rdata_b1[INTERN_WIDTH-1:0] : rdata_b0[INTERN_WIDTH-1:0];
                b_im_s1 <= src_bank ? rdata_b1[2*INTERN_WIDTH-1:INTERN_WIDTH] : rdata_b0[2*INTERN_WIDTH-1:INTERN_WIDTH];
                tw_re_s1 <= tw_re;
                tw_im_s1 <= tw_im;
            end else begin
                a_re_s1 <= 0; a_im_s1 <= 0; b_re_s1 <= 0; b_im_s1 <= 0;
                tw_re_s1 <= 0; tw_im_s1 <= 0;
            end

            // a 延迟链（3级：和 bw 对齐）
            a_re_d[0] <= a_re_s1;
            a_im_d[0] <= a_im_s1;
            for (p = 1; p < 3; p = p + 1) begin
                a_re_d[p] <= a_re_d[p-1];
                a_im_d[p] <= a_im_d[p-1];
            end

            // 地址和 valid 流水线（pipe_v 延迟1拍，和 RAM 读数据对齐）
            addr_a_pipe[0] <= calc_addr_a;
            addr_b_pipe[0] <= calc_addr_b;
            wb_bank_pipe[0] <= ~src_bank;
            pipe_v[0] <= (state == S_PROC && butterfly_cnt < N/2);
            for (p = 1; p < PIPE_DEPTH; p = p + 1) begin
                addr_a_pipe[p] <= addr_a_pipe[p-1];
                addr_b_pipe[p] <= addr_b_pipe[p-1];
                wb_bank_pipe[p] <= wb_bank_pipe[p-1];
                pipe_v[p] <= pipe_v[p-1];
            end

            //---- 写回（流水线末端 PIPE_DEPTH-1）----
            if (pipe_v[PIPE_DEPTH-1]) begin
                $display("WB stage=%0d addr_a=%0d y1=%0d y2=%0d bank=%0d",
                    stage_cnt, addr_a_pipe[PIPE_DEPTH-1], y1_re_t, y2_re_t, wb_bank_pipe[PIPE_DEPTH-1]);
                if (wb_bank_pipe[PIPE_DEPTH-1] == 0) begin
                    we_a0 <= 1; addr_a0 <= addr_a_pipe[PIPE_DEPTH-1]; wdata_a0 <= {y1_im_t, y1_re_t};
                    we_b0 <= 1; addr_b0 <= addr_b_pipe[PIPE_DEPTH-1]; wdata_b0 <= {y2_im_t, y2_re_t};
                end else begin
                    we_a1 <= 1; addr_a1 <= addr_a_pipe[PIPE_DEPTH-1]; wdata_a1 <= {y1_im_t, y1_re_t};
                    we_b1 <= 1; addr_b1 <= addr_b_pipe[PIPE_DEPTH-1]; wdata_b1 <= {y2_im_t, y2_re_t};
                end
            end

            //---- 状态机 ----
            case (state)
                S_IDLE: begin
                    busy <= 0;
                    dout_valid <= 0;
                    if (start) begin
                        busy <= 1;
                        if (din_valid) begin
                            we_a0 <= 1; addr_a0 <= 0;
                            wdata_a0 <= {{(INTERN_WIDTH-DIN_WIDTH){din_im[DIN_WIDTH-1]}}, din_im,
                                        {(INTERN_WIDTH-DIN_WIDTH){din_re[DIN_WIDTH-1]}}, din_re};
                            load_cnt <= 1; state <= S_LOAD;
                        end else begin
                            load_cnt <= 0; state <= S_LOAD;
                        end
                    end
                end

                S_LOAD: begin
                    if (din_valid) begin
                        we_a0 <= 1; addr_a0 <= bit_reverse(load_cnt);
                        wdata_a0 <= {{(INTERN_WIDTH-DIN_WIDTH){din_im[DIN_WIDTH-1]}}, din_im,
                                    {(INTERN_WIDTH-DIN_WIDTH){din_re[DIN_WIDTH-1]}}, din_re};
                        if (load_cnt == N-1) begin
                            state <= S_PROC; stage_cnt <= 0; butterfly_cnt <= 0; drain_cnt <= 0;
                        end else begin
                            load_cnt <= load_cnt + 1;
                        end
                    end
                end

                S_PROC: begin
                    if (butterfly_cnt < N/2) begin
                        // 设置读地址
                        if (src_bank == 0) begin addr_a0 <= calc_addr_a; addr_b0 <= calc_addr_b; end
                        else begin addr_a1 <= calc_addr_a; addr_b1 <= calc_addr_b; end
                        tw_addr <= calc_tw_addr;

                        if (butterfly_cnt == N/2 - 1) begin
                            butterfly_cnt <= N/2;
                            drain_cnt <= PIPE_DEPTH + 1;
                        end else begin
                            butterfly_cnt <= butterfly_cnt + 1;
                        end
                    end else if (butterfly_cnt == N/2 && drain_cnt == 0) begin
                        // drain 结束后的 wait_one 周期，地址更新为新 stage
                        if (stage_cnt == LOG2_N - 1) begin
                            state <= S_UNLOAD; unload_cnt <= 0;
                        end else begin
                            stage_cnt <= stage_cnt + 1;
                            butterfly_cnt <= 0;
                        end
                    end else if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end
                end

                S_UNLOAD: begin
                    if (UNLOAD_BANK == 0) addr_a0 <= unload_cnt;
                    else addr_a1 <= unload_cnt;
                    dout_valid <= 1;
                    if (dout_ready) begin
                        if (unload_cnt == N-1) begin
                            state <= S_IDLE; busy <= 0; done <= 1;
                        end else begin
                            unload_cnt <= unload_cnt + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
