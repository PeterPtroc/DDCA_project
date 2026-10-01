# 用户指南

## 接线与启动

1. 关闭板卡电源。
2. 用一根 3.3 V 兼容杜邦线连接 Pmod `JA1` 与 `JB1`；使用外部被测信号时移除该线，并确保信号地与板卡 GND 相连。
3. 连接 USB-JTAG/UART，烧录 `build/vivado/rv32_realtime_scope.bit`。
4. 释放 CPU RESETN。启动时数码管短暂显示 READY，随后进入频率页。

JB1 没有过压保护，只能接受 3.3 V LVCMOS 数字信号。

## 开关

| 开关 | 0 | 1 / 编码 |
| --- | --- | --- |
| SW0 | rising trigger | falling trigger |
| SW[2:1] | 00 AUTO | 01 NORMAL、10 SINGLE、11 FREE |
| SW3 | generator off | generator on |
| SW[7:4] | 频率预设 0..15 | 见下表 |
| SW[11:8] | 占空比预设 0..15 | 10,15,20,...,80,90% |
| SW12 | raw | 最近四周期平均 |
| SW13 | telemetry off | 每 100 ms 一个二进制 MEA2 包 |
| SW14 | normal | JA1→JB1 expected/measured 自检 |
| SW15 | instrument UI | architecture debug UI |

频率预设依次为：1 Hz、10 Hz、100 Hz、1 kHz、2 kHz、5 kHz、10 kHz、20 kHz、50 kHz、100 kHz、200 kHz、390.625 kHz、1 MHz、2 MHz、5 MHz、10 MHz。预设范围不等同于已经实板签核的输入范围；以 `specification.md` 的实测表为准。

## 按钮和模式

- LEFT/RIGHT：循环切换 Frequency、Duty、Period、High、Low、Timebase；SW15 打开时切换 9 个 CPU 性能计数页。
- UP：更快时基；DOWN：更慢时基。索引限制在 0..15，调整值会覆盖显示约 1 秒。
- CENTER：AUTO/NORMAL/FREE 中切换 RUN/HOLD。SINGLE 中同时清除并 arm live/deep capture，两个硬件采集都完成后进入 HOLD。

AUTO 等待触发，超时仍更新；NORMAL 只在边沿满足时更新；SINGLE 只抓一帧和一次深度采集；FREE 忽略触发连续发布。

## 时基

| Index | sample_div | 每 LED 时间 | 16 点窗口 |
| ---: | ---: | ---: | ---: |
| 0 | 1 | 10 ns | 160 ns |
| 1 | 2 | 20 ns | 320 ns |
| 2 | 5 | 50 ns | 800 ns |
| 3 | 10 | 100 ns | 1.6 us |
| 4 | 20 | 200 ns | 3.2 us |
| 5 | 50 | 500 ns | 8 us |
| 6 | 100 | 1 us | 16 us |
| 7 | 200 | 2 us | 32 us |
| 8 | 500 | 5 us | 80 us |
| 9 | 1000 | 10 us | 160 us |
| 10 | 2000 | 20 us | 320 us |
| 11 | 5000 | 50 us | 800 us |
| 12 | 10000 | 100 us | 1.6 ms |
| 13 | 20000 | 200 us | 3.2 ms |
| 14 | 50000 | 500 us | 8 ms |
| 15 | 100000 | 1 ms | 16 ms |

## 显示

LED0 是最早样本，LED15 是最新样本。触发模式下选定边沿对齐在 LED7 附近。数码管用 `F`、`d`、`P`、`H`、`L`、`t` 标识页，并用 `k/M/n/u/m` 与小数点显示工程单位；无有效边沿时显示近似 `no-SiG`。SINGLE 深度采集真正 armed 并等待边沿时显示 `Ar`；HOLD 时 LED 和数值缓存都冻结，数码管显示 `HOLD`；固件致命结果显示 `Err`。恢复 RUN 后回到测量页。

RGB0：绿 RUN、蓝 HOLD、黄 SINGLE armed/wait、红 error。RGB1：绿 signal、黄 waiting trigger、红 no signal；自检启用时绿/红为 PASS/FAIL。

## UART

接口为 115200 8N1。推荐使用 `tools/analyzer_cli.py` 的 `status`、`measure`、`run`、`hold`、`single`、`dump`、`perf` 子命令。dump 若没有已完成的深度采集会先 arm 并等待真实触发；无输入时因此会等待而不是导出正在写入的 RAM。

```powershell
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --packet capture.cap2
```

CLI 校验 CAP2 CRC 后才写 CSV/VCD；VCD 时间步自动采用头内的 `sample_div × 10 ns`。

正式 100 kHz/30% 回路签核时再打开 SW14，并运行
`.\scripts\test_hardware.ps1 -Port COM9 -RequireSelfTest`。脚本同时检查
PRF2 中的 CRC16.B 执行计数，并在 `build/hardware/` 留存 CAP2、CSV、VCD。

## 常见问题

- `NO SIG`：确认共同地、JB1 电平、SW3、跳线和至少两个完整上升沿；初始无信号超时约 1 秒。
- NORMAL 不更新：输入没有匹配 SW0 的边沿，属于预期行为；可先切 AUTO 或 FREE。
- SINGLE 一直黄：尚未触发，或 4096 点采集尚未完成。
- CLI 读到意外二进制：SW13 的 MEA2 遥测正在输出；执行交互命令前先关闭 SW13。
- 高频读数不稳定：打开 SW12 平均；最终可信范围以实板 characterization 为准。
