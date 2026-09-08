#!/usr/bin/env python3
"""Compare RTL vs Python iterative SC with exact same LLR"""

def f(a, b):
    sa = 1 if a >= 0 else -1
    sb = 1 if b >= 0 else -1
    return sa * sb * min(abs(a), abs(b))

def g(a, b, u):
    return b + a if u == 0 else b - a

def sc_decode_iterative(llr, n, frozen_set):
    logn = n.bit_length() - 1
    alpha = [[0]*n for _ in range(logn+1)]
    alpha[0] = list(llr)
    u_hat = [0]*n

    for leaf_idx in range(n):
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

        if leaf_idx in frozen_set:
            u_hat[leaf_idx] = 0
        else:
            u_hat[leaf_idx] = 0 if alpha[logn][leaf_idx] >= 0 else 1

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

Q_N = [0,1,2,4,8,16,3,32,5,6,9,10,12,17,18,20,33,7,34,24,11,36,13,19,14,40,21,22,35,48,25,37,26,38,15,28,41,42,23,49,44,50,27,52,39,29,56,30,43,45,46,51,53,54,57,58,31,60,47,55,59,61,62,63]

N = 64
K = 32
K_TOTAL = 48
frozen = set(Q_N[:N-K_TOTAL])
info_positions = Q_N[N-K_TOTAL:N-K_TOTAL+K]

# Exact LLR from RTL
llr = [8,8,-7,8,-10,4,8,-8,7,-2,-10,-11,6,-8,-8,12,-11,11,8,-8,7,7,12,-7,-3,3,10,-3,8,-5,4,16,7,-3,12,6,10,8,-8,12,5,-5,9,3,-11,1,13,8,-5,-13,5,-12,5,-6,-7,-5,-7,-7,-4,-5,-5,5,9,4]

# info from RTL
info = [0,1,0,1,1,1,0,0,1,0,0,1,1,1,1,1,0,0,1,0,1,1,1,1,0,0,0,1,1,1,1,1]

u_dec = sc_decode_iterative(llr, N, frozen)

print("Python decoded info:")
dec_info = []
for i, pos in enumerate(info_positions):
    dec_info.append(u_dec[pos])
print(f"  dec = {''.join(str(b) for b in dec_info)}")
print(f"  info= {''.join(str(b) for b in info)}")

errors = sum(1 for a,b in zip(dec_info, info) if a != b)
print(f"  errors={errors}/{K}")

# Print per-leaf u_hat for info positions
print("\nPer-position comparison:")
for i, pos in enumerate(info_positions):
    if u_dec[pos] != info[i]:
        print(f"  pos={pos} (info[{i}]): info={info[i]} dec={u_dec[pos]} alpha[6]={u_dec[pos]}")
