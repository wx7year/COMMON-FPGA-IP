# FIR IP 核设计文档

## 1. 概述

自研 FIR 滤波器 IP 核，替代 Xilinx FIR Compiler IP 核。核心特性是**自动资源优化**：根据时钟频率和输入数据率自动计算所需乘法器数量，在保证实时处理的前提下使用最少的 DSP48 资源。

## 2. 文件结构

```
fir/
├── rtl/
│   └── fir_top.v           # 顶层：自动并行度 MAC + AXI4-Stream 接口
├── tb/
│   ├── tb_fir_top.sv       # 自检测试平台
│   └── data/               # 测试向量（系数、输入、期望输出）
├── model/
│   ├── fir_model.c         # C golden model（含系数生成）
│   └── Makefile            # 编译 + 生成测试向量
├── scripts/
│   └── gen_test_input.py   # 测试输入生成脚本
└── doc/
    └── fir_design.md       # 本文档
```

## 3. 自动资源优化原理

### 3.1 过采样比

```
OVERSAMPLE = CLK_FREQ / SAMPLE_RATE
```

表示每个输入样点之间有多少个时钟周期可用。例如 80MHz 时钟、10MHz 数据率 → OVERSAMPLE = 8。

### 3.2 有效抽头数

```
EFF_TAPS = SYMMETRIC ? ceil(NUM_TAPS/2) : NUM_TAPS
```

对称系数时利用 h[k] = h[N-1-k]，先做 x[n-k] + x[n-(N-1-k)] 预加，乘法次数减半。

### 3.3 自动乘法器数量

```
NUM_MULT = ceil(EFF_TAPS / OVERSAMPLE)
```

每个乘法器时分复用 `TAPS_PER_MULT = ceil(EFF_TAPS / NUM_MULT)` 个抽头。只要 `TAPS_PER_MULT ≤ OVERSAMPLE`，就能在输入间隔内完成所有运算，保证实时。

### 3.4 示例

| 配置 | OVERSAMPLE | EFF_TAPS | NUM_MULT | TAPS_PER_MULT |
|---|---|---|---|---|
| 80MHz/10MHz, 32tap 对称 | 8 | 16 | 2 | 8 |
| 80MHz/10MHz, 64tap 对称 | 8 | 32 | 4 | 8 |
| 80MHz/10MHz, 16tap 非对称 | 8 | 16 | 2 | 8 |
| 80MHz/80MHz, 32tap 对称 | 1 | 16 | 16 | 1 |
| 122.88MHz/15.36MHz, 32tap | 8 | 16 | 2 | 8 |

> 对比：Xilinx FIR Compiler 全展开 32tap 需要 32 个 DSP48，本设计在 8 倍过采样下仅需 2 个。

## 4. 架构

### 4.1 多 MAC 并行通道

用 `generate` 块自动生成 `NUM_MULT` 个 MAC 通道：

```
通道 0: 处理抽头 [0, TAPS_PER_MULT)
通道 1: 处理抽头 [TAPS_PER_MULT, 2*TAPS_PER_MULT)
...
通道 m: 处理抽头 [m*TAPS_PER_MULT, (m+1)*TAPS_PER_MULT)
```

每个通道：
1. 系数 ROM 寻址（组合逻辑）
2. 对称预加（组合逻辑）
3. 乘法器（1 周期延迟，DSP48）
4. 累加器（TAPS_PER_MULT 周期）

所有通道输出求和得到最终结果。

### 4.2 控制状态机

```
IDLE → MAC → OUT → IDLE
```

- **IDLE**：等待输入，移位寄存器更新
- **MAC**：所有通道并行累加，TAPS_PER_MULT+2 周期完成
- **OUT**：输出有效，等待 m_axis_tready

### 4.3 定点格式

| 信号 | 位宽 |
|---|---|
| 输入 | DATA_WIDTH (默认16) |
| 系数 | COEFF_WIDTH (默认16, Q1.15) |
| 对称预加 | DATA_WIDTH+1 |
| 乘法输出 | DATA_WIDTH+COEFF_WIDTH+1 |
| 单通道累加 | ACC_WIDTH = DATA+COEFF+$clog2(TAPS_PER_MULT)+2 |
| 多通道求和 | SUM_WIDTH = ACC_WIDTH+$clog2(NUM_MULT)+1 |
| 输出 | OUT_WIDTH = DATA+COEFF+$clog2(NUM_TAPS)+1 |

## 5. 资源估算

### 5.1 典型配置（32tap, 对称, 80MHz/10MHz）

