# 实板验证记录

板卡：Digilent Nexys A7-100T。物理数据路径必须是 `FPGA JA1 -> Dupont jumper -> FPGA JB1`；RTL 仿真中的内部 loopback 不能替代本记录。

## 自动化前置条件

- bitstream：`build/vivado/rv32_realtime_scope.bit`
- 串口：115200 8N1（示例 COM9）
- 基础回路开关：SW3=1、SW[7:4]=9、SW[11:8]=4，其余 0（100 kHz、30%、AUTO rising）
- 正式自检门禁：在上述基础上再置 SW14=1
- 一根 JA1→JB1 跳线

```powershell
vivado -mode batch -source scripts/program_analyzer.tcl
.\scripts\test_hardware.ps1 -Port COM9 -RequireSelfTest
```

脚本验证 SCP2 SELFTEST PASS、有效 MEA2、100 kHz/30% period/high/low、
CAP2 4096 点、512 字节非恒定 payload、trigger index 2048、包 CRC、
PRF2 CRC16.B 计数，并在 `build/hardware/` 生成真实 CAP2、CSV 和 VCD。

## 自动化结果

2026-10-02，SHA-256 为
`82D42CB55A9F162988D5A354DB687B146B94E852B08D6B10652C404044D5394A`
的 pre-display-fix bitstream 已烧录到 Digilent target `210292B7F710A`。在真实
`JA1 -> JB1` 回路、100 kHz/30% 和 SW14=1 条件下，`COM9` 门禁结果为：

```text
SCP2 SELFTEST PASS
frequency=100000Hz period=1000 high=301 low=699 duty=30.1%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x8cd5 ones=2048
PRF2 crc_instructions=538
```

`build/hardware/physical_100khz_30pct.cap2`、`.csv` 和 `.vcd` 均来自这次
实测。自动门禁证明该点的物理回路、测量、深度采集、512 字节
打包、CRC 与 `CRC16.B` 计数通过；在该阶段，它不替代人工 UI 检查和
下表 characterization。最终接受范围见本文末尾的用户免除记录。

随后烧录了加入数码管 `PASS`/`FAIL` 页的当前 bitstream，SHA-256 为
`B4F98AF5A9BDFDD1493A19EDB452B5EE73C9BEAF27B41C91297B25001A629CD4`。
JA1 -> JB1 接通时用户目测数码管为 `PASS`，断开时为 `FAIL`；断开时 COM9
也返回 `SCP2 SELFTEST FAIL`。

随后一个 release candidate 进一步加入 `HOLD` 页，SHA-256 为
`2DBD805C5C896A4338B22813A9EB8C1F0C779928D4A55A252E85CC4A0D5CAE9C`。
它已烧录；断开回路时 COM9 返回 `SCP2 SELFTEST FAIL`，恢复回路后返回
`SCP2 SELFTEST PASS`。此精确位流的自动门禁结果为：

```text
frequency=100000Hz period=1000 high=300 low=700 duty=30%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x1944 ones=2048
PRF2 crc_instructions=538
```

对应 CAP2、CSV、VCD 位于 `build/hardware/final/`；CSV 共 4097 行（表头加
4096 个样本），独立重解析确认 VCD 时间步为 5000 ns。当前精确位流的
用户已在该精确位流上目测确认数码管 `PASS` 与绿色自检灯；`FAIL` 已在前一
显示修复位流上目测确认。该阶段的最终位流 `HOLD` 目测尚未完成；后来由
文末记录的用户验收决定免除。

上一候选位流 SHA-256 为
`9009120DA08A4ABA16210A6769B0A0CCD0E2EE5CB63E73C756ABA07790C61756`，新增
SINGLE 深度采集真正 armed 时的 `Ar` 页面，以及 `0xdeadxxxx` 致命状态的
`Err` 页面。完整回归、实现、时序、DRC 与 JTAG 烧录均通过；setup/hold
分别为 `+0.086 ns` / `+0.051 ns`。重新烧录这一精确镜像后，当前哈希的
自动硬件门禁通过：

```text
SCP2 SELFTEST PASS
frequency=100000Hz period=1000 high=300 low=700 duty=30%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x1944 ones=2048
PRF2 crc_instructions=1076
```

`build/hardware/final/` 中的 CAP2、CSV、VCD 已由该哈希重新生成；另取
10 次 MEA2 样本，频率、period/high/low 分别稳定为
`100000 Hz`、`1000/300/700 ticks`。用户随后在该精确哈希上肉眼确认
数码管 `PASS`、绿色自检灯稳定。该观察只签核当前自检状态，不代替其余
模式、按钮、时基与无信号检查。

完成默认 Vivado source set 清理后，当前发布候选 SHA-256 为
`C1B970187AC0B0AC6DA618D85285CEBB48DC4352717C9B8070C94E32B23B9FD0`。
旧多通道、pattern、重复 PWM、旧 edge-meter 与 VGA 模块仍供 regression
使用，但不进入发布工程。该哈希实现、时序、DRC、JTAG 烧录均通过，并已
在 100 kHz/20% 下得到 10 次完全一致的 `100000 Hz`、`1000/200/800 ticks`
读数。该哈希随后被触发加固版本取代，因此未再作为发布镜像补做 30% 门禁。

触发加固后的当前候选位流 SHA-256 为
`933713F7DDE57B287ED80B6541C8FB07FA81726D5A7454FBDB33FC06D77BE39B`。
Deep Capture 现在每个 100 MHz 时钟检查边沿，存储采样仍使用共享
`sample_div`，从而消除了 100 kHz/20% 下因相位混叠导致 `dump` 永久等待的
问题。完整回归、生产工程重建、实现与 DRC 均通过；setup/hold WNS 为
`+0.024 ns`/`+0.035 ns`。该精确镜像在 100 kHz/30%、SW14=1 下通过正式门禁：

