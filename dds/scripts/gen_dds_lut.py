#!/usr/bin/env python3
"""
Generate DDS sin/cos LUT memory file.
Full period LUT, 16-bit signed output.
"""
import math
import os

LUT_DEPTH = 1024
OUTPUT_WIDTH = 16
SCALE = (1 << (OUTPUT_WIDTH - 1)) - 1  # 32767

def generate_lut(output_path):
    with open(output_path, 'w') as f:
        for i in range(LUT_DEPTH):
            phase = 2.0 * math.pi * i / LUT_DEPTH
            sin_val = int(round(math.sin(phase) * SCALE))
            cos_val = int(round(math.cos(phase) * SCALE))
            # 格式：{cos, sin} 拼接，每个 OUTPUT_WIDTH 位
            combined = ((cos_val & ((1 << OUTPUT_WIDTH) - 1)) << OUTPUT_WIDTH) | (sin_val & ((1 << OUTPUT_WIDTH) - 1))
            f.write(f"{combined:08x}\n")
    print(f"Generated {output_path}: {LUT_DEPTH} entries, {OUTPUT_WIDTH}x2 bit")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "..", "rtl", "dds_sin_cos_lut.mem")
    generate_lut(output_path)
