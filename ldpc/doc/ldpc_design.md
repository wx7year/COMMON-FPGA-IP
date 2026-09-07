# LDPC IP 核设计文档

## 概述

5G NR QC-LDPC（准循环低密度奇偶校验）编解码器 IP 核。
- 编码器：基于基矩阵的准循环编码，前替代求解校验位
- 译码器：Layered Min-Sum（分层最小和），支持可配置迭代次数

## 文件

```
ldpc/
├── rtl/
│   ├── ldpc_encoder.v        # LDPC 编码器
│   ├── ldpc_decoder.v        # LDPC 译码器（分层Min-Sum）
│   ├── ldpc_cnu.v            # 校验节点更新单元（串行Min-Sum）
│   ├── ldpc_cyclic_shift.v   # 循环移位器
│   └── ldpc_base_graph_rom.v # 基矩阵ROM
├── tb/tb_ldpc.sv             # 测试平台
├── model/ldpc_model.c        # C golden model（编码+译码）
├── scripts/gen_base_graph.py # 基矩阵生成脚本
└── doc/ldpc_design.md        # 本文档
```

## 基矩阵

5G NR 定义两种基矩阵（3GPP TS 38.212）：
- BG1：4×26，信息位22列，适用于码率 > 1/3
- BG2：4×14，信息位10列，适用于码率 ≤ 1/3

每个元素：-1（零矩阵）或 0..383（ZC×ZC 循环右移量）。
Lifting size ZC ∈ {2,3,...,384}，共 51 个值。

基矩阵从 .mem 文件加载（`$readmemh`），由 `gen_base_graph.py` 生成。
当前提供 4×8 测试基矩阵用于功能验证，真实 BG1/BG2 值需从 38.212 填入脚本。

## 编码器 (ldpc_encoder)

### 编码流程
1. 信息位 s 分成 K_b 个 ZC-bit 块，存入 info_ram
2. 计算每行校验方程的信息位部分：rhs[r] = ⊕ H[r][c]·s[c]（循环移位+异或）
3. 前替代求解校验位：p[r] = rhs[r] ⊕ ⊕ H[r][K_b+j]·p[j]（j < r）
4. 输出 s + p（共 N_b×ZC bit）

### 资源
- 1 个循环移位器（组合逻辑）
- 1 块基矩阵 ROM
- info_ram（K_b × ZC）+ parity_ram（M_b × ZC）
- RHS 寄存器组（ROWS × ZC）
- 无乘法器，无 DSP

### 延迟
K_b×ZC(加载) + ROWS×K_b(计算RHS) + M_b²(求解) + N_b×ZC(输出)

## 译码器 (ldpc_decoder)

### 算法：Layered Min-Sum
对每一层（校验方程组）：
1. 读取该层所有非零列的后验 LLR（经循环移位对齐）
2. CNU 计算校验消息 L(r_ij) = sign × min_excl × α（α=0.75）
3. 更新后验 LLR：L(q) = channel_LLR + new_msg - old_msg
迭代至校验满足或达到最大迭代次数。

### CNU 单元 (ldpc_cnu)
串行 Min-Sum：
- 输入 ZC 个 LLR（ZC 周期）
- 跟踪 min1（最小绝对值）、min2（次小）、min1_idx、sign_total
- 输出[i] = (sign_total ⊕ sign[i]) ? -min_excl_i : min_excl_i
- 归一化因子 α=0.75（移位减法实现：out - out>>>2）
- 延迟：2ZC+2 周期

### 存储
- channel_ram：信道 LLR（N_b × ZC × LLR_WIDTH）
- post_ram：后验 LLR（分层更新）
- msg_ram：校验消息（ROWS × N_b × ZC × LLR_WIDTH）

### 参数
| 参数 | 默认 | 说明 |
|---|---|---|
| BG | 1 | 1=BG1, 2=BG2, 0=测试矩阵 |
| ZC | 4 | Lifting size |
| LLR_WIDTH | 6 | LLR 位宽 |
| MAX_ITER | 8 | 最大迭代次数 |

## 资源估算（ZC=4, 测试矩阵）

| 模块 | LUT | FF | DSP | BRAM |
|---|---|---|---|---|
| 编码器 | ~300 | ~200 | 0 | 0 |
| 译码器 | ~800 | ~600 | 0 | 0-1 |
| CNU | ~100 | ~80 | 0 | 0 |

> 大 ZC（如 384）时，msg_ram 需改 BRAM，CNU 可扩展多通道并行。

## 验证

- 编码器：全零输入 → 全零输出
- 编码器：单比特输入 → 校验位关系验证
- 译码器：C model 对比（需生成测试向量）

## 已知限制

1. 基矩阵值需从 38.212 标准填入（当前为测试矩阵）
2. 译码器校验检查（syndrome）为简化版，需完善
3. 大 ZC 时存储需改 BRAM，当前用寄存器组
4. CNU 为单通道串行，大 ZC 时吞吐低，可扩展多通道
5. 译码器循环移位在 LLR 维度的实现需根据 ZC 细化