```text
SCP2 SELFTEST PASS
frequency=100000Hz period=1000 high=300 low=700 duty=30%
CAP2 samples=4096 packed=512 trigger=2048 CRC=0x146a ones=1638
PRF2 crc_instructions=538
```

不重新烧录又连续执行 3 次 `dump`+`perf`，三次均完成，CRC 均为
`0x146a`，`CRC16.B` 计数依次增加到 1076、1614、2152。当前哈希的 10 次
100 kHz/30%、1 kHz 的 20/30/50/70/80%，以及 10 kHz/20% 测量均为零
tick 误差。证据保存在 `build/hardware/final_933713f7/`。

用户在 10 kHz/20% 通过后明确要求停止后续实物验证，并按验收决定将剩余
频点和人工 UI 检查视为不阻塞发布。下文把这些项目标为 `WAIVED`，表示未
另行实测，不能作为测量范围或 UI 行为的实验依据。

## 频率与占空比 characterization

每个测量值记录稳定读数范围；误差 tick 以 10 ns 为单位。`WAIVED` 表示按
用户要求跳过，不构成产品保证。

| Generator | Duty | Expected period/high | Measured frequency | Measured period/high/low | Result |
| ---: | ---: | ---: | ---: | --- | --- |
| 1 kHz | 20% | 100000 / 20000 | 1000..1000 Hz | 100000..100000 / 20000..20000 / 80000..80000 | PASS (10/10, current hash) |
| 1 kHz | 30% | 100000 / 30000 | 1000..1000 Hz | 100000..100000 / 30000..30000 / 70000..70000 | PASS (10/10, current hash) |
| 1 kHz | 50% | 100000 / 50000 | 1000..1000 Hz | 100000..100000 / 50000..50000 / 50000..50000 | PASS (10/10, current hash) |
| 1 kHz | 70% | 100000 / 70000 | 1000..1000 Hz | 100000..100000 / 70000..70000 / 30000..30000 | PASS (10/10, current hash) |
| 1 kHz | 80% | 100000 / 80000 | 1000..1000 Hz | 100000..100000 / 80000..80000 / 20000..20000 | PASS (10/10, current hash) |
| 10 kHz | 20% | 10000 / 2000 | 10000..10000 Hz | 10000..10000 / 2000..2000 / 8000..8000 | PASS (10/10, current hash) |
| 10 kHz | 30% / 50% / 70% / 80% | 10000 / varies | WAIVED | WAIVED | WAIVED by user |
| 100 kHz | 20% | 1000 / 200 | 100000..100000 Hz | 1000..1000 / 200..200 / 800..800 | PASS (10/10, prior `C1B970...` hash only) |
| 100 kHz | 30% | 1000 / 300 | 100000..100000 Hz | 1000..1000 / 300..300 / 700..700 | PASS (10/10, current hash) |
| 100 kHz | 20% / 50% / 70% / 80% | 1000 / varies | WAIVED | WAIVED | WAIVED by user on current hash |
| 390.625 kHz | 20% / 30% / 50% / 70% / 80% | 256 / varies | WAIVED | WAIVED | WAIVED by user |
| 1 MHz | 20% / 30% / 50% / 70% / 80% | 100 / varies | WAIVED | WAIVED | WAIVED by user |
| 2 MHz | 20% / 50% / 80% | 50 / varies | WAIVED | WAIVED | WAIVED by user |
| 5 MHz | 20% / 50% / 80% | 20 / varies | WAIVED | WAIVED | WAIVED by user |
| 10 MHz | 20% / 50% / 80% | 10 / varies | WAIVED | WAIVED | WAIVED by user |

Highest current-hash point actually measured: **100 kHz at 30% duty**.

Shortest current-hash pulse actually measured: **3.00 us**.
No continuous maximum-frequency/minimum-pulse-width guarantee is claimed because
the remaining characterization was waived.

## 人工 UI 检查

以下项目原计划由观察板卡的人确认。除已经由 UART/产物直接证明的项目外，
用户要求跳过后续实物检查；这些项目以 `WAIVED` 关闭发布门禁，但没有实验
证据：

- [x] 上电/RESET 后 READY，无明显数码管闪烁 - WAIVED
- [x] 16 个 LED 只显示波形；16 档时基至少逐档抽查 - WAIVED
- [x] AUTO 稳定刷新；NORMAL 无匹配边沿保持；FREE 连续更新 - WAIVED
- [x] SINGLE 在 live/deep 完成后冻结；HOLD 冻结 LED 与数值 - WAIVED
- [x] Frequency、Duty、Period、High、Low、Timebase、NO SIG 页面可辨识 - WAIVED
- [x] RGB0 RUN/HOLD/SINGLE/error；RGB1 signal/wait/no-signal/self-test PASS/FAIL - WAIVED
- [x] 五个按钮均正确，CENTER 单击不重复触发 - WAIVED
- [x] SW0..SW15 的定义均生效 - WAIVED
- [x] 关闭发生器或拔线后超时进入 NO SIG，不保留旧频率 - WAIVED
- [x] `status/measure/dump/perf` 串口命令通过 - PASS on current hash；`run/hold/single` 的额外实物观察 WAIVED
- [x] CSV 与 VCD 可解析，VCD 时间步与 sample_div 一致 - PASS on current hash
- [x] SW14 在 100 kHz/30% 下 `status` 包含 `SELFTEST PASS` - PASS；RGB 肉眼确认 WAIVED