| 资源 | 本设计 (NUM_MULT=2) | Xilinx FIR Compiler (全展开) | Xilinx FIR Compiler (8倍过采样) |
|---|---|---|---|
| DSP48 | 2 | 16 (对称) / 32 (非对称) | 2-4 |
| LUT | ~300-500 | ~800-1200 | ~400-600 |
| FF | ~200-400 | ~500-800 | ~300-500 |
| BRAM | 0 | 0 | 0-1 |

### 5.2 资源随配置变化

- DSP48 数量 = NUM_MULT（自动计算，与过采样比成反比）
- LUT/FF 主要是移位寄存器（NUM_TAPS × DATA_WIDTH）和控制逻辑
- 系数 ROM 用分布式 RAM（EFF_TAPS × COEFF_WIDTH），抽头数大时综合器自动推断 BRAM

## 6. 接口

### 6.1 AXI4-Stream

- 输入：`s_axis_tdata[DATA_WIDTH-1:0]`，实信号
- 输出：`m_axis_tdata[OUT_WIDTH-1:0]`，全精度
- `s_axis_tlast` / `m_axis_tlast` 透传
- 背压：`s_axis_tready = ~busy`

### 6.2 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| NUM_TAPS | 32 | 抽头数 |
| DATA_WIDTH | 16 | 数据位宽 |
| COEFF_WIDTH | 16 | 系数位宽 |
| CLK_FREQ | 80_000_000 | 时钟频率 (Hz) |
| SAMPLE_RATE | 10_000_000 | 输入数据率 (Hz) |
| SYMMETRIC | 1 | 1=对称系数, 0=非对称 |
| COEFF_FILE | "fir_coeff.mem" | 系数文件 ($readmemh) |

### 6.3 系数文件格式

每行一个十六进制数（有符号，COEFF_WIDTH 位），对称时只存前半部分：

```
// 32tap 对称滤波器，存 16 个系数
7fff
6a00
...
```

由 `model/fir_model.c gen_coeff` 或 Python 脚本生成。

## 7. 验证流程

### 7.1 生成测试向量

```bash
cd fir/model
make gen_all NUM_TAPS=32 CUTOFF=0.25 SYMMETRIC=symmetric
```

生成：
- `tb/data/fir_coeff.mem` — 低通滤波器系数（Hamming窗，截止0.25fs）
- `tb/data/fir_input.txt` — 随机输入
- `tb/data/fir_expected.txt` — C model 期望输出

### 7.2 运行仿真

编译 `tb_fir_top.sv` + `fir_top.v`，运行后查看 PASS/FAIL。

### 7.3 测试覆盖

- [x] 随机输入：全范围比对
- [ ] 冲激响应：验证系数正确性
- [ ] 阶跃响应：验证稳态
- [ ] 正弦波：验证频率响应
- [ ] 边界值：最大正/负输入溢出测试

## 8. 延迟

```
延迟 = TAPS_PER_MULT + 3 周期
```

| 配置 | TAPS_PER_MULT | 延迟 (80MHz) |
|---|---|---|
| 32tap 对称, 8倍过采样 | 8 | 11 周期 = 137.5ns |
| 64tap 对称, 8倍过采样 | 8 | 11 周期 = 137.5ns |
| 32tap 对称, 1倍过采样 | 16 | 19 周期 = 237.5ns |

## 9. 已知限制与扩展方向

1. **单速率滤波器**：不支持多速率（抽取/插值），需扩展
2. **系数固定**：编译时从文件加载，不支持运行时重配（可扩展为 AXI4-Lite 配置接口）
3. **实信号**：当前仅支持实信号，复数信号需实例化两个（I/Q 各一）
4. **无块浮点**：全精度输出，下游需自行截断
5. **大抽头数移位寄存器**：NUM_TAPS > 128 时建议改用 RAM -based 移位寄存器以省 LUT

## 10. 替换 Xilinx FIR Compiler 迁移指南

| Xilinx FIR Compiler | 本设计 | 说明 |
|---|---|---|
| aclk | clk | |
| aresetn | rst_n | |
| s_axis_data_tdata | s_axis_tdata | |
| s_axis_data_tvalid | s_axis_tvalid | |
| s_axis_data_tready | s_axis_tready | |
| s_axis_data_tlast | s_axis_tlast | |
| m_axis_data_tdata | m_axis_tdata | 全精度输出 |
| m_axis_data_tvalid | m_axis_tvalid | |
| m_axis_data_tready | m_axis_tready | |
| m_axis_data_tlast | m_axis_tlast | |
| 系数配置 (COE文件) | COEFF_FILE 参数 | .mem 格式 |
| 过采样率配置 | CLK_FREQ/SAMPLE_RATE 参数 | 自动计算 |

---

*版本：v1.0*
*日期：2026-09-07*
