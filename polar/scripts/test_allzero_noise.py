#!/usr/bin/env python3
"""测试全 0 信息位有噪声"""
import random, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_verilog_consistent import encode, scl_decode, bhattacharyya_qn

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

for sigma in [0.3, 0.5, 0.8]:
    random.seed(42)
    total_err = 0
    num_frames = 20
    for frame in range(num_frames):
        u = [0]*N  # 全 0
        codeword = encode(u, N)
        llr = []
        for i in range(N):
            x = -1.0 if codeword[i] else 1.0
            y = x + random.gauss(0, sigma)
            llr_real = y * (2.0 / (sigma*sigma))
            llr_int = max(-32, min(31, int(llr_real)))
            llr.append(llr_int)
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != 0)
        total_err += err
    print(f"all-zero sigma={sigma}: err={total_err}/{num_frames*K}")

# 全 1 信息位有噪声
for sigma in [0.3, 0.5]:
    random.seed(42)
    total_err = 0
    num_frames = 20
    for frame in range(num_frames):
        u = [0]*N
        for i in range(K):
            u[q_n[N-K+i]] = 1
        codeword = encode(u, N)
        llr = []
        for i in range(N):
            x = -1.0 if codeword[i] else 1.0
            y = x + random.gauss(0, sigma)
            llr_real = y * (2.0 / (sigma*sigma))
            llr_int = max(-32, min(31, int(llr_real)))
            llr.append(llr_int)
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != 1)
        total_err += err
    print(f"all-one sigma={sigma}: err={total_err}/{num_frames*K}")
