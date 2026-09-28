# Nexys A7-100T 五级流水 RISC-V 数字信号分析仪
## Codex 直达 MVP：完整工程计划 / 实施合同

> 目标：让 Codex 在现有仓库中持续工作，直到完成一个可仿真、可综合、可生成 bitstream、可在 Nexys A7-100T 上通过一根杜邦线完成真实闭环验证的 MVP。
>
> MVP 必须体现课程核心：五级流水 RISC-V CPU、扩展指令、forwarding、Load-use 冒险处理、控制冒险 flush、定制 RISC-V 指令；并把 CPU 用于真实 FPGA 外设控制与真实信号采集，而不是只跑纯软件测试。

---

# 0. 给 Codex 的总指令

把本文件放在仓库根目录，命名为 `CODEX_MVP.md`。

对 Codex 下达：

> 严格执行 `CODEX_MVP.md`。先检查仓库现状和本机工具链，然后按依赖顺序实施，不要跳过自动测试，不要只写计划。目标是持续完成实现、仿真、验证、Vivado 构建和文档，直到达到本文件的 MVP Definition of Done。除非遇到真正无法自动解决的外部阻塞（例如本机没有 Vivado、没有 Nexys A7-100T、缺少官方 XDC、无法物理插接杜邦线），否则不要停下来询问。遇到一般工程问题自行选择最简单、风险最低、可验证的方案。禁止在 MVP 前加入 VGA、DDR2、Ethernet、Cache、MMU、RTOS、复杂 GUI 等范围外功能。
>
> 每完成一个里程碑必须：
> 1. 运行对应测试；
> 2. 修复全部失败；
> 3. 更新 `STATUS.md`；
> 4. 记录实际命令和结果；
> 5. 再进入下一阶段。
>
> 如果仓库已有用户代码，优先复用，不要无故重写；重构前先理解现状。所有新功能都必须有测试。

---

# 1. 项目最终定位

项目名建议：

**RV32 Digital Analyzer on Nexys A7-100T**

中文：

**基于自研五级流水 RISC-V 处理器的数字信号采集与分析仪**

MVP 是一个真正跑在 Nexys A7-100T 上的闭环系统：

```text
                         Nexys A7-100T
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │             自研 RV32 五级流水 CPU                  │   │
│   │                                                     │   │
│   │   IF → ID → EX → MEM → WB                           │   │
│   │        │      │                                     │   │
│   │        │      ├─ Forwarding                         │   │
│   │        │      ├─ Branch/JAL/JALR redirect           │   │
│   │        └──────┴─ Load-use Hazard                    │   │
│   │                                                     │   │
│   │                 CRC16.B Custom ISA                  │   │
│   └───────────────────┬─────────────────────────────────┘   │
│                       │                                     │
│                   Data/MMIO Bus                             │
│                       │                                     │
│        ┌──────────────┼──────────────┬──────────────┐       │
│        ▼              ▼              ▼              ▼       │
│      UART           PWM           Capture          PERF     │
│                       │              ▲                      │
│                       │              │                      │
│                    Pmod JA        Pmod JB[7:0]              │
│                       │              │                      │
│                       └── 杜邦线 ────┘                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

物理闭环：

```text
Pmod JA 第一数据脚（PWM OUT）
             │
             │ 一根杜邦线
             ▼
Pmod JB 第一数据脚（Capture CH0）
```

MVP 固定演示：

1. CPU 完成上电自检。
2. CPU 通过 MMIO 设置 PWM：
   - 系统时钟：100 MHz
   - PERIOD = 1000 tick
   - HIGH = 300 tick
   - 输出 = 100 kHz、30% 占空比。
3. CPU 设置 Capture：
   - 8 路数字输入；
   - CH0 上升沿触发；
   - 100 MSa/s；
   - 深度 4096 samples；
   - post-trigger only。
4. Capture 硬件等待真实 Pmod 输入边沿并采样。
5. CPU 从 Capture Memory 读取真实采样结果。
6. CPU 软件计算：
   - 周期 samples；
   - 高电平 samples；
   - 频率；
   - 占空比。
7. CPU 通过板载 USB-UART 输出结果。
8. CPU 输出流水线性能计数：
   - cycle；
   - instret；
   - load-use stalls；
   - EX/MEM forwarding；
   - MEM/WB forwarding；
   - branch flush；
   - CRC16.B 执行次数。
9. 最终打印 `RESULT=PASS` 并点亮 PASS LED。

---

# 2. MVP 明确不做的东西

在 MVP 达成前禁止加入：

- VGA 波形显示
- DDR2
- Ethernet
- USB Host
- Cache
- MMU
- Linux / RTOS
- 中断系统
- AXI 总线
- 复杂 SoC 框架
- 分支预测
- 乘除法 M 扩展
- 浮点
- 多核
- pre-trigger
- I2C / SPI 协议解析
- PC GUI
- DMA
- 复杂 trigger expression

这些全部只能在 MVP release 之后做。

---

# 3. 技术约束

## 3.1 RTL 风格

综合 RTL 优先使用 Verilog-2001 `.v`。

要求：

- 所有 RTL 文件加入：
  ```verilog
  `default_nettype none
  ```
- 时序逻辑使用非阻塞赋值 `<=`
- 组合逻辑使用阻塞赋值 `=`
- 所有 `case` 有 `default`
- 所有组合 always 块保证完整赋值，不允许 latch
- 每级流水寄存器必须携带 `valid`
- bubble = `valid=0`
- x0 永远为 0
- 所有模块接口要清晰，禁止一个超大 `cpu.v` 塞全部逻辑
- MVP 不使用厂商专用 IP，除非官方 XDC 和 Vivado 工程本身
- 所有模块都应可单独仿真

