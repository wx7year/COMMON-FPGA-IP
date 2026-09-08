#!/usr/bin/env python3
"""Generate FIR expected output by convolving input with coefficients."""
import os

# 31 taps, from fir_coeff_31.vh (h[0] to h[30])
COEFFS = [
    0, 22, 51, 77, 72, 0, -150, -339, -463, -387, 0,
    721, 1674, 2643, 3368, 18187, 3368, 2643, 1674, 721, 0,
    -387, -463, -339, -150, 0, 72, 77, 51, 22, 0
]

def fir_filter(input_data):
    """Direct-form FIR filter."""
    n_taps = len(COEFFS)
    result = []
    for i in range(len(input_data)):
        acc = 0
        for j in range(n_taps):
            if i - j >= 0:
                acc += input_data[i - j] * COEFFS[j]
        result.append(acc)
    return result

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, "..", "tb", "data")

    for name in ["impulse", "random"]:
        infile = os.path.join(data_dir, f"{name}_input.txt")
        outfile = os.path.join(data_dir, f"{name}_expected.txt")

        with open(infile) as f:
            input_data = [int(line.strip()) for line in f if line.strip()]

        output = fir_filter(input_data)

        with open(outfile, "w") as f:
            for v in output:
                f.write(f"{v}\n")

        print(f"Generated {name} expected output: {len(output)} samples")
        print(f"  First 5: {output[:5]}")

if __name__ == "__main__":
    main()
