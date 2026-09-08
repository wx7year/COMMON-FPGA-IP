#!/usr/bin/env python3
"""递归版本浮点数测试"""
import random, math, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_recursive_sc import sc_decode_recursive, encode, bhattacharyya_qn

N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

# 浮点数 ±1e6（完美信道）
random.seed(42)
total_err = 0
for frame in range(50):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [1e6 if x == 0 else -1e6 for x in codeword]
    u_hat = sc_decode_recursive(llr, N, frozen_mask)
    err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
    total_err += err
print(f"Recursive float ±1e6: BER={total_err/(50*K):.4f}")

# 浮点数 ±8
random.seed(42)
total_err = 0
for frame in range(50):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8.0 if x == 0 else -8.0 for x in codeword]
    u_hat = sc_decode_recursive(llr, N, frozen_mask)
    err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
    total_err += err
print(f"Recursive float ±8: BER={total_err/(50*K):.4f}")

# 检查 N=8 info=[1,1,0,0] 的 right_alpha
N = 8
K = 4
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

info = [1,1,0,0]
u = [0]*N
for i in range(K):
    u[q_n[N-K+i]] = info[i]
codeword = encode(u, N)
llr = [1e6 if x == 0 else -1e6 for x in codeword]
print(f"\nN=8 info={info} cw={codeword}")
print(f"llr={llr}")

# 手动计算 right_alpha
from test_recursive_sc import f, g
left_alpha = [f(llr[i], llr[i+4]) for i in range(4)]
print(f"left_alpha={left_alpha}")
# 左子树判决后 u_hat[0..3]
u_hat_left = [0,0,0,1]  # 冻结位 0,0,0，信息位 1
right_alpha = [g(llr[i], llr[i+4], u_hat_left[i]) for i in range(4)]
print(f"right_alpha={right_alpha}")
