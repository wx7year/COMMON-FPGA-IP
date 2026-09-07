/*
 * LDPC Golden Model (C)
 * QC-LDPC 编码器 + Layered Min-Sum 译码器
 *
 * 编译：gcc -O2 -o ldpc_model ldpc_model.c -lm
 * 用法：
 *   ./ldpc_model enc <bg.mem> <rows> <cols> <zc> <input.txt> <output.txt>
 *   ./ldpc_model dec <bg.mem> <rows> <cols> <zc> <llr.txt> <output.txt> <max_iter>
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int ROWS, COLS, K_B, M_B, ZC;
static int *bg;  // 基矩阵，-1=零矩阵

static int bg_at(int r, int c) { return bg[r * COLS + c]; }

static void cyclic_right_shift(const int *in, int *out, int shift) {
    int i;
    for (i = 0; i < ZC; i++)
        out[(i + shift) % ZC] = in[i];
}

/* 读取基矩阵 */
static int load_bg(const char *fname, int rows, int cols) {
    FILE *f = fopen(fname, "r");
    int i, val;
    if (!f) { perror("load_bg"); return -1; }
    bg = (int *)malloc(rows * cols * sizeof(int));
    for (i = 0; i < rows * cols; i++) {
        if (fscanf(f, "%x", &val) != 1) { fprintf(stderr, "bg read error\n"); return -1; }
        bg[i] = (val == 511) ? -1 : val;
    }
    fclose(f);
    return 0;
}

/* LDPC 编码 */
static void ldpc_encode(const int *info, int *codeword) {
    int r, c, i;
    int *rhs = (int *)calloc(ROWS * ZC, sizeof(int));
    int *parity = (int *)calloc(M_B * ZC, sizeof(int));
    int *tmp = (int *)malloc(ZC * sizeof(int));
    int *shifted = (int *)malloc(ZC * sizeof(int));

    /* 计算 rhs[r] = Σ H[r][c] * info[c] */
    for (r = 0; r < ROWS; r++) {
        for (c = 0; c < K_B; c++) {
            int sh = bg_at(r, c);
            if (sh >= 0) {
                cyclic_right_shift(&info[c * ZC], shifted, sh);
                for (i = 0; i < ZC; i++)
                    rhs[r * ZC + i] ^= shifted[i];
            }
        }
    }

    /* 前替代求解校验位 */
    for (r = 0; r < M_B; r++) {
        memcpy(&parity[r * ZC], &rhs[r * ZC], ZC * sizeof(int));
        for (c = 0; c < r; c++) {
            int sh = bg_at(r, K_B + c);
            if (sh >= 0) {
                cyclic_right_shift(&parity[c * ZC], shifted, sh);
                for (i = 0; i < ZC; i++)
                    parity[r * ZC + i] ^= shifted[i];
            }
        }
    }

    /* 输出：信息位 + 校验位 */
    memcpy(codeword, info, K_B * ZC * sizeof(int));
    memcpy(&codeword[K_B * ZC], parity, M_B * ZC * sizeof(int));

    free(rhs); free(parity); free(tmp); free(shifted);
}

/* Min-Sum 校验节点更新（串行） */
static void min_sum_update(const double *llr, int n, double *msg) {
    int i;
    double min1 = 1e30, min2 = 1e30;
    int min1_idx = 0;
    int sign_total = 0;

    for (i = 0; i < n; i++) {
        double abs_val = fabs(llr[i]);
        int sign = (llr[i] < 0) ? 1 : 0;
        sign_total ^= sign;
        if (abs_val < min1) {
            min2 = min1;
            min1 = abs_val;
            min1_idx = i;
        } else if (abs_val < min2) {
            min2 = abs_val;
        }
    }

    for (i = 0; i < n; i++) {
        double min_excl = (i == min1_idx) ? min2 : min1;
        int out_sign = sign_total ^ ((llr[i] < 0) ? 1 : 0);
        msg[i] = out_sign ? -min_excl * 0.75 : min_excl * 0.75;
    }
}

