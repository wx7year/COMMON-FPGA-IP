#!/usr/bin/env python3
"""验证 CRC 编码器和译码器的一致性"""

def crc16_bits(bits):
    """LFSR: 初始 0xFFFF, 多项式 0x1021, MSB 在前"""
    crc = 0xFFFF
    for bit in bits:
        feedback = ((crc >> 15) & 1) ^ bit
        crc = ((crc << 1) & 0xFFFF)
        if feedback:
            crc ^= 0x1021
    return crc

# 测试：信息位全 0，K=32
K = 32
info = 0
info_bits = [(info >> i) & 1 for i in range(K)]  # LSB 在前

# 编码器：计算 info_bits 的 CRC
crc_val = crc16_bits(info_bits)
print(f"Encoder CRC: 0x{crc_val:04X}")

# 编码器附加 CRC 位：info_bits[K+i] = crc_val[15-i] (MSB 在前)
crc_bits = [(crc_val >> (15-i)) & 1 for i in range(16)]
print(f"CRC bits (MSB first): {''.join(str(b) for b in crc_bits)}")

# 译码器：输入 info_bits + crc_bits，看结果是否为 0
total_bits = info_bits + crc_bits
result = crc16_bits(total_bits)
print(f"Decoder CRC check: 0x{result:04X}")
print(f"CRC pass: {result == 0}")

# 测试全 1
info = (1 << K) - 1
info_bits = [(info >> i) & 1 for i in range(K)]
crc_val = crc16_bits(info_bits)
print(f"\nAll-one info CRC: 0x{crc_val:04X}")
crc_bits = [(crc_val >> (15-i)) & 1 for i in range(16)]
total_bits = info_bits + crc_bits
result = crc16_bits(total_bits)
print(f"Decoder CRC check: 0x{result:04X}, pass: {result == 0}")
