#!/usr/bin/env python3
"""测试 N=8,16,32,64 全 0/全 1 无噪声"""
import sys
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
    """生成可靠性序列"""
    z = [0.5]*N  # 初始 Z
    for stage in range(N.bit_length()-1):
        half = N >> (stage+1)
        new_z = z[:]
        for i in range(0, N, half*2):
            for j in range(half):
                new_z[i+j] = 2*z[i+j] - z[i+j]**2
                new_z[i+half+j] = z[i+half+j]**2
        z = new_z
    # 按 Z 降序排列（最不可靠在前）
    indices = list(range(N))
    indices.sort(key=lambda i: -z[i])
    return indices

for N in [8, 16, 32, 64]:
    K = N//2
    q_n = bhattacharyya_qn(N)
    frozen_mask = [1]*N
    for i in range(K):
        frozen_mask[q_n[N-K+i]] = 0
    
    for label, info_val in [("all-0", 0), ("all-1", (1<<K)-1)]:
        info = [(info_val >> i) & 1 for i in range(K)]
        u = [0]*N
        for i in range(K):
            u[q_n[N-K+i]] = info[i]
        codeword = encode(u, N)
        llr = [31 if x == 0 else -31 for x in codeword]
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
        # 统计 alpha=0 的信息位数量
        print(f"N={N} K={K} {label}: err={err}/{K} pm={pm}")
