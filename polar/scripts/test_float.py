#!/usr/bin/env python3
"""浮点数 LLR 测试（不量化）"""
import random, math, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_verilog_consistent import encode, bhattacharyya_qn, pm_inc

def f_float(a, b):
    return (1 if a >= 0 else -1) * (1 if b >= 0 else -1) * min(abs(a), abs(b))

def g_float(a, b, u):
    return (b + a) if u == 0 else (b - a)

def scl_float(llr, N, frozen_mask, L=4):
    LOG2N = N.bit_length() - 1
    paths = []
    for _ in range(L):
        alpha = [[0.0]*N for _ in range(LOG2N+1)]
        for i in range(N):
            alpha[0][i] = llr[i]
        paths.append({'alpha': alpha, 'u_hat': [0]*N, 'pm': 0.0})
    
    for leaf in range(N):
        for p in paths:
            for stage in range(LOG2N):
                block_size = N >> stage
                half = block_size >> 1
                block_start = leaf - (leaf % block_size)
                if (leaf % block_size) < half:
                    for ji in range(half):
                        p['alpha'][stage+1][block_start+ji] = f_float(
                            p['alpha'][stage][block_start+ji],
                            p['alpha'][stage][block_start+half+ji]
                        )
        is_frozen = frozen_mask[leaf]
        if is_frozen:
            for p in paths:
                p['u_hat'][leaf] = 0
                p['pm'] += max(0.0, -p['alpha'][LOG2N][leaf])
        else:
            candidates = []
            for p in paths:
                a = p['alpha'][LOG2N][leaf]
                for u in [0, 1]:
                    candidates.append({
                        'alpha': [row[:] for row in p['alpha']],
                        'u_hat': p['u_hat'][:],
                        'pm': p['pm'] + max(0.0, (2*u-1)*a),
                        'u': u
                    })
            candidates.sort(key=lambda c: c['pm'])
            new_paths = []
            for i in range(L):
                c = candidates[i]
                c['u_hat'][leaf] = c['u']
                new_paths.append({'alpha': c['alpha'], 'u_hat': c['u_hat'], 'pm': c['pm']})
            paths = new_paths
        for p in paths:
            for stage in range(LOG2N-1, -1, -1):
                block_size = N >> stage
                half = block_size >> 1
                block_start = leaf - (leaf % block_size)
                offset = (leaf % block_size) % half
                uhat_idx = block_start + offset
                p['alpha'][stage+1][block_start+half+offset] = g_float(
                    p['alpha'][stage][block_start+offset],
                    p['alpha'][stage][block_start+half+offset],
                    p['u_hat'][uhat_idx]
                )
    best = min(paths, key=lambda p: p['pm'])
    return best['u_hat'], best['pm']

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

# 无噪声浮点数
random.seed(42)
total_err = 0
for frame in range(50):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [1e6 if x == 0 else -1e6 for x in codeword]  # 极大 LLR 模拟完美信道
    u_hat, pm = scl_float(llr, N, frozen_mask, L=4)
    total_err += sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
print(f"Float noiseless (LLR=±1e6): BER={total_err/(50*K):.4f}")

# 无噪声有限 LLR=±8
random.seed(42)
total_err = 0
for frame in range(50):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8.0 if x == 0 else -8.0 for x in codeword]
    u_hat, pm = scl_float(llr, N, frozen_mask, L=4)
    total_err += sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
print(f"Float noiseless (LLR=±8): BER={total_err/(50*K):.4f}")

# AWGN 浮点数 sigma=0.5
random.seed(42)
total_err = 0
for frame in range(50):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = []
    for i in range(N):
        x = -1.0 if codeword[i] else 1.0
        y = x + random.gauss(0, 0.5)
        llr.append(y * (2.0 / (0.5*0.5)))
    u_hat, pm = scl_float(llr, N, frozen_mask, L=4)
    total_err += sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
print(f"Float AWGN sigma=0.5: BER={total_err/(50*K):.4f}")
