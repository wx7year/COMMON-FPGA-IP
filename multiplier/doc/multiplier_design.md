# Multiplier IP 核设计文档

## 概述

通用乘法器 IP 核，包含一般有符号乘法器和复数乘法器（3乘法/4乘法结构可配置）。

## 文件

```
multiplier/
├── rtl/multiplier_top.v     # 一般乘法器
├── rtl/complex_mult_top.v   # 复数乘法器
├── tb/tb_multiplier.sv      # 测试平台
├── model/muldiv_model.c     # C golden model
└── doc/multiplier_design.md # 本文档
```

## 一般乘法器 (multiplier_top)

可配置流水线级数：
- PIPE_STAGES=0：组合逻辑
- PIPE_STAGES=1：输入寄存
- PIPE_STAGES≥2：输入+输出寄存（全流水）

资源：1 个 DSP48（位宽适合时）。

## 复数乘法器 (complex_mult_top)

计算 (a+bi)·(c+di) = (ac-bd) + (ad+bc)i

**3乘法结构 (USE_3_MULT=1)**：
```
k1 = c·(a+b), k2 = a·(d-c), k3 = b·(c+d)
real = k1-k3, imag = k1+k2
```
- 省 1 个 DSP48，延迟 3 周期

**4乘法结构 (USE_3_MULT=0)**：
```
real = ac-bd, imag = ad+bc
```
- 延迟 2 周期，多用 1 个 DSP

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| A_WIDTH | 16 | 被乘数位宽 |
| B_WIDTH/C_WIDTH | 16 | 乘数位宽 |
| PIPE_STAGES | 2 | 一般乘法器流水级数 |
| USE_3_MULT | 1 | 复数乘法器：1=3乘法(省资源), 0=4乘法(低延迟) |

## 资源对比

| 配置 | DSP48 | 延迟 |
|---|---|---|
| 一般乘法器 | 1 | 2 |
| 复数 3乘法 | 3 | 3 |
| 复数 4乘法 | 4 | 2 |

## 验证

- 一般乘法：100×200, -50×30
- 复数乘法：(3+4i)(1+2i) = -5+10i
