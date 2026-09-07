/*
 * LDPC Decoder - 5G NR QC-LDPC, Layered Min-Sum
 *
 * 架构：分层调度 + 串行 CNU（每 z 位置调用一次）
 * 每层流程：
 *   1. S_SCAN: 扫描非零列，保存 col_list/shift_list/msg_old_list
 *   2. 对每个 z: CNU输入=shift(post)[z]-msg_old[z]，输出存 msg_new_list
 *   3. S_UPDATE: post[c]=inv_shift(shift(post[c])-msg_old+msg_new, s)
 */
module ldpc_decoder #(
    parameter integer BG          = 0,
    parameter integer ZC          = 4,
    parameter integer ROWS        = 4,
    parameter integer N_B         = 8,
    parameter integer K_B         = 4,
    parameter integer M_B         = 4,
    parameter integer LLR_WIDTH   = 6,
    parameter integer MAX_ITER    = 4,
    parameter integer MAX_DEGREE  = 6,
    parameter integer SHIFT_W     = 9,
    parameter integer ZC_W        = $clog2(ZC),
    parameter integer BLOCK_W     = ZC * LLR_WIDTH,
    parameter integer ITER_W      = $clog2(MAX_ITER+1),
    parameter integer DEG_W       = $clog2(MAX_DEGREE+1),
    parameter         BG_MEM_FILE = "ldpc_bg_test.mem"
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    output reg                      busy,
    output reg                      done,
    output reg [ITER_W-1:0]         iter_count,

    input  wire [BLOCK_W-1:0]       s_axis_tdata,
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

    localparam S_IDLE   = 4'd0;
    localparam S_LOAD   = 4'd1;
    localparam S_ITER   = 4'd2;
    localparam S_SCAN   = 4'd3;
    localparam S_Z_CNU  = 4'd4;
    localparam S_UPDATE = 4'd5;
    localparam S_NEXT   = 4'd6;
    localparam S_OUTPUT = 4'd7;

    reg [3:0] state;

    reg [BLOCK_W-1:0] channel_ram [0:N_B-1];
    reg [BLOCK_W-1:0] post_ram    [0:N_B-1];
    reg [BLOCK_W-1:0] msg_ram     [0:ROWS*N_B-1];

    reg [N_B_W-1:0]  load_cnt;
    reg [ITER_W-1:0] iter_cnt;
    reg [ROWS_W-1:0] layer_cnt;
    reg [N_B_W-1:0]  col_cnt;
    reg [ZC_W:0]     z_cnt;
    reg [DEG_W:0]    deg_cnt;

    // 非零列列表 + msg_old 快照（S_SCAN 时保存）
    reg [DEG_W-1:0]  degree;
    reg [N_B_W-1:0]  col_list   [0:MAX_DEGREE-1];
    reg [ZC_W-1:0]   shift_list [0:MAX_DEGREE-1];
    reg [BLOCK_W-1:0] msg_old_list [0:MAX_DEGREE-1];

    // 基矩阵 ROM
    wire [SHIFT_W-1:0] bg_shift;
    wire bg_is_zero = (bg_shift == 9'd511);

    ldpc_base_graph_rom #(
        .BG(BG), .ROWS(ROWS), .N_B(N_B), .K_B(K_B), .M_B(M_B),
        .SHIFT_W(SHIFT_W), .MEM_FILE(BG_MEM_FILE)
    ) u_bg_rom (
        .row(layer_cnt), .col(col_cnt), .shift_out(bg_shift)
    );

    // CNU
    reg cnu_start;
    wire cnu_done;
    reg signed [LLR_WIDTH-1:0] cnu_llr_in;
    reg cnu_llr_valid;
    wire signed [LLR_WIDTH-1:0] cnu_msg_out;
    wire cnu_msg_valid;

    ldpc_cnu #(.LLR_WIDTH(LLR_WIDTH), .NUM_INPUTS(MAX_DEGREE), .ALPHA(1)) u_cnu (
        .clk(clk), .rst_n(rst_n),
        .start(cnu_start), .busy(), .done(cnu_done),
        .llr_in(cnu_llr_in), .llr_valid(cnu_llr_valid),
        .msg_out(cnu_msg_out), .msg_valid(cnu_msg_valid)
    );

    // 当前 z 的 msg_new 收集
    reg signed [LLR_WIDTH-1:0] msg_new_z [0:MAX_DEGREE-1];
    reg [DEG_W:0] cnu_out_cnt;

    // 取 shift_right(block, shift) 的第 z 个 LLR（与编码器方向一致）
    // 右移 shift: out[z] = in[(z-shift+ZC)%ZC]
    function signed [LLR_WIDTH-1:0] shifted_llr;
        input [BLOCK_W-1:0] block;
        input [ZC_W-1:0] shift;
        input [ZC_W-1:0] z;
        integer src;
        begin
            src = (z + ZC - shift) % ZC;
            shifted_llr = block[(src+1)*LLR_WIDTH-1 -: LLR_WIDTH];
        end
    endfunction

    assign s_axis_tready = (state == S_LOAD);
    assign m_axis_tvalid = (state == S_OUTPUT);
    assign m_axis_tlast  = (state == S_OUTPUT) && (load_cnt == N_B - 1);

    integer mi, di;
    reg [N_B_W-1:0] upd_idx;
    reg [ZC_W:0] upd_z;
    reg [BLOCK_W-1:0] new_post_block;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0;
            iter_count <= 'd0; load_cnt <= 'd0; iter_cnt <= 'd0;
            layer_cnt <= 'd0; col_cnt <= 'd0; z_cnt <= 'd0; deg_cnt <= 'd0;
            degree <= 'd0; cnu_start <= 1'b0; cnu_llr_valid <= 1'b0;
            cnu_out_cnt <= 'd0; upd_idx <= 'd0; upd_z <= 'd0;
        end else begin
            done <= 1'b0;
            cnu_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        state <= S_LOAD; busy <= 1'b1; load_cnt <= 'd0;
                    end
                end

                S_LOAD: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        channel_ram[load_cnt] <= s_axis_tdata;
                        post_ram[load_cnt] <= s_axis_tdata;
                        if (s_axis_tlast || load_cnt == N_B - 1) begin
                            state <= S_ITER; iter_cnt <= 'd0;
                            for (mi = 0; mi < ROWS*N_B; mi = mi + 1)
                                msg_ram[mi] <= 'd0;
                        end else load_cnt <= load_cnt + 1'b1;
                    end
                end

                S_ITER: begin
                    layer_cnt <= 'd0;
                    state <= S_SCAN; col_cnt <= 'd0; degree <= 'd0;
                end

                S_SCAN: begin
                    if (!bg_is_zero) begin
                        col_list[degree] <= col_cnt;
                        shift_list[degree] <= bg_shift[ZC_W-1:0];
                        msg_old_list[degree] <= msg_ram[layer_cnt * N_B + col_cnt];
                        degree <= degree + 1'b1;
                    end
                    if (col_cnt == N_B - 1) begin
                        state <= S_Z_CNU; z_cnt <= 'd0; deg_cnt <= 'd0;
                        cnu_out_cnt <= 'd0; cnu_start <= 1'b1;
                    end else col_cnt <= col_cnt + 1'b1;
                end

                S_Z_CNU: begin
                    // 串行输入当前 z 的所有非零列 LLR（不足 MAX_DEGREE 填 0）
                    if (deg_cnt < MAX_DEGREE) begin
                        cnu_llr_valid <= 1'b1;
                        if (deg_cnt < degree) begin
                            cnu_llr_in <= shifted_llr(post_ram[col_list[deg_cnt]], shift_list[deg_cnt], z_cnt[0 +: ZC_W])
                                        - $signed(msg_old_list[deg_cnt][(z_cnt[0 +: ZC_W]+1)*LLR_WIDTH-1 -: LLR_WIDTH]);
                        end else begin
                            cnu_llr_in <= {1'b0, {LLR_WIDTH-1{1'b1}}};  // 填充最大正LLR，不影响min/sum
                        end
                        deg_cnt <= deg_cnt + 1'b1;
                    end else cnu_llr_valid <= 1'b0;

                    // 收集 CNU 输出
                    if (cnu_msg_valid) begin
                        msg_new_z[cnu_out_cnt] <= cnu_msg_out;
                        cnu_out_cnt <= cnu_out_cnt + 1'b1;
                    end

                    if (cnu_done) begin
                        // 写回 msg_ram 当前 z 位置
                        for (di = 0; di < MAX_DEGREE; di = di + 1) begin
                            if (di < degree)
                                msg_ram[layer_cnt*N_B+col_list[di]][(z_cnt[0 +: ZC_W]+1)*LLR_WIDTH-1 -: LLR_WIDTH] <= msg_new_z[di];
                        end
                        if (z_cnt == ZC - 1) begin
                            state <= S_UPDATE; upd_idx <= 'd0;
                        end else begin
                            z_cnt <= z_cnt + 1'b1;
                            deg_cnt <= 'd0; cnu_out_cnt <= 'd0;
                            cnu_start <= 1'b1;
                        end
                    end
                end

                S_UPDATE: begin
                    // 逐列更新 post: post_new[z] = post_old[z] - msg_old[(z+s)%ZC] + msg_new[(z+s)%ZC]
                    // msg_ram 已更新为 msg_new
                    if (upd_idx < degree) begin
                        if (upd_z < ZC) begin
                            new_post_block[(upd_z[0 +: ZC_W]+1)*LLR_WIDTH-1 -: LLR_WIDTH] <=
                                $signed(post_ram[col_list[upd_idx]][(upd_z[0 +: ZC_W]+1)*LLR_WIDTH-1 -: LLR_WIDTH])
                                - $signed(msg_old_list[upd_idx][((upd_z[0 +: ZC_W]+shift_list[upd_idx])%ZC+1)*LLR_WIDTH-1 -: LLR_WIDTH])
                                + $signed(msg_ram[layer_cnt*N_B+col_list[upd_idx]][((upd_z[0 +: ZC_W]+shift_list[upd_idx])%ZC+1)*LLR_WIDTH-1 -: LLR_WIDTH]);
                            upd_z <= upd_z + 1'b1;
                        end else begin
                            post_ram[col_list[upd_idx]] <= new_post_block;
                            upd_idx <= upd_idx + 1'b1;
                            upd_z <= 'd0;
                        end
                    end else state <= S_NEXT;
                end

                S_NEXT: begin
                    if (layer_cnt == ROWS - 1) begin
                        iter_cnt <= iter_cnt + 1'b1;
                        iter_count <= iter_cnt + 1'b1;
                        if (iter_cnt == MAX_ITER - 1) begin
                            state <= S_OUTPUT; load_cnt <= 'd0;
                        end else state <= S_ITER;
                    end else begin
                        layer_cnt <= layer_cnt + 1'b1;
                        state <= S_SCAN; col_cnt <= 'd0; degree <= 'd0;
                    end
                end

                S_OUTPUT: begin
                    if (m_axis_tready) begin
                        if (load_cnt == N_B - 1) begin
                            state <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                        end else load_cnt <= load_cnt + 1'b1;
                    end
                end
            endcase
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < ZC; gi = gi + 1) begin : gen_hd
            assign m_axis_tdata[gi] = post_ram[load_cnt][(gi+1)*LLR_WIDTH-1];
        end
    endgenerate

endmodule
