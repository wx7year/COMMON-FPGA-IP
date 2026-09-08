#!/usr/bin/env python3
"""修复版 SC/SCL：使用部分判决数组"""
import random, math

def f(a, b):
    return (1 if a >= 0 else -1) * (1 if b >= 0 else -1) * min(abs(a), abs(b))

def g(a, b, u):
    return (b + a) if u == 0 else (b - a)

def saturate(v, bits=6):
    mx = (1 << (bits-1)) - 1
    mn = -(1 << (bits-1))
    return max(mn, min(mx, v))

def encode(u, N):
    codeword = u[:]
    for stage in range(N.bit_length()-1):
        half = 1 << stage
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

def sc_decode_fixed(llr, N, frozen_mask):
    """修复版 SC：使用部分判决数组"""
    LOG2N = N.bit_length() - 1
    alpha = [[0]*N for _ in range(LOG2N+1)]
    # u_hat[stage][i]: stage 层的部分判决
    u_hat = [[0]*N for _ in range(LOG2N+1)]
    for i in range(N):
        alpha[0][i] = llr[i]
    
    for leaf in range(N):
        # S_FORWARD
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
        # 判决
        a = alpha[LOG2N][leaf]
        if frozen_mask[leaf]:
            u_hat[LOG2N][leaf] = 0
        else:
            u_hat[LOG2N][leaf] = 0 if a >= 0 else 1
        
        # S_BACKWARD：从最内层到最外层计算部分判决
        for stage in range(LOG2N-1, -1, -1):
            block_size = N >> stage
            half = block_size >> 1
            block_start = leaf - (leaf % block_size)
            offset = (leaf % block_size) % half
            # 计算当前层的部分判决
            # u_hat[stage][left] = u_hat[stage+1][left] ^ u_hat[stage+1][right]
            # u_hat[stage][right] = u_hat[stage+1][right]
            left_idx = block_start + offset
            right_idx = block_start + half + offset
            u_hat[stage][left_idx] = u_hat[stage+1][left_idx] ^ u_hat[stage+1][right_idx]
            u_hat[stage][right_idx] = u_hat[stage+1][right_idx]
            # g 函数使用 u_hat[stage+1][left_idx]（当前层的左半部分判决）
            alpha[stage+1][right_idx] = saturate(g(
                alpha[stage][left_idx],
                alpha[stage][right_idx],
                u_hat[stage+1][left_idx]
            ))
    return u_hat[LOG2N]

# N=4 验证
N = 4
K = 2
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0
print("N=4:")
for info_val in range(4):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8 if x == 0 else -8 for x in codeword]
    u_hat = sc_decode_fixed(llr, N, frozen_mask)
    dec = [u_hat[q_n[N-K+i]] for i in range(K)]
    err = sum(1 for i in range(K) if dec[i] != info[i])
    print(f"  info={info} cw={codeword} dec={dec} err={err}")

# N=8 穷举
N = 8
K = 4
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0
total_err = 0
for info_val in range(16):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8 if x == 0 else -8 for x in codeword]
    u_hat = sc_decode_fixed(llr, N, frozen_mask)
    dec = [u_hat[q_n[N-K+i]] for i in range(K)]
    err = sum(1 for i in range(K) if dec[i] != info[i])
    total_err += err
print(f"\nN=8 exhaustive: {total_err}/64 = {total_err/64:.4f}")

# N=64 AWGN
N = 64
K = 32
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0

for sigma in [0.3, 0.5, 0.8]:
    random.seed(42)
    total_err = 0
    num_frames = 50
    for frame in range(num_frames):
        info = [random.randint(0,1) for _ in range(K)]
        u = [0]*N
        for i in range(K):
            u[q_n[N-K+i]] = info[i]
        codeword = encode(u, N)
        llr = []
        for i in range(N):
            x = -1.0 if codeword[i] else 1.0
            y = x + random.gauss(0, sigma)
            llr_real = y * (2.0 / (sigma*sigma))
            llr_int = max(-32, min(31, int(llr_real)))
            llr.append(llr_int)
        u_hat = sc_decode_fixed(llr, N, frozen_mask)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
        total_err += err
    ebno = 10*math.log10(1.0/(sigma*sigma)) - 10*math.log10(K/N)
    print(f"N=64 sigma={sigma} Eb/N0={ebno:.1f}dB BER={total_err/(num_frames*K):.4f}")
