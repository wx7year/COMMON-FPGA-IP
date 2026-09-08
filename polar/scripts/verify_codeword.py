#!/usr/bin/env python3
"""Verify encoder codeword matches LLR signs"""

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

Q_N = [0,1,2,4,8,16,3,32,5,6,9,10,12,17,18,20,33,7,34,24,11,36,13,19,14,40,21,22,35,48,25,37,26,38,15,28,41,42,23,49,44,50,27,52,39,29,56,30,43,45,46,51,53,54,57,58,31,60,47,55,59,61,62,63]

N = 64
K = 32
K_TOTAL = 48
info_positions = Q_N[N-K_TOTAL:N-K_TOTAL+K]
crc_positions = Q_N[N-K_TOTAL+K:N]

info = [0,1,0,1,1,1,0,0,1,0,0,1,1,1,1,1,0,0,1,0,1,1,1,1,0,0,0,1,1,1,1,1]

# Build u vector (CRC bits unknown, set to 0 for now)
u = [0]*N
for i, pos in enumerate(info_positions):
    u[pos] = info[i]

# Encode with CRC=0
codeword_no_crc = encode(u, N)

llr = [8,8,-7,8,-10,4,8,-8,7,-2,-10,-11,6,-8,-8,12,-11,11,8,-8,7,7,12,-7,-3,3,10,-3,8,-5,4,16,7,-3,12,6,10,8,-8,12,5,-5,9,3,-11,1,13,8,-5,-13,5,-12,5,-6,-7,-5,-7,-7,-4,-5,-5,5,9,4]

# Check LLR sign vs codeword
print("LLR sign mismatches (codeword=0 but LLR<0, or codeword=1 but LLR>0):")
mismatches = 0
for i in range(N):
    expected_sign = 1 if codeword_no_crc[i] == 0 else -1
    actual_sign = 1 if llr[i] >= 0 else -1
    if expected_sign != actual_sign:
        mismatches += 1
        if mismatches <= 10:
            print(f"  pos={i}: codeword={codeword_no_crc[i]} llr={llr[i]}")

print(f"Total sign mismatches: {mismatches}/{N}")
print(f"Codeword (CRC=0): {''.join(str(b) for b in codeword_no_crc)}")
print(f"LLR sign:        {''.join('0' if l>=0 else '1' for l in llr)}")
