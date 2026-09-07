#!/usr/bin/env python3
"""
FIR 系数生成脚本
生成窗函数法低通 FIR 系数, 输出 Verilog parameter 格式和系数文件.

用法:
    python gen_fir_coeff.py [n_taps] [coeff_width] [cutoff_norm] [window]
    默认: 31 taps, 16bit, cutoff=0.2, Hamming窗

输出:
    - coeff_<n_taps>.vh: Verilog localparam 系数 (扁平化, 可直接 include)
    - coeff_<n_taps>.txt: 十进制系数 (每行一个)
"""
import sys
import math
import os


def hamming(n, N):
    """Hamming 窗, N = n_taps - 1"""
    return 0.54 - 0.46 * math.cos(2 * math.pi * n / N)


def hann(n, N):
    return 0.5 * (1 - math.cos(2 * math.pi * n / N))


def blackman(n, N):
    return 0.42 - 0.5 * math.cos(2 * math.pi * n / N) + 0.08 * math.cos(4 * math.pi * n / N)


def gen_fir_coeff(n_taps=31, cutoff=0.2, window='hamming'):
    """窗函数法生成低通 FIR 系数 (归一化到直流增益 1)"""
    N = n_taps - 1
    M = N / 2.0
    h = []
    for n in range(n_taps):
        x = n - M
        if abs(x) < 1e-9:
            sinc = 1.0
        else:
            sinc = math.sin(math.pi * cutoff * x) / (math.pi * x)
        if window == 'hamming':
            w = hamming(n, N)
        elif window == 'hann':
            w = hann(n, N)
        elif window == 'blackman':
            w = blackman(n, N)
        else:
            w = 1.0
        h.append(sinc * w)
    # 归一化
    s = sum(h)
    h = [v / s for v in h]
    return h


def quantize(val, q_width):
    scale = 2 ** (q_width - 1) - 1
    v = int(round(val * scale))
    v = max(-(2 ** (q_width - 1)), min(2 ** (q_width - 1) - 1, v))
    return v


def main():
    n_taps = int(sys.argv[1]) if len(sys.argv) > 1 else 31
    q_width = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    cutoff = float(sys.argv[3]) if len(sys.argv) > 3 else 0.2
    window = sys.argv[4] if len(sys.argv) > 4 else 'hamming'

    h = gen_fir_coeff(n_taps, cutoff, window)
    hq = [quantize(v, q_width) for v in h]

    script_dir = os.path.dirname(os.path.abspath(__file__))
    rtl_dir = os.path.join(script_dir, "..", "rtl")

    # 写 Verilog parameter 文件
    vh_path = os.path.join(rtl_dir, f"fir_coeff_{n_taps}.vh")
    hex_width = q_width // 4
    with open(vh_path, "w", encoding="utf-8") as f:
        f.write("//\n")
        f.write(f"// FIR 系数文件 - {n_taps} taps, {window}窗, cutoff={cutoff}\n")
        f.write(f"// 自动生成, 请勿手动编辑\n")
        f.write(f"// 位宽: {q_width}bit, 有符号\n")
        f.write("// 格式: {h[N-1], h[N-2], ..., h[1], h[0]}\n")
        f.write("//\n\n")
        f.write(f"localparam integer FIR_N_TAPS = {n_taps};\n")
        f.write(f"localparam integer FIR_COEFF_WIDTH = {q_width};\n\n")
        f.write(f"localparam [{n_taps*q_width-1}:0] FIR_COEFFS = {{\n")
        # Verilog 拼接: 最高位是 h[N-1]
        for idx, k in enumerate(reversed(range(n_taps))):
            comma = "," if idx < n_taps - 1 else ""
            v = hq[k] & ((1 << q_width) - 1)
            f.write(f"    {q_width}'h{v:0{hex_width}x}  // h[{k}] = {hq[k]} ({h[k]:.6f}){comma}\n")
        f.write("};\n")

    # 写十进制系数文件
    txt_path = os.path.join(script_dir, f"coeff_{n_taps}.txt")
    with open(txt_path, "w", encoding="utf-8") as f:
        for v in hq:
            f.write(f"{v}\n")

    print(f"Generated: {vh_path}")
    print(f"Generated: {txt_path}")
    print(f"  taps={n_taps}, width={q_width}, cutoff={cutoff}, window={window}")
    print(f"  First 8 coefficients: {hq[:8]}")
    print(f"  Sum of quantized coeffs: {sum(hq)} (DC gain check)")


if __name__ == "__main__":
    main()
