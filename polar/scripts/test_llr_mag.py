#!/usr/bin/env python3
"""测试不同 LLR 幅度下全 1 的性能"""
import sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from ref_scl_decode import scl_decode

def encode(u, N):
    codeword = u[:]
    for stage in range(N.bit_length()-1):
        half = N >> (stage+1)
        temp = codeword[:]
        for i in range(N):
            if i % (half*2) < half:
                temp[i] = codeword[i] ^ codeword[i+half]
        codeword = temp
    return codeword

def bhattacharyya_qn(N):
    z = [0.5]*N
    for stage in range(N.bit_length()-1):
        half = N >> (stage+1)
        new_z = z[:]
        for i in range(0, N, half*2):
            for j in range(half):
                new_z[i+j] = 2*z[i+j] - z[i+j]**2
                new_z[i+half+j] = z[i+half+j]**2
        z = new_z
    indices = list(range(N))
    indices.sort(key=lambda i: -z[i])
    return indices

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

info = [(1 << K) - 1]  # all 1
u = [0]*N
for i in range(K):
    u[q_n[N-K+i]] = 1
codeword = encode(u, N)

for llr_mag in [1, 2, 4, 8, 16, 31]:
    llr = [llr_mag if x == 0 else -llr_mag for x in codeword]
    u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
    err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != 1)
    print(f"LLR mag={llr_mag:2d}: err={err:2d}/{K} pm={pm}")
