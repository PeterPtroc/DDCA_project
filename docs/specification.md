# 技术规格

## 固定设计参数

| 项目 | 规格 |
| --- | --- |
| FPGA board | Digilent Nexys A7-100T, XC7A100T-1CSG324 |
| System clock | 100 MHz |
| Digital time resolution | 10 ns |
| Input | JB1，3.3 V LVCMOS 数字输入，共享 2FF 同步 |
| Test output | JA1，3.3 V LVCMOS 单通道 PWM |
| Live display | 16 samples，LED0 oldest，LED15 newest |
| Live window | 160 ns 至 16 ms，16 档 1-2-5 时基 |
| Trigger | rising / falling；AUTO / NORMAL / SINGLE / FREE |
| Trigger position | live LED7 附近；deep index 2048 |
| Deep capture | 4096×1，2048 pre，trigger+2047 post |
| Measurement | frequency、period、high、low、duty、signal-present |
| Averaging | 可选最近四完整周期平均 |
| No-signal | 有历史时 `max(4×period,100 ms)`，上限 1 s；初始 1 s |
| UART | 115200 8N1 |
| Capture transport | CAP2，512-byte packed payload，CRC16/MODBUS |
| PC export | single-channel CSV and VCD；VCD step=`sample_div×10 ns` |

## 数值定义

`period_ticks`、`high_ticks`、`low_ticks` 以 100 MHz tick 为单位。`low = period - high`，固件占空比为 `floor(high × 10000 / period)`，范围 0.00%..100.00%。`frequency_hz` 由 32 周期迭代无符号除法得到 `floor(100000000 / period)`；平均打开时 divisor 为四周期平均值。

同步器会增加固定观测延迟，但不改变稳定周期信号的 period/high 宽度；输入边沿接近时钟边界时存在 10 ns 数字量化误差。

## 实现签核

最终实现数字、setup/hold、DRC 和 v1.0 面积对比记录在根目录 `STATUS.md`。构建门禁为 setup WNS ≥ 0、hold WNS ≥ 0、DRC 0 Error/0 Critical Warning；100 MHz/10 ns 约束不得放宽。

## Verified input range

最大可靠输入频率、最小可靠脉宽与误差范围只接受 Nexys A7 实物实验。当前
哈希实际测得的最高点为 100 kHz/30%，最短高脉宽为 3.00 us；这不是连续
范围保证。完整数据见 `hardware_validation.md`。用户要求跳过其余矩阵，故
标为 `WAIVED` 的频点不构成保证；发生器提供到 10 MHz 的预设也不等于测量
链路已签核到 10 MHz。

## 电气限制

本设计没有衰减、钳位、隔离、阻抗匹配或模拟采样前端。JB1 不耐受 5 V、12 V、RS-232 或负电压，不能用于市电或未知电平。外部 3.3 V 数字源必须与板卡共地。