## 3.2 时钟

MVP 全系统使用 Nexys A7 板载 100 MHz 时钟。

不要自行在 fabric 中生成新的时钟。

CPU、PWM、UART、Capture 都使用同一个 100 MHz `clk`。

这样避免 CDC。

若综合后 CPU 100 MHz timing 不通过：

1. 先优化组合路径；
2. 优先优化 CRC 单元和 decode；
3. 仍不通过再讨论额外 clock domain。

不要一开始就引入多时钟。

## 3.3 Reset

内部统一：

```text
rst = 同步高有效 reset
```

顶层根据 Nexys A7 实际按键极性转换。

所有控制寄存器、pipeline valid、计数器在 reset 后进入确定状态。

---

# 4. CPU 架构

## 4.1 五级流水

必须是：

```text
IF
 │
 ▼
IF/ID
 │
 ▼
ID
 │
 ▼
ID/EX
 │
 ▼
EX
 │
 ▼
EX/MEM
 │
 ▼
MEM
 │
 ▼
MEM/WB
 │
 ▼
WB
```

每条流水寄存器至少携带：

- valid
- pc
- instruction
- 必要数据
- 必要控制信号

必须能产生 architectural retire trace。

---

# 5. 支持的 ISA

MVP 支持以下 RV32I 子集。

## 5.1 R-type

```text
ADD
SUB
SLL
SLT
SLTU
XOR
SRL
SRA
OR
AND
```

## 5.2 I-type arithmetic

```text
ADDI
SLTI
SLTIU
XORI
ORI
ANDI
SLLI
SRLI
SRAI
```

## 5.3 Load / Store

```text
LW
SW
```

MVP 只要求 word load/store。

不要求：

```text
LB/LBU/LH/LHU
SB/SH
```

## 5.4 Branch

```text
BEQ
BNE
BLT
BGE
BLTU
BGEU
```

## 5.5 Upper Immediate

```text
LUI
AUIPC
```

## 5.6 Jump

```text
JAL
JALR
```

JALR 必须实现，因为裸机汇编函数返回需要：

```asm
jalr x0, 0(ra)
```

## 5.7 Custom

```text
CRC16.B
```

---

# 6. CRC16.B 自定义指令

采用 RISC-V custom-0 opcode。

编码：

```text
funct7 = 0000000
rs2
rs1
funct3 = 000
rd
opcode = 0001011   # 0x0B
```

汇编语法：

```asm
crc16.b rd, rs1, rs2
```

语义：

```text
old_crc = rs1[15:0]
byte    = rs2[7:0]

new_crc = CRC16_MODBUS_UPDATE(old_crc, byte)

rd[15:0]  = new_crc
rd[31:16] = 0
```

CRC 定义：

```text
CRC-16/MODBUS
poly = 0xA001
LSB first
```

初始化由软件决定。

硬件自检：

```text
input = ASCII "123456789"
init  = 0xFFFF
expected CRC register value = 0x4B37
```

实现建议：

不要在 EX 阶段串行跑 8 个 cycle。

MVP 要保持 single-cycle EX。

优先方案：

```text
index = (old_crc ^ byte) & 0xff
new_crc = (old_crc >> 8) ^ crc_table[index]
```

使用 256 × 16 常量 ROM / case table。

提供：

```text
tools/gen_crc16_table.py
```

由脚本生成 RTL table 或 hex。

---

# 7. CPU 数据通路行为

## 7.1 Register File

- 32 × 32 bit
- x0 硬连 0
- 两个异步读口
- 一个同步写口
- 为避免 WB/ID 同周期歧义，实现 write-through/bypass：

```text
如果 WB 正在写 rd，
且 ID 同周期读取相同寄存器，
ID 读到 WB 新值。
```

## 7.2 Immediate Generator

支持：

```text
I
S
B
U
J
```

立即数符号扩展必须逐类测试。

## 7.3 ALU

至少支持：

```text
ADD
SUB
SLL
SLT
SLTU
XOR
SRL
SRA
OR
AND
PASS_B
CRC16
```

`PASS_B` 可用于 LUI。

---

# 8. Hazard / Forwarding 规则

这是 MVP 的核心，不允许弱化。

## 8.1 EX/MEM → EX Forwarding

示例：

```asm
add x3, x1, x2
sub x4, x3, x5
```

第二条不 stall。

优先级最高。

## 8.2 MEM/WB → EX Forwarding

如果 EX/MEM 不命中，再检查 MEM/WB。

## 8.3 不允许 forward x0

所有 forwarding 条件必须：

```text
rd != 0
```

## 8.4 Store Data Forwarding

必须正确处理：

```asm
add x3, x1, x2
sw  x3, 0(x5)
```

store data 使用 forward 后的 rs2 值。

## 8.5 Branch Operand Forwarding

Branch 在 EX 判定。

branch compare 使用 forward 后的 rs1 / rs2。

例如：

```asm
add x3, x1, x2
beq x3, x4, target
```

必须正确。

## 8.6 Load-use

示例：

```asm
lw  x3, 0(x1)
add x4, x3, x5
```

必须 stall 1 cycle。

Hazard 单元使用：

```text
uses_rs1
uses_rs2
```

避免立即数指令产生假 stall。

规则：

```text
if ID/EX 是 load
and ID/EX.rd != 0
and (
    (IF/ID uses rs1 && IF/ID.rs1 == ID/EX.rd)
 || (IF/ID uses rs2 && IF/ID.rs2 == ID/EX.rd)
)
=> load_use_stall
```

