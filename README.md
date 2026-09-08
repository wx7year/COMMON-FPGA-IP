# COMMON-FPGA-IP

5G UE 物理层自研 FPGA IP 核集合。原使用 Vivado IP 核（黑盒、仿真慢），现全部重写为可综合 RTL，资源对齐或优于官方 IP，支持时钟/采样率自动资源优化。

## 已完成 IP 核

| IP 核 | 功能 | 关键参数 | 仿真状态 |
|---|---|---|---|
| **FFT** | 1024 点复数 FFT/IFFT | DIN=16bit, TWIDDLE=16bit, DOUT=26bit, 乒乓 RAM + 单蝶形流水线, DIT位反序输入 | ModelSim PASS (Forward max err 350 LSB, IFFT max err 1 LSB) |
| **FIR** | 31 抽头对称 FIR 滤波器 | DATA=16bit, COEFF=16bit, 对称预加优化, 80MHz/10MHz 自动降并行度(NUM_MULT=2) | ModelSim PASS (2048 样本 0 误差) |
| **CORDIC** | 旋转模式(sin/cos) + 向量模式(atan2/magnitude) | DATA=16bit, ANGLE=16bit(Q2.14), 16 级迭代, 内部加宽 4bit | ModelSim PASS |
| **Multiplier** | 一般有符号乘法 + 复数乘法 | 可配流水级数; 复数乘法支持 3 乘法(省 DSP)/4 乘法(低延迟) | ModelSim PASS |
| **Divider** | 恢复余数法有符号除法 | 余数与被除数同号(同 C 语言 %) | ModelSim PASS |
| **DDS** | 直接数字频率合成器 | 32bit 相位累加器, 1024pt sin/cos LUT, 相位截断+幅度抖动 | ModelSim PASS |
| **Polar** | Polar 编码器 + SC 译码器 | N=1024, 冻结位生成, 逐次消除 SC 译码 | ModelSim PASS |
| **LDPC** | QC-LDPC 编码器 + 分层 Min-Sum 译码器 | BG1/BG2 参数化, CNU 归一化 α=0.75, 可配迭代次数 | 端到端无噪声 BER=0 |

## 目录结构

```
3_RES/
├── 0_DOC/                  # 项目计划文档
├── fft/                    # FFT IP 核
│   ├── rtl/                # RTL 源码
│   ├── tb/                 # Testbench
│   ├── model/              # C golden model
│   ├── scripts/            # Python 辅助脚本(生成 twiddle 等)
│   └── doc/                # 设计文档
├── fir/                    # FIR IP 核（同上结构）
├── cordic/                 # CORDIC IP 核
├── multiplier/             # 乘法器 IP 核（一般+复数）
├── divider/                # 除法器 IP 核
├── ldpc/                   # LDPC 编解码器
│   ├── rtl/
│   │   ├── ldpc_encoder.v      # 编码器
│   │   ├── ldpc_decoder.v      # 分层 Min-Sum 译码器
│   │   ├── ldpc_cnu.v          # 校验节点更新单元
│   │   ├── ldpc_cyclic_shift.v # 循环移位器
│   │   └── ldpc_base_graph_rom.v # 基矩阵 ROM
│   ├── tb/
│   │   ├── tb_ldpc.sv          # 编码器测试
│   │   ├── tb_ldpc_cnu.sv      # CNU 单元测试
│   │   └── tb_ldpc_e2e.sv      # 编码→BPSK→AWGN→译码 端到端测试
│   ├── model/              # C golden model
│   ├── scripts/            # 基矩阵生成脚本
│   └── doc/
└── sim/                    # ModelSim 仿真工作目录
    └── ldpc_bg_test.mem    # 测试用基矩阵(4×8, ZC=4)
```

## 仿真方法（ModelSim）

所有 IP 核均使用 ModelSim 仿真，无需编译 Vivado IP。

### 单个 IP 核仿真

以 LDPC 端到端为例：

```bash
cd sim
vlib work
vlog -sv ../ldpc/rtl/ldpc_cyclic_shift.v \
        ../ldpc/rtl/ldpc_base_graph_rom.v \
        ../ldpc/rtl/ldpc_encoder.v \
        ../ldpc/rtl/ldpc_cnu.v \
        ../ldpc/rtl/ldpc_decoder.v \
        ../ldpc/tb/tb_ldpc_e2e.sv
vsim -c tb_ldpc_e2e -do "run -all; quit -f"
```

