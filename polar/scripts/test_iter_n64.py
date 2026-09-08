#!/usr/bin/env python3
"""Test iterative SC decoder with N=64, matching RTL Q_N sequence"""
import random

def f(a, b):
    sa = 1 if a >= 0 else -1
    sb = 1 if b >= 0 else -1
    return sa * sb * min(abs(a), abs(b))

def g(a, b, u):
    return b + a if u == 0 else b - a

def encode(u, n):
    x = list(u)
    stage = 0
    while (1 << stage) < n:
        half = 1 << stage
        for i in range(0, n, 2*half):
            for j in range(half):
                x[i+j] = x[i+j] ^ x[i+j+half]
        stage += 1
    return x

def sc_decode_iterative(llr, n, frozen_set):
    logn = n.bit_length() - 1
    alpha = [[0.0]*n for _ in range(logn+1)]
    alpha[0] = list(llr)
    u_hat = [0]*n

    for leaf_idx in range(n):
        # S_FORWARD
        stage = 0
        while stage < logn:
            half = n >> (stage + 1)
            block_size = n >> stage
            block_start = leaf_idx - (leaf_idx % block_size)
            if (leaf_idx % block_size) < half:
                for ji in range(half):
                    alpha[stage+1][block_start+ji] = f(
                        alpha[stage][block_start+ji],
                        alpha[stage][block_start+ji+half]
                    )
            stage += 1

        # S_DECISION
        if leaf_idx in frozen_set:
            u_hat[leaf_idx] = 0
        else:
            u_hat[leaf_idx] = 0 if alpha[logn][leaf_idx] >= 0 else 1

        # S_BACKWARD
        stage = logn - 1
        while stage >= 0:
            half = n >> (stage + 1)
            block_size = n >> stage
            block_start = leaf_idx - (leaf_idx % block_size)
            if leaf_idx == block_start + half - 1:
                for offset in range(half):
                    u_partial = 0
                    for ji in range(half):
                        if (ji & offset) == offset:
                            u_partial ^= u_hat[block_start+ji]
                    alpha[stage+1][block_start+half+offset] = g(
                        alpha[stage][block_start+offset],
                        alpha[stage][block_start+half+offset],
                        u_partial
                    )
            stage -= 1

    return u_hat

# Q_N sequence from q_n_64.vh
Q_N = [0,1,2,4,8,16,3,32,5,6,9,10,12,17,18,20,33,7,34,24,11,36,13,19,14,40,21,22,35,48,25,37,26,38,15,28,41,42,23,49,44,50,27,52,39,29,56,30,43,45,46,51,53,54,57,58,31,60,47,55,59,61,62,63]

N = 64
K = 32
K_TOTAL = 48  # K + CRC_LEN
frozen = set(Q_N[:N-K_TOTAL])  # first 16
info_positions = Q_N[N-K_TOTAL:N-K_TOTAL+K]  # next 32 (info only, not CRC)

print(f"Frozen positions: {sorted(frozen)}")
print(f"Info positions: {info_positions}")

random.seed(42)
sigma = 0.5
errors = 0
total = 0
for trial in range(100):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i, pos in enumerate(info_positions):
        u[pos] = info[i]
    # CRC positions (simplified: set to 0 for this test)
    codeword = encode(u, N)
    llr = []
    for c in codeword:
        x = -1.0 if c else 1.0
        y = x + random.gauss(0, sigma)
        llr.append(y * (2.0 / (sigma*sigma)))
    u_dec = sc_decode_iterative(llr, N, frozen)
    for i, pos in enumerate(info_positions):
        if u_dec[pos] != info[i]:
            errors += 1
        total += 1

print(f"N=64 K=32: errors={errors}/{total}, BER={errors/total}")
