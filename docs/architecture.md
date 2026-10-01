# 系统架构

## 设计边界

本项目是单通道数字测量仪，不是模拟示波器。默认顶层只保留 Nexys A7-100T 上实际使用的时钟、复位、开关、按钮、16 个普通 LED、两颗 RGB LED、八位数码管、USB-UART、JA1 输出与 JB1 输入；VGA 不在默认 bitstream 中。

## 数据面与控制面

```text
JB1 asynchronous input
        |
   shared 2FF synchronizer
        |
        +---------- Edge Meter ---------- measurement registers
        |
        +---------- Live Scope ---------- LED[15:0]
        |
        +---------- Deep Capture -------- 4096 x 1 window
                                                |
                                                v
RV32 five-stage CPU <--------- MMIO -------- UART / SevenSeg / controls
        |
        +-- forwarding, load-use interlock, branch flush
        +-- CRC16.B custom instruction
        +-- retire trace and performance counters

Signal Generator ---------------- JA1 -- physical jumper -- JB1
```

实时路径不等待 CPU。`edge_meter_scope` 在硬件中标记边沿并迭代计算频率；`live_scope` 直接发布 16 点触发对齐帧；数码管扫描也完全由硬件完成。CPU 的非阻塞主循环只处理配置变化、按钮事件、20 Hz 数值缓存、UART 和自检。

## 两条采集路径

Live Scope 保存短历史，在 AUTO/NORMAL/SINGLE 中把所选边沿放在 LED7，随后收集剩余点并原子发布 16 位帧。FREE 每 16 个采样发布一帧。HOLD 阻止新帧发布；AUTO 在 1024 个采样点未见触发时强制刷新，恒高/恒低仍可见。

Deep Capture 是独立的 4096×1 环形预触发窗口。触发前保留 2048 点；满足上升/下降沿后写入触发点和后续 2047 点，按时间顺序映射到 `0x40010000..0x40013fff`，每个 word 仅 bit0 有效。它只用于 SINGLE、dump 与调试，不参与实时 LED 刷新。

三个消费者只接收 `mmio_decoder` 内唯一 `input_sync` 输出，避免三套同步器形成不同采样时间基准。

## 测量

边沿测量输出 `period_ticks`、`high_ticks`、`low_ticks`、`frequency_hz`、`edge_age`、`valid` 和 `signal_present`。时钟 tick 为 10 ns。有效周期后的超时为 `max(4×period, 100 ms)`，上限 1 s；初次获得完整周期前的无边沿判定为 1 s。SW12 可将最近四个完整周期的 period/high 作移位平均，频率同样使用平均周期。

## MMIO

| Base | 外设 | 主要寄存器 |
| --- | --- | --- |
| `0x40000000` | GPIO / test result | switches/buttons 兼容寄存器与测试结果 |
| `0x40001000` | UART | TX、status、RX |
| `0x40002000` | Timer | 64-bit 100 MHz cycle counter |
| `0x40003000` | Signal Generator | control、period、high、status |
| `0x40004000` | Deep Capture | control/status、edge、sample_div、count、trigger_index |
| `0x40005000` | Live Scope | control/status、mode、edge、sample_div、frame、frame_counter |
| `0x40006000` | Performance | cycle、instret、stall、forwarding、flush、branch、taken、CRC |
| `0x40007000` | Buttons / switches | debounced state、clear-on-read events、synchronized switches |
| `0x40008000` | Seven segment | data0、data1、decimal points、enable |
| `0x40009000` | Edge Meter | status、period、high、low、frequency、edge_age |
| `0x40010000` | Capture window | 4096 chronological one-bit samples |

`0x4000A000` 的旧八通道 pattern generator 在 v2 默认设计中关闭，仅由 legacy regression 的显式兼容参数启用。

## CAP2 传输

包由 26 字节小端头、512 字节位打包样本和 2 字节小端 CRC16 组成：

```text
magic[4] version[1] flags[1] count[2] sample_div[4]
trigger_index[2] period[4] high[4] frequency[4]
packed_samples[512] crc16[2]
```

样本 `n` 位于 payload 字节 `n>>3` 的 bit `n&7`。CRC 初值 `0xffff`、多项式 `0xa001`，覆盖头和 payload；固件对每个字节执行自定义 `CRC16.B`。

## 时序策略

系统时钟固定 100 MHz、周期约束固定 10 ns。外部开关、按钮、JB1 与 UART RX 是异步输入并由同步器接收；没有把内部同步路径声明成 false path。实现脚本在写 bitstream 前硬性拒绝负 setup/hold slack 和 Error/Critical Warning 级 DRC。
