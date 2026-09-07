/*
 * LDPC Encoder - 5G NR QC-LDPC
 * 5G NR 准循环 LDPC 编码器
 *
 * 支持 BG1（4×26，K_b=22）和 BG2（4×14，K_b=10），Zc 可配置。
 *
 * 编码算法：
 *   1. 信息位 s 分成 K_b 个 Zc-bit 块
 *   2. 计算每行校验方程的信息位部分 rhs[r] = Σ H[r][c]·s[c]（循环移位+异或）
 *   3. 前替代求解校验位：p[r] = rhs[r] ⊕ Σ_{j<r} H[r][K_b+j]·p[j]
 *   4. 输出 s + p（共 N_b×Zc bit）
 *
 * 资源：1 个循环移位器（组合）+ 1 块基矩阵 ROM（组合输出）+ RAM，无 DSP
 */
module ldpc_encoder #(
    parameter integer BG          = 1,
    parameter integer ZC          = 4,
    parameter integer ROWS        = 4,
    parameter integer N_B         = (BG == 1) ? 26 : 14,
    parameter integer K_B         = (BG == 1) ? 22 : 10,
    parameter integer M_B         = 4,
    parameter integer SHIFT_W     = 9,
    parameter integer ZC_W        = $clog2(ZC),
    parameter         BG_MEM_FILE = "ldpc_bg1.mem"
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     start,
    output reg                      busy,
    output reg                      done,

    input  wire [ZC-1:0]            s_axis_tdata,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,

    output wire [ZC-1:0]            m_axis_tdata,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast
);

    localparam ROWS_W = $clog2(ROWS);
    localparam N_B_W  = $clog2(N_B);
    localparam K_B_W  = $clog2(K_B);
    localparam M_B_W  = $clog2(M_B);

    //==========================================================================
    // 状态机
    //==========================================================================
    localparam S_IDLE     = 3'd0;
    localparam S_LOAD     = 3'd1;
    localparam S_CALC_RHS = 3'd2;
    localparam S_SOLVE    = 3'd3;
    localparam S_OUTPUT   = 3'd4;

    reg [2:0] state;

    //==========================================================================
    // 信息位 RAM
    //==========================================================================
    reg [ZC-1:0] info_ram [0:K_B-1];
    reg [K_B_W-1:0] info_waddr;

    always @(posedge clk) begin
        if (state == S_LOAD && s_axis_tvalid && s_axis_tready) begin
            info_ram[info_waddr] <= s_axis_tdata;
            info_waddr <= info_waddr + 1'b1;
        end
    end

    //==========================================================================
    // 校验位 RAM
    //==========================================================================
    reg [ZC-1:0] parity_ram [0:M_B-1];
    reg [M_B_W-1:0] parity_waddr;
    reg parity_we;
    reg [ZC-1:0] parity_wdata;

    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (pi = 0; pi < M_B; pi = pi + 1)
                parity_ram[pi] <= 'd0;
        end else if (parity_we) begin
            parity_ram[parity_waddr] <= parity_wdata;
        end
    end

    //==========================================================================
    // RHS 寄存器组
    //==========================================================================
    reg [ZC-1:0] rhs_reg [0:ROWS-1];
    reg [ROWS_W-1:0] rhs_waddr;
    reg rhs_we;
    reg [ZC-1:0] rhs_wdata;

    integer ri;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ri = 0; ri < ROWS; ri = ri + 1)
                rhs_reg[ri] <= 'd0;
        end else if (rhs_we) begin
            rhs_reg[rhs_waddr] <= rhs_wdata;
        end
    end

    //==========================================================================
    // 计数器（必须在组合赋值之前声明）
    //==========================================================================
    reg [ROWS_W-1:0] calc_row;
    reg [K_B_W-1:0]  calc_col;
    reg [M_B_W-1:0]  solve_row;
    reg [M_B_W-1:0]  solve_col;
    reg [N_B_W-1:0]  out_cnt;
    reg [ZC-1:0] rhs_acc;     // RHS 行内累积
    reg [ZC-1:0] parity_acc;  // parity 行内累积

    //==========================================================================
    // 基矩阵 ROM（组合输出）+ 循环移位器（组合输出）
    //==========================================================================
    wire [ROWS_W-1:0] bg_row;
    wire [N_B_W-1:0]  bg_col;
    wire [SHIFT_W-1:0] bg_shift;
    wire bg_is_zero = (bg_shift == 9'd511);
    wire [ZC-1:0] shift_din;
    wire [ZC_W-1:0] shift_amount = bg_shift[ZC_W-1:0];
    wire [ZC-1:0] shift_dout;

    assign bg_row = (state == S_CALC_RHS) ? calc_row :
                    (state == S_SOLVE) ? solve_row : 'd0;
    assign bg_col = (state == S_CALC_RHS) ? calc_col :
                    (state == S_SOLVE && solve_col > 0) ? (K_B + solve_col - 1) : 'd0;
    assign shift_din = (state == S_CALC_RHS) ? info_ram[calc_col] :
                       (state == S_SOLVE && solve_col > 0) ? parity_ram[solve_col - 1] : 'd0;

    ldpc_base_graph_rom #(
        .BG(BG), .ROWS(ROWS), .N_B(N_B), .K_B(K_B), .M_B(M_B),
        .SHIFT_W(SHIFT_W), .MEM_FILE(BG_MEM_FILE)
    ) u_bg_rom (
        .row(bg_row), .col(bg_col), .shift_out(bg_shift)
    );

    ldpc_cyclic_shift #(.ZC(ZC)) u_cyclic_shift (
        .din(shift_din), .shift(shift_amount), .dout(shift_dout)
    );

    //==========================================================================
    // 输出数据寄存器
    //==========================================================================
    reg [ZC-1:0] m_axis_tdata_reg;

    //==========================================================================
    // 主控制状态机
    //==========================================================================
    assign s_axis_tready = (state == S_LOAD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            info_waddr <= 'd0;
            parity_we <= 1'b0;
            rhs_we <= 1'b0;
            calc_row <= 'd0;
            calc_col <= 'd0;
            solve_row <= 'd0;
            solve_col <= 'd0;
            out_cnt <= 'd0;
            m_axis_tdata_reg <= 'd0;
        end else begin
            done <= 1'b0;
            rhs_we <= 1'b0;
            parity_we <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    info_waddr <= 'd0;
                    if (start) begin
                        state <= S_LOAD;
                        busy <= 1'b1;
                    end
                end

                S_LOAD: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (s_axis_tlast || (info_waddr == K_B - 1)) begin
                            state <= S_CALC_RHS;
                            calc_row <= 'd0;
                            calc_col <= 'd0;
                            for (ri = 0; ri < ROWS; ri = ri + 1)
                                rhs_reg[ri] <= 'd0;
                        end
                    end
                end

                S_CALC_RHS: begin
                    // 用 rhs_acc 在行内累积，避免读后写冲突
                    if (calc_col == 0)
                        rhs_acc <= !bg_is_zero ? shift_dout : 'd0;
                    else
                        rhs_acc <= rhs_acc ^ (!bg_is_zero ? shift_dout : 'd0);

                    // 行结束时写入 rhs_reg
                    if (calc_col == K_B - 1) begin
                        rhs_we <= 1'b1;
                        rhs_waddr <= calc_row;
                        rhs_wdata <= (calc_col == 0) ?
                                     (!bg_is_zero ? shift_dout : 'd0) :
                                     (rhs_acc ^ (!bg_is_zero ? shift_dout : 'd0));
                        calc_col <= 'd0;
                        if (calc_row == ROWS - 1) begin
                            state <= S_SOLVE;
                            solve_row <= 'd0;
                            solve_col <= 'd0;
                        end else begin
                            calc_row <= calc_row + 1'b1;
                        end
                    end else begin
                        calc_col <= calc_col + 1'b1;
                    end
                end

                S_SOLVE: begin
                    if (solve_col == 0) begin
                        // 初始化：p[solve_row] = rhs[solve_row]
                        parity_acc <= rhs_reg[solve_row];
                        if (solve_row == 0) begin
                            // 无 j<0，本行直接完成
                            parity_we <= 1'b1;
                            parity_waddr <= solve_row;
                            parity_wdata <= rhs_reg[solve_row];
                            solve_col <= 'd0;
                            if (solve_row == M_B - 1) begin
                                state <= S_OUTPUT;
                                out_cnt <= 'd0;
                                m_axis_tdata_reg <= info_ram[0];
                            end else begin
                                solve_row <= solve_row + 1'b1;
                            end
                        end else begin
                            solve_col <= 1'b1;  // j=0
                        end
                    end else begin
                        // j = solve_col - 1，范围 0..solve_row-1
                        parity_acc <= parity_acc ^ (!bg_is_zero ? shift_dout : 'd0);

                        if (solve_col == solve_row) begin
                            // 本行完成，写入 parity_ram
                            parity_we <= 1'b1;
                            parity_waddr <= solve_row;
                            parity_wdata <= parity_acc ^ (!bg_is_zero ? shift_dout : 'd0);
                            solve_col <= 'd0;
                            if (solve_row == M_B - 1) begin
                                state <= S_OUTPUT;
                                out_cnt <= 'd0;
                                m_axis_tdata_reg <= info_ram[0];
                            end else begin
                                solve_row <= solve_row + 1'b1;
                            end
                        end else begin
                            solve_col <= solve_col + 1'b1;
                        end
                    end
                end

                S_OUTPUT: begin
                    // m_axis_tvalid/tlast 为组合输出
                    // m_axis_tdata_reg 已预加载当前 out_cnt 对应的数据

                    if (m_axis_tready) begin
                        if (out_cnt == N_B - 1) begin
                            state <= S_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            out_cnt <= out_cnt + 1'b1;
                            // 预加载下一个数据
                            if (out_cnt + 1 < K_B)
                                m_axis_tdata_reg <= info_ram[out_cnt + 1];
                            else
                                m_axis_tdata_reg <= parity_ram[out_cnt + 1 - K_B];
                        end
                    end
                end
            endcase
        end
    end

    // 输出（组合输出 tvalid/tlast，寄存器输出 tdata）
    assign m_axis_tvalid = (state == S_OUTPUT);
    assign m_axis_tlast  = (state == S_OUTPUT) && (out_cnt == N_B - 1);
    assign m_axis_tdata  = m_axis_tdata_reg;

endmodule
