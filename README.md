# RV32 实时数字示波分析仪

Nexys A7-100T 上的单通道数字示波器：JB1 同时接入实时波形、边沿测量和 4096 点采集，RV32I + Zicsr CPU 运行 FreeRTOS 四任务应用。系统提供八路固定 JA 测试信号、LED 波形、十进制数码管和 UART CAP2/CSV/VCD 导出。

本仓库还包含独立的 **PtrocOS 实验系统**，支持 RV32M、DDR2/DMA、VGA/PS2、FAT/exFAT、音视频及受信任 ELF 应用。构建与使用见 [PtrocOS 开发说明](docs/ptrocos-development.md)。两套系统使用不同顶层和构建入口。

## 快速启动

需要 64 位 Windows、PowerShell 5.1/7、Python 3（加入 PATH）及 Vivado。固件构建首次自动下载并校验 xPack RISC-V GCC 15.2.0-1，之后复用 `tools/.local/`；固定版本见 [toolchain.json](tools/toolchain.json)。自备工具链可使用 `-ToolchainPrefix` 或 `RISCV_TOOLCHAIN_PREFIX`，详见 [固件说明](sw/freertos/README.md)。

在仓库根目录执行：

```powershell
.\build_freertos.bat
.\open_vivado_gui.bat
```

按提示设置 Vivado 路径，在 GUI 中生成位流，再通过 Hardware Manager 下载。批处理构建可用 `vivado -mode batch -source scripts/build_bitstream.tcl`。固件必须先生成；输出为 `build/hex/freertos.hex` 和 `build/vivado/rv32_realtime_scope.bit`。修改固件或 RTL 后须重新生成并下载位流。

## 接线与板载控制

**JB1 仅接收 3.3 V LVCMOS 数字信号。** 没有模拟前端或过压保护，不能接入 5 V、RS-232、电源轨或未知电平。断电后将任一路 JA 信号跳接 JB1，再上电；验证脚本默认使用 JA9。

| 输出 | 频率 | 占空比 | 周期计数 | 高电平计数 |
| --- | ---: | ---: | ---: | ---: |
| JA1 | 1 kHz | 20% | 100000 | 20000 |
| JA2 | 2 kHz | 30% | 50000 | 15000 |
| JA3 | 5 kHz | 40% | 20000 | 8000 |
| JA4 | 14,242.985 Hz | 50.007% | 7021 | 3511 |
| JA7 | 20 kHz | 60% | 5000 | 3000 |
| JA8 | 50 kHz | 70% | 2000 | 1400 |
| JA9 | 100 kHz | 80% | 1000 | 800 |
| JA10 | 200 kHz | 90% | 500 | 450 |

JA5/JA11 为 GND，JA6/JA12 为 3.3 V 电源。

| 输入 | 作用 |
| --- | --- |
| SW0 | 上升沿 / 下降沿 |
| SW[2:1] | AUTO / NORMAL / SINGLE / FREE |
| SW12 | 四周期测量平均 |
| SW13 | MEA2 周期遥测 |
| SW15 | 追加九个 CPU 性能计数器页 |
| CENTER | RUN/HOLD；SINGLE 模式下启动采集 |
| LEFT / RIGHT | 切换显示页 |
| UP / DOWN | 更快 / 更慢时基 |

其余开关未分配。RGB0 显示运行/采集状态，RGB1 显示信号/触发状态。LED0 是最早样本，LED15 是最新样本。显示页依次为频率、周期、高/低电平计数、占空比（单位 0.01%）和测量状态；计数单位为 10 ns。数码管补零显示八位十进制，超过 `99,999,999` 显示 `--------`，UART 保留完整数值。

## UART 与导出

UART 为 115200 8N1。将 `COM9` 替换为实际串口：

```powershell
python -m pip install pyserial
python tools/analyzer_cli.py --port COM9 status
python tools/analyzer_cli.py --port COM9 measure
python tools/analyzer_cli.py --port COM9 dump --output capture.csv --vcd capture.vcd --packet capture.cap2
python tools/analyzer_cli.py --port COM9 cancel
python tools/analyzer_cli.py --port COM9 perf
python tools/capture_dump.py capture.cap2 capture.vcd --csv capture.csv
```

采集等待期限为 1 秒加上本次 4096 点采样时间。超时返回 `ERR2 TIMEOUT`；`cancel` 清除采集及待导出请求，返回 `ERR2 CANCELLED`。等待中新的 SINGLE 会重新采集。CAP2 开始发送后先完成整帧，再处理取消；协议和参数冻结规则见 [系统架构](docs/architecture.md#cap2)。

## 验证与文档

```powershell
.\scripts\test_freertos.ps1
.\scripts\test_hardware.ps1 -Port COM9 -ExpectedOutput JA9 -OptionalDump
.\scripts\test_hardware_soak.ps1 -Port COM9 -ExpectedOutput JA9 -DurationMinutes 10
```

第一条重建固件并运行 RTL/SoC 回归；后两条需要已下载位流及对应跳线，日志保存于 `build/hardware/`。仅运行仿真不能认定板卡验收通过。

- [系统架构](docs/architecture.md)：CPU、trap、MMIO、采集和时序门槛。
- [仿真验证](src/sim/README.md)：测试范围及复现入口。
- [PtrocOS 开发说明](docs/ptrocos-development.md)：实验固件、命令和接口导航。
