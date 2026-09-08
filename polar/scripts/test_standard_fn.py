#!/usr/bin/env python3
"""标准 5G NR F=[[1,0],[1,1]] SCL 测试"""
import random, math

def f(a, b):
    sign = (1 if a >= 0 else -1) * (1 if b >= 0 else -1)
    return sign * min(abs(a), abs(b))

def g(a, b, u):
    """标准 g: u=0 -> b-a, u=1 -> b+a"""
    return (b - a) if u == 0 else (b + a)

def saturate(v, bits=6):
    mx = (1 << (bits-1)) - 1
    mn = -(1 << (bits-1))
    return max(mn, min(mx, v))

def pm_inc(llr, u):
    prod = llr if u == 1 else -llr
    return max(0, prod)

def encode(u, N):
    """标准 5G NR: 先内层再外层, right=left^right"""
    codeword = u[:]
    for stage in range(N.bit_length()-1):
        half = 1 << stage  # half=1,2,...,N/2
        temp = codeword[:]
        for i in range(N):
            if i % (half*2) >= half:
                temp[i] = codeword[i-half] ^ codeword[i]
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

def scl_decode(llr, N, frozen_mask, L=4):
    LOG2N = N.bit_length() - 1
    paths = []
    for _ in range(L):
        alpha = [[0]*N for _ in range(LOG2N+1)]
        for i in range(N):
            alpha[0][i] = llr[i]
        paths.append({'alpha': alpha, 'u_hat': [0]*N, 'pm': 0})
    
    for leaf in range(N):
        for p in paths:
            for stage in range(LOG2N):
                block_size = N >> stage
                half = block_size >> 1
                block_start = leaf - (leaf % block_size)
                if (leaf % block_size) < half:
                    for ji in range(half):
                        p['alpha'][stage+1][block_start+ji] = saturate(f(
                            p['alpha'][stage][block_start+ji],
                            p['alpha'][stage][block_start+half+ji]
                        ))
        
        is_frozen = frozen_mask[leaf]
        
        if is_frozen:
            for p in paths:
                p['u_hat'][leaf] = 0
                p['pm'] += pm_inc(p['alpha'][LOG2N][leaf], 0)
        else:
            candidates = []
            for p in paths:
                a = p['alpha'][LOG2N][leaf]
                for u in [0, 1]:
                    candidates.append({
                        'alpha': [row[:] for row in p['alpha']],
                        'u_hat': p['u_hat'][:],
                        'pm': p['pm'] + pm_inc(a, u),
                        'u': u
                    })
            candidates.sort(key=lambda c: (c['pm'], c['u']))
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
                p['alpha'][stage+1][block_start+half+offset] = saturate(g(
                    p['alpha'][stage][block_start+offset],
                    p['alpha'][stage][block_start+half+offset],
                    p['u_hat'][uhat_idx]
                ))
    
    best = min(paths, key=lambda p: p['pm'])
    return best['u_hat'], best['pm']

# N=4 验证
N = 4
K = 2
q_n = bhattacharyya_qn(N)
frozen_mask = [1]*N
for i in range(K):
    frozen_mask[q_n[N-K+i]] = 0
print(f"N=4 Q_N: {q_n}")
for info_val in range(4):
    info = [(info_val >> i) & 1 for i in range(K)]
    u = [0]*N
    for i in range(K):
        u[q_n[N-K+i]] = info[i]
    codeword = encode(u, N)
    llr = [8 if x == 0 else -8 for x in codeword]
    u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
    dec = [u_hat[q_n[N-K+i]] for i in range(K)]
    err = sum(1 for i in range(K) if dec[i] != info[i])
    print(f"  info={info} cw={codeword} dec={dec} err={err}")

# N=64 AWGN 测试
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
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        err = sum(1 for i in range(K) if u_hat[q_n[N-K+i]] != info[i])
        total_err += err
    ebno = 10*math.log10(1.0/(sigma*sigma)) - 10*math.log10(K/N)
    print(f"N=64 sigma={sigma} Eb/N0={ebno:.1f}dB BER={total_err/(num_frames*K):.4f}")
