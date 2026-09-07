# FFT IP 核设计文档

## 1. 概述

自研 Radix-2 FFT/IFFT IP 核，替代 Xilinx FFT v9.1 IP 核。采用单蝶形时分复用 + 乒乓 RAM 架构，资源占用与 Xilinx FFT Radix-2 Lite 模式对齐或更优。

## 2. 文件结构

```
fft/
├── rtl/
│   ├── fft_top.v           # 顶层：AXI4-Stream 接口，正向/反向可配置
│   ├── fft_core.v          # 核心：控制器 + 乒乓RAM + 蝶形调度
│   ├── fft_butterfly.v     # 蝶形运算单元（A±B*W）
│   ├── fft_complex_mult.v  # 复数乘法器（3乘法结构，省1个DSP）
│   └── fft_twiddle_rom.v   # 旋转因子 ROM（initial块综合时计算）
├── tb/
│   ├── tb_fft_top.sv       # 自检测试平台
│   └── data/               # 测试向量（由 C model 生成）
├── model/
│   ├── fft_model.c         # C golden model
│   └── Makefile            # 编译 + 生成测试向量
├── scripts/
│   └── gen_twiddle.py      # 旋转因子生成脚本（备用）
└── doc/
    └── fft_design.md       # 本文档
```

## 3. 架构

### 3.1 顶层（fft_top）

- AXI4-Stream 输入输出接口
- `fwd_inv` 引脚配置正向/反向（在 s_axis_tlast 时锁存）
- IFFT 实现：输入共轭 → FFT → 输出共轭 → 除以 N（右移 log2(N)）
- 输入格式：`{Q[DIN_WIDTH-1:0], I[DIN_WIDTH-1:0]}`
- 输出格式：`{Q[DOUT_WIDTH-1:0], I[DOUT_WIDTH-1:0]}`

### 3.2 核心（fft_core）

**乒乓双口 RAM 架构：**
- 2 块双口 RAM（bank0/bank1），深度 N，宽度 2×INTERN_WIDTH
- 偶数级读 bank0 写 bank1，奇数级读 bank1 写 bank0
- 源 bank 和目标 bank 不同，读和写完全并行无冲突

**单蝶形流水线（6级）：**
1. S0：计算地址，读源 RAM，读旋转因子 ROM
2. S1：寄存 RAM 输出（A, B）和旋转因子
3. S2-S4：复数乘法 B×W（3 周期延迟，3乘法结构）
4. S5：右移去增益 + 蝶形运算 A±B×W
5. S6：写回目标 RAM

每周期发起 1 个蝶形运算，处理 N 点需要 N×log2(N)/2 个周期。

### 3.3 复数乘法器（fft_complex_mult）

3 乘法公式，比标准 4 乘法省 1 个 DSP48：
```
k1 = c × (a + b)
k2 = a × (d - c)
k3 = b × (c + d)
real = k1 - k3 = ac - bd
imag = k1 + k2 = ad + bc
```
延迟 3 周期，输出位宽 A_WIDTH + C_WIDTH + 1。

### 3.4 定点格式

| 信号 | 位宽 | 格式 |
|---|---|---|
| 输入 I/Q | DIN_WIDTH (默认16) | 有符号定点 |
| 旋转因子 | TWIDDLE_WIDTH (默认16) | Q1.15 |
| 复数乘输出 | DIN+LOG2_N + TWIDDLE_WIDTH + 1 | 全精度 |
| 右移后 | DIN+LOG2_N + 2 | 去旋转因子增益 |
| 蝶形输出 | DIN+LOG2_N + 3 | 截断到 DIN+LOG2_N |
| 内部 RAM | DIN+LOG2_N (默认26) | 全精度 |
| 输出 I/Q | DOUT_WIDTH (默认26) | 可截断 |

每级运算后有效位宽增长 1 bit（蝶形加法），log2(N) 级后总增长 log2(N) bit。

## 4. 性能与资源

### 4.1 吞吐

| FFT 点数 | 处理周期 | 80MHz 耗时 | 最大连续帧速率 |
|---|---|---|---|
| 256 | 1024+6+512 = 1542 | 19.3 us | ~52 MHz |
| 512 | 2304+6+1024 = 3334 | 41.7 us | ~24 MHz |
| 1024 | 5120+6+2048 = 7174 | 89.7 us | ~11 MHz |
| 2048 | 11264+6+4096 = 15366 | 192 us | ~5.3 MHz |

