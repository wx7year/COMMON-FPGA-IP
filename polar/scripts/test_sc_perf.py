#!/usr/bin/env python3
"""修复后 SC 的详细性能测试"""
import random, math, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_sc_v3 import sc_decode_v3, encode, bhattacharyya_qn

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

# 不同 sigma，更多帧数
for sigma in [0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0]:
    random.seed(42)
    total_err = 0
    num_frames = 100
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
        u_hat = sc_decode_v3(llr, N, frozen_mask)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
        total_err += err
    ebno = 10*math.log10(1.0/(sigma*sigma)) - 10*math.log10(K/N)
    print(f"sigma={sigma:.1f} Eb/N0={ebno:.1f}dB BER={total_err/(num_frames*K):.4f}")

# 无噪声，不同 LLR 幅度
print("\nNoiseless, different LLR magnitude:")
for mag in [1, 2, 4, 8, 16, 31]:
    random.seed(42)
    total_err = 0
    num_frames = 100
    for frame in range(num_frames):
        info = [random.randint(0,1) for _ in range(K)]
        u = [0]*N
        for i in range(K):
            u[q_n[N-K+i]] = info[i]
        codeword = encode(u, N)
        llr = [mag if x == 0 else -mag for x in codeword]
        u_hat = sc_decode_v3(llr, N, frozen_mask)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
        total_err += err
    print(f"  mag={mag:2d}: BER={total_err/(num_frames*K):.4f}")
