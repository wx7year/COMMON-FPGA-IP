/*
 * FIR Golden Model (C)
 * 直接型 FIR 滤波器，用于生成测试向量和与 RTL 比对
 *
 * 编译：gcc -O2 -o fir_model fir_model.c -lm
 * 用法：
 *   ./fir_model <num_taps> <coeff_file> <input_file> <output_file> [symmetric]
 *   ./fir_model gen_coeff <num_taps> <coeff_file> <type> <cutoff>
 *
 * 系数文件格式：每行一个十六进制数（有符号，COEFF_WIDTH 位）
 * 输入/输出文件格式：每行一个十进制整数
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define COEFF_WIDTH 16

/* 读取系数文件（十六进制） */
static int read_coeff(const char *fname, double *h, int n) {
    FILE *f = fopen(fname, "r");
    int i;
    unsigned int val;
    if (!f) { perror("fopen coeff"); return -1; }
    for (i = 0; i < n; i++) {
        if (fscanf(f, "%x", &val) != 1) {
            fprintf(stderr, "Coeff read error at %d\n", i);
            fclose(f);
            return -1;
        }
        /* 有符号扩展 */
        if (val & (1u << (COEFF_WIDTH - 1)))
            val |= ~((1u << COEFF_WIDTH) - 1);
        h[i] = (int)val / (double)(1 << (COEFF_WIDTH - 1));
    }
    fclose(f);
    return 0;
}

/* 直接型 FIR 卷积 */
static void fir_filter(const double *h, int n_taps,
                       const double *x, int n_in,
                       double *y, int symmetric) {
    int i, k;
    double *delay = (double *)calloc(n_taps, sizeof(double));

    for (i = 0; i < n_in; i++) {
        /* 移位 */
        for (k = n_taps - 1; k > 0; k--)
            delay[k] = delay[k-1];
        delay[0] = x[i];

        /* 卷积 */
        double acc = 0;
        if (symmetric) {
            int half = (n_taps + 1) / 2;
            for (k = 0; k < half; k++) {
                if (k == n_taps - 1 - k) {
                    /* 中间抽头（N奇数）：不加倍 */
                    acc += h[k] * delay[k];
                } else {
                    double pre = delay[k] + delay[n_taps - 1 - k];
                    acc += h[k] * pre;
                }
            }
        } else {
            for (k = 0; k < n_taps; k++)
                acc += h[k] * delay[k];
        }
        y[i] = acc;
    }
    free(delay);
}

/* 生成 sinc 低通滤波器系数（窗函数法） */
static void gen_lowpass(double *h, int n, double cutoff_norm) {
    int i;
    int mid = (n - 1) / 2;
    for (i = 0; i < n; i++) {
        double x = i - mid;
        double sinc = (x == 0) ? 2 * cutoff_norm : sin(2 * M_PI * cutoff_norm * x) / (M_PI * x);
        double window = 0.54 - 0.46 * cos(2 * M_PI * i / (n - 1));  // Hamming
        h[i] = sinc * window;
    }
}

/* 写系数文件（十六进制，Q1.15 格式） */
static int write_coeff(const char *fname, const double *h, int n, int symmetric) {
    FILE *f = fopen(fname, "w");
    int i, count;
    if (!f) { perror("fopen write coeff"); return -1; }

    count = symmetric ? (n + 1) / 2 : n;
    for (i = 0; i < count; i++) {
        int q = (int)round(h[i] * (1 << (COEFF_WIDTH - 1)));
        if (q > (1 << (COEFF_WIDTH - 1)) - 1) q = (1 << (COEFF_WIDTH - 1)) - 1;
        if (q < -(1 << (COEFF_WIDTH - 1))) q = -(1 << (COEFF_WIDTH - 1));
        fprintf(f, "%04x\n", q & ((1 << COEFF_WIDTH) - 1));
    }
    fclose(f);
    printf("Written %d coefficients to %s\n", count, fname);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage:\n");
        fprintf(stderr, "  %s filter <num_taps> <coeff_file> <input_file> <output_file> [symmetric]\n", argv[0]);
        fprintf(stderr, "  %s gen_coeff <num_taps> <coeff_file> <lowpass> <cutoff_norm> [symmetric]\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "gen_coeff") == 0) {
        int n = atoi(argv[2]);
        const char *fname = argv[3];
        double cutoff = atof(argv[5]);
        int symmetric = (argc > 6 && strcmp(argv[6], "symmetric") == 0);
        double *h = (double *)malloc(n * sizeof(double));
        gen_lowpass(h, n, cutoff);
        write_coeff(fname, h, n, symmetric);
        free(h);
        return 0;
    }

    if (strcmp(argv[1], "filter") == 0) {
        int n_taps = atoi(argv[2]);
        const char *coeff_file = argv[3];
        const char *input_file = argv[4];
        const char *output_file = argv[5];
        int symmetric = (argc > 6 && strcmp(argv[6], "symmetric") == 0);

        int eff_taps = symmetric ? (n_taps + 1) / 2 : n_taps;
        double *h = (double *)malloc(eff_taps * sizeof(double));

        if (read_coeff(coeff_file, h, eff_taps) != 0) return 1;

        /* 读取输入 */
        FILE *fin = fopen(input_file, "r");
        if (!fin) { perror("fopen input"); return 1; }
        int n_in = 0, cap = 1024;
        double *x = (double *)malloc(cap * sizeof(double));
        int val;
        while (fscanf(fin, "%d", &val) == 1) {
            if (n_in >= cap) { cap *= 2; x = realloc(x, cap * sizeof(double)); }
            x[n_in++] = val;
        }
        fclose(fin);

        /* FIR 滤波 */
        double *y = (double *)malloc(n_in * sizeof(double));
        fir_filter(h, n_taps, x, n_in, y, symmetric);

        /* 写输出（量化为整数，Q(COEFF_WIDTH-1) 格式放大） */
        FILE *fout = fopen(output_file, "w");
        if (!fout) { perror("fopen output"); return 1; }
        int i;
        for (i = 0; i < n_in; i++) {
            long q = (long)round(y[i] * (1 << (COEFF_WIDTH - 1)));
            fprintf(fout, "%ld\n", q);
        }
        fclose(fout);
        printf("Filtered %d samples -> %s\n", n_in, output_file);

        free(h); free(x); free(y);
        return 0;
    }

    fprintf(stderr, "Unknown command: %s\n", argv[1]);
    return 1;
}
