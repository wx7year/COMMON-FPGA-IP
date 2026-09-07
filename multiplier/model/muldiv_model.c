/*
 * Multiplier / Divider Golden Model (C)
 * 乘法器和除法器的参考模型
 *
 * 编译：gcc -O2 -o muldiv_model muldiv_model.c
 * 用法：
 *   ./muldiv_model mul <a> <b>
 *   ./muldiv_model div <a> <b>
 */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s mul <a> <b>\n", argv[0]);
        fprintf(stderr, "       %s div <a> <b>\n", argv[0]);
        return 1;
    }

    if (argv[1][0] == 'm') {
        long long a = atoll(argv[2]);
        long long b = atoll(argv[3]);
        printf("%lld * %lld = %lld\n", a, b, a * b);
    } else {
        long long a = atoll(argv[2]);
        long long b = atoll(argv[3]);
        if (b == 0) { printf("Division by zero!\n"); return 1; }
        printf("%lld / %lld = %lld, remainder = %lld\n", a, b, a / b, a % b);
    }
    return 0;
}