> 处理周期 = N×log2(N)/2 + 6(排空) + N(加载) + N(卸载)

### 4.2 资源估算（N=1024, 16bit 输入）

| 资源 | 本设计 | Xilinx FFT Radix-2 Lite |
|---|---|---|
| LUT | ~800-1200 | ~1000-1500 |
| FF | ~600-900 | ~800-1200 |
| DSP48 | 3 (复数乘) | 3-4 |
| BRAM36 | 4 (2块双口RAM×26bit≈2BRAM) | 2-4 |
| 旋转因子 ROM | 分布式/BRAM | 分布式/BRAM |

> 实际资源以综合报告为准。

### 4.3 时钟/数据率自动适配

本设计为单蝶形架构，适用场景：
- **过采样比 ≥ N×log2(N)/(2×f_clk/f_sample)** 时可连续处理
- 例：80MHz 时钟、10MHz 数据率、1024点 → 过采样比 8，处理时间 90us < 帧时间 102.4us ✓
- 若数据率更高（如等时钟 80MHz），需使用多蝶形并行版本（待扩展）

## 5. 验证流程

### 5.1 生成测试向量

```bash
cd fft/model
make gen_all N=1024
# 生成：
#   tb/data/input_1024.txt        - 随机输入
#   tb/data/expected_fft_1024.txt - 正向FFT期望输出
#   tb/data/expected_ifft_1024.txt - 反向FFT期望输出
```

### 5.2 运行仿真

使用 ModelSim/VCS/Xcelium 编译 `tb_fft_top.sv` 和 `rtl/*.v`，运行后查看 PASS/FAIL 报告。

误差阈值默认 ±4 LSB，可在 testbench 中修改 `ERR_THRESHOLD` 参数。

### 5.3 测试覆盖

- [x] 正向 FFT：随机输入，逐点比对
- [x] 反向 FFT：随机输入，逐点比对
- [ ] 冲激响应（单脉冲输入）
- [ ] 直流信号（全1输入）
- [ ] 奈奎斯特频率信号
- [ ] 边界值（最大正/负输入）

## 6. 接口时序

### 6.1 输入

- `s_axis_tvalid` + `s_axis_tready` 握手
- `s_axis_tlast` 标记帧尾，同时锁存 `fwd_inv`
- 连续 N 个样点为一帧

### 6.2 输出

- `m_axis_tvalid` 输出有效
- `m_axis_tlast` 标记帧尾
- 输出为自然序（DIT 位反序已在内部重排）
- 帧间延迟：加载 N + 处理 N×log2(N)/2+6 + 卸载 N

## 7. 已知限制与扩展方向

1. **仅支持 2 的幂次点数**：通过 parameter N 配置
2. **单蝶形架构**：高数据率场景需多蝶形并行版本
3. **固定 unscaled 模式**：内部全精度，输出可截断；暂不支持块浮点
4. **旋转因子 ROM 用 initial 块**：若综合工具不支持，改用 `scripts/gen_twiddle.py` 生成 .hex + `$readmemh`
5. **无 AXI4-Stream config 通道**：fwd_inv 通过引脚配置，如需运行时切换可扩展 config 通道

## 8. 替换 Xilinx FFT IP 的迁移指南

| Xilinx FFT 信号 | 本设计对应 | 说明 |
|---|---|---|
| aclk | clk | |
| aresetn | rst_n | |
| s_axis_config_tdata[0] | fwd_inv | 1=正向, 0=反向 |
| s_axis_data_tdata | s_axis_tdata | {Q,I} 格式 |
| s_axis_data_tvalid | s_axis_tvalid | |
| s_axis_data_tready | s_axis_tready | |
| s_axis_data_tlast | s_axis_tlast | |
| m_axis_data_tdata | m_axis_tdata | {Q,I} 格式 |
| m_axis_data_tvalid | m_axis_tvalid | |
| m_axis_data_tready | m_axis_tready | |
| m_axis_data_tlast | m_axis_tlast | |
| event_frame_started | (未引出) | 可扩展 |
| event_tlast_unexpected | (未引出) | 可扩展 |
| event_tlast_missing | (未引出) | 可扩展 |

---

*版本：v1.0*
*日期：2026-09-07*