行为：

```text
PC 保持
IF/ID 保持
ID/EX 注入 bubble(valid=0)
EX/MEM 正常推进
MEM/WB 正常推进
```

---

# 9. Control Hazard

Branch、JAL、JALR 都在 EX 阶段决定 redirect。

redirect 时：

```text
PC = redirect_target
flush IF/ID
flush ID/EX
```

redirect 优先级高于 load-use stall。

流水控制优先级：

```text
1. reset
2. EX redirect
3. load-use stall
4. normal advance
```

redirect 发生时：

- 当前 EX 指令本身继续进入 EX/MEM；
- 只杀死年轻指令；
- IF/ID valid = 0；
- ID/EX valid = 0。

---

# 10. Commit / Retire 定义

MEM/WB 中：

```text
valid == 1
```

即视为 retire 一条指令。

不要求该指令写 rd。

因此：

- branch 会 retire
- store 会 retire
- jump 会 retire
- 普通 ALU 会 retire

`instret` 只统计有效 retire，不统计 bubble。

---

# 11. CPU 外部接口

建议 `rv32_core.v` 顶层接口：

```verilog
module rv32_core (
    input  wire        clk,
    input  wire        rst,

    // Instruction memory
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Data / MMIO
    output wire        dmem_valid,
    output wire        dmem_we,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,

    // Retire trace
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_insn,
    output wire        retire_rd_we,
    output wire [4:0]  retire_rd,
    output wire [31:0] retire_rd_data,

    // Events for perf counter
    output wire        event_stall_load,
    output wire [1:0]  event_fwd_ex_count,
    output wire [1:0]  event_fwd_wb_count,
    output wire        event_flush,
    output wire        event_branch,
    output wire        event_branch_taken,
    output wire        event_custom_crc
);
```

MVP 无 wait-state。

所有 slave 必须单周期可访问。

---

# 12. Memory Architecture

## 12.1 Instruction Memory

地址：

```text
0x0000_0000
```

容量：

```text
8 KiB
2048 × 32 bit
```

实现：

```text
reg [31:0] imem [0:2047];
```

读取：

```text
asynchronous read
```

初始化：

```text
$readmemh
```

Vivado 中保证固件 hex 被加入工程。

PC reset：

```text
0x0000_0000
```

## 12.2 Data RAM

地址：

```text
0x1000_0000 - 0x1000_0FFF
```

容量：

```text
4 KiB
1024 × 32 bit
```

MVP：

- async read
- sync write
- 只支持 word 对齐
- 未对齐访问可定义为 unsupported

栈顶建议：

```text
sp = 0x1000_1000
```

---

# 13. MMIO Memory Map

整个地址表一旦实现后冻结。

## 13.1 GPIO

Base:

```text
0x4000_0000
```

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | LED_OUT | RW | low 16 bit |
| 0x04 | SW_IN | R | low 16 bit |
| 0x08 | BTN_IN | R | low 5 bit |
| 0x0C | TEST_RESULT | RW | firmware/testbench mailbox |

`TEST_RESULT` 约定：

```text
0x600D600D = PASS
0xDEADxxxx = FAIL
```

---

## 13.2 UART TX

Base:

```text
0x4000_1000
```

115200 8N1。

100 MHz 下整数 divider：

```text
868
```

寄存器：

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | TXDATA | W | low8 enqueue byte |
| 0x04 | STATUS | R | bit0 = tx_ready |

MVP 只要求 TX。

RX 留到后续。

软件写 TXDATA 前必须轮询 `tx_ready=1`。

---

## 13.3 Timer

Base:

```text
0x4000_2000
```

| Offset | Name | R/W |
|---|---|---|
| 0x00 | TIME_LO | R |
| 0x04 | TIME_HI | R |

64-bit free-running 100 MHz counter。

主要用途：

- timeout
- benchmark
- firmware delay

---

## 13.4 PWM

Base:

```text
0x4000_3000
```

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | CONTROL | RW | bit0 enable |
| 0x04 | PERIOD | RW | period ticks |
| 0x08 | HIGH | RW | high ticks |

规则：

```text
counter = 0 .. PERIOD-1
output = counter < HIGH
```

MVP 默认：

```text
PERIOD = 1000
HIGH   = 300
```

结果：

```text
100 MHz / 1000 = 100 kHz
Duty = 30%
```

异常参数：

- PERIOD < 2：输出 0
- HIGH > PERIOD：按 PERIOD clamp 或输出全高；选一种并文档固定

推荐 clamp。

---

## 13.5 Capture Control

Base:

```text
0x4000_4000
```

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | CONTROL | W | bit0 ARM pulse, bit1 CLEAR pulse |
| 0x04 | STATUS | R | bit0 armed, bit1 triggered, bit2 done |
| 0x08 | TRIG_CH | RW | 0..7 |
| 0x0C | TRIG_EDGE | RW | 0 rising, 1 falling |
| 0x10 | DEPTH | RW | 1..4096 |
| 0x14 | COUNT | R | captured samples |
| 0x18 | TRIGGER_INDEX | R | MVP 固定 0 |

MVP 不做 pre-trigger。

ARM 之后：

```text
WAIT_TRIGGER
    ↓
检测目标边沿
    ↓
触发 sample 写入 index=0
    ↓
连续写到 DEPTH-1
    ↓
DONE
```

---

## 13.6 Capture Sample Window

Base:

```text
0x4000_5000
```

每一个 sample 映射成一个 32-bit word：

