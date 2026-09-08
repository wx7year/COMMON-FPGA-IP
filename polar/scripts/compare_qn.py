#!/usr/bin/env python3
"""对比 Bhattacharyya vs 行权重可靠性序列"""
import random, math, sys
sys.path.insert(0, r'D:\3_Work\16_5G_NR_DS\3_RES\polar\scripts')
from test_verilog_consistent import encode, scl_decode, bhattacharyya_qn

def row_weight_qn(N):
    """按行权重升序（最不可靠在前），权重相同按索引升序"""
    indices = list(range(N))
    indices.sort(key=lambda i: (bin(i).count('1'), i))
    return indices

N = 64
K = 32

for qn_name, qn in [("Bhattacharyya", bhattacharyya_qn(N)), ("RowWeight", row_weight_qn(N))]:
    frozen_mask = [1]*N
    for i in range(K):
        frozen_mask[qn[N-K+i]] = 0
    
    # 无噪声随机
    random.seed(42)
    total_err = 0
    for frame in range(50):
        info = [random.randint(0,1) for _ in range(K)]
        u = [0]*N
        for i in range(K):
            u[qn[N-K+i]] = info[i]
        codeword = encode(u, N)
        llr = [8 if x == 0 else -8 for x in codeword]
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        total_err += sum(1 for i in range(K) if u_hat[qn[N-K+i]] != info[i])
    print(f"{qn_name} noiseless random: BER={total_err/(50*K):.4f}")
    
    # AWGN sigma=0.5
    random.seed(42)
    total_err = 0
    for frame in range(50):
        info = [random.randint(0,1) for _ in range(K)]
        u = [0]*N
        for i in range(K):
            u[qn[N-K+i]] = info[i]
        codeword = encode(u, N)
        llr = []
        for i in range(N):
            x = -1.0 if codeword[i] else 1.0
            y = x + random.gauss(0, 0.5)
            llr_real = y * (2.0 / (0.5*0.5))
            llr_int = max(-32, min(31, int(llr_real)))
            llr.append(llr_int)
        u_hat, pm = scl_decode(llr, N, frozen_mask, L=4)
        total_err += sum(1 for i in range(K) if u_hat[qn[N-K+i]] != info[i])
    print(f"{qn_name} AWGN sigma=0.5: BER={total_err/(50*K):.4f}")
