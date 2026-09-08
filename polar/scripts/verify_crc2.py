#!/usr/bin/env python3
"""Verify CRC encoder vs decoder consistency"""

def crc_encoder(data_bits, poly=0x1021, width=16, init=0xFFFF):
    """Simulate crc_encoder.v LFSR"""
    reg = init
    for bit in data_bits:
        feedback = ((reg >> (width-1)) & 1) ^ bit
        # left shift
        reg = ((reg << 1) & ((1<<width)-1))
        # apply polynomial
        if feedback:
            reg ^= poly
        # bit 0 is feedback (poly[0]=1)
        # actually: crc_next[0] = feedback, crc_next[i] = reg[i-1] ^ (feedback & poly[i])
        # Let's redo properly
        pass
    # Redo properly
    reg = init
    for bit in data_bits:
        feedback = ((reg >> (width-1)) & 1) ^ bit
        next_reg = 0
        for i in range(width):
            if i == 0:
                next_reg |= feedback << i
            else:
                prev = (reg >> (i-1)) & 1
                if (poly >> i) & 1:
                    next_reg |= (prev ^ feedback) << i
                else:
                    next_reg |= prev << i
        reg = next_reg
    return reg

def crc_checker(data_bits, poly=0x1021, width=16, init=0xFFFF):
    """Simulate polar_scl_decoder.v CRC check"""
    reg = init
    for bit in data_bits:
        feedback = ((reg >> (width-1)) & 1) ^ bit
        # left shift, LSB=0
        reg = ((reg << 1) & ((1<<width)-1))
        # apply polynomial
        if feedback:
            reg ^= poly
    return reg

# Test: random 32 info bits
import random
random.seed(42)
info = [random.randint(0,1) for _ in range(32)]
crc = crc_encoder(info)
print(f"info = {info}")
print(f"crc  = {crc:04x}")

# CRC bits MSB first (as in encoder: info_bits[K+pi] = crc_result[CRC_LEN-1-pi])
crc_bits = [(crc >> (15-i)) & 1 for i in range(16)]
print(f"crc_bits (MSB first) = {crc_bits}")

# Full K_TOTAL bits: info + crc_bits (MSB first)
total = info + crc_bits
remainder = crc_checker(total)
print(f"remainder after checking total = {remainder:04x}")
print(f"CRC pass: {remainder == 0}")

# Also test with decoder's exact bit order
# decoder: cci=0..K_TOTAL-1, u_hat[Q_N[N-K_TOTAL+cci]]
# encoder: info_bits[cnt] placed at Q_N[N-K_TOTAL+cnt]
# So order is info_bits[0]..info_bits[K_TOTAL-1] = info[0]..info[K-1], crc_msb..crc_lsb
# This matches total above