```text
addr = 0x40005000 + index * 4
read_data[7:0] = sample
read_data[31:8] = 0
```

index：

```text
0..4095
```

这样 CPU 无需 byte load 指令。

Capture memory：

```text
4096 × 8 bit
```

建议：

```verilog
(* ram_style = "distributed" *)
reg [7:0] capture_mem [0:4095];
```

原因：

- sampler 同步写
- CPU 异步读
- MVP 无 wait state
- 32 Kbit 对 A7-100T 可接受

MVP 后再迁移到 BRAM。

---

## 13.7 Performance Counters

Base:

```text
0x4000_6000
```

| Offset | Name |
|---|---|
| 0x00 | CYCLE_LO |
| 0x04 | INSTRET |
| 0x08 | STALL_LOAD |
| 0x0C | FWD_EX |
| 0x10 | FWD_WB |
| 0x14 | FLUSH |
| 0x18 | BRANCH |
| 0x1C | BRANCH_TAKEN |
| 0x20 | CUSTOM_CRC |
| 0x24 | CLEAR |

定义：

- `cycle`：reset 后每个系统 clock +1
- `instret`：每 retire 一条 +1
- `stall_load`：每个 load-use stall cycle +1
- `fwd_ex`：每个 EX/MEM forwarding operand +1
- `fwd_wb`：每个 MEM/WB forwarding operand +1
- `flush`：每次 redirect +1
- `branch`：每 retire/执行有效 branch +1
- `branch_taken`：taken branch +1
- `custom_crc`：CRC16.B retire +1

---

# 14. Capture Input Synchronizer

外部 8 路数字输入必须经过 2FF synchronizer：

```text
Pmod
 ↓
sync_ff1
 ↓
sync_ff2
 ↓
capture_sample
```

触发逻辑使用：

```text
prev_sample
curr_sample
```

rising：

```text
~prev[ch] & curr[ch]
```

falling：

```text
prev[ch] & ~curr[ch]
```

MVP 所有 8 路同时采样。

---

# 15. Nexys A7 顶层 I/O

RTL 顶层逻辑命名建议：

```text
clk100
reset
uart_tx
led[15:0]
sw[15:0]
btn[4:0]
pwm_out
capture_in[7:0]
```

物理映射：

```text
pwm_out        -> Pmod JA 第一数据脚
capture_in[7:0] -> Pmod JB 八个数据脚
```

闭环时：

```text
JA 第一数据脚 -> JB 第一数据脚
```

重要：

**不要凭记忆硬写 FPGA package pin。**

Codex 必须：

1. 优先寻找仓库已有 Nexys A7-100T XDC；
2. 否则寻找本机已安装的 Digilent board files / master XDC；
3. 否则生成 `constraints/nexys_a7_100t.xdc` 模板，并在 `STATUS.md` 明确记录“缺少官方 XDC 是唯一外部阻塞”。

只从 Digilent 官方 master XDC 拷贝实际 pin mapping。

必须设置：

```text
create_clock -period 10.000
```

---

# 16. 工程目录

目标目录：

```text
.
├── CODEX_MVP.md
├── README.md
├── STATUS.md
├── Makefile
│
├── rtl/
│   ├── top/
│   │   └── nexys_a7_top.v
│   │
│   ├── cpu/
│   │   ├── rv32_core.v
│   │   ├── decoder.v
│   │   ├── imm_gen.v
│   │   ├── regfile.v
│   │   ├── alu.v
│   │   ├── branch_unit.v
│   │   ├── forwarding_unit.v
│   │   ├── hazard_unit.v
│   │   ├── crc16_unit.v
│   │   ├── if_id_reg.v
│   │   ├── id_ex_reg.v
│   │   ├── ex_mem_reg.v
│   │   └── mem_wb_reg.v
│   │
│   ├── memory/
│   │   ├── imem.v
│   │   ├── dmem.v
│   │   └── capture_mem.v
│   │
│   ├── bus/
│   │   └── mmio_decoder.v
│   │
│   └── peripheral/
│       ├── gpio_mmio.v
│       ├── uart_tx.v
│       ├── uart_mmio.v
│       ├── timer_mmio.v
│       ├── pwm_mmio.v
│       ├── logic_capture.v
│       └── perf_counter.v
│
├── tb/
│   ├── tb_alu.v
│   ├── tb_imm_gen.v
│   ├── tb_crc16.v
│   ├── tb_uart_tx.v
│   ├── tb_pwm_capture.v
│   ├── tb_cpu.v
│   ├── tb_cpu_trace.v
│   └── tb_soc_mvp.v
│
├── fw/
│   ├── isa_test.S
│   ├── hazard_test.S
│   ├── crc_test.S
│   └── mvp.S
│
├── tools/
│   ├── rv32asm.py
│   ├── rv32ref.py
│   ├── diff_trace.py
│   ├── gen_crc16_table.py
│   └── gen_random_tests.py
│
├── constraints/
│   └── nexys_a7_100t.xdc
│
├── scripts/
│   ├── build_bitstream.tcl
│   ├── program_board.tcl
│   └── vivado_sources.tcl
│
└── build/
    └── .gitkeep
```

---

# 17. 自带 Mini Assembler

不要把 MVP 成功依赖于用户额外安装 RISC-V GNU toolchain。

实现：

```text
tools/rv32asm.py
```

支持：

- x0..x31
- ABI alias：
  - zero
  - ra
  - sp
  - gp
  - tp
  - t0..t6
  - s0..s11
  - a0..a7
- label
- 注释
- `.word`
- 所有 MVP ISA
- `crc16.b`

