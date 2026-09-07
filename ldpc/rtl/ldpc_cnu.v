/*
 * LDPC Check Node Update (CNU) - Serial Min-Sum
 * LDPC 校验节点更新单元：串行最小和算法
 *
 * 输入一组 NUM_INPUTS 个 LLR 值（串行输入），
 * 输出对应的校验消息（串行输出）。
 *
 * 在 QC-LDPC 分层译码中，NUM_INPUTS = 当前层非零列数（degree），
 * 对每个 z 位置调用一次 CNU。
 *
 * Min-Sum 算法：
 *   对每个输入 i，输出 = (符号乘积 ⊕ 输入i符号) × 除i外的最小绝对值
 *   归一化 α=0.75: out = out - (out >>> 2)
 *
 * 延迟：NUM_INPUTS（输入）+ 1 + NUM_INPUTS（输出）= 2*NUM_INPUTS+1 周期
 */
module ldpc_cnu #(
    parameter integer LLR_WIDTH   = 6,
    parameter integer NUM_INPUTS  = 5,
    parameter integer CNT_W       = $clog2(NUM_INPUTS+1),
    parameter integer ALPHA       = 1  // 0=无归一化, 1=0.75, 2=0.875
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     start,
    output wire                     busy,
    output reg                      done,

    input  wire signed [LLR_WIDTH-1:0] llr_in,
    input  wire                     llr_valid,

    output wire signed [LLR_WIDTH-1:0] msg_out,
    output wire                     msg_valid
);

    localparam S_IDLE  = 2'd0;
    localparam S_INPUT = 2'd1;
    localparam S_CALC  = 2'd2;
    localparam S_OUT   = 2'd3;

    reg [1:0] state;
    reg [CNT_W-1:0] cnt;

    reg signed [LLR_WIDTH-1:0] input_buf [0:NUM_INPUTS-1];
    reg [$clog2(NUM_INPUTS)-1:0] in_waddr;

    reg [LLR_WIDTH-2:0] min1_abs;
    reg [LLR_WIDTH-2:0] min2_abs;
    reg [$clog2(NUM_INPUTS)-1:0] min1_idx;
    reg                 sign_total;

    wire [LLR_WIDTH-2:0] cur_abs = llr_in[LLR_WIDTH-1] ? -llr_in : llr_in[LLR_WIDTH-2:0];
    wire cur_sign = llr_in[LLR_WIDTH-1];

    reg [$clog2(NUM_INPUTS)-1:0] out_raddr;
    wire signed [LLR_WIDTH-1:0] cur_llr = input_buf[out_raddr];
    wire cur_is_min1 = (out_raddr == min1_idx);
    wire [LLR_WIDTH-2:0] min_excl = cur_is_min1 ? min2_abs : min1_abs;
    wire out_sign = sign_total ^ cur_llr[LLR_WIDTH-1];

    reg signed [LLR_WIDTH-1:0] msg_raw;
    always @(*) begin
        msg_raw = out_sign ? -$signed({1'b0, min_excl}) : $signed({1'b0, min_excl});
        case (ALPHA)
            1: msg_raw = msg_raw - (msg_raw >>> 2);
            2: msg_raw = msg_raw - (msg_raw >>> 3);
            default: ;
        endcase
    end

    assign busy = (state != S_IDLE);
    assign msg_valid = (state == S_OUT);
    assign msg_out = msg_raw;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            cnt <= 'd0;
            in_waddr <= 'd0;
            min1_abs <= 'd0;
            min2_abs <= 'd0;
            min1_idx <= 'd0;
            sign_total <= 1'b0;
            out_raddr <= 'd0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_INPUT;
                        cnt <= 'd0;
                        in_waddr <= 'd0;
                        min1_abs <= {LLR_WIDTH-1{1'b1}};
                        min2_abs <= {LLR_WIDTH-1{1'b1}};
                        sign_total <= 1'b0;
                    end
                end

                S_INPUT: begin
                    if (llr_valid) begin
                        input_buf[in_waddr] <= llr_in;
                        in_waddr <= in_waddr + 1'b1;
                        sign_total <= sign_total ^ cur_sign;

                        if (cur_abs < min1_abs) begin
                            min2_abs <= min1_abs;
                            min1_abs <= cur_abs;
                            min1_idx <= in_waddr;
                        end else if (cur_abs < min2_abs) begin
                            min2_abs <= cur_abs;
                        end

                        if (cnt == NUM_INPUTS - 1) begin
                            state <= S_CALC;
                            cnt <= 'd0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                S_CALC: begin
                    out_raddr <= 'd0;
                    state <= S_OUT;
                    cnt <= 'd0;
                end

                S_OUT: begin
                    if (cnt == NUM_INPUTS - 1) begin
                        state <= S_IDLE;
                        done <= 1'b1;
                    end else begin
                        out_raddr <= out_raddr + 1'b1;
                        cnt <= cnt + 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
