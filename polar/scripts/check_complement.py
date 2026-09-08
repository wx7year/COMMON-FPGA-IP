#!/usr/bin/env python3
"""统计 N=8 codeword 左右半关系"""
def encode(u, N):
    codeword = u[:]
    for stage in range(N.bit_length()-1):
        half = 1 << stage
        temp = codeword[:]
        for i in range(N):
            if i % (half*2) < half:
                temp[i] = codeword[i] ^ codeword[i+half]
        codeword = temp
    return codeword

N = 8
K = 4
q_n = [0,1,2,4,3,5,6,7]
info_pos = q_n[N-K:]  # [3,5,6,7]

complement_count = 0
for info_val in range(16):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[info_pos[i]] = info[i]
    codeword = encode(u, N)
    left = codeword[:4]
    right = codeword[4:]
    is_complement = all(left[i] == 1-right[i] for i in range(4))
    is_equal = all(left[i] == right[i] for i in range(4))
    if is_complement:
        complement_count += 1
        print(f"info={info} cw={codeword} LEFT~RIGHT")
    elif is_equal:
        print(f"info={info} cw={codeword} LEFT==RIGHT")

print(f"\nComplement: {complement_count}/16")
