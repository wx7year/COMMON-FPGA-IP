#!/usr/bin/env python3
"""
LDPC 基矩阵生成脚本
生成 .mem 格式的基矩阵文件，供 RTL ($readmemh) 和 C model 使用

5G NR LDPC 基矩阵（3GPP TS 38.212 Table 5.3.2-1/2）：
  BG1: 4行 × 26列，信息位22列，校验位4列
  BG2: 4行 × 14列，信息位10列，校验位4列

每个元素：
  -1 (511) = 零矩阵
  0..383  = ZC×ZC 循环移位矩阵的右移量

注意：本脚本提供一个简化的测试基矩阵（4×8）用于功能验证。
真实 5G NR 基矩阵值请从 38.212 标准填入 bg1_matrix / bg2_matrix。
"""

import argparse
import os

# 简化测试基矩阵：4行 × 8列，信息位4列 + 校验位4列
# 校验位部分采用下三角结构，每行连接到对应的校验位
TEST_BG = [
    [0,    1,    2,    3,    0,    511,  511,  511],  # row0: info + p0
    [1,    2,    3,    0,    1,    0,    511,  511],  # row1: info + p0->p1
    [2,    3,    0,    1,    511,  1,    0,    511],  # row2: info + p1->p2
    [3,    0,    1,    2,    511,  511,  1,    0  ],  # row3: info + p2->p3
]

# 5G NR BG1 (4×26) - 占位，需从 38.212 填入准确值
# 格式：每行26个元素，-1表示零矩阵
BG1 = None  # 待填入

# 5G NR BG2 (4×14) - 占位
BG2 = None  # 待填入


def write_mem(matrix, path):
    """写 .mem 文件：每行一个十六进制数，行优先"""
    rows = len(matrix)
    cols = len(matrix[0])
    with open(path, 'w') as f:
        for r in range(rows):
            for c in range(cols):
                val = matrix[r][c]
                if val < 0:
                    val = 511  # -1 表示零矩阵
                f.write(f"{val:03x}\n")
    print(f"Written {rows}×{cols} = {rows*cols} entries to {path}")


def main():
    parser = argparse.ArgumentParser(description='LDPC base graph generator')
    parser.add_argument('--bg', type=int, choices=[0, 1, 2], default=0,
                        help='0=test(4x8), 1=BG1(4x26), 2=BG2(4x14)')
    parser.add_argument('--out', type=str, default='../rtl/ldpc_bg_test.mem',
                        help='Output .mem file')
    args = parser.parse_args()

    if args.bg == 0:
        matrix = TEST_BG
    elif args.bg == 1:
        if BG1 is None:
            print("WARNING: BG1 values not filled. Using test matrix.")
            print("Please fill bg1_matrix with values from 3GPP 38.212 Table 5.3.2-1")
            matrix = TEST_BG
        else:
            matrix = BG1
    else:
        if BG2 is None:
            print("WARNING: BG2 values not filled. Using test matrix.")
            matrix = TEST_BG
        else:
            matrix = BG2

    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    write_mem(matrix, args.out)

    # 打印基矩阵供检查
    print("\nBase graph:")
    for r, row in enumerate(matrix):
        vals = [f"{v:4d}" if v >= 0 else "  -1" for v in row]
        print(f"  row{r}: {' '.join(vals)}")


if __name__ == '__main__':
    main()