### 各模块编译文件清单

| 模块 | 需编译的 RTL 文件 | Testbench |
|---|---|---|
| FFT | `fft_top.v` `fft_core.v` `fft_butterfly.v` `fft_complex_mult.v` `fft_twiddle_rom.v` | `tb_fft_top.sv` |
| FIR | `fir_top.v` | `tb_fir_top.sv` |
| Multiplier | `multiplier_top.v` `complex_mult_top.v` | `tb_multiplier.sv` |
| Divider | `divider_top.v` | `tb_divider.sv` |
| CORDIC | `cordic_top.v` | `tb_cordic.sv` |
| DDS | `dds_top.v` | `tb_dds.sv` |
| Polar | `polar_encoder.v` `polar_sc_decoder.v` | `tb_polar.sv` |
| CNU | `ldpc_cnu.v` | `tb_ldpc_cnu.sv` |
| LDPC 编码器 | `ldpc_cyclic_shift.v` `ldpc_base_graph_rom.v` `ldpc_encoder.v` | `tb_ldpc.sv` |
| LDPC 端到端 | 上述 + `ldpc_cnu.v` `ldpc_decoder.v` | `tb_ldpc_e2e.sv` |

## 设计约定

- **接口**：AXI4-Stream（`s_axis_*` / `m_axis_*`），低电平复位 `rst_n`
- **复数格式**：`{Q, I}`，与现有 UE 项目一致
- **通用 IP 核**：不加 `nr_` 前缀（FFT/FIR/CORDIC/Multiplier/Divider）
- **资源优化**：时钟/采样率不匹配时自动减少并行度（如 80MHz 时钟 / 10MHz 数据率 → 过采样比 8 → 减少 DSP 数量）
- **语言**：Verilog/SystemVerilog，Testbench 用 SystemVerilog

## LDPC 说明

当前使用 4×8 测试基矩阵（ZC=4）验证逻辑。真实 5G NR BG1(4×26)/BG2(4×14) 基矩阵值需从 3GPP TS 38.212 表 5.3.2-1/2 填入 `ldpc/scripts/gen_base_graph.py`。

端到端误码率（测试矩阵, 4 次迭代）：
- 无噪声：BER = 0
- σ=0.3：BER ≈ 1.25%
- σ=0.7：BER ≈ 31%（码长仅 32bit，属正常）

## Git 使用

### 首次克隆（其他电脑）

```bash
git clone git@github.com:wx7year/COMMON-FPGA-IP.git
```

> 如未配置 SSH key：`ssh-keygen -t ed25519 -C "your_email"`，然后将 `~/.ssh/id_ed25519.pub` 内容添加到 GitHub → Settings → SSH and GPG keys。

### 日常提交

```bash
git add -A
git commit -m "修改说明"
git push
```

### 拉取最新代码

```bash
git pull
```

### 查看状态和历史

```bash
git status          # 查看修改了哪些文件
git log --oneline   # 查看提交历史
git diff            # 查看具体改动
```

### 已忽略的文件

`.gitignore` 已排除以下内容，不会被提交：
- `sim/work/` — ModelSim 编译库
- `sim/xsim.dir/` — Vivado Xsim 编译产物
- `sim/*.wlf` `sim/*.wdb` — 波形文件
- `sim/*.log` `sim/*.pb` — 仿真日志
- 编辑器临时文件（`.vscode/`、`.idea/` 等）

## 后续计划

1. LDPC 填入真实 BG1/BG2 基矩阵，大 ZC 验证
2. LDPC 译码器加 early termination（syndrome 检查）
3. Polar 译码器升级为 SCL+CRC（5G NR 实际方案）
4. 各 IP 核综合资源对比（vs Vivado 官方 IP）
5. C model 编译验证 + 联合仿真（当前环境无 gcc）
6. FFT 增加运行时可配置点数（当前固定 1024）

## 环境

- 仿真器：ModelSim SE-64 2020.4
- 综合工具：Vivado 2021.1（待综合验证）
- 操作系统：Windows