伪指令至少支持：

```text
nop
li
mv
j
ret
call
```

其中：

```text
nop = addi x0,x0,0
mv  = addi rd,rs,0
j   = jal x0,label
ret = jalr x0,0(ra)
call label = jal ra,label
```

`li` 支持完整 32-bit：

```text
LUI + ADDI
```

输出：

```text
build/<program>.hex
```

每行一个 32-bit hex word，直接供 `$readmemh`。

---

# 18. Python ISA Reference Model

实现：

```text
tools/rv32ref.py
```

状态：

```text
pc
x[32]
data memory
```

必须支持与 RTL 完全相同的 ISA 和 CRC16.B。

所有算术严格 32-bit wrap。

signed compare 明确使用 signed 32-bit。

x0 每步恢复 0。

Reference model 输出 architectural trace：

```text
step,pc,insn,rd_we,rd,rd_data,mem_we,mem_addr,mem_data
```

RTL 仿真同样输出 trace。

`tools/diff_trace.py` 做逐 retire 对比。

只比较 architectural state，不比较 pipeline timing。

---

# 19. CPU Trace

`tb_cpu_trace.v` 每 retire 一条输出一行：

```text
pc
instruction
rd_we
rd
rd_value
```

若是 store，额外输出：

```text
mem_we
mem_addr
mem_wdata
```

trace 必须只在 retire/architectural event 上生成，不能把 bubble 输出成指令。

---

# 20. Firmware：ISA Test

`fw/isa_test.S` 必须覆盖：

## 算术边界

```text
0
1
-1
0x7fffffff
0x80000000
0xffffffff
```

## signed / unsigned

必须验证：

```text
SLT
SLTU
SLTI
SLTIU
BLT
BGE
BLTU
BGEU
```

例如：

```text
0xffffffff
vs
1
```

signed 和 unsigned 结果必须不同。

## shift

验证：

```text
0
1
31
```

shift amount 仅取低 5 bit。

## control flow

覆盖：

```text
BEQ
BNE
BLT
BGE
BLTU
BGEU
JAL
JALR
AUIPC
```

成功：

```text
TEST_RESULT = 0x600D600D
```

失败：

```text
TEST_RESULT = 0xDEAD0001 + case_id
```

---

# 21. Firmware：Hazard Test

`fw/hazard_test.S`

必须专门测试：

## EX/MEM forwarding

```asm
add x3,x1,x2
sub x4,x3,x5
```

## MEM/WB forwarding

插一条无关指令后使用。

## 双 operand forwarding

让 ALU A/B 同时来自 forward。

## store-data forwarding

```asm
add x3,x1,x2
sw x3,0(x5)
lw x4,0(x5)
```

## load-use

```asm
lw  x3,0(x1)
add x4,x3,x5
```

检查：

- architectural result 正确；
- `STALL_LOAD` 恰好增加。

## branch dependency

```asm
add x3,x1,x2
beq x3,x4,target
```

## taken branch flush

错误路径中放：

```text
写入一个绝不应该被改变的 magic register/memory
```

验证没有 commit。

---

# 22. Firmware：CRC Test

`fw/crc_test.S`

输入：

```text
"123456789"
```

每个 byte 用：

```asm
crc16.b
```

init：

```text
0xffff
```

最终：

```text
0x4b37
```

错误：

```text
TEST_RESULT = 0xDEAD00C1
```

正确：

```text
TEST_RESULT = 0x600D600D
```

---

# 23. Firmware：MVP

`fw/mvp.S`

这是最终上板程序。

启动顺序必须：

## 23.1 初始化

```text
sp = 0x10001000
LED = boot pattern
```

## 23.2 CRC 自检

运行 CRC16.B known vector。

失败立即：

```text
LED = fail
TEST_RESULT = 0xDEAD00C1
UART: "C FAIL\n"
halt
```

成功：

```text
UART: "C OK\n"
```

## 23.3 设置 PWM

```text
PWM.CONTROL = 0
PWM.PERIOD  = 1000
PWM.HIGH    = 300
PWM.CONTROL = 1
```

## 23.4 Capture 配置

```text
TRIG_CH   = 0
TRIG_EDGE = rising
DEPTH     = 4096
CLEAR
ARM
```

## 23.5 等待 done

使用 Timer 设置 timeout。

建议 timeout：

```text
10,000,000 system cycles
```

即约 100 ms。

如果 timeout：

```text
TEST_RESULT = 0xDEAD1001
UART = "TMO\n"
LED = fail
halt
```

## 23.6 分析采样

Capture index 0 应为触发上升沿后的 high sample。

软件读取：

```text
sample[i] & 1
```

寻找：

1. 第一个 falling edge -> `fall_idx`
2. 下一次 rising edge -> `next_rise_idx`

计算：

```text
period_samples = next_rise_idx
high_samples   = fall_idx
```

因为 trigger index 固定为 0。

容差：

```text
period expected = 1000
accept 998..1002

high expected = 300
accept 298..302
```

任何找不到边沿：

```text
FAIL
```

## 23.7 软件整数除法

MVP 不实现 M 扩展。

实现软件：

```text
udiv32(numerator, denominator)
```

使用 32 轮 restoring division。

计算：

```text
frequency_hz = 100000000 / period_samples
```

计算：

```text
duty_permille =
    high_samples * 1000 / period_samples
```

因为没有 MUL：

```text
x * 1000
= (x << 10) - (x << 4) - (x << 3)
```

## 23.8 UART 输出

必须实现：

