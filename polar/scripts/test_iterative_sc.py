#!/usr/bin/env python3
"""
Python iterative SC decoder matching RTL state machine exactly.
Used to verify RTL algorithm.
"""
import random

def f(a, b):
    sa = 1 if a >= 0 else -1
    sb = 1 if b >= 0 else -1
    return sa * sb * min(abs(a), abs(b))

def g(a, b, u):
    return b + a if u == 0 else b - a

def encode(u, n):
    """F=[[1,1],[0,1]]: left=left^right, right unchanged"""
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
    """Iterative SC decoder matching RTL"""
    logn = n.bit_length() - 1
    # alpha[stage][idx]
    alpha = [[0.0]*n for _ in range(logn+1)]
    alpha[0] = list(llr)
    u_hat = [0]*n

    leaf_idx = 0
    while leaf_idx < n:
        # S_FORWARD: compute f from stage 0 to logn-1
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

        # S_BACKWARD: compute g from stage logn-1 down to 0
        stage = logn - 1
        while stage >= 0:
            half = n >> (stage + 1)
            block_size = n >> stage
            block_start = leaf_idx - (leaf_idx % block_size)
            if leaf_idx == block_start + half - 1:
                for offset in range(half):
                    # partial decision: encode(u_hat[block_start:block_start+half], half)
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

        leaf_idx += 1

    return u_hat

# Test N=4
random.seed(42)
N = 4
K = 1
frozen = {0, 1, 2}  # Q_N for N=4: [0,1,2,3], info at 3

errors = 0
for trial in range(1000):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    u[3] = info[0]  # info at Q_N[3]=3
    codeword = encode(u, N)
    # BPSK + AWGN
    sigma = 0.5
    llr = []
    for c in codeword:
        x = -1.0 if c else 1.0
        y = x + random.gauss(0, sigma)
        llr.append(y * (2.0 / (sigma*sigma)))
    u_dec = sc_decode_iterative(llr, N, frozen)
    if u_dec[3] != info[0]:
        errors += 1

print(f"N=4 K=1: errors={errors}/1000, BER={errors/1000}")

# Test N=8
N = 8
K = 4
# Q_N for N=8 (Bhattacharyya): [0,1,2,4,3,5,6,7]
# frozen = first N-K = 4: {0,1,2,4}
frozen = {0, 1, 2, 4}
info_positions = [3, 5, 6, 7]

errors = 0
for trial in range(1000):
    info = [random.randint(0,1) for _ in range(K)]
    u = [0]*N
    for i, pos in enumerate(info_positions):
        u[pos] = info[i]
    codeword = encode(u, N)
    sigma = 0.5
    llr = []
    for c in codeword:
        x = -1.0 if c else 1.0
        y = x + random.gauss(0, sigma)
        llr.append(y * (2.0 / (sigma*sigma)))
    u_dec = sc_decode_iterative(llr, N, frozen)
    for i, pos in enumerate(info_positions):
        if u_dec[pos] != info[i]:
            errors += 1

print(f"N=8 K=4: errors={errors}/4000, BER={errors/4000}")
