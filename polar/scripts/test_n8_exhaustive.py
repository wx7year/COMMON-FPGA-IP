#!/usr/bin/env python3
"""N=8 穷举所有信息位组合"""
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

N = 8
K = 4
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0
print(f"Q_N: {q_n}, info positions: {q_n[N-K:]}")

total_err = 0
for info_val in range(16):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [1 if x == 0 else -1 for x in codeword]
    u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
    dec_info = [u_hat[q_n[N-K+i]] for i in range(K)]
    err = sum(1 for i in range(K) if dec_info[i] != info[i])
    total_err += err
    if err > 0:
        print(f"info={info} codeword={codeword} dec={dec_info} err={err} pm={pm}")

print(f"\nTotal: {total_err}/{16*K} = {total_err/(16*K):.4f}")
