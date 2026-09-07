/*
 * FFT Golden Model (C)
 * Radix-2 DIT FFT/IFFT，用于生成测试向量和与 RTL 比对
 *
 * 编译：gcc -O2 -o fft_model fft_model.c -lm
 * 用法：
 *   ./fft_model <N> <forward|inverse> <input_file> <output_file>
 *   ./fft_model <N> gen <input_file>   生成随机测试输入
 *
 * 文件格式：每行 "re im"（十进制整数）
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct { double re, im; } complex_t;

/* 位反序 */
static unsigned int bit_reverse(unsigned int x, int log2_n) {
    unsigned int r = 0;
    int i;
    for (i = 0; i < log2_n; i++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
    }
    return r;
}

/* Radix-2 DIT FFT（原位运算） */
static void fft_dit(complex_t *x, int n, int inverse) {
    int log2_n = 0;
    int i, j, k, len;
    double sign = inverse ? 1.0 : -1.0;  /* IFFT 旋转因子取正 */

    while ((1 << log2_n) < n) log2_n++;

    /* 位反序重排 */
    for (i = 0; i < n; i++) {
        j = bit_reverse(i, log2_n);
        if (i < j) {
            complex_t t = x[i]; x[i] = x[j]; x[j] = t;
        }
    }

    /* Cooley-Tukey 蝶形 */
    for (len = 2; len <= n; len <<= 1) {
        double angle = sign * 2.0 * M_PI / len;
        complex_t wlen = { cos(angle), sin(angle) };
        for (i = 0; i < n; i += len) {
            complex_t w = { 1.0, 0.0 };
            for (j = 0; j < len / 2; j++) {
                complex_t u = x[i + j];
                complex_t v = {
                    x[i + j + len/2].re * w.re - x[i + j + len/2].im * w.im,
                    x[i + j + len/2].re * w.im + x[i + j + len/2].im * w.re
                };
                x[i + j].re = u.re + v.re;
                x[i + j].im = u.im + v.im;
                x[i + j + len/2].re = u.re - v.re;
                x[i + j + len/2].im = u.im - v.im;
                /* w *= wlen */
                complex_t wn = {
                    w.re * wlen.re - w.im * wlen.im,
                    w.re * wlen.im + w.im * wlen.re
                };
                w = wn;
            }
        }
    }

    /* IFFT 除以 N */
    if (inverse) {
        for (i = 0; i < n; i++) {
            x[i].re /= n;
            x[i].im /= n;
        }
    }
}

static int read_complex(const char *fname, complex_t *x, int n) {
    FILE *f = fopen(fname, "r");
    int i;
    if (!f) { perror("fopen"); return -1; }
    for (i = 0; i < n; i++) {
        if (fscanf(f, "%lf %lf", &x[i].re, &x[i].im) != 2) {
            fprintf(stderr, "Read error at line %d\n", i);
            fclose(f);
            return -1;
        }
    }
    fclose(f);
    return 0;
}

static int write_complex(const char *fname, const complex_t *x, int n, int quant_shift) {
    FILE *f = fopen(fname, "w");
    int i;
    if (!f) { perror("fopen"); return -1; }
    for (i = 0; i < n; i++) {
        /* 量化为整数：乘以 2^quant_shift 后四舍五入 */
        long re = (long)floor(x[i].re * (1 << quant_shift) + 0.5);
        long im = (long)floor(x[i].im * (1 << quant_shift) + 0.5);
        fprintf(f, "%ld %ld\n", re, im);
    }
    fclose(f);
    return 0;
}

static void gen_random(complex_t *x, int n) {
    int i;
    for (i = 0; i < n; i++) {
        x[i].re = (rand() % 2001) - 1000;  /* -1000..1000 */
        x[i].im = (rand() % 2001) - 1000;
    }
}

int main(int argc, char **argv) {
    int n, log2_n;
    complex_t *x;

    if (argc < 4) {
        fprintf(stderr, "Usage:\n");
        fprintf(stderr, "  %s <N> <forward|inverse> <input_file> <output_file>\n", argv[0]);
        fprintf(stderr, "  %s <N> gen <output_file>  (generate random input)\n", argv[0]);
        return 1;
    }

    n = atoi(argv[1]);
    log2_n = 0;
    while ((1 << log2_n) < n) log2_n++;
    if ((1 << log2_n) != n) {
        fprintf(stderr, "Error: N must be power of 2\n");
        return 1;
    }

    x = (complex_t *)malloc(n * sizeof(complex_t));
    if (!x) { perror("malloc"); return 1; }

    if (strcmp(argv[2], "gen") == 0) {
        gen_random(x, n);
        if (write_complex(argv[3], x, n, 0) != 0) return 1;
        printf("Generated %d random samples -> %s\n", n, argv[3]);
    } else {
        int inverse = (strcmp(argv[2], "inverse") == 0);
        if (read_complex(argv[3], x, n) != 0) return 1;
        fft_dit(x, n, inverse);
        /* 输出量化：FFT 输出放大 N 倍，右移 log2_n 对齐 RTL 全精度输出 */
        if (write_complex(argv[4], x, n, 0) != 0) return 1;
        printf("%s FFT: %d points -> %s\n", inverse ? "Inverse" : "Forward", n, argv[4]);
    }

    free(x);
    return 0;
}
