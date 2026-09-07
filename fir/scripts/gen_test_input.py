#!/usr/bin/env python3
"""
FIR 测试输入生成脚本
生成随机/冲激/阶跃等测试输入

用法：
    python gen_test_input.py --n 2048 --out ../tb/data/fir_input.txt --type random
    python gen_test_input.py --n 2048 --out ../tb/data/fir_input.txt --type impulse
    python gen_test_input.py --n 2048 --out ../tb/data/fir_input.txt --type step
    python gen_test_input.py --n 2048 --out ../tb/data/fir_input.txt --type sine --freq 0.1
"""

import argparse
import random
import math
import os


def gen_random(n, amp=1000):
    return [random.randint(-amp, amp) for _ in range(n)]


def gen_impulse(n, pos=0):
    x = [0] * n
    x[pos] = 32767  # 最大正输入
    return x


def gen_step(n, pos=0):
    return [0 if i < pos else 10000 for i in range(n)]


def gen_sine(n, freq_norm=0.1, amp=10000):
    return [int(amp * math.sin(2 * math.pi * freq_norm * i)) for i in range(n)]


def main():
    parser = argparse.ArgumentParser(description='FIR test input generator')
    parser.add_argument('--n', type=int, default=2048, help='Number of samples')
    parser.add_argument('--out', type=str, required=True, help='Output file')
    parser.add_argument('--type', choices=['random', 'impulse', 'step', 'sine'],
                        default='random', help='Input signal type')
    parser.add_argument('--freq', type=float, default=0.1, help='Sine frequency (normalized)')
    parser.add_argument('--amp', type=int, default=10000, help='Amplitude')
    args = parser.parse_args()

    if args.type == 'random':
        data = gen_random(args.n, args.amp)
    elif args.type == 'impulse':
        data = gen_impulse(args.n)
    elif args.type == 'step':
        data = gen_step(args.n, args.n // 4)
    elif args.type == 'sine':
        data = gen_sine(args.n, args.freq, args.amp)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w') as f:
        for v in data:
            f.write(f"{v}\n")

    print(f"Generated {args.n} samples ({args.type}) -> {args.out}")


if __name__ == '__main__':
    main()
