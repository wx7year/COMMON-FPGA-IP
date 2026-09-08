#!/usr/bin/env python3
"""快速验证 N=4 SCL"""
import sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from ref_scl_decode import scl_decode, f, g, saturate, pm_inc

def encode(u, N):
    """F=[[1,1],[0,1]] 跨步合并，先外层再内层"""
    codeword = u[:]
    for stage in range(N.bit_length()-1):
        half = N >> (stage+1)
        temp = codeword[:]
        for i in range(N):
            if i % (half*2) < half:
                temp[i] = codeword[i] ^ codeword[i+half]
        codeword = temp
    return codeword

N = 4
K = 2
# Q_N for N=4 (Bhattacharyya): [0,1,2,3], 信息位 Q_N[2..3]=[2,3]
q_n = [0,1,2,3]
frozen_mask = [1,1,0,0]

errors = 0
total = 0
for info_val in range(4):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [31 if x == 0 else -31 for x in codeword]
    u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
    dec_info = [u_hat[q_n[N-K+i]] for i in range(K)]
    err = sum(1 for i in range(K) if dec_info[i] != info[i])
    errors += err
    total += K
    print(f"info={info} codeword={codeword} dec={dec_info} err={err} pm={pm}")

print(f"\nTotal: {errors}/{total}")
