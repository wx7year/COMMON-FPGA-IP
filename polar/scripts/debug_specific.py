#!/usr/bin/env python3
"""调试 info=[1,0,0,0]"""
import sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_verilog_consistent import encode, scl_decode, bhattacharyya_qn, f, g, saturate

N = 8
K = 4
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

info = [1,0,0,0]
u = [0]*N
for i in range(K):
    u[q_n[N-K+i]] = info[i]
print(f"u: {u}")
codeword = encode(u, N)
print(f"codeword: {codeword}")
llr = [8 if x == 0 else -8 for x in codeword]
print(f"llr: {llr}")

# SC 译码（单路径），打印每个叶子
LOG2N = 3
alpha = [[0]*N for _ in range(LOG2N+1)]
u_hat = [0]*N
for i in range(N):
    alpha[0][i] = llr[i]

for leaf in range(N):
    for stage in range(LOG2N):
        block_size = N >> stage
        half = block_size >> 1
        block_start = leaf - (leaf % block_size)
        if (leaf % block_size) < half:
            for ji in range(half):
                alpha[stage+1][block_start+ji] = saturate(f(
                    alpha[stage][block_start+ji],
                    alpha[stage][block_start+half+ji]
                ))
    a = alpha[LOG2N][leaf]
    if frozen_mask[leaf]:
        u_hat[leaf] = 0
    else:
        u_hat[leaf] = 0 if a >= 0 else 1
    print(f"leaf={leaf} alpha={a:3d} frozen={frozen_mask[leaf]} u={u_hat[leaf]} expected={u[leaf]}")
    for stage in range(LOG2N-1, -1, -1):
        block_size = N >> stage
        half = block_size >> 1
        block_start = leaf - (leaf % block_size)
        offset = (leaf % block_size) % half
        uhat_idx = block_start + offset
        alpha[stage+1][block_start+half+offset] = saturate(g(
            alpha[stage][block_start+offset],
            alpha[stage][block_start+half+offset],
            u_hat[uhat_idx]
        ))

print(f"\nu_hat: {u_hat}")
dec_info = [u_hat[q_n[N-K+i]] for i in range(K)]
print(f"dec_info: {dec_info}")
print(f"info: {info}")
err = sum(1 for i in range(K) if dec_info[i] != info[i])
print(f"err: {err}")
