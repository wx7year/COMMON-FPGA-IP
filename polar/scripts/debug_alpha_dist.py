#!/usr/bin/env python3
"""打印信息位叶子的 alpha 值分布"""
import random, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_verilog_consistent import encode, bhattacharyya_qn, f, g, saturate

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0
info_pos = [q_n[N-K+i] for i in range(K)]

random.seed(42)
info = [random.randint(0,1) for _ in range(K)]
u = [0]*N
for i in range(K):
    u[info_pos[i]] = info[i]
codeword = encode(u, N)
llr = [8 if x == 0 else -8 for x in codeword]

# SC 译码，记录信息位叶子的 alpha
LOG2N = 6
alpha = [[0]*N for _ in range(LOG2N+1)]
u_hat = [0]*N
for i in range(N):
    alpha[0][i] = llr[i]

info_leaf_alphas = []
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
    if not frozen_mask[leaf]:
        expected = u[leaf]
        decided = 0 if a >= 0 else 1
        info_leaf_alphas.append((leaf, a, expected, decided, expected==decided))
        u_hat[leaf] = decided
    else:
        u_hat[leaf] = 0
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

print("Info leaf alphas (leaf, alpha, expected, decided, correct):")
zero_count = 0
err_count = 0
for leaf, a, exp, dec, correct in info_leaf_alphas:
    if a == 0:
        zero_count += 1
    if not correct:
        err_count += 1
    print(f"  leaf={leaf:2d} alpha={a:4d} exp={exp} dec={dec} {'OK' if correct else 'ERR'}")
print(f"\nZero alpha: {zero_count}/{K}")
print(f"Errors: {err_count}/{K}")

# 检查 codeword 左右半关系
left = codeword[:32]
right = codeword[32:]
hamming = sum(1 for i in range(32) if left[i] != right[i])
print(f"\nCodeword left/right hamming distance: {hamming}/32")
print(f"Left weight: {sum(left)}, Right weight: {sum(right)}")
