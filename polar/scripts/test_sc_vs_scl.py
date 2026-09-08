#!/usr/bin/env python3
"""测试 SC (L=1) 和 SCL (L=4) 的对比"""
import random, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_verilog_consistent import encode, bhattacharyya_qn, f, g, saturate, pm_inc

def sc_decode(llr, N, frozen_mask):
    """单路径 SC 译码"""
    LOG2N = N.bit_length() - 1
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
    return u_hat

def scl_decode(llr, N, frozen_mask, L=4):
    from test_verilog_consistent import scl_decode as scl
    return scl(llr, N, frozen_mask, L)

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

# 全 1 无噪声
u = [0]*N
for i in range(K):
    u[q_n[N-K+i]] = 1
codeword = encode(u, N)
llr = [8 if x == 0 else -8 for x in codeword]

u_sc = sc_decode(llr, N, frozen_mask)
u_scl, pm = scl_decode(llr, N, frozen_mask, L=4)

err_sc = sum(1 for i in range(K) if u_sc[q_n[N-K+i]] != 1)
err_scl = sum(1 for i in range(K) if u_scl[q_n[N-K+i]] != 1)
print(f"all-one noiseless: SC err={err_sc}/{K}, SCL err={err_scl}/{K}")

# 全 1 有噪声
for sigma in [0.3, 0.5]:
    random.seed(42)
    total_sc = 0
    total_scl = 0
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
        u_sc = sc_decode(llr, N, frozen_mask)
        u_scl, pm = scl_decode(llr, N, frozen_mask, L=4)
        total_sc += sum(1 for i in range(K) if u_sc[q_n[N-K+i]] != 1)
        total_scl += sum(1 for i in range(K) if u_scl[q_n[N-K+i]] != 1)
    print(f"all-one sigma={sigma}: SC err={total_sc}/{num_frames*K}, SCL err={total_scl}/{num_frames*K}")
