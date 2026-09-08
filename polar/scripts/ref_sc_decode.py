#!/usr/bin/env python3
"""Polar SC/SCL 参考模型，用于和 RTL 对比"""
import sys

def f(a, b):
    """f function: sign(a)*sign(b)*min(|a|,|b|)"""
    sign = (1 if a >= 0 else -1) * (1 if b >= 0 else -1)
    return sign * min(abs(a), abs(b))

def g(a, b, u):
    """g function for F=[[1,1],[0,1]]: u=0 -> b+a, u=1 -> b-a"""
    if u == 0:
        return b + a
    else:
        return b - a

def saturate(v, bits=6):
    """饱和到 bits 位有符号数"""
    max_val = (1 << (bits-1)) - 1
    min_val = -(1 << (bits-1))
    if v > max_val: return max_val
    if v < min_val: return min_val
    return v

def sc_decode(llr, N, frozen_mask):
    """SC 译码，返回 u_hat"""
    LOG2N = N.bit_length() - 1
    alpha = [[0]*N for _ in range(LOG2N+1)]
    u_hat = [0]*N
    
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
        
        # S_DECISION
        a = alpha[LOG2N][leaf]
        if frozen_mask[leaf]:
            u_hat[leaf] = 0
        else:
            u_hat[leaf] = 0 if a >= 0 else 1
        
        # S_BACKWARD
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

def main():
    # 读取 Q_N 序列
    q_n = []
    with open(r'D:\3_Work\16_5G_NR_DS\3_RES\polar\rtl\q_n_64.txt', 'r') as f:
        for line in f:
            q_n.append(int(line.strip()))
    
    N = 64
    K = 32
    CRC_LEN = 16
    K_TOTAL = K + CRC_LEN
    
    # 冻结位掩码
    frozen_mask = [1]*N
    for i in range(K_TOTAL):
        frozen_mask[q_n[N-K_TOTAL+i]] = 0
    
    # 测试全 0 信息位
    # 编码器：u = 0 (冻结), info=0, CRC=0 的 CRC
    # 先计算 CRC
    def crc16(data, length):
        crc = 0xFFFF
        for i in range(length):
            bit = (data >> i) & 1
            feedback = ((crc >> 15) & 1) ^ bit
            crc = ((crc << 1) & 0xFFFF)
            if feedback:
                crc ^= 0x1021
        return crc
    
    # 全 1 信息位
    info = (1 << K) - 1
    crc_val = crc16(info, K)
    print(f"CRC of all-one info: 0x{crc_val:04X}")
    
    # 构造 u
    u = [0]*N
    for i in range(K):
        u[q_n[N-K_TOTAL+i]] = (info >> i) & 1
    for i in range(CRC_LEN):
        u[q_n[N-K_TOTAL+K+i]] = (crc_val >> (CRC_LEN-1-i)) & 1
    
    # 极化编码
    codeword = u[:]
    for stage in range(6):
        half = N >> (stage+1)
        temp = codeword[:]
        for i in range(N):
            if i % (half*2) < half:
                temp[i] = codeword[i] ^ codeword[i+half]
        codeword = temp
    
    print(f"Codeword: {''.join(str(x) for x in codeword)}")
    print(f"Number of 1s in codeword: {sum(codeword)}")
    
    # LLR
    llr = [31 if x == 0 else -31 for x in codeword]
    
    # SC 译码
    u_hat = sc_decode(llr, N, frozen_mask)
    
    # 比对信息位
    errors = 0
    for i in range(K):
        idx = q_n[N-K_TOTAL+i]
        if u_hat[idx] != u[idx]:
            errors += 1
            print(f"  ERR info[{i}] leaf={idx}: expected={u[idx]} got={u_hat[idx]} alpha={alpha_val(idx, llr, N, frozen_mask)}")
    
    print(f"Total errors: {errors}/{K}")

def alpha_val(leaf_target, llr, N, frozen_mask):
    """计算某个叶子的 alpha[LOG2N]"""
    LOG2N = N.bit_length() - 1
    alpha = [[0]*N for _ in range(LOG2N+1)]
    u_hat = [0]*N
    for i in range(N):
        alpha[0][i] = llr[i]
    
    for leaf in range(leaf_target+1):
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
    return alpha[LOG2N][leaf_target]

if __name__ == '__main__':
    main()
