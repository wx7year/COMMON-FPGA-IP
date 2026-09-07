#!/usr/bin/env python3
"""
FFT 旋转因子生成脚本
生成 .hex / .mif / .vh 格式的旋转因子 ROM 初始化文件

用法：
    python gen_twiddle.py --n 1024 --width 16 --format hex
    python gen_twiddle.py --n 1024 --width 16 --format vh
    python gen_twiddle.py --n 1024 --width 16 --format mif

旋转因子：W_N^k = exp(-2πjk/N), k = 0 .. N/2-1
量化为 width 位有符号定点数（Q1.(width-1) 格式）
"""

import argparse
import math
import os


def gen_twiddle(n, width):
    """生成旋转因子列表，返回 [(re_int, im_int), ...]"""
    scale = (1 << (width - 1)) - 1  # 最大正值，留 1 LSB 余量
    factors = []
    for k in range(n // 2):
        angle = -2.0 * math.pi * k / n
        re = int(round(scale * math.cos(angle)))
        im = int(round(scale * math.sin(angle)))
        factors.append((re, im))
    return factors


def write_hex(factors, width, path):
    """写 Verilog $readmemh 格式：每行一个 2*width 位的十六进制数 {im, re}"""
    with open(path, 'w') as f:
        for re, im in factors:
            # 有符号数转无符号位模式
            re_u = re & ((1 << width) - 1)
            im_u = im & ((1 << width) - 1)
            val = (im_u << width) | re_u
            f.write(f"{val:0{(2*width+3)//4}x}\n")
    print(f"Written {len(factors)} entries to {path} (hex)")


def write_vh(factors, width, path):
    """写 Verilog header 格式：parameter 数组初始化"""
    with open(path, 'w') as f:
        f.write("// Auto-generated twiddle factor ROM\n")
        f.write(f"// N={len(factors)*2}, WIDTH={width}\n\n")
        f.write(f"localparam integer TWIDDLE_DEPTH = {len(factors)};\n")
        f.write(f"localparam integer TWIDDLE_WIDTH = {width};\n\n")
        f.write("reg [2*TWIDDLE_WIDTH-1:0] twiddle_rom [0:TWIDDLE_DEPTH-1];\n\n")
        f.write("initial begin\n")
        for i, (re, im) in enumerate(factors):
            re_u = re & ((1 << width) - 1)
            im_u = im & ((1 << width) - 1)
            val = (im_u << width) | re_u
            f.write(f"    twiddle_rom[{i}] = {2*width}'h{val:x};\n")
        f.write("end\n")
    print(f"Written {len(factors)} entries to {path} (vh)")


def write_mif(factors, width, path):
    """写 Intel/Altera MIF 格式"""
    depth = len(factors)
    with open(path, 'w') as f:
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = {2*width};\n")
        f.write("ADDRESS_RADIX = DEC;\n")
        f.write("DATA_RADIX = HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for i, (re, im) in enumerate(factors):
            re_u = re & ((1 << width) - 1)
            im_u = im & ((1 << width) - 1)
            val = (im_u << width) | re_u
            f.write(f"    {i} : {val:0{(2*width+3)//4}X};\n")
        f.write("END;\n")
    print(f"Written {depth} entries to {path} (mif)")


def main():
    parser = argparse.ArgumentParser(description='FFT twiddle factor generator')
    parser.add_argument('--n', type=int, default=1024, help='FFT size (power of 2)')
    parser.add_argument('--width', type=int, default=16, help='Twiddle factor bit width')
    parser.add_argument('--format', choices=['hex', 'vh', 'mif', 'all'], default='all')
    parser.add_argument('--outdir', default='../rtl', help='Output directory')
    args = parser.parse_args()

    assert (args.n & (args.n - 1)) == 0, "N must be power of 2"

    factors = gen_twiddle(args.n, args.width)

    os.makedirs(args.outdir, exist_ok=True)
    base = f"twiddle_n{args.n}_w{args.width}"

    if args.format in ('hex', 'all'):
        write_hex(factors, args.width, os.path.join(args.outdir, base + '.hex'))
    if args.format in ('vh', 'all'):
        write_vh(factors, args.width, os.path.join(args.outdir, base + '.vh'))
    if args.format in ('mif', 'all'):
        write_mif(factors, args.width, os.path.join(args.outdir, base + '.mif'))


if __name__ == '__main__':
    main()
