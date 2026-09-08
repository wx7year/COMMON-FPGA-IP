#!/usr/bin/env python3
"""SCL 参考模型，用和 RTL testbench 相同的随机种子"""
import random

def f(a, b):
    sign = (1 if a >= 0 else -1) * (1 if b >= 0 else -1)
    return sign * min(abs(a), abs(b))

def g(a, b, u):
    return (b + a) if u == 0 else (b - a)

def saturate(v, bits=6):
    mx = (1 << (bits-1)) - 1
    mn = -(1 << (bits-1))
    return max(mn, min(mx, v))

def pm_inc(llr, u):
    prod = llr if u == 1 else -llr
    return max(0, prod)

def awgn(seed, sigma):
    """Box-Muller，和 SystemVerilog $dist_normal 类似"""
    random.seed(seed)
    u1 = random.random()
    u2 = random.random()
    import math
    z = math.sqrt(-2*math.log(u1)) * math.cos(2*math.pi*u2)
    return z * sigma

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

def crc16_bits(bits):
    crc = 0xFFFF
    for bit in bits:
        feedback = ((crc >> 15) & 1) ^ bit
        crc = ((crc << 1) & 0xFFFF)
        if feedback:
            crc ^= 0x1021
    return crc

def main():
    q_n = []
    with open(r'D:\3_Work\16_5G_NR_DS\3_RES\polar\rtl\q_n_64.txt', 'r') as f:
        for line in f:
            q_n.append(int(line.strip()))
    
    N = 64
    K = 32
    CRC_LEN = 16
    K_TOTAL = K + CRC_LEN
    sigma = 0.5
    seed = 12345
    
    frozen_mask = [1]*N
    for i in range(K_TOTAL):
        frozen_mask[q_n[N-K_TOTAL+i]] = 0
    
    total_err = 0
    for frame in range(10):
        random.seed(seed + frame)
        info = random.getrandbits(K)
        
        info_bits = [(info >> i) & 1 for i in range(K)]
        crc_val = crc16_bits(info_bits)
        crc_bits = [(crc_val >> (15-i)) & 1 for i in range(16)]
        
        u = [0]*N
        for i in range(K):
            u[q_n[N-K_TOTAL+i]] = info_bits[i]
        for i in range(CRC_LEN):
            u[q_n[N-K_TOTAL+K+i]] = crc_bits[i]
        
        codeword = u[:]
        for stage in range(6):
            half = N >> (stage+1)
            temp = codeword[:]
            for i in range(N):
                if i % (half*2) < half:
                    temp[i] = codeword[i] ^ codeword[i+half]
            codeword = temp
        
        llr = []
        for i in range(N):
            x = -1.0 if codeword[i] else 1.0
            y = x + awgn(seed + frame + i, sigma)
            llr_real = y * (2.0 / (sigma*sigma))
            llr_int = int(llr_real)
            llr_int = max(-32, min(31, llr_int))
            llr.append(llr_int)
        
        u_hat, best_pm = scl_decode(llr, N, frozen_mask, L=4)
        
        err = 0
        for i in range(K):
            idx = q_n[N-K_TOTAL+i]
            if u_hat[idx] != u[idx]:
                err += 1
        total_err += err
        print(f"Frame {frame}: errors={err}/{K}, best_pm={best_pm}")
    
    print(f"\nTotal errors: {total_err}/{10*K}, BER: {total_err/(10*K):.6f}")

if __name__ == '__main__':
    main()
