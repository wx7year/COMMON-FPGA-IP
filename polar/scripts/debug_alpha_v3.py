#!/usr/bin/env python3
"""修复后版本的 alpha 分布检查"""
import random, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_sc_v3 import encode, bhattacharyya_qn, f, g, saturate, update_partial

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

# 无噪声
llr = [8 if x == 0 else -8 for x in codeword]

LOG2N = 6
alpha = [[0]*N for _ in range(LOG2N+1)]
u_hat = [[0]*N for _ in range(LOG2N+1)]
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
    if frozen_mask[leaf]:
        u_hat[LOG2N][leaf] = 0
    else:
        u_hat[LOG2N][leaf] = 0 if a >= 0 else 1
    update_partial(u_hat, N)
    for stage in range(LOG2N-1, -1, -1):
        block_size = N >> stage
        half = block_size >> 1
        block_start = leaf - (leaf % block_size)
        if leaf == block_start + half - 1:
            for offset in range(half):
                alpha[stage+1][block_start+half+offset] = saturate(g(
                    alpha[stage][block_start+offset],
                    alpha[stage][block_start+half+offset],
                    u_hat[stage+1][block_start+offset]
                ))
    if not frozen_mask[leaf]:
        info_leaf_alphas.append((leaf, a, u[leaf], u_hat[LOG2N][leaf]))

zero_count = sum(1 for _,a,_,_ in info_leaf_alphas if a == 0)
err_count = sum(1 for _,a,exp,dec in info_leaf_alphas if exp != dec)
print(f"Info leaves: {len(info_leaf_alphas)}, zero alpha: {zero_count}, errors: {err_count}")
print("\nLeaf alpha values (first 20):")
for leaf, a, exp, dec in info_leaf_alphas[:20]:
    print(f"  leaf={leaf:2d} alpha={a:4d} exp={exp} dec={dec} {'OK' if exp==dec else 'ERR'}")
