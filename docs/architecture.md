# PtrocOS 系统架构

PtrocOS 使用 Nexys A7-100T 的自研 RV32IM + Zicsr CPU、128 MiB DDR2、FreeRTOS、VGA、PS/2、SD 和音频。`ptrocos_soc` 用于基础及媒体固件，`ptrocos_elf_soc` 增加可写指令 RAM；对应板级顶层是 `ptrocos_nexys_a7_top` 和 `ptrocos_elf_nexys_a7_top`。

```text
RV32IM + Zicsr + CRC16.B
├── ROM / RAM / ELF 指令 RAM
├── CLINT：mtime / mtimecmp / MSIP
├── ptrocos_mmio：GPIO / UART / timer / perf / 按键 / 数码管
├── DDR word bus ← DMA
│   └── word_bus_cdc → DDR2 AXI bridge → MIG → 128 MiB DDR2
├── VGA 文本 / PS/2 键盘 / SD SPI / PCM 音频
└── VGA DDR framebuffer → AXI read arbiter → MIG
```

JA/JB 未分配。示波器采集、边沿测量、实时波形、触发和固定测试信号已从本分支移除。RGB 灯通过 GPIO 寄存器由软件控制。

## CPU 与内存

CPU 时钟为 100 MHz，DDR UI 为 81.25 MHz，VGA 像素时钟为 25.2 MHz。RV32M 采用迭代乘除法；访存等待期间保持请求，完成时仅提交一次。CPU 保留精确 trap、中断、MRET 和自定义 `CRC16.B` 指令，未实现 cache、MMU 或进程隔离。

| 地址 | 用途 |
| --- | --- |
| `0x00000000..0x0000ffff` | 64 KiB 固件 ROM；数据侧只读，包含 `.rodata` 与初始化镜像 |
| `0x00010000..0x00013fff` | ELF SoC 的 16 KiB 可写指令 RAM |
| `0x02000000` 页 | CLINT；MSIP `+0x0000`，mtimecmp `+0x4000`，mtime `+0xbff8` |
| `0x10000000..0x1000ffff` | 系统 RAM；实际软件布局以 `sw/ptrocos/linker.ld` 为准 |
| `0x80000000..0x87ffffff` | 128 MiB DDR2；越界访问返回 fault |

ELF 指令 RAM 使用四个 RAMB36E1、下降沿端口及关联于 CPU 时钟的半周期路径。受信任 ELF 应用以 M-mode 运行，调用约定与装载检查见 [ELF 文档](ptrocos-elf.md)。

## 外设地址

清理保留已有外设基址。公共外设由 `src/rtl/bus/ptrocos_mmio.v` 解码；DMA、视频、键盘、SD 与音频由 SoC 独立解码。

| 基址 | 外设 | 主要寄存器或文档 |
| --- | --- | --- |
| `0x40000000` | GPIO | `+0x00` LED，`+0x04` 开关，`+0x08` 按键，`+0x0c` 固件结果，`+0x10` RGB |
| `0x40001000` | UART | `+0x00` TX，`+0x04` 状态，`+0x08` RX；115200 8N1、接收 FIFO |
| `0x40002000` | timer | 只读运行计数；FreeRTOS tick 使用 CLINT |
| `0x40006000` | 性能计数器 | cycle/instret/stall/forward/flush/branch/taken/CRC；写 `+0x24` 清零 |
| `0x40007000` | 按键/开关 | `+0x00` 去抖按键，读 `+0x04` 取出并清事件，`+0x08` 同步开关 |
| `0x40008000` | 数码管 | `+0x00/+0x04` 八位编码，`+0x08` 小数点，`+0x0c` 使能 |
| `0x4000a000` | DMA | [开发说明](ptrocos-development.md) |
| `0x4000b000` | VGA 文本控制 | [文本控制台](ptrocos-text.md) |
| `0x4000c000` | PS/2 键盘 | [文本控制台](ptrocos-text.md) |
| `0x4000d000` | SD SPI | [存储](ptrocos-storage.md) |
| `0x4000e000` | DDR 图形控制 | [图形](ptrocos-graphics.md) |
| `0x4000f000` | PCM 音频 | [媒体](ptrocos-media.md) |
| `0x40010000..0x40013fff` | VGA 文本单元窗口 | [文本控制台](ptrocos-text.md) |

已撤销的 `0x40004000`、`0x40005000`、`0x40009000` 页面读零、忽略写入。原采集窗口地址如今由 VGA 文本单元使用，保留现有 PtrocOS 文本接口。

GPIO 的 `+0x10` 为六位 RGB 输出：bit0/1/2 对应 RGB0 的 R/G/B，bit3/4/5 对应 RGB1 的 R/G/B，高位忽略，复位全灭。LED 与 RGB 独立，可用 `PTROCOS_MMIO32(PTROCOS_RGB_ADDR)` 写入。GPIO 原有四个寄存器的行为保持不变；按键与开关继续使用 `input_sync` 两级同步器。

## 软件与第三方代码

`sw/ptrocos` 包含板级支持、裸机验证固件、FreeRTOS shell、存储、媒体和 ELF 应用支持。`sw/ptrocos/startup.S` 是裸机 trap 入口；`sw/ptrocos/os/startup.S` 安装 FreeRTOS trap 入口，`os/runtime.c` 提供 freestanding C 内存操作。`os/FreeRTOSConfig.h` 为系统配置。

FreeRTOS V11.3.1 内核位于 `third_party/freertos/kernel`，原 MIT 许可证和文件头完整保留，来源见同目录上级的 `PROVENANCE.md`。FatFs 位于 `third_party/fatfs`，字体位于 `third_party/font8x8`。`sw/freertos/README.md` 仅保留为快速启动链接的兼容说明。

## 时序与验收

`create_ptrocos_project.tcl` 列出实际 RTL 和约束，禁用自动增量检查点。CPU/DDR 和视频跨域使用 held-payload mailbox，payload 路径限制为 10 ns；不对整个时钟域设置假路径。MIG、像素时钟、ELF 半周期路径仍参与时序分析。

`finalize_ptrocos_timing.tcl` 检查时钟、CDC 覆盖、ELF RAM 和音频开漏输出，保存 routed checkpoint 及报告，并要求 setup WNS ≥ +0.100 ns、非负 hold/pulse、无阻断 DRC。自动物理优化同时针对 CPU、DDR UI 和像素时钟增加临时 setup 余量，报告前恢复正常约束。生成位流前由 `check_routed_timing.tcl` 再检查 setup/hold。

固件、RTL 仿真与物理板卡验收分别记录。回归入口见 [仿真验证](../src/sim/README.md)，最新验证范围和物理待验项目见 [开发说明](ptrocos-development.md#验证边界)。