```text
uart_putc
uart_puts_short 或硬编码短字符串
uart_puthex32
uart_put_u32_decimal
```

最终至少输出：

```text
MVP
C OK
P=1000
H=300
F=100000
D=300
S=<stall_count>
X=<fwd_ex_count>
W=<fwd_wb_count>
L=<flush_count>
R=PASS
```

其中：

```text
D=300
```

代表 300 permille = 30.0%。

## 23.9 PASS

通过后：

```text
LED_OUT = 0x00FF
TEST_RESULT = 0x600D600D
UART = "RESULT=PASS\n"
```

程序进入 idle loop。

---

# 24. Unit Tests

所有模块必须有自动测试。

## 24.1 ALU

`tb_alu.v`

覆盖：

- add overflow wrap
- subtract
- signed/unsigned compare
- left/right shift
- arithmetic right shift
- logic ops

## 24.2 Immediate

`tb_imm_gen.v`

每种：

```text
I
S
B
U
J
```

至少正数、负数、边界。

## 24.3 CRC

`tb_crc16.v`

验证：

```text
"123456789"
0xffff -> 0x4b37
```

并对 Python reference 生成若干随机 `(crc,byte)` pair。

## 24.4 UART TX

`tb_uart_tx.v`

检查：

- start bit
- 8 data bits
- stop bit
- tx_ready/busy

## 24.5 PWM + Capture

`tb_pwm_capture.v`

直接 loopback：

```text
pwm_out -> capture_in[0]
```

设置：

```text
period=1000
high=300
depth=4096
```

检查：

- 能 trigger
- count=4096
- 数据中 period ≈1000
- high ≈300

---

# 25. CPU Differential Test

流程：

```text
.S
 ↓
rv32asm.py
 ↓
.hex
 ├──────────────→ RTL tb_cpu_trace
 │
 └──────────────→ rv32ref.py
                     │
                     ▼
                 ref.trace

RTL.trace
   │
   └──── diff_trace.py ──── PASS/FAIL
```

必须通过：

```text
isa_test
hazard_test
crc_test
```

然后再做至少一组随机 arithmetic/control program。

随机程序不要生成无限循环。

随机测试必须固定 seed 并记录。

---

# 26. SoC Integration Simulation

`tb_soc_mvp.v`

实例化：

```text
nexys_a7_top 或 soc_top
```

仿真中：

```text
pwm_out -> capture_in[0]
capture_in[7:1] = 0
```

UART 可以：

- 真正 decode serial line；
- 或至少监视 `TEST_RESULT`。

自动测试成功条件：

```text
TEST_RESULT == 0x600D600D
```

timeout 后仍未 PASS -> test fail。

还要 assert：

```text
Capture done
period in tolerance
high in tolerance
custom_crc_count > 0
instret > 0
```

---

# 27. Makefile

必须提供至少：

```bash
make help
make asm
make unit
make cpu-test
make diff
make soc-sim
make test
make synth
make bit
make program
make clean
```

定义：

## `make test`

必须依次运行：

```text
Python tests
RTL unit tests
ISA directed test
hazard test
CRC test
differential tests
SoC MVP integration simulation
```

全部通过才 exit 0。

## `make bit`

调用 Vivado batch：

```text
scripts/build_bitstream.tcl
```

输出：

```text
build/vivado/nexys_a7_mvp.bit
build/vivado/timing_summary.rpt
build/vivado/utilization.rpt
```

若 timing fail：

```text
make bit
```

必须返回非零或在日志中明确标红。

---

# 28. Simulator Tool Detection

Codex 启动时检测：

```text
iverilog
verilator
python3
pytest
vivado
```

优先：

```text
iverilog
```

如果没有：

```text
verilator
```

如果两个都没有：

- 仍完成 RTL 和测试代码；
- 在 `STATUS.md` 记录 blocker；
- 不要伪造测试通过。

如果没有 Vivado：

- 完成全部非 Vivado 测试；
- 生成完整 Tcl/XDC；
- 不要声称 bitstream 已构建。

---

# 29. Vivado Batch Flow

不要要求用户手动点 GUI 才能构建。

`scripts/build_bitstream.tcl`：

1. create in-memory/project build
2. add RTL
3. add `program.hex`
4. add XDC
5. set top
6. synth_design
7. opt_design
8. place_design
9. route_design
10. report_timing_summary
11. report_utilization
12. write_bitstream

若 timing violation：

Codex 必须读 report 并修 RTL。

不要在 timing fail 时直接宣告完成。

---

# 30. Hardware Programming

若本机 Vivado hardware server 和板子可访问：

`make program`

自动：

1. open_hw
2. connect_hw_server
3. open target
4. find XC7A100T device
5. program `nexys_a7_mvp.bit`

如果发现多块板：

不要瞎选，记录并要求用户指定。

---

# 31. 实物 MVP 验证步骤

必须在 `README.md` 写清楚：

## 接线

1. 断电或保持安全状态。
2. 用一根杜邦线连接：
   ```text
   JA 第一数据脚 -> JB 第一数据脚
   ```
3. 因为是同一块板，公共地已共享，不需要额外 GND jumper。
4. 不要把 3.3V/VCC 脚接到信号脚。

## UART

```text
115200
8N1
```

## 操作

1. Program FPGA
2. 打开板载 USB-UART
3. Reset
4. 等待输出

预期：

```text
MVP
C OK
P=1000
H=300
F=100000
D=300
...
RESULT=PASS
```

容差内 PASS 即成功。

---

# 32. 课程功能到实物功能映射

必须在 README / 报告说明：

