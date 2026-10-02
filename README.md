# RV32 Real-Time Digital Scope

基于自研五级流水 RISC-V 处理器的“单通道实时数字示波分析仪 + 8 路固定板载测试信号”。项目面向 Nexys A7-100T 和 3.3 V 数字信号：唯一测量输入 JB1 经同步后并行送入实时波形、边沿测量和 4096 点深度采集；RV32 CPU 负责 Scope 配置、板载 UI、UART 与采集管理。

```text
JB1 -> 2FF synchronizer -> Live Scope -----> LED[15:0]
                      +-> Edge Meter ------> RV32 CPU -> Seven Segment / UART
                      +-> Deep Capture 4096x1

JA1/2/3/4/7/8/9/10 <- Eight fixed test signals (always on)
```

## 主要功能

- 自研五级流水 RV32 CPU，含 forwarding、load-use stall、控制冲刷、`CRC16.B`、retire trace 和性能计数器
- 单通道 16 点 LED 实时波形，支持 AUTO、NORMAL、SINGLE、FREE、RUN/HOLD
- 上升沿/下降沿触发与 16 档时基
- 硬件测量 frequency、period、high、low、duty 和无信号超时
- 4096×1 深度采集，trigger index 固定为 2048
- JA 的 8 路数字 I/O 持续输出固定频率/占空比测试波形
- 八位数码管、RGB 状态灯、按钮、开关和 115200 8N1 UART
- 可选 CAP2、CSV 和 VCD 导出；CAP2 使用 CPU 自定义指令计算 CRC16

## 连接与运行

演示时先断电，用一根 Dupont 线将下表任一路 JA 输出连接到唯一测量输入 `JB1`，再上电并根据固定表检查测量结果。运行硬件验证脚本时使用 `JA9 -> JB1`。

| 固定输出 | 频率 | 占空比 | period ticks | high ticks |
| --- | ---: | ---: | ---: | ---: |
| JA1 | 1 kHz | 20% | 100000 | 20000 |
| JA2 | 2 kHz | 30% | 50000 | 15000 |
| JA3 | 5 kHz | 40% | 20000 | 8000 |
| JA4 | 14,242 Hz nominal | 50% nominal | 7021 | 3511 |
| JA7 | 20 kHz | 60% | 5000 | 3000 |
| JA8 | 50 kHz | 70% | 2000 | 1400 |
| JA9 | 100 kHz | 80% | 1000 | 800 |
| JA10 | 200 kHz | 90% | 500 | 450 |

JA 是 12 针 Pmod：JA1–JA4、JA7–JA10 是上述 8 路数字 I/O；JA5/JA11 是 GND，JA6/JA12 是 3.3 V 电源，不能作为额外信号输出。JA4 受 100 MHz 整数 tick 限制，实际为 14,242.985 Hz、50.007%。

```powershell
.\scripts\test.ps1
vivado -mode batch -source scripts/create_vivado_project.tcl
vivado -mode batch -source scripts/build_bitstream.tcl
vivado -mode batch -source scripts/program_analyzer.tcl
.\scripts\test_hardware.ps1 -Port COM9
```

生成的位流为 `build/vivado/rv32_realtime_scope.bit`，默认固件为 `build/hex/scope.hex`。若还需要 CAP2/CSV/VCD 与 CRC 指令计数，可运行：

```powershell
.\scripts\test_hardware.ps1 -Port COM9 -OptionalDump
```

> JB1 只允许接入 3.3 V LVCMOS 兼容数字信号。本项目没有模拟前端、衰减网络或过压保护，不能连接 5 V、RS-232、电源轨或未知电平。

## 板载控制

| 输入 | 作用 |
| --- | --- |
| SW0 | 上升沿 / 下降沿 |
| SW[2:1] | AUTO / NORMAL / SINGLE / FREE |
| SW12 | 四周期测量平均 |
| SW13 | MEA2 周期遥测 |
| SW15 | CPU 性能计数器页 |
| CENTER | RUN/HOLD；SINGLE 下启动采集 |
| LEFT / RIGHT | 切换显示页 |
| UP / DOWN | 更快 / 更慢时基 |

SW3–SW11 和 SW14 未分配功能。RGB0 显示 RUN、HOLD、SINGLE 等待或错误；RGB1 显示有效信号、等待触发或无信号。LED0 是实时帧最早点，LED15 是最新点。

## UART 与离线导出

安装 `pyserial` 后可查询状态、测量值、控制 RUN/HOLD/SINGLE，或导出深度采集：

```powershell
python -m pip install pyserial
python tools/analyzer_cli.py --port COM9 status
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --packet capture.cap2
python tools/analyzer_cli.py --port COM9 perf
```

也可单独转换已有 CAP2：

```powershell
python tools/capture_dump.py capture.cap2 capture.vcd --csv capture.csv
```

## 验证

`scripts/test.ps1` 只运行最终课程设计所需的三层验证：

1. `tb_cpu_trace` + Python reference：`isa_test`、`hazard_test`、`crc_test`
2. `tb_scope_core`：8 路固定测试波形、边沿测量、实时波形、深度采集和基础 UI
3. `tb_soc_realtime_scope`：JA4/JA9 模拟跳线 + CPU + `scope.S` + MMIO + peripherals 集成

更多设计与实测信息见 [系统架构](docs/architecture.md)、[实板验证](docs/hardware_validation.md) 和 [当前状态](STATUS.md)。
