#!/usr/bin/env python3
"""Generate FFT test vectors: input and expected output (pure Python, no numpy)."""
import cmath
import os
import random

N = 1024
DIN_WIDTH = 16
DOUT_WIDTH = 26
SCALE_IN = (1 << (DIN_WIDTH - 1)) - 1  # 32767

def fft_radix2(x, inverse=False):
    """Cooley-Tukey radix-2 FFT. Note: scaling only at top level for IFFT."""
    n = len(x)
    if n == 1:
        return x
    even = fft_radix2(x[0::2], inverse)
    odd = fft_radix2(x[1::2], inverse)
    sign = 1 if inverse else -1
    result = [0] * n
    for k in range(n // 2):
        w = cmath.exp(sign * 2j * cmath.pi * k / n)
        result[k] = even[k] + w * odd[k]
        result[k + n // 2] = even[k] - w * odd[k]
    return result

def ifft_radix2(x):
    """IFFT with proper 1/N scaling at top level only."""
    return [v / len(x) for v in fft_radix2(x, inverse=True)]

def bit_reverse(x, n):
    """Bit-reverse permutation for FFT input."""
    log2n = n.bit_length() - 1
    result = [0] * n
    for i in range(n):
        rev = 0
        for b in range(log2n):
            if i & (1 << b):
                rev |= 1 << (log2n - 1 - b)
        result[rev] = x[i]
    return result

def quantize_c(v, width):
    """Quantize complex value to fixed-point."""
    scale = (1 << (width - 1)) - 1
    re = int(round(v.real))
    im = int(round(v.imag))
    re = max(-scale - 1, min(scale, re))
    im = max(-scale - 1, min(scale, im))
    return re, im

def generate_test(data_dir):
    os.makedirs(data_dir, exist_ok=True)

    # Test 1: Random input
    random.seed(42)
    input_data = []
    for i in range(N):
        re = random.randint(-SCALE_IN // 2, SCALE_IN // 2)
        im = random.randint(-SCALE_IN // 2, SCALE_IN // 2)
        input_data.append(complex(re, im))

    # Write input
    with open(os.path.join(data_dir, "input_1024.txt"), "w") as f:
        for v in input_data:
            f.write(f"{int(v.real)} {int(v.imag)}\n")

    # Forward FFT expected output
    # Our FFT core uses bit-reversed input, natural output
    # Let's check: the core likely takes natural input and does bit-reverse internally
    # For now, compute standard FFT (natural input)
    fft_out = fft_radix2(input_data, inverse=False)
    with open(os.path.join(data_dir, "expected_fft_1024.txt"), "w") as f:
        for v in fft_out:
            re, im = quantize_c(v, DOUT_WIDTH)
            f.write(f"{re} {im}\n")

    # Inverse FFT expected output
    ifft_out = ifft_radix2(input_data)
    with open(os.path.join(data_dir, "expected_ifft_1024.txt"), "w") as f:
        for v in ifft_out:
            re, im = quantize_c(v, DOUT_WIDTH)
            f.write(f"{re} {im}\n")

    print(f"Generated FFT test vectors in {data_dir}")
    print(f"  Input: random, range [-{SCALE_IN//2}, {SCALE_IN//2}]")
    print(f"  Output width: {DOUT_WIDTH} bits")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, "..", "tb", "data")
    generate_test(data_dir)
