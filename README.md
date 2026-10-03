# RV32 实时数字示波分析仪

本项目在 Nexys A7-100T 上实现一套单通道实时数字示波分析仪，并提供 8 路固定板载测试信号。系统只接收 3.3 V 数字信号：唯一的测量输入 JB1 经同步后，同时送入实时波形、边沿测量和 4096 点深度采集模块。RV32 CPU 负责示波器配置、板载交互、UART 通信和采集管理。

```text
JB1 -> 两级触发器同步器 -> 实时波形 ------> LED[15:0]
                         +-> 边沿测量 -----> RV32 CPU -> 八位数码管 / UART
                         +-> 4096×1 深度采集

JA1/2/3/4/7/8/9/10 <- 8 路固定测试信号（持续输出）
```

## 主要功能

- 自研五级流水 RV32 CPU，支持数据前递、加载-使用冒险停顿、控制冒险冲刷、自定义 `CRC16.B` 指令、指令提交跟踪和性能计数器
- 单通道 16 点 LED 实时波形，支持 `AUTO`、`NORMAL`、`SINGLE`、`FREE` 和 `RUN/HOLD`
- 上升沿/下降沿触发与 16 档时基
- 边沿测量硬件计算 `period_ticks` 和 `high_ticks`，并检测无信号超时；CPU 计算 `frequency_hz` 和 `low_ticks`，供占空比显示、UART 响应和 CAP2 数据包使用
- 4096×1 深度采集，触发位置固定为第 2048 点
- JA 的 8 路数字输出持续产生固定频率、固定占空比的测试波形
- 八位数码管、RGB 状态灯、按钮、开关和 115200 8N1 UART
- 支持导出 CAP2、CSV 和 VCD；CAP2 校验使用 CPU 自定义指令计算 CRC16

## 连接与运行

演示时先断电，用一根杜邦线将下表任一路 JA 输出连接到唯一测量输入 `JB1`，再上电并根据固定表检查测量结果。运行硬件验证脚本时使用 `JA9 -> JB1`。

| 固定输出 | 频率 | 占空比 | 周期计数 | 高电平计数 |
| --- | ---: | ---: | ---: | ---: |
| JA1 | 1 kHz | 20% | 100000 | 20000 |
| JA2 | 2 kHz | 30% | 50000 | 15000 |
| JA3 | 5 kHz | 40% | 20000 | 8000 |
| JA4 | 标称 14,242 Hz | 标称 50% | 7021 | 3511 |
| JA7 | 20 kHz | 60% | 5000 | 3000 |
| JA8 | 50 kHz | 70% | 2000 | 1400 |
| JA9 | 100 kHz | 80% | 1000 | 800 |
| JA10 | 200 kHz | 90% | 500 | 450 |

JA 是 12 针 Pmod 接口：JA1–JA4、JA7–JA10 是上述 8 路数字输出；JA5/JA11 是 GND，JA6/JA12 是 3.3 V 电源，不能作为额外信号输出。JA4 受 100 MHz 整数时钟计数限制，实际输出为 14,242.985 Hz、50.007%。

```powershell
.\scripts\test.ps1
vivado -mode batch -source scripts/create_vivado_project.tcl
vivado -mode batch -source scripts/build_bitstream.tcl
vivado -mode batch -source scripts/program_analyzer.tcl
.\scripts\test_hardware.ps1 -Port COM9
```

生成的位流位于 `build/vivado/rv32_realtime_scope.bit`，默认固件位于 `build/hex/scope.hex`。如需同时检查 CAP2/CSV/VCD 导出和 CRC 指令计数，可运行：

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
| CENTER | 切换 RUN/HOLD；在 SINGLE 模式下启动采集 |
| LEFT / RIGHT | 切换显示页 |
| UP / DOWN | 更快 / 更慢时基 |

SW3–SW11 和 SW14 未分配功能。RGB0 显示 RUN、HOLD、SINGLE 等待或错误状态；RGB1 显示有效信号、等待触发或无信号状态。LED0 对应实时帧中最早的采样点，LED15 对应最新的采样点。

## UART 与离线导出

安装 `pyserial` 后，可以查询状态和测量值、控制 RUN/HOLD/SINGLE，或导出深度采集结果：

```powershell
python -m pip install pyserial
python tools/analyzer_cli.py --port COM9 status
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --packet capture.cap2
python tools/analyzer_cli.py --port COM9 perf
```

已有的 CAP2 数据包也可以单独转换：

```powershell
python tools/capture_dump.py capture.cap2 capture.vcd --csv capture.csv
```

## 验证

`scripts/test.ps1` 运行课程设计使用的三层验证：

1. `tb_cpu_trace` 与 Python 参考模型：`isa_test`、`hazard_test`、`crc_test`
2. `tb_scope_core`：8 路固定测试波形、边沿测量、实时波形、深度采集和基础交互
3. `tb_soc_realtime_scope`：集成验证 JA4/JA9 模拟跳线、CPU、`scope.S`、MMIO 和各外设

模块关系和实现细节见 [系统架构](docs/architecture.md)，仿真分层与测试范围见 [仿真验证](src/sim/README.md)。
