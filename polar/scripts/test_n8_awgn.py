#!/usr/bin/env python3
"""N=8 AWGN 测试"""
import random, math, sys
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

for sigma in [0.3, 0.5, 0.8]:
    random.seed(42)
    total_err = 0
    num_frames = 500
    for frame in range(num_frames):
        info = [random.randint(0,1) for _ in range(K)]
        u = [0]*N
        for i in range(K):
            u[q_n[N-K+i]] = info[i]
        codeword = encode(u, N)
        llr = []
        for i in range(N):
            x = -1.0 if codeword[i] else 1.0
            y = x + random.gauss(0, sigma)
            llr_real = y * (2.0 / (sigma*sigma))
            llr_int = max(-32, min(31, int(llr_real)))
            llr.append(llr_int)
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
        total_err += err
    print(f"N=8 sigma={sigma} BER={total_err/(num_frames*K):.4f}")
