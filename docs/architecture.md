# 系统架构

## 数据通路

```text
JB1 asynchronous input
        |
   2FF synchronizer
        |
        +---- Live Scope ------ 16-bit frame ------ LED[15:0]
        +---- Edge Meter ------ period/high/low/frequency
        +---- Deep Capture ---- 4096 x 1 sample window
                                           |
                                           v
Five-stage RV32 CPU <-------- MMIO --------+---- Seven Segment
        |                                  +---- UART
        +---- forwarding / load-use stall / branch flush
        +---- CRC16.B / retire trace / performance counters

Signal Generator -------------------------- JA1
```

输入只经过一组 `input_sync`，三个消费者共享同一个同步结果。实时数据面不等待 CPU：`live_scope` 发布 LED 帧，`edge_meter_scope` 完成边沿计时和频率除法，`scope_capture` 管理环形采样窗口。CPU 运行 `scope.S`，负责配置变化、按钮事件、数码管内容、UART、自检和深度采集传输。

## CPU

`rv32_core` 是五级流水 RV32 实现，保留 EX/WB forwarding、load-use interlock、branch/control flush、自定义 `CRC16.B` 指令、architectural retire trace 和性能事件。指令存储器默认加载 `build/hex/scope.hex`；CPU 行为由三组 directed firmware 与独立 Python reference 做差分验证。

## 实时波形与深度采集

Live Scope 保存短历史。AUTO/NORMAL/SINGLE 模式将所选边沿对齐到 LED7，FREE 模式每 16 个样本发布一帧；HOLD 阻止新帧发布，AUTO 在长时间无触发时强制刷新。`sample_div` 控制时基。

Deep Capture 是 4096×1 环形窗口。触发前保留 2048 点，触发后收集剩余样本，最终按时间顺序映射到 `0x40010000..0x40013fff`，trigger index 固定为 2048。边沿检测在 100 MHz 时钟域进行，存储采样仍遵循 `sample_div`。

## 边沿测量

Edge Meter 输出 `period_ticks`、`high_ticks`、`low_ticks`、`frequency_hz`、`edge_age`、`valid` 和 `signal_present`。一个 tick 为 10 ns；可选最近四周期平均。无有效边沿超过动态超时后清除有效状态，避免数码管保留过期读数。

## MMIO

| Base | 外设 |
| --- | --- |
| `0x40000000` | GPIO / firmware test result |
| `0x40001000` | UART |
| `0x40002000` | 64-bit timer |
| `0x40003000` | Signal Generator |
| `0x40004000` | Deep Capture control/status |
| `0x40005000` | Live Scope |
| `0x40006000` | Performance counters |
| `0x40007000` | Buttons / switches |
| `0x40008000` | Seven segment |
| `0x40009000` | Edge Meter |
| `0x40010000` | 4096-sample capture window |

## CAP2

UART 深度采集包包含 26 字节小端头、512 字节位打包样本和 2 字节 CRC16：

```text
magic[4] version[1] flags[1] count[2] sample_div[4]
trigger_index[2] period[4] high[4] frequency[4]
packed_samples[512] crc16[2]
```

CRC 使用初值 `0xffff` 和多项式 `0xa001`，覆盖头与 payload；固件逐字节执行 `CRC16.B`。

## 顶层与时序

`nexys_a7_top` 只暴露 100 MHz 时钟、复位、开关、按钮、16 个 LED、两颗 RGB LED、八位数码管、UART、JA1 和 JB1。生产工程使用显式 RTL source list。实现脚本在写位流前要求 routed setup/hold slack 均非负，且 DRC 无 Error 或 Critical Warning。