| 课程点 | 本项目实现 |
|---|---|
| 五级流水 | IF/ID/EX/MEM/WB |
| 数据流 | CPU 数据通路 + MMIO |
| 控制流 | Branch/JAL/JALR |
| 扩展移位指令 | SLL/SRL/SRA + immediate |
| bne/blt/bge | 完整 B 类扩展 |
| auipc | 实现 |
| forwarding | EX/MEM + MEM/WB |
| Load-use | 自动 1-cycle stall |
| 定制 RISC-V 指令 | CRC16.B |
| FPGA 验证 | Nexys A7-100T |
| 实际应用 | PWM→真实引脚→采集→CPU分析 |

---

# 33. 里程碑

Codex 必须严格按依赖顺序。

---

## M0：Repo Bootstrap

完成：

- 目录
- README skeleton
- STATUS.md
- Makefile
- simulator/tool detection
- basic lint conventions

验收：

```text
make help
```

工作。

---

## M1：基础组合模块

完成：

- regfile
- imm_gen
- ALU
- branch unit
- crc16_unit
- decoder

验收：

```text
make unit
```

相关单元全部 PASS。

---

## M2：无 Hazard 五级流水

完成：

- IF/ID
- ID/EX
- EX/MEM
- MEM/WB
- basic core
- valid/bubble
- retire trace
- IMEM/DMEM

先让无依赖程序跑通。

验收：

```text
isa_basic no-dependency test PASS
```

---

## M3：Hazard 完整化

完成：

- forwarding
- store forwarding
- branch operand forwarding
- load-use stall
- branch/jump flush

验收：

```text
hazard_test PASS
perf stall/forward counters match expectation
```

---

## M4：Reference / Differential

完成：

- assembler
- reference interpreter
- trace
- diff

验收：

```text
isa_test differential PASS
hazard_test differential PASS
crc_test differential PASS
```

---

## M5：MMIO / 外设

完成：

- mmio decoder
- GPIO
- UART TX
- timer
- PWM
- capture
- perf counter

验收：

```text
tb_pwm_capture PASS
uart unit PASS
mmio tests PASS
```

---

## M6：SoC Integration

完成：

```text
CPU + firmware + MMIO + PWM + capture + UART
```

仿真 loopback。

验收：

```text
tb_soc_mvp:
TEST_RESULT == 0x600D600D
```

---

## M7：Vivado

完成：

- official Nexys A7 XDC
- batch synthesis
- implementation
- timing
- bitstream

验收：

```text
bitstream exists
timing met
no critical DRC
```

---

## M8：Physical MVP

实板：

```text
JA PWM
  │
  └── jumper ─→ JB CH0
```

UART：

```text
RESULT=PASS
```

LED PASS。

到此创建：

```text
git tag v0.1-mvp
```

只有到这里才能开始 VGA / protocol decoder 等扩展。

---

# 34. STATUS.md 格式

Codex 每阶段更新：

```markdown
# STATUS

## Environment
- Python:
- iverilog:
- verilator:
- Vivado:
- Board/XDC:

## Milestones
- [x] M0
- [ ] M1
...

## Latest Tests
Command:
Result:

## Vivado
WNS:
TNS:
Utilization:

## Blockers
- none

## Next
...
```

禁止把“未运行”写成 PASS。

---

# 35. Error / Risk Policy

## 风险 1：100 MHz timing

先优化 RTL。

尤其：

- CRC table path
- branch compare + target
- giant decoder mux

不要立即引入新 clock domain。

## 风险 2：Capture async-read memory 不推成 BRAM

这是预期。

MVP 优先简单单周期 CPU read。

4096×8 distributed RAM 可接受。

后续再改 true dual-port BRAM。

## 风险 3：UART 仿真太慢

单元测试可以使用可参数化 divider：

```text
SIM_BAUD_DIV
```

综合默认仍为 868。

不要修改真实接口行为。

## 风险 4：Firmware 太大

IMEM 初始 8 KiB。

若不够：

```text
先优化字符串/测试
```

不要立即上 DDR2。

## 风险 5：没有 RISC-V GCC

已用自研 Python assembler，MVP 不依赖 GNU toolchain。

## 风险 6：XDC 缺失

这是唯一允许停在硬件构建前的外部 blocker 之一。

不能编造 package pin。

---

# 36. Coding Quality / Review Checklist

Codex 每次提交前检查：

- [ ] 没有 latch warning
- [ ] 没有 multiple driver
- [ ] 没有 x0 被写
- [ ] bubble 不 retire
- [ ] flushed instruction 不 commit
- [ ] load-use 只 stall 必要情况
- [ ] EX/MEM forwarding 优先于 MEM/WB
- [ ] load 不能错误从 EX/MEM forward
- [ ] store data forwarding 正确
- [ ] JAL/JALR PC+4 正确
- [ ] JALR target bit0 清零
- [ ] signed compare 正确
- [ ] SRA 正确符号扩展
- [ ] B/J immediate 拼接正确
- [ ] MMIO word aligned
- [ ] UART 写 busy 时软件会 poll
- [ ] capture trigger 不重复重启
- [ ] reset 后 capture/PWM 默认 idle
- [ ] CRC known vector PASS
- [ ] `make test` 全 PASS
- [ ] timing met 后才称 FPGA build 成功

---

# 37. 最终 Definition of Done

只有满足全部条件才能宣告 MVP 完成。

## RTL

- [ ] 五级流水真实存在
- [ ] pipeline valid/bubble 正确
- [ ] RV32I 目标子集实现
- [ ] EX/MEM forwarding
- [ ] MEM/WB forwarding
- [ ] store forwarding
- [ ] branch forwarding
- [ ] load-use stall
- [ ] branch/JAL/JALR flush
- [ ] CRC16.B custom instruction

