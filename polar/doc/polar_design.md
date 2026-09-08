# Polar 码编解码器设计文档

## 概述

5G NR Polar 码编码器和 SC（连续消除）译码器。Polar 码是 3GPP 5G NR 控制信道的标准编码方案（38.212）。

## 编码器

### 架构
- 输入：K 个信息位（串行）
- 信息位放置：最后 K 个位置（简化近似，非真实 38.212 可靠性序列）
- 极化变换：全组合逻辑，generate 实现 log2(N) 级蝶形
- 输出：N 个编码位（串行）

### 蝶形运算
```
左输出 = a ^ b
右输出 = b
```
对应生成矩阵 F^T = [[1,1],[0,1]]，与译码器 f/g 函数匹配。

### 状态机
- S_IDLE：空闲
- S_LOAD：加载 K 个信息位到 u_reg[N-K..N-1]
- S_ENC：组合逻辑变换（1 拍）
- S_OUTPUT：串行输出 N 位

## SC 译码器

### 架构
深度优先遍历极化码树：
1. **Forward**（根→叶子）：对路径上每个 stage，计算当前节点的所有左子元素（f 函数）
2. **Decision**：叶子硬判决（冻结位强制 0）
3. **Backward**（叶子→根）：计算右子元素（g 函数，用左子叶子判决）

### f/g 函数
- f(a,b) = sign(a)·sign(b)·min(|a|,|b|)（min-sum 近似）
- g(a,b,u) = b + (1-2u)·a

### 蝶形索引
- stage s：half = N/2^(s+1)
- 节点起始：node_start = leaf - (leaf % (N>>s))
- 左子元素：alpha[s+1][node_start+j] = f(alpha[s][node_start+j], alpha[s][node_start+half+j])
- 右子元素：alpha[s+1][node_start+half+j] = g(alpha[s][node_start+j], alpha[s][node_start+half+j], u_hat[node_start+j])

### 状态机
- S_IDLE / S_LOAD / S_FORWARD / S_DECISION / S_BACKWARD / S_OUTPUT

### 冻结位
前 N-K 个位置为冻结位，判决时强制为 0。

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| N | 64 | 母码长度 |
| K | 32 | 信息位数 |
| LLR_WIDTH | 6 | LLR 位宽 |

## 仿真验证

ModelSim 端到端仿真（编码→BPSK→AWGN→译码）：
- 全零输入：BER=0
- 随机输入无噪声：BER≈0.5（信息位连续放置导致部分位 LLR=0）
- 与 Python 参考模型结果一致

### 已知局限
1. **信息位放置**：连续放置最后 K 位，非真实 38.212 可靠性序列，导致部分位 LLR=0
2. **SC 译码**：次优译码，5G NR 实际用 SCL（连续消除列表）+ CRC
3. **无子块交织和速率匹配**：当前为核心极化变换版本
4. **LLR 量化**：6bit，大 LLR 会饱和

## 资源估算（N=64）
- alpha 存储：(LOG2N+1)×N×LLR_WIDTH = 7×64×6 = 2688 bit ≈ 42 个 36bit BRAM 或分布式 RAM
- f/g 组合逻辑：每 stage 最多 N/2 个 f 函数
- 总 LUT：约 1000-2000
- 总 FF：约 500-1000
- 延迟：约 N×LOG2N + N ≈ 448 时钟

## 文件清单
- `rtl/polar_encoder.v` — 编码器
- `rtl/polar_sc_decoder.v` — SC 译码器
- `tb/tb_polar_e2e.sv` — 端到端 testbench
- `doc/polar_design.md` — 本文档

## 后续优化方向
1. **真实可靠性序列**：加载 38.212 表 5.3.1.2-1
2. **SCL 译码**：保留 L 个候选路径，路径度量 PM
3. **CRC 辅助**：在候选路径中选 CRC 正确的
4. **子块交织**：38.212 子块交织
5. **速率匹配**：打孔/缩短/重复
6. **大 N 支持**：N=128/256/512/1024，alpha 改用 BRAM
7. **early termination**：CRC 正确即停止