/* LDPC 译码（简化版，小 ZC 验证用） */
static int ldpc_decode(const double *channel_llr, int *decoded, int max_iter) {
    int iter, r, c, i;
    int N = COLS * ZC;
    double *post_llr = (double *)malloc(N * sizeof(double));
    double *msg = (double *)calloc(ROWS * COLS * ZC, sizeof(double));
    double *col_llr = (double *)malloc(ZC * sizeof(double));
    double *col_msg = (double *)malloc(ZC * sizeof(double));
    int *syndrome = (int *)calloc(ROWS * ZC, sizeof(int));

    memcpy(post_llr, channel_llr, N * sizeof(double));

    for (iter = 0; iter < max_iter; iter++) {
        /* 分层更新 */
        for (r = 0; r < ROWS; r++) {
            for (c = 0; c < COLS; c++) {
                int sh = bg_at(r, c);
                if (sh < 0) continue;
                /* 读取该列的后验 LLR（经循环移位） */
                for (i = 0; i < ZC; i++)
                    col_llr[(i + sh) % ZC] = post_llr[c * ZC + i];
                /* 减去旧的校验消息 */
                for (i = 0; i < ZC; i++)
                    col_llr[i] -= msg[(r * COLS + c) * ZC + i];
                /* Min-Sum 更新 */
                min_sum_update(col_llr, ZC, col_msg);
                /* 存回新消息 */
                memcpy(&msg[(r * COLS + c) * ZC], col_msg, ZC * sizeof(double));
                /* 更新后验 LLR */
                for (i = 0; i < ZC; i++)
                    post_llr[c * ZC + (i + sh) % ZC] = channel_llr[c * ZC + (i + sh) % ZC] + col_msg[i];
            }
        }

        /* 硬判决 + 校验（简化：检查是否全零，实际应计算 syndrome） */
        int all_zero = 1;
        for (i = 0; i < N; i++) {
            decoded[i] = (post_llr[i] < 0) ? 1 : 0;
            if (post_llr[i] != channel_llr[i]) all_zero = 0;
        }
        (void)all_zero;
    }

    free(post_llr); free(msg); free(col_llr); free(col_msg); free(syndrome);
    return max_iter;
}

int main(int argc, char **argv) {
    if (argc < 7) {
        fprintf(stderr, "Usage:\n");
        fprintf(stderr, "  %s enc <bg.mem> <rows> <cols> <zc> <input.txt> <output.txt>\n", argv[0]);
        fprintf(stderr, "  %s dec <bg.mem> <rows> <cols> <zc> <llr.txt> <output.txt> <max_iter>\n", argv[0]);
        return 1;
    }

    const char *bg_file = argv[2];
    ROWS = atoi(argv[3]);
    COLS = atoi(argv[4]);
    ZC = atoi(argv[5]);
    M_B = 4;
    K_B = COLS - M_B;

    if (load_bg(bg_file, ROWS, COLS) != 0) return 1;

    if (strcmp(argv[1], "enc") == 0) {
        int *info = (int *)malloc(K_B * ZC * sizeof(int));
        int *codeword = (int *)malloc(COLS * ZC * sizeof(int));
        FILE *fin = fopen(argv[6], "r");
        FILE *fout = fopen(argv[7], "w");
        int i;
        for (i = 0; i < K_B * ZC; i++) fscanf(fin, "%d", &info[i]);
        fclose(fin);
        ldpc_encode(info, codeword);
        for (i = 0; i < COLS * ZC; i++) fprintf(fout, "%d\n", codeword[i]);
        fclose(fout);
        printf("Encoded %d info bits -> %d codeword bits\n", K_B * ZC, COLS * ZC);
        free(info); free(codeword);
    } else {
        int max_iter = atoi(argv[8]);
        double *llr = (double *)malloc(COLS * ZC * sizeof(double));
        int *decoded = (int *)malloc(COLS * ZC * sizeof(int));
        FILE *fin = fopen(argv[6], "r");
        FILE *fout = fopen(argv[7], "w");
        int i;
        for (i = 0; i < COLS * ZC; i++) fscanf(fin, "%lf", &llr[i]);
        fclose(fin);
        ldpc_decode(llr, decoded, max_iter);
        for (i = 0; i < COLS * ZC; i++) fprintf(fout, "%d\n", decoded[i]);
        fclose(fout);
        printf("Decoded %d bits, max_iter=%d\n", COLS * ZC, max_iter);
        free(llr); free(decoded);
    }

    free(bg);
    return 0;
}
