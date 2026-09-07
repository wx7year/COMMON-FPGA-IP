# CORDIC IP 核设计文档

## 概述

迭代式 CORDIC（COordinate Rotation DIgital Computer），支持旋转模式和向量模式。用于计算 sin/cos、atan2、magnitude、相位旋转等，无乘法器。

## 文件

```
cordic/
├── rtl/cordic_top.v       # CORDIC 顶层
├── tb/tb_cordic.sv        # 测试平台
├── model/cordic_model.c   # C golden model
└── doc/cordic_design.md   # 本文档
```

## 架构

迭代式（时分复用），1 个运算单元，ITERATIONS 周期完成一次运算。

**旋转模式 (mode=0)**：(x,y,z) → (x·cos(z)-y·sin(z), x·sin(z)+y·cos(z), 0)
- 求 sin/cos：输入 x=1/K, y=0, z=angle

**向量模式 (mode=1)**：(x,y,z) → (√(x²+y²), 0, z+atan2(y,x))
- 求 atan2/magnitude：输入 z=0

## 迭代公式

```
d = mode ? -sign(y) : sign(z)
x_next = x - d · y · 2^(-i)
y_next = y + d · x · 2^(-i)
z_next = z - d · atan(2^(-i))
```

## 增益预补偿

CORDIC 固有增益 K = ∏ cos(atan(2^-i)) ≈ 0.60725。
`COMPENSATE_GAIN=1` 时，输入 x 预乘 K（移位加法实现，无乘法器）：
K ≈ 2⁻¹ + 2⁻⁴ + 2⁻⁵ + 2⁻⁷ + 2⁻⁸ + 2⁻¹⁰ + 2⁻¹¹ + 2⁻¹²

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| DATA_WIDTH | 16 | 数据位宽 |
| ANGLE_WIDTH | 16 | 角度位宽（Q2.14） |
| ITERATIONS | 16 | 迭代次数（=数据位宽时精度最优） |
| COMPENSATE_GAIN | 1 | 1=输入x预乘K |

## 资源

- LUT：~200-300（加法器+移位+角度ROM）
- FF：~100-200
- DSP48：0
- BRAM：0（角度表用分布式 ROM）

## 延迟

ITERATIONS + 2 周期。

## 收敛范围

|z| < 1.743 rad（~99.7°），超出需外部象限折叠。

## 验证

- 旋转模式：sin/cos(45°) 误差 < 2%
- 向量模式：atan2(1,1)=45° 误差 < 2%
