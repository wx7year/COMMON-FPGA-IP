#!/usr/bin/env python3
"""检查 N=8 错误帧"""
import sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_sc_v3 import sc_decode_v3, encode, bhattacharyya_qn

N = 8
K = 4
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

for info_val in range(16):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8 if x == 0 else -8 for x in codeword]
    u_hat = sc_decode_v3(llr, N, frozen_mask)
    dec = [u_hat[q_n[N-K+i]] for i in range(K)]
    err = sum(1 for i in range(K) if dec[i] != info[i])
    if err > 0:
        print(f"info={info} cw={codeword} dec={dec} err={err}")