## Verification

- [ ] ALU test PASS
- [ ] immediate test PASS
- [ ] CRC unit PASS
- [ ] UART test PASS
- [ ] PWM/Capture test PASS
- [ ] ISA directed test PASS
- [ ] hazard directed test PASS
- [ ] CRC firmware PASS
- [ ] RTL/reference differential PASS
- [ ] SoC MVP simulation PASS

## Software

- [ ] mini assembler
- [ ] reference model
- [ ] mvp firmware
- [ ] timeout
- [ ] sample analysis
- [ ] software divide
- [ ] UART formatted result

## FPGA

- [ ] Nexys A7 official XDC
- [ ] Vivado synth PASS
- [ ] implementation PASS
- [ ] timing met
- [ ] bitstream generated

## Physical

- [ ] PWM 真正从 Pmod 输出
- [ ] 一根 jumper 回接 Capture CH0
- [ ] Capture 真正触发
- [ ] CPU 读取真实采样
- [ ] period = 998..1002
- [ ] high = 298..302
- [ ] calculated frequency ≈ 100 kHz
- [ ] duty ≈ 30%
- [ ] UART 打印结果
- [ ] PASS LED
- [ ] TEST_RESULT = 0x600D600D

## Documentation

- [ ] README 能让另一个人从零复现
- [ ] MMIO 表完整
- [ ] ISA 表完整
- [ ] 自定义指令编码完整
- [ ] 接线说明完整
- [ ] 所有 build/test 命令完整
- [ ] STATUS.md 与实际一致

---

# 38. MVP 之后的扩展顺序

只在 `v0.1-mvp` 后开始。

建议顺序：

```text
v0.2  可调 sample divider
 ↓
v0.3  pre-trigger ring buffer
 ↓
v0.4  VGA waveform viewer
 ↓
v0.5  UART protocol decoder
 ↓
v0.6  CRC16.B 软件 vs 自定义指令 benchmark
 ↓
v0.7  I2C decoder
 ↓
v0.8  SPI decoder
 ↓
v0.9  PC serial GUI
```

DDR2 / Ethernet 最后考虑。

---

# 39. 最终演示脚本

最终演示不从波形窗口开始。

先展示实物：

```text
Nexys A7-100T
JA ─ jumper ─ JB
USB-UART ─ PC
```

Reset。

终端：

```text
MVP
C OK
P=1000
H=300
F=100000
D=300
S=...
X=...
W=...
L=...
RESULT=PASS
```

然后解释：

1. 100 kHz / 30% PWM 是 CPU 通过 MMIO 配出来的；
2. 信号真正从 FPGA 引脚出去；
3. 经真实杜邦线返回另一个 FPGA 引脚；
4. Capture 硬件在 100 MHz 采样；
5. CPU 从采样 RAM 中读取数据；
6. CPU 软件算周期、频率、占空比；
7. CPU 自己的流水线在此过程中发生 forwarding / load-use stall / branch flush；
8. 性能计数器统计这些事件；
9. CRC16.B 是自定义 ISA 扩展，并通过标准向量验证。

最后再展示 RTL / ILA / 仿真波形作为“内部证据”，而不是把它们当作唯一演示。

---

# 40. Codex 最后交付物

完成时必须交付：

```text
README.md
STATUS.md
CODEX_MVP.md

rtl/**
tb/**
fw/**
tools/**
constraints/**
scripts/**

build/*.hex
build/vivado/*.bit
build/vivado/timing_summary.rpt
build/vivado/utilization.rpt
```

并在最终回复中明确列出：

1. 已完成里程碑；
2. 实际运行过的测试；
3. 测试结果；
4. Vivado timing；
5. bitstream 路径；
6. 若实板已连接，物理测试结果；
7. 若尚未实板验证，唯一剩余的人工操作是什么。

---

# 41. Codex 行为约束

Codex 不得：

- 只给方案不写代码；
- 只写 RTL 不写测试；
- 测试失败后跳过；
- 用 `sleep`/硬编码结果伪造 PASS；
- 直接在 testbench 强行写内部寄存器绕过 CPU；
- 用 MicroBlaze 替代自研 CPU；
- 用现成 RISC-V softcore 替代自研 CPU；
- 把 Zynq/ARM 当主处理器；
- 把课程要求的 forwarding / load-use 写成软件 NOP；
- 用错误路径上的 NOP 避免 control hazard；
- 在没跑 Vivado 时声称 FPGA build 成功；
- 在没有实板结果时声称实物 MVP 已验证；
- 编造 Nexys A7 package pin。

Codex 可以：

- 为测试增加辅助 debug output；
- 对模块内部重构；
- 增加 assertion；
- 增加 Python 验证工具；
- 优化 CRC table；
- 在不改变架构和 MMIO contract 的前提下修实现细节。

---

# 42. 最后一句执行要求

**不要把这个项目做成“一个能跑几个指令的 CPU”。**

最终必须形成这个闭环：

```text
Firmware
   ↓
自研五级流水 RISC-V
   ↓
MMIO
   ↓
PWM peripheral
   ↓
Nexys A7 真实 Pmod 输出
   ↓
真实杜邦线
   ↓
Nexys A7 真实 Pmod 输入
   ↓
Capture hardware
   ↓
Sample memory
   ↓
RISC-V software analysis
   ↓
UART
   ↓
真实测量结果 + PASS
```

到这里才叫 MVP。
