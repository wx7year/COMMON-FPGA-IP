/*
 * CORDIC Golden Model (C)
 * 迭代式 CORDIC，旋转/向量模式
 *
 * 编译：gcc -O2 -o cordic_model cordic_model.c -lm
 * 用法：
 *   ./cordic_model <iterations> <mode> <x> <y> <z>
 *   mode: 0=旋转, 1=向量
 *   角度格式：Q2.14（输入 z 为整数，实际角度 = z / 2^14 * pi? 不，z/2^14 rad）
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc < 6) {
        fprintf(stderr, "Usage: %s <iter> <mode(0=rot,1=vec)> <x> <y> <z_q2_14>\n", argv[0]);
        return 1;
    }

    int iterations = atoi(argv[1]);
    int mode = atoi(argv[2]);
    double x = atof(argv[3]);
    double y = atof(argv[4]);
    double z = atof(argv[5]) / 16384.0;  // Q2.14

    double K = 1.0;
    int i;
    for (i = 0; i < iterations; i++) {
        double atan_val = atan(1.0 / (1 << i));
        K *= cos(atan_val);

        int d;
        if (mode == 0)  // 旋转：d = sign(z)
            d = (z >= 0) ? 1 : -1;
        else            // 向量：d = -sign(y)
            d = (y < 0) ? 1 : -1;

        double x_next = x - d * y * (1.0 / (1 << i));
        double y_next = y + d * x * (1.0 / (1 << i));
        double z_next = z - d * atan_val;

        x = x_next;
        y = y_next;
        z = z_next;
    }

    printf("x_out = %.6f (K*input = %.6f)\n", x, x * K);
    printf("y_out = %.6f\n", y);
    printf("z_out = %.6f rad (%.4f deg)\n", z, z * 180.0 / M_PI);
    printf("K = %.6f\n", K);

    return 0;
}
