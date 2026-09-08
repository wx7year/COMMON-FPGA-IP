#!/usr/bin/env python3
"""测试 N=8 随机信息位无噪声，打印第一个错误帧"""
import random
import sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from ref_scl_decode import scl_decode, f, g, saturate, pm_inc

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
    z = [0.5]*N
    for stage in range(N.bit_length()-1):
        half = N >> (stage+1)
        new_z = z[:]
        for i in range(0, N, half*2):
            for j in range(half):
                new_z[i+j] = 2*z[i+j] - z[i+j]**2
                new_z[i+half+j] = z[i+half+j]**2
        z = new_z
    indices = list(range(N))
    indices.sort(key=lambda i: -z[i])
    return indices

def sc_decode_debug(llr, N, frozen_mask, u_expected):
    """SC 译码，打印每个叶子的 alpha"""
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
        if u_hat[leaf] != u_expected[leaf]:
            print(f"  MISMATCH leaf={leaf} alpha={a} u={u_hat[leaf]} expected={u_expected[leaf]} frozen={frozen_mask[leaf]}")
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

N = 8
K = 4
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

random.seed(42)
for frame in range(20):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8 if x == 0 else -8 for x in codeword]
    u_hat = sc_decode_debug(llr, N, frozen_mask, u)
    err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
    if err > 0:
        print(f"Frame {frame}: info={info} codeword={codeword} err={err}/{K}")
        print(f"  u_expected={u}")
        print(f"  u_hat     ={u_hat}")
        break
