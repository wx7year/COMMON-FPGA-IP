# DDS (Direct Digital Synthesis) 设计文档

## 概述

直接数字频率合成器，用于生成正弦/余弦波。广泛用于 5G UE 的载波生成、调制解调、测试信号源等场景。

## 架构

```
ftw ──→ [相位累加器] ──→ [+ phase_offset] ──→ [相位截断] ──→ [LUT] ──→ {cos, sin}
         32bit                                取高10bit        1024×32bit
```

1. **相位累加器**：32 位，每个时钟周期累加频率控制字 FTW
2. **相位偏移**：叠加 phase_offset，支持相位调制
3. **相位截断**：取高 10 位作为 LUT 地址（1024 点）
4. **LUT 查找**：完整周期 sin/cos 表，16bit 有符号
5. **输出寄存器**：打拍输出

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| PHASE_WIDTH | 32 | 相位累加器位宽 |
| LUT_ADDR_W | 10 | LUT 地址位宽（1024 点） |
| OUTPUT_WIDTH | 16 | 输出位宽 |

## 频率计算

```
f_out = f_clk × FTW / 2^PHASE_WIDTH
```

例：f_clk=100MHz，FTW=0x00400000（2^32/1024）
→ f_out = 100MHz × 4194304 / 4294967296 ≈ 97.656 kHz

频率分辨率 = f_clk / 2^32 ≈ 0.023 Hz（100MHz 时钟）

## 接口

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| clk | input | 1 | 时钟 |
| rst_n | input | 1 | 低电平复位 |
| ftw | input | 32 | 频率控制字 |
| phase_offset | input | 32 | 相位偏移 |
| m_axis_tdata | output | 32 | {cos[15:0], sin[15:0]} |
| m_axis_tvalid | output | 1 | 输出有效 |

## 资源估算

- 相位累加器：1 个 32bit 加法器（~32 LUT6 + 32 FF）
- LUT：1024 × 32bit = 4 个 BRAM36（或分布式 RAM）
- 输出寄存器：32 FF
- 总计：约 4 BRAM + 100 LUT + 100 FF

## 仿真验证

ModelSim 仿真通过：
- 幅度：|sin|max = |cos|max = 32767（满幅）
- 频率：2048 采样 4 次过零（2 个周期），符合预期
- 相位偏移：π/2 偏移正确
- 直流模式：ftw=0 时输出恒定

## 文件清单

- `rtl/dds.v` — DDS 顶层
- `rtl/dds_sin_cos_lut.mem` — sin/cos LUT（1024 点，hex 格式）
- `tb/tb_dds.sv` — Testbench
- `scripts/gen_dds_lut.py` — LUT 生成脚本

## 后续优化方向

1. **1/4 周期 LUT**：利用 sin/cos 对称性，LUT 存储量减为 1/4
2. **泰勒级数修正**：小 LUT + 插值，进一步减少存储
3. **幅度控制**：添加 AM 调制
4. **相位噪声整形**：添加 dither 改善 SFDR
5. **多通道**：支持多通道 DDS（共享 LUT）
